-- Passive graph of GUI states that were actually observed by the exporter.
local Gui = {}
local Graph = {}
Graph.__index = Graph
local STATE_PROPERTIES = {"Visible", "Enabled", "Text", "Active", "Interactable",
    "Selected", "Selectable", "TextEditable", "ScrollingEnabled", "Playing"}

function Gui.new(cfg, context)
    cfg = cfg or {}
    local cacheEntries = math.max(0, math.floor(tonumber(cfg.guiStateCacheEntries) or 128))
    local cacheBytes = math.max(0, math.floor(tonumber(cfg.guiStateCacheBytes) or 1048576))
    return setmetatable({context = context, current = {}, buttonIds = {}, activations = {},
        states = {}, transitions = {}, transitionByKey = {}, previous = nil,
        cache = {}, cacheQueue = {}, cacheHead = 1, cacheTail = 0, cacheSize = 0, cacheBytes = 0,
        invalidIds = {}, invalidCount = 0,
        maxCacheEntries = cacheEntries, maxCacheBytes = cacheBytes,
        cacheEvictions = 0, uncachedStates = 0, writeErrors = 0, fingerprintErrors = 0,
        emitErrors = 0, commits = 0, revision = 0, committedRevision = -1}, Graph)
end

function Graph:observe(record)
    if type(record) ~= "table" or record.instanceId == nil then return false end
    local id = record.instanceId
    if record.operation == "remove" then
        if self.current[id] then self.current[id] = nil; self.revision = self.revision + 1 end
        if self.invalidIds[id] then self.invalidIds[id] = nil; self.invalidCount = self.invalidCount - 1 end
        return true
    end
    local properties = {}
    local source = type(record.properties) == "table" and record.properties or {}
    for _, name in ipairs(STATE_PROPERTIES) do
        local value = source[name]
        if type(value) == "boolean" or type(value) == "string" or type(value) == "number" then
            properties[name] = value
        end
    end
    local projected = {instanceId = id, parentInstanceId = record.parentInstanceId,
        className = record.className, path = record.path, properties = properties}
    local ok, fingerprint = pcall(self.context.fingerprint, projected)
    if not ok or type(fingerprint) ~= "string" then
        self.fingerprintErrors = self.fingerprintErrors + 1
        if not self.invalidIds[id] then self.invalidIds[id] = true; self.invalidCount = self.invalidCount + 1 end
        return false
    end
    if self.invalidIds[id] then self.invalidIds[id] = nil; self.invalidCount = self.invalidCount - 1 end
    local previous = self.current[id]
    if not previous or previous.fingerprint ~= fingerprint
        or previous.record.parentInstanceId ~= projected.parentInstanceId
        or previous.record.path ~= projected.path or previous.record.className ~= projected.className then
        self.current[id] = {record = projected, fingerprint = fingerprint}
        self.revision = self.revision + 1
    end
    if record.className == "TextButton" or record.className == "ImageButton" then
        self.buttonIds[id] = true
    end
    return true
end

function Graph:noteActivation(event)
    if type(event) ~= "table" or event.instanceId == nil then return end
    local id = event.instanceId
    self.activations[id] = (self.activations[id] or 0) + 1
end

local function sortedIds(current)
    local ids = {}
    for id in pairs(current) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        if type(a) == type(b) then return a < b end
        return tostring(a) < tostring(b)
    end)
    return ids
end

