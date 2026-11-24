-- Passive graph of observed GUI projections. Schema 2 stores immutable deltas.
local Gui = {}
local Graph = {}
Graph.__index = Graph
local PROPERTIES = {"Visible", "Enabled", "Text", "Active", "Interactable", "Selected", "Selectable", "TextEditable", "ScrollingEnabled", "Playing"}

local function idsOf(map)
    local ids = {}
    for id in pairs(map) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) < type(b)
    end)
    return ids
end
local function scalar(value)
    local t = type(value)
    if t == "nil" then return "n" end
    local s = t == "number" and string.format("%.17g", value) or tostring(value)
    return t .. ":" .. #s .. ":" .. s
end
local function canonicalRecord(record)
    local p = {scalar(record.instanceId), scalar(record.parentInstanceId), scalar(record.className), scalar(record.path)}
    for _, name in ipairs(PROPERTIES) do p[#p + 1] = scalar(record.properties[name]) end
    return table.concat(p, "|")
end
local function canonical(map, ids)
    local out = {}
    for _, id in ipairs(ids) do
        local part = canonicalRecord(map[id])
        out[#out + 1] = #part .. ":" .. part
    end
    return table.concat(out)
end
local function same(a, b)
    if not a or not b or a.instanceId ~= b.instanceId or a.parentInstanceId ~= b.parentInstanceId
        or a.className ~= b.className or a.path ~= b.path then return false end
    for _, name in ipairs(PROPERTIES) do
        if a.properties[name] ~= b.properties[name] then return false end
    end
    return true
end
local function read(context, path)
    local ok, status, value = pcall(context.read, path)
    if not ok then return "error", status end
    if status ~= "ok" and status ~= "missing" and status ~= "error" then return "error", "invalid read status" end
    return status, value
end
-- Iterative replay bounds stack usage; the caller supplies disk reads.
function Gui.reconstruct(context, stateId)
    local chain, visited = {}, {}
    local id: any = stateId
    while id do
        if type(id) ~= "number" or id < 1 or id % 1 ~= 0 or visited[id] then return nil, "invalid state chain" end
        visited[id] = true
        local status, state = read(context, string.format("gui/states/state%06d.json", id))
        if status ~= "ok" or type(state) ~= "table" or state.schemaVersion ~= 2 or state.stateId ~= id
            or type(state.upserts) ~= "table" or type(state.removes) ~= "table"
            or type(state.elementCount) ~= "number" then return nil, "unreadable state " .. tostring(id) end
        if state.baseStateId ~= nil and (type(state.baseStateId) ~= "number" or state.baseStateId >= id) then
            return nil, "invalid base state"
        end
        chain[#chain + 1] = state
        id = state.baseStateId
    end
    local map = {}
    for i = #chain, 1, -1 do
        local state = chain[i]
        for _, removed in ipairs(state.removes) do map[removed] = nil end
        for _, record in ipairs(state.upserts) do
            if type(record) ~= "table" or record.instanceId == nil or type(record.properties) ~= "table" then
                return nil, "invalid projected record"
            end
            map[record.instanceId] = record
        end
        if #idsOf(map) ~= state.elementCount then return nil, "state element count mismatch" end
    end
    return map
end
function Gui.new(cfg, context)
    cfg = cfg or {}
    return setmetatable({context=context, current={}, committed={}, buttonIds={}, activations={}, states={},
        transitions={}, transitionByKey={}, previous=nil, revision=0, committedRevision=-1,
        invalidIds={}, invalidCount=0, commits=0, transitionCount=0, writeErrors=0, readErrors=0,
        fingerprintErrors=0, emitErrors=0, cacheEvictions=0, uncachedStates=0, diskReuses=0,
        stateBytes=0, fullSnapshotEquivalentBytes=0, pending=nil}, Graph)
end
function Graph:observe(record)
    if type(record) ~= "table" or record.instanceId == nil then return false end
    local id = record.instanceId
    if record.operation == "remove" then
        if self.current[id] then self.current[id] = nil; self.revision += 1 end
        if self.invalidIds[id] then self.invalidIds[id] = nil; self.invalidCount -= 1 end
        return true
    end
    local properties = {}
    local source = type(record.properties) == "table" and record.properties or {}
    for _, name in ipairs(PROPERTIES) do
        local value = source[name]
        if type(value) == "boolean" or type(value) == "string" or type(value) == "number" then properties[name] = value end
    end
    local projected = {instanceId=id, parentInstanceId=record.parentInstanceId, className=record.className,
        path=record.path, properties=properties}
    local ok, fingerprint = pcall(self.context.fingerprint, projected)
    if not ok or type(fingerprint) ~= "string" then
        self.fingerprintErrors += 1
        if not self.invalidIds[id] then self.invalidIds[id] = true; self.invalidCount += 1 end
        return false
    end
    if self.invalidIds[id] then self.invalidIds[id] = nil; self.invalidCount -= 1 end
    if not same(self.current[id], projected) then self.current[id] = projected; self.revision += 1 end
    if record.className == "TextButton" or record.className == "ImageButton" then self.buttonIds[id] = true end
    return true
end
function Graph:noteActivation(event)
    if type(event) ~= "table" or event.instanceId == nil then return end
    self.activations[event.instanceId] = (self.activations[event.instanceId] or 0) + 1
end
local function measure(context, payload)
    if type(context.measure) ~= "function" then return 0 end
    local ok, n = pcall(context.measure, payload)
    return ok and type(n) == "number" and n or 0
end
local function finishPending(self)
    local pending = self.pending
    if not pending then return true end
    local reconstructed = Gui.reconstruct(self.context, pending.descriptor.stateId)
    if not reconstructed or canonical(reconstructed, idsOf(reconstructed)) ~= pending.key then
        self.readErrors += 1; return false
    end
    local status, descriptor = read(self.context, pending.lookupPath)
    if status == "error" then self.readErrors += 1; return false end
    if status == "missing" then
        local wrote, result = pcall(self.context.write, pending.lookupPath, pending.descriptor)
        if not wrote or result ~= true then self.writeErrors += 1; return false end
    elseif type(descriptor) ~= "table" or descriptor.stateId ~= pending.descriptor.stateId
        or descriptor.digest ~= pending.descriptor.digest or descriptor.path ~= pending.descriptor.path
        or descriptor.schemaVersion ~= 2 then
        self.readErrors += 1; return false
    end
    self.states[pending.descriptor.stateId] = pending.state
    self.stateBytes += pending.stateBytes
    self.fullSnapshotEquivalentBytes += pending.fullBytes
    self.pending = nil
    return true
end
function Graph:commit(reason)
    if self.invalidCount > 0 then return nil end
    if not finishPending(self) then return nil end
    reason = type(reason) == "string" and reason or "observation"
    if self.previous and self.committedRevision == self.revision then
        self.commits += 1; self.states[self.previous].observations += 1; return self.previous
    end
    local revision, snapshot = self.revision, {}
    local ids = idsOf(self.current)
    for _, id in ipairs(ids) do snapshot[id] = self.current[id] end
    local key = canonical(snapshot, ids)
    local ok, digest = pcall(self.context.digest, key)
    if not ok or type(digest) ~= "string" or not digest:match("^[%w_%-]+$") then self.fingerprintErrors += 1; return nil end
    local slot, stateId = 1, nil
    while true do
        local lookupPath = "gui/states/lookup/" .. digest .. "/" .. slot .. ".json"
        local status, descriptor = read(self.context, lookupPath)
        if status == "error" then self.readErrors += 1; return nil end
        if status == "missing" then break end
        if type(descriptor) ~= "table" or descriptor.schemaVersion ~= 2 or descriptor.digest ~= digest
            or type(descriptor.stateId) ~= "number" or not self.states[descriptor.stateId]
            or descriptor.path ~= string.format("gui/states/state%06d.json", descriptor.stateId) then
            self.readErrors += 1; return nil
        end
        local candidate = Gui.reconstruct(self.context, descriptor.stateId)
        if not candidate then self.readErrors += 1; return nil end
        if canonical(candidate, idsOf(candidate)) == key then stateId = descriptor.stateId; self.diskReuses += 1; break end
        slot += 1
    end
    if not stateId then
        stateId = #self.states + 1
        local upserts, removes = {}, {}
        local baseline = not self.previous or (stateId - 1) % 64 == 0
        for index, id in ipairs(ids) do
            if index % 128 == 0 and self.context.budget then self.context.budget:checkpoint("gui_state") end
            if baseline or not same(self.committed[id], snapshot[id]) then upserts[#upserts + 1] = snapshot[id] end
        end
        if not baseline then
            for _, id in ipairs(idsOf(self.committed)) do if not snapshot[id] then removes[#removes + 1] = id end end
        end
        local path = string.format("gui/states/state%06d.json", stateId)
        local payload = {schemaVersion=2, stateId=stateId,
            evidence="observed_gui_state", upserts=upserts, removes=removes, elementCount=#ids}
        if not baseline then payload.baseStateId = self.previous end
        local descriptor = {schemaVersion=2, digest=digest, stateId=stateId, path=path}
        local lookupPath = "gui/states/lookup/" .. digest .. "/" .. slot .. ".json"
        local wrote, result = pcall(self.context.write, path, payload)
        if not wrote or result ~= true then self.writeErrors += 1; return nil end
        local all = {}; for _, id in ipairs(ids) do all[#all + 1] = snapshot[id] end
        self.pending = {lookupPath=lookupPath, descriptor=descriptor, key=key,
            state={stateId=stateId, path=path, elementCount=#ids, observations=0, firstReason=reason},
            stateBytes=measure(self.context, payload) + measure(self.context, descriptor),
            fullBytes=measure(self.context, {schemaVersion=1, stateId=stateId,
                evidence="observed_gui_state", elements=all})}
        if not finishPending(self) then return nil end
    end
    if self.previous and self.previous ~= stateId then
        local event = {event="gui_state_transition", fromStateId=self.previous, toStateId=stateId,
            reason=reason, evidence="successive_observations", causal=false}
        local emitted, sequence = pcall(self.context.emit, event)
        if not emitted or type(sequence) ~= "number" then self.emitErrors += 1; return nil end
        self.transitionCount += 1
        local transitionKey = tostring(self.previous) .. ":" .. tostring(stateId) .. ":" .. reason
        local transition = self.transitionByKey[transitionKey]
        if not transition then
            transition = {fromStateId=self.previous, toStateId=stateId, reason=reason,
                evidence="successive_observations", causal=false, count=0, firstSequence=sequence}
            self.transitionByKey[transitionKey] = transition; self.transitions[#self.transitions + 1] = transition
        end
        transition.count += 1; transition.lastSequence = sequence
    end
    self.commits += 1
    self.states[stateId].observations += 1
    self.previous = stateId; self.committed = snapshot; self.committedRevision = revision
    return stateId
end
function Graph:summary()
    local buttons, activated, activationCount = 0, 0, 0
    for id in pairs(self.buttonIds) do buttons += 1; if self.activations[id] then activated += 1 end end
    for _, count in pairs(self.activations) do activationCount += count end
    return {states=#self.states, transitions=self.transitionCount, transitionKinds=#self.transitions, observations=self.commits,
        knownButtons=buttons, activatedKnownButtons=activated, unactivatedKnownButtons=buttons-activated,
        observedActivations=activationCount, cacheEntries=0, cacheBytes=0, cacheEvictions=0, uncachedStates=#self.states,
        writeErrors=self.writeErrors, readErrors=self.readErrors, fingerprintErrors=self.fingerprintErrors,
        emitErrors=self.emitErrors, diskReuses=self.diskReuses, stateBytes=self.stateBytes,
        byteMeasurementsAvailable=type(self.context.measure)=="function",
        fullSnapshotEquivalentBytes=self.fullSnapshotEquivalentBytes,
        savedBytes=self.fullSnapshotEquivalentBytes-self.stateBytes, scope="observed_only",
        unexplored="Unactivated controls and unobserved or lazy interfaces remain unexplored."}
end
function Graph:index()
    local buttons = {}
    for id in pairs(self.buttonIds) do buttons[#buttons + 1] = {instanceId=id, activationCount=self.activations[id] or 0} end
    table.sort(buttons, function(a,b) return a.instanceId < b.instanceId end)
    return {schemaVersion=2, scope="observed_only", states=self.states, transitions=self.transitions,
        buttons=buttons, coverage=self:summary(), notes={"Transitions reflect successive observed states, not proven causality.",
            "State changes between observations and unobserved interfaces may be missing.",
            "Transition sequences are queued; checkpoint durability is declared by the capture."}}
end
function Graph:checkpoint()
    if self.pending and not finishPending(self) then return false end
    local ok, result = pcall(self.context.write, "gui/states/index.json", self:index())
    if not ok or result ~= true then self.writeErrors += 1; return false end
    return true
end
return Gui
