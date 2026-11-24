-- Appended to the deterministic Engine capture mock by build_mock_runtime_journal_e2e.py.
-- Exercises the actual Engine -> RuntimeObserver -> signature interning -> Journal path.
local occurrenceCount = 10000
local callback, disconnect
local e2eEnv = {}
function getgenv() return e2eEnv end
function typeof(value)
    if type(value) == "table" and type(value.ClassName) == "string" then return "Instance" end
    return type(value)
end
local function wireTree(root)
    local function visit(node, parent)
        node.Parent = parent
        function node:IsDescendantOf(ancestor)
            local current = self.Parent
            while current do
                if current == ancestor then return true end
                current = current.Parent
            end
            return false
        end
        for _, child in ipairs(node._children or {}) do visit(child, node) end
    end
    visit(root, nil)
end
wireTree(gui)
wireTree(storage)
local previousAdapter = e2eEnv.LesbhubCobaltAdapter
e2eEnv.LesbhubCobaltAdapter = {
    version = 1,
    subscribe = function(onObservation)
        callback = onObservation
        return function() disconnect = true; callback = nil end
    end,
}

local captureControl = {}
local captured, captureError = Exporter.capture({
    label = "RuntimeJournalE2E",
    targets = {PlayerGui = true, ReplicatedStorage = true},
    continuous = true,
    continuousInterval = 1,
    observeRemotes = true,
    observeGuiActions = false,
    includeReconstructedCode = false,
    textboxValues = false,
    chunkSize = 25,
    yieldEvery = 30,
}, function(info)
    if info.stage ~= "monitoring_start" then return end
    assert(type(callback) == "function", "Engine did not subscribe the runtime observer")
    local args = {n = 3, "PRIVATE_ARGUMENT", 42, {secret = "MUST_NOT_BE_STORED"}}
    local types = {"string", "number", "table"}
    for i = 1, occurrenceCount do
        -- This is an adapter callback shape, not genuine Cobalt traffic.
        callback({argumentCount = 3, argumentTypes = types, invokeKind = "Request"},
            game:GetService("ReplicatedStorage")._children[1]._children[1], "Outgoing",
            game:GetService("Players").LocalPlayer:FindFirstChild("PlayerGui")._children[5])
    end
    captureControl.stopRequested = true
end, captureControl)
e2eEnv.LesbhubCobaltAdapter = previousAdapter
assert(captured, captureError)
assert(captured.manifest.status == "stopped")
assert(disconnect and callback == nil, "observer subscription was not cleaned up")
assert(captured.manifest.diagnostics.remoteObservations == occurrenceCount)
assert(captured.manifest.dedup.eventsWritten >= occurrenceCount)

