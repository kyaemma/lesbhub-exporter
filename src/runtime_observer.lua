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
        links = {}, droppedRelations = 0, pending = {}, pendingByOrigin = {}, droppedPending = 0}, Observer)
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
    if #self.links >= MAX_RELATIONS then self.droppedRelations = self.droppedRelations + 1; return end
    self.links[#self.links + 1] = {kind = "temporal_association", causal = false,
        guiSequence = gui.sequence, remoteSequence = remote.sequence,
        guiInstanceId = gui.instanceId, remoteInstanceId = remote.instanceId,
        guiEventType = gui.eventType, toStateId = gui.toStateId,
        deltaSeconds = delta}
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

function Observer:observe(metadata, remote, direction, origin)
    if self.state ~= "attached" or (direction ~= "Incoming" and direction ~= "Outgoing") then return end
    local ok, identity = pcall(self.context.resolve, remote)
    if not ok or type(identity) ~= "table" or not identity.instanceId then self.skipped = self.skipped + 1; return end
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
    local caller
    if origin ~= nil then
        local callerOk, value = pcall(self.context.resolve, origin)
        if callerOk and type(value) == "table" then caller = value end
    end
    local row = {instanceId = identity.instanceId, robloxPath = identity.robloxPath,
        className = identity.className, direction = direction, argumentTypes = types,
        argumentCount = count, invokeKind = invokeKind, scriptId = caller and caller.scriptId or nil,
        callerInstanceId = caller and caller.instanceId or nil,
        evidence = "cobalt_observed", elapsedSeconds = elapsed(self)}
    local emitted, sequence = pcall(self.context.emit, row)
    if not emitted then self.skipped = self.skipped + 1; return end
    self.calls = self.calls + 1
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
end

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
    return {state = self.state, reason = self.reason, observedCalls = self.calls,
        skipped = self.skipped, droppedRelations = self.droppedRelations,
        droppedPendingCallers = self.droppedPending, pendingOverflowOccurrences = self.droppedPending,
        pendingOverflowCountMeaning = "occurrences_not_distinct_pairs", correlationWindowSeconds = self.window}
end

function Observer:remoteStats()
    for _, pending in ipairs(self.pending) do
        local ok, caller = pcall(self.context.resolve, pending.origin)
        local stats = self.counts[pending.remoteId]
        if ok and type(caller) == "table" and caller.scriptId and stats then
            stats.observedScriptLinks[caller.scriptId] = true
        end
    end
    self.pending = {}
    self.pendingByOrigin = {}
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
