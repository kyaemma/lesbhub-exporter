-- Passive metadata observer. The adapter is supplied by our separate Cobalt plugin.
local Runtime = {}
local Observer = {}
Observer.__index = Observer
local MAX_RECENT, MAX_RELATIONS, MAX_PENDING = 128, 2048, 512
local TYPES = { ["nil"] = true, boolean = true, number = true, string = true,
    table = true, ["function"] = true, thread = true, userdata = true,
    Instance = true, Vector2 = true, Vector3 = true, CFrame = true, Color3 = true,
    UDim = true, UDim2 = true, EnumItem = true, Ray = true, Rect = true,
    BrickColor = true, NumberRange = true, NumberSequence = true, ColorSequence = true,
    buffer = true, unknown = true, ["..."] = true }

function Runtime.new(cfg, context)
    cfg = cfg or {}
    return setmetatable({cfg = cfg, context = context, state = "unavailable",
        reason = "not_started", cleanup = nil, started = false,
        startedAt = context.startedAt or context.now(), window = math.max(0, tonumber(cfg.correlationWindowSeconds) or 2),
        calls = 0, skipped = 0, counts = {}, recentGui = {}, recentRemote = {},
        links = {}, temporalRelations=0, droppedRelations = 0, pending = {}, pendingByOrigin = {}, droppedPending = 0,
        inFlightCalls = 0, raw = {}, rawHead = 1, rawTail = 0,
        rawPeak = 0, rawLost = 0, rawBusy = false, unresolvedCalls = 0}, Observer)
end

local function elapsed(self)
    return math.max(0, self.context.now() - self.startedAt)
end