local base = captured.folder
local index = assert(writes[base .. "/journal/index.json"], "journal index was not written")
local signatures = assert(writes[base .. "/remotes/signatures.json"], "signature table was not written")
assert(index.version == 1 and signatures.version == 1)
local stream = assert(index.streams["remote-observations"])
assert(stream.events == occurrenceCount, "index event count lost callback occurrences")
assert(#signatures.signatures == 1, "identical call shape should intern one signature")
local definition = signatures.signatures[1]
assert(definition.signatureId == 1 and definition.argumentCount == 3)
assert(definition.invokeKind == "Request")
assert(definition.argumentTypes[1] == "string" and definition.argumentTypes[2] == "number"
    and definition.argumentTypes[3] == "table")

local expectedSequence, rowsSeen = nil, 0
local remoteId
for _, segment in ipairs(stream.segments) do
    local payload = assert(writes[base .. "/" .. segment.path], "indexed journal segment is missing")
    assert(payload.version == 1 and payload.stream == "remote-observations")
    assert(segment.count == #payload.rows)
    for _, row in ipairs(payload.rows) do
        if expectedSequence then assert(row.sequence == expectedSequence, "journal occurrence order has a gap") end
        expectedSequence = row.sequence + 1
        assert(row.direction == "Outgoing" and row.signatureId == 1)
        assert(row.evidence == "cobalt_observed")
        assert(type(row.instanceId) == "number" and row.instanceId > 0)
        if remoteId then assert(row.instanceId == remoteId) else remoteId = row.instanceId end
        assert(row.argumentCount == nil and row.argumentTypes == nil and row.invokeKind == nil,
            "verbose observation data escaped into compact journal rows")
        rowsSeen += 1
    end
    if #payload.rows > 0 then
        assert(segment.firstSequence == payload.rows[1].sequence)
        assert(segment.lastSequence == payload.rows[#payload.rows].sequence)
    end
end
assert(rowsSeen == occurrenceCount, "not every observer callback reached durable journal segments")

local function containsPrivate(value, seen)
    if type(value) == "string" then
        return value:find("PRIVATE_ARGUMENT", 1, true) ~= nil
            or value:find("MUST_NOT_BE_STORED", 1, true) ~= nil
    end
    if type(value) ~= "table" then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    for key, child in pairs(value) do
        if containsPrivate(key, seen) or containsPrivate(child, seen) then return true end
    end
    return false
end
assert(not containsPrivate(index) and not containsPrivate(signatures), "raw payload reached persisted observation metadata")
for _, segment in ipairs(stream.segments) do
    assert(not containsPrivate(writes[base .. "/" .. segment.path]), "raw payload reached journal segment")
end
print("Runtime journal E2E OK: 10000 observer occurrences, compact signature, ordered durable rows")

-- Exercise a persistent replacement PlayerGui plus rename/reparent, same-source
-- cloned modules and an add/remove transient in one Engine monitoring session.
local oldGui = gui
local groupA = instance("GroupA", "Folder")
local groupB = instance("GroupB", "Folder")
local moved = instance("MoveMe", "TextLabel", {Text = "before"})
local cloneA = instance("CloneA", "ModuleScript")
local cloneB = instance("CloneB", "ModuleScript")
function cloneA:GetDebugId() return "topology-clone-a" end
function cloneB:GetDebugId() return "topology-clone-b" end
groupA._children = {moved, cloneA, cloneB}
gui._children = {groupA, groupB}
wireTree(gui)
local topologyReplacement = instance("PlayerGui", "PlayerGui", nil, {
    instance("RebornScreen", "ScreenGui", nil, {
        instance("PersistentAfterReplacement", "TextLabel", {Text = "survives root swap"}),
    }),
})
topologyReplacement.DescendantAdded, topologyReplacement.DescendantRemoving = eventSignal(), eventSignal()
local activeRoot = gui
local previousFind = players.LocalPlayer.FindFirstChild
players.LocalPlayer.FindFirstChild = function(_, name)
    return name == "PlayerGui" and activeRoot or nil
end
decompile = function() return "return 'same cloned module source'" end
local topologyControl, replacementSeen = {}, false
local topology, topologyError = Exporter.capture({
    label = "PlayerGuiTopologyE2E",
    targets = {PlayerGui = true},
    continuous = true,
    continuousInterval = 1,
    observeRemotes = false,
    includeReconstructedCode = true,
    textboxValues = false,
    chunkSize = 25,
    yieldEvery = 30,
}, function(info)
    if info.stage == "monitoring_start" then
        moved.Name = "RenamedMoveMe"
        moved.Text = "after"
        groupA._children = {cloneA, cloneB}
        groupB._children = {moved}
        moved.Parent = groupB
        oldGui.DescendantRemoving:Fire(moved)
        oldGui.DescendantAdded:Fire(moved)
        local transient = instance("TopologyTransient", "TextLabel", {Text = "short lived"})
        transient.Parent = oldGui
        oldGui.DescendantAdded:Fire(transient)
        oldGui.DescendantRemoving:Fire(transient)
        transient.Parent = nil
        activeRoot = topologyReplacement
        replacementSeen = true
    elseif replacementSeen and info.stage == "service_done" and info.service == "PlayerGui" then
        topologyControl.stopRequested = true
    end
end, topologyControl)
decompile = nil
players.LocalPlayer.FindFirstChild = previousFind
assert(topology, topologyError)
assert(topology.manifest.status == "stopped")
assert(topology.manifest.diagnostics.remoteObservations == 0)
assert(topologyReplacement.DescendantAdded:Count() == 0
    and topologyReplacement.DescendantRemoving:Count() == 0)

local topologyBase = topology.folder
local scriptIndex = assert(writes[topologyBase .. "/scripts/index.json"])
local clones = {}
for _, entry in ipairs(scriptIndex.scripts or {}) do
    if entry.name == "CloneA" or entry.name == "CloneB" then clones[entry.name] = entry end
end
assert(clones.CloneA and clones.CloneB and clones.CloneA.scriptId ~= clones.CloneB.scriptId,
    "same-source ModuleScripts must remain distinct logical instances")
assert(clones.CloneA.outputPath == clones.CloneB.outputPath,
    "identical decompiled clone contents should share one physical output")

local sawPersistentReplacement, sawRename, sawTransientAdd, sawTransientRemove = false, false, false, false
local function containsName(value, wanted, seen)
    if type(value) ~= "table" then return false end
    seen = seen or {}
    if seen[value] then return false end
    seen[value] = true
    if value.name == wanted then return true end
    for _, child in pairs(value) do
        if containsName(child, wanted, seen) then return true end
    end
    return false
end
for path, value in pairs(writes) do
    if path:find(topologyBase, 1, true) and type(value) == "table" then
        if containsName(value, "PersistentAfterReplacement") then sawPersistentReplacement = true end
        for _, row in ipairs(value.records or {}) do
            if row.name == "RenamedMoveMe" then sawRename = true end
            if row.name == "TopologyTransient" and row.operation == "add" then sawTransientAdd = true end
            if row.name == "TopologyTransient" and row.operation == "remove" then sawTransientRemove = true end
        end
    end
end
assert(sawPersistentReplacement, "replacement PlayerGui persistent subtree was not captured")
assert(sawRename, "renamed instance did not appear under its new name")
assert(sawTransientAdd and sawTransientRemove, "short-lived GUI subtree events were lost")
assert(groupA._children[1] == cloneA and groupB._children[1] == moved,
    "fixture reparent operation was not applied")
print("PlayerGui topology E2E OK: replacement subtree, rename/reparent, clone dedup, transient pair")