function Graph:commit(reason)
    if self.invalidCount > 0 then return nil end
    reason = type(reason) == "string" and reason or "observation"
    if self.previous and self.committedRevision == self.revision then
        self.commits = self.commits + 1
        self.states[self.previous].observations = self.states[self.previous].observations + 1
        return self.previous
    end
    -- Commit may yield at budget checkpoints; a later change must remain dirty.
    local revision = self.revision
    local ids = sortedIds(self.current)
    local snapshot = {}
    for index, id in ipairs(ids) do snapshot[index] = self.current[id] end
    local parts, records = {}, {}
    for index, id in ipairs(ids) do
        if index%128==0 and self.context.budget then self.context.budget:checkpoint("gui_state")end
        local item = snapshot[index]
        local fp = item.fingerprint
        local ident = type(id) .. ":" .. tostring(id)
        local parent = type(item.record.parentInstanceId) .. ":" .. tostring(item.record.parentInstanceId)
        local path = tostring(item.record.path or "")
        parts[#parts + 1] = tostring(#ident) .. ":" .. ident .. tostring(#parent) .. ":" .. parent
            .. tostring(#path) .. ":" .. path .. tostring(#fp) .. ":" .. fp
        records[#records + 1] = item.record
    end
    local key = table.concat(parts)
    local stateId = self.cache[key]
    if not stateId then
        stateId = #self.states + 1
        local path = string.format("gui/states/state%06d.json", stateId)
        local payload = {schemaVersion = 1, stateId = stateId, evidence = "observed_gui_state",
            elements = records}
        local ok, written = pcall(self.context.write, path, payload)
        if not ok or written ~= true then
            self.writeErrors = self.writeErrors + 1
            return nil
        end
        self.states[stateId] = {stateId = stateId, path = path, elementCount = #records,
            observations = 0, firstReason = reason}
        local bytes = #key
        if self.maxCacheEntries > 0 and bytes <= self.maxCacheBytes then
            while self.cacheSize >= self.maxCacheEntries or self.cacheBytes + bytes > self.maxCacheBytes do
                local oldest = self.cacheQueue[self.cacheHead]
                self.cacheQueue[self.cacheHead] = nil
                self.cacheHead = self.cacheHead + 1
                self.cache[oldest.key] = nil
                self.cacheSize = self.cacheSize - 1
                self.cacheBytes = self.cacheBytes - #oldest.key
                self.cacheEvictions = self.cacheEvictions + 1
            end
            self.cache[key] = stateId
            if self.cacheSize == 0 then
                self.cacheQueue = {}; self.cacheHead = 1; self.cacheTail = 0
            elseif self.cacheHead > math.max(256, self.maxCacheEntries * 2) then
                local compact = {}
                for i = self.cacheHead, self.cacheTail do compact[#compact + 1] = self.cacheQueue[i] end
                self.cacheQueue = compact; self.cacheHead = 1; self.cacheTail = #compact
            end
            self.cacheTail = self.cacheTail + 1
            self.cacheQueue[self.cacheTail] = {key = key}
            self.cacheSize = self.cacheSize + 1
            self.cacheBytes = self.cacheBytes + bytes
        else
            self.uncachedStates = self.uncachedStates + 1
        end
    end
    self.commits = self.commits + 1
    self.states[stateId].observations = self.states[stateId].observations + 1
    if self.previous and self.previous ~= stateId then
        local event = {event = "gui_state_transition", fromStateId = self.previous,
            toStateId = stateId, reason = reason, evidence = "successive_observations",
            causal = false}
        local ok, sequence = pcall(self.context.emit, event)
        if not ok then self.emitErrors = self.emitErrors + 1 end
        local keyTransition = tostring(self.previous) .. ":" .. tostring(stateId) .. ":" .. reason
        local transition = self.transitionByKey[keyTransition]
        if not transition then
            transition = {fromStateId = self.previous, toStateId = stateId,
                reason = reason, evidence = "successive_observations", causal = false,
                count = 0, firstSequence = ok and sequence or nil}
            self.transitionByKey[keyTransition] = transition
            self.transitions[#self.transitions + 1] = transition
        end
        transition.count = transition.count + 1
        transition.lastSequence = ok and sequence or nil
    end
    self.previous = stateId
    self.committedRevision = revision
    return stateId
end

function Graph:summary()
    local buttons, activated, activationCount = 0, 0, 0
    for id in pairs(self.buttonIds) do
        buttons = buttons + 1
        if self.activations[id] then activated = activated + 1 end
    end
    for _, count in pairs(self.activations) do activationCount = activationCount + count end
    return {states = #self.states, transitions = #self.transitions, observations = self.commits,
        knownButtons = buttons, activatedKnownButtons = activated,
        unactivatedKnownButtons = buttons - activated, observedActivations = activationCount,
        cacheEntries = self.cacheSize, cacheBytes = self.cacheBytes,
        cacheEvictions = self.cacheEvictions, uncachedStates = self.uncachedStates,
        writeErrors = self.writeErrors, fingerprintErrors = self.fingerprintErrors,
        emitErrors = self.emitErrors, scope = "observed_only",
        unexplored = "Unactivated controls and unobserved or lazy interfaces remain unexplored."}
end

function Graph:index()
    local buttons = {}
    for id in pairs(self.buttonIds) do
        buttons[#buttons + 1] = {instanceId = id, activationCount = self.activations[id] or 0}
    end
    table.sort(buttons, function(a, b) return a.instanceId < b.instanceId end)
    return {schemaVersion = 1, scope = "observed_only", states = self.states,
        transitions = self.transitions, buttons = buttons, coverage = self:summary(),
        notes = {"Transitions reflect successive observed states, not proven causality.",
            "State changes between observations and unobserved interfaces may be missing.",
            "Evicted fingerprints can result in a new file for a previously observed state."}}
end
return Gui