local function addRecent(list, row)
    list[#list + 1] = row
    if #list > MAX_RECENT then table.remove(list, 1) end
end

local function correlate(self, gui, remote)
    if not gui.sequence or not remote.sequence then return end
    local delta = remote.elapsedSeconds - gui.elapsedSeconds
    if math.abs(delta) > self.window then return end
    local row={kind = "temporal_association", causal = false,
        guiSequence = gui.sequence, remoteSequence = remote.sequence,
        guiInstanceId = gui.instanceId, remoteInstanceId = remote.instanceId,
        guiEventType = gui.eventType, toStateId = gui.toStateId, deltaSeconds = delta}
    if type(self.context.emitRelation)=="function"then
        local ok,sequence=pcall(self.context.emitRelation,row)
        if ok and sequence then self.temporalRelations=self.temporalRelations+1
        else self.droppedRelations=self.droppedRelations+1 end
    elseif #self.links<MAX_RELATIONS then self.links[#self.links+1]=row;self.temporalRelations=self.temporalRelations+1
    else self.droppedRelations=self.droppedRelations+1 end
end

function Observer:noteGuiAction(event)
    if type(event) ~= "table" then return end
    -- Transitions happen frequently without user interaction. Only opt into a
    -- particular transition explicitly; routine state snapshots are not actions.
    local eventType = event.event
    if eventType ~= "activated" and not (eventType == "gui_state_transition" and event.correlate == true) then return end
    local row = {sequence = event.sequence, instanceId = event.instanceId,
        eventType = eventType, toStateId = event.toStateId,
        elapsedSeconds = tonumber(event.elapsedSeconds) or elapsed(self)}
    for _, remote in ipairs(self.recentRemote) do correlate(self, row, remote) end
    addRecent(self.recentGui, row)
end

function Observer:_observe(metadata, remote, direction, origin, admitted)
    if (not admitted and self.state ~= "attached") or (direction ~= "Incoming" and direction ~= "Outgoing") then return false end
    local ok, identity = pcall(self.context.resolve, remote)
    local pathEvidence = "deferred_resolution"
    if not ok or type(identity) ~= "table" or not identity.instanceId then
        identity = admitted and admitted.cached or nil
        pathEvidence = "last_structural_observation"
    end
    local resolved = type(identity) == "table" and identity.instanceId ~= nil
    if not resolved and not admitted then self.skipped = self.skipped + 1; return false end
    metadata = type(metadata) == "table" and metadata or {}
    local count = tonumber(metadata.argumentCount) or 0
    if count ~= count or count < 0 or count == math.huge then count = 0 end
    count = math.floor(count)
    local types = {}
    if type(metadata.argumentTypes) == "table" then
        for i = 1, math.min(count, 32) do
            local kind = metadata.argumentTypes[i]
            types[i] = type(kind) == "string" and TYPES[kind] and kind or "unknown"
        end
    end
    if count > 32 then types[#types + 1] = "..." end
    local invokeKind = metadata.invokeKind
    if invokeKind ~= "Request" and invokeKind ~= "Callback" then invokeKind = nil end
    local caller, callerPathEvidence
    if origin ~= nil and resolved then
        local callerOk, value = pcall(self.context.resolve, origin)
        if callerOk and type(value) == "table" and value.instanceId then
            caller = value; callerPathEvidence = "deferred_resolution"
        elseif admitted and admitted.cachedCaller then
            caller = admitted.cachedCaller; callerPathEvidence = "last_structural_observation"
        end
    end
    local row = {instanceId = resolved and identity.instanceId or nil, robloxPath = resolved and identity.robloxPath or nil,
        className = resolved and identity.className or nil, direction = direction, argumentTypes = types,
        argumentCount = count, invokeKind = invokeKind, scriptId = caller and caller.scriptId or nil,
        callerInstanceId = caller and caller.instanceId or nil,
        evidence = "cobalt_observed", elapsedSeconds = admitted and admitted.elapsedSeconds or elapsed(self),
        sequence = admitted and admitted.sequence or nil, observedAtUtc = admitted and admitted.observedAtUtc or nil}
    if admitted then
        row.identityStatus = resolved and "resolved" or "unresolved"
        row.reason = not resolved and "deferred_identity_unavailable" or nil
        row.pathEvidence = resolved and pathEvidence or nil
        row.scopeBasis = resolved and (pathEvidence == "deferred_resolution" and "resolved_at_drain" or "last_known") or nil
        row.callerPathEvidence = caller and callerPathEvidence or nil
    end
    if admitted and type(self.context.canEmit) == "function" and not self.context.canEmit() then return false end
    local emitted, sequence = pcall(self.context.emit, row)
    if not emitted or not sequence then
        if admitted then self.rawProcessingFailed = true end
        if admitted and type(self.context.onRawProcessError) == "function" then pcall(self.context.onRawProcessError) end
        return false
    end
    self.calls = self.calls + 1
    if not resolved then self.unresolvedCalls = self.unresolvedCalls + 1; return true end
    local stats = self.counts[identity.instanceId]
    if not stats then
        stats = {instanceId = identity.instanceId, robloxPath = identity.robloxPath,
            className = identity.className, incoming = 0, outgoing = 0, signatures = {}, signatureCount = 0, omittedSignatures = 0, observedScriptLinks = {}}
        self.counts[identity.instanceId] = stats
    end
    local side = direction == "Incoming" and "incoming" or "outgoing"
    stats[side] = stats[side] + 1
    local key = direction .. "(" .. table.concat(types, ",") .. ")/" .. count
    if stats.signatures[key] then stats.signatures[key] = stats.signatures[key] + 1
    elseif stats.signatureCount < 48 then stats.signatures[key] = 1; stats.signatureCount = stats.signatureCount + 1
    else stats.omittedSignatures = stats.omittedSignatures + 1 end
    if caller and caller.scriptId then stats.observedScriptLinks[caller.scriptId] = true
    elseif origin ~= nil then
        local remoteId = identity.instanceId
        local accepted = self.pendingByOrigin[origin]
        if not (accepted and accepted[remoteId]) then
            if #self.pending < MAX_PENDING then
                if not accepted then accepted = {}; self.pendingByOrigin[origin] = accepted end
                accepted[remoteId] = true
                self.pending[#self.pending + 1] = {origin = origin, remoteId = remoteId}
            else
                -- Rejected keys are not retained, keeping the lookup bounded.
                -- This is an occurrence count, not an exact count of distinct pairs.
                self.droppedPending = self.droppedPending + 1
            end
        end
    end
    local observed = {sequence = sequence or row.sequence, elapsedSeconds = row.elapsedSeconds, instanceId = identity.instanceId}
    for _, gui in ipairs(self.recentGui) do correlate(self, gui, observed) end
    addRecent(self.recentRemote, observed)
    return true
end

function Observer:_admitRaw(metadata, remote, direction, origin)
        if direction ~= "Incoming" and direction ~= "Outgoing" then return end
        local size = self.rawTail - self.rawHead + 1
        if size >= (self.cfg.rawQueueLimit or 16384) then
            self.rawLost = self.rawLost + 1
            if type(self.context.onRawOverflow) == "function" then pcall(self.context.onRawOverflow) end
            return
        end
        metadata = type(metadata) == "table" and metadata or {}
        local count = tonumber(rawget(metadata, "argumentCount")) or 0
        if count ~= count or count < 0 or count == math.huge then count = 0 end
        count = math.floor(count)
        local originalTypes, types = rawget(metadata, "argumentTypes"), {}
        if type(originalTypes) == "table" then
            for i = 1, math.min(count, 32) do
                local kind = rawget(originalTypes, i)
                types[i] = type(kind) == "string" and TYPES[kind] and kind or "unknown"
            end
        end
        local invokeKind = rawget(metadata, "invokeKind")
        if invokeKind ~= "Request" and invokeKind ~= "Callback" then invokeKind = nil end
        local sequence, observedAtUtc, elapsedSeconds = self.context.reserve()
        local cached = type(self.context.peekRemote) == "function" and self.context.peekRemote(remote) or nil
        local cachedCaller = origin ~= nil and type(self.context.peekCaller) == "function" and self.context.peekCaller(origin) or nil
        self.rawTail = self.rawTail + 1
        self.raw[self.rawTail] = {metadata={argumentCount=count,argumentTypes=types,invokeKind=invokeKind},
            remote=remote, origin=origin, direction=direction, sequence=sequence,
            observedAtUtc=observedAtUtc, elapsedSeconds=elapsedSeconds, cached=cached, cachedCaller=cachedCaller}
        self.rawPeak = math.max(self.rawPeak, size + 1)
end

function Observer:observe(...)
    if self.state ~= "attached" then return end
    if self.cfg.deferRaw then
        local ok = pcall(self._admitRaw, self, ...)
        if not ok then
            self.rawLost = self.rawLost + 1
            if type(self.context.onRawError) == "function" then pcall(self.context.onRawError) end
        end
        return
    end
    self.inFlightCalls = self.inFlightCalls + 1
    local ok, result = pcall(self._observe, self, ...)
    self.inFlightCalls = self.inFlightCalls - 1
    if not ok then self.skipped = self.skipped + 1; return end
    return result
end

function Observer:inFlight() return self.inFlightCalls end

function Observer:drainRaw(maximum)
    if self.rawBusy or self.rawProcessingFailed then return false end
    self.rawBusy = true
    local limit = math.min(self.rawTail, self.rawHead + (maximum or math.huge) - 1)
    while self.rawHead <= limit do
        local item = self.raw[self.rawHead]
        local ok, emitted = pcall(self._observe, self, item.metadata, item.remote, item.direction, item.origin, item)
        if not ok or not emitted then
            if not ok then
                self.rawProcessingFailed = true
                if type(self.context.onRawProcessError) == "function" then pcall(self.context.onRawProcessError) end
            end
            self.rawBusy = false; return false
        end
        self.raw[self.rawHead] = nil
        self.rawHead = self.rawHead + 1
    end
    if self.rawHead > self.rawTail then
        self.raw = {}; self.rawHead = 1; self.rawTail = 0
    elseif self.rawHead > 8192 then
        -- Sustained traffic may never empty the FIFO; compact only on the pump,
        -- keeping storage bounded by the queue limit rather than session age.
        local compact, count = {}, 0
        for index = self.rawHead, self.rawTail do
            count = count + 1; compact[count] = self.raw[index]
        end
        self.raw = compact; self.rawHead = 1; self.rawTail = count
    end
    self.rawBusy = false
    return true
end
function Observer:rawPending() return self.rawTail - self.rawHead + 1 end

function Observer:start()
    if self.started then return self.state end
    self.started = true
    if self.cfg.observeRemotes == false then self.state = "disabled"; self.reason = "disabled_by_config"; return self.state end
    local env = (type(getgenv) == "function" and getgenv()) or _G
    local adapter = env and env.LesbhubCobaltAdapter
    if type(adapter) ~= "table" or adapter.version ~= 1 or type(adapter.subscribe) ~= "function" then
        self.state = "unavailable"; self.reason = "cobalt_adapter_unavailable"; return self.state
    end
    self.state = "attached"
    local ok, cleanup = pcall(adapter.subscribe, function(...) self:observe(...) end, function(reason)
        if self.state ~= "attached" then return end
        self.cleanup = nil
        self.state = "unloaded"
        self.reason = reason or "cobalt_unloaded"
    end)
    if self.state == "unloaded" then
        if ok and type(cleanup) == "function" then pcall(cleanup) end
    elseif not ok or type(cleanup) ~= "function" then
        self.state = "subscribe_failed"; self.reason = "cobalt_subscription_failed"
    elseif self.state == "attached" then
        self.cleanup = cleanup; self.reason = nil
    else
        pcall(cleanup)
    end
    return self.state
end

function Observer:stop()
    local cleanup = self.cleanup
    self.cleanup = nil
    if self.state == "attached" then self.state = "detached"; self.reason = "capture_stopped" end
    if cleanup then
        local ok = pcall(cleanup)
        if not ok then self.state = "cleanup_failed"; self.reason = "cobalt_unsubscribe_failed" end
    end
    return self.state
end

function Observer:summary()
    return {state = self.state, reason = self.reason, observedCalls = self.calls, temporalRelations=self.temporalRelations,
        skipped = self.skipped, unresolvedCalls = self.unresolvedCalls, pendingRawObservations = self:rawPending(),
        lostRawObservations = self.rawLost, rawPeak = self.rawPeak, droppedRelations = self.droppedRelations,
        droppedPendingCallers = self.droppedPending, pendingOverflowOccurrences = self.droppedPending,
        pendingOverflowCountMeaning = "occurrences_not_distinct_pairs", correlationWindowSeconds = self.window}
end

function Observer:remoteStats(resolvePending)
    if resolvePending~=false then
    for _, pending in ipairs(self.pending) do
        local ok, caller = pcall(self.context.resolve, pending.origin)
        local stats = self.counts[pending.remoteId]
        if ok and type(caller) == "table" and caller.scriptId and stats then
            stats.observedScriptLinks[caller.scriptId] = true
        end
    end
    self.pending = {}
    self.pendingByOrigin = {}
    end
    local rows = {}
    for _, row in pairs(self.counts) do
        local links = {}
        for id in pairs(row.observedScriptLinks) do links[#links + 1] = id end
        table.sort(links)
        rows[#rows + 1] = {instanceId = row.instanceId, robloxPath = row.robloxPath,
            className = row.className, incoming = row.incoming, outgoing = row.outgoing,
            signatures = row.signatures, omittedSignatures = row.omittedSignatures, observedScriptLinks = links}
    end
    table.sort(rows, function(a, b) return a.instanceId < b.instanceId end)
    return rows
end
function Observer:relations() return self.links end
return Runtime
