-- Synthetic-only exact-identity and path-resolution tests for Relations.
local Relations = require("../src/relations")

local relations = Relations.new({}, {budget = {checkpoint = function(self, stage)
    self.calls = (self.calls or 0) + 1
    assert(stage:find("relations", 1, true))
end}, knownIdentity = function(instanceId)
    return ({[20] = "Part", [21] = "Folder"})[instanceId]
end})
local function add(instanceId, category, className, path, parentInstanceId, properties, scriptId)
    assert(relations:register({instanceId = instanceId, category = category, className = className,
        path = path, parentInstanceId = parentInstanceId, properties = properties or {},
        scriptId = scriptId}, path:match("^([^/]+)")))
end

add(1, "scripts", "LocalScript", "PlayerScripts/Caller", nil, {}, "s1")
add(2, "scripts", "ModuleScript", "ReplicatedStorage/Package/Module", nil, {}, "s2")
add(3, "remotes", "RemoteEvent", "ReplicatedStorage/Events/Ready")
add(4, "gui", "ScreenGui", "PlayerGui/Main", nil)
add(5, "gui", "TextButton", "PlayerGui/Main/Start", 4)
add(6, "scripts", "ModuleScript", "ReplicatedStorage/Duplicate/Item", nil, {}, "s6")
add(7, "scripts", "ModuleScript", "ReplicatedStorage/Duplicate/Item", nil, {}, "s7")
add(8, "gui", "TextLabel", "PlayerGui/Homonym/Status")
add(9, "gui", "TextLabel", "StarterGui/Homonym/Status")
add(10, "scripts", "LocalScript", "PlayerScripts/Refs", nil, {
    Value = {kind = "InstanceRef", instanceId = 3, className = "RemoteEvent"},
    ExternalPart = {kind = "InstanceRef", instanceId = 20, className = "Part"},
    Unknown = {kind = "InstanceRef", instanceId = 99, className = "Folder"},
}, "s10")
add(11, "gui", "TextButton", "PlayerGui/Main/Start", nil) -- duplicate full path is ambiguous
assert(not relations:register({instanceId = 22, category = "world", className = "Part",
    path = "Workspace/Placed", properties = {
        ObjectValue = {kind = "InstanceRef", instanceId = 20, className = "Part"},
        Nested = {metadata = {kind = "InstanceRef", instanceId = 21, className = "Folder"}},
    }}, "Workspace"), "Non-catalog records must stay outside the lightweight path catalog")
assert(relations:register({instanceId = 12, category = "scripts", className = "ModuleScript",
    name = "Named", path = "ReplicatedStorage/Named", parentPath = "ReplicatedStorage",
    properties = {}, scriptId = "s12"}, "ReplicatedStorage"))
assert(relations:register({instanceId = 13, category = "scripts", className = "ModuleScript",
    name = "Named", path = "ReplicatedStorage/Named~2", parentPath = "ReplicatedStorage",
    properties = {}, scriptId = "s13"}, "ReplicatedStorage"))

local analyzed = relations:analyze({
    {instanceId = 1, scriptId = "s1", analysis = {
        imports = {
            {kind = "require", pathCandidate = "ReplicatedStorage/Package/Module", line = 4, byteOffset = 29,
                evidence = "static_text", confidence = "candidate"},
            {kind = "require", pathCandidate = "ReplicatedStorage/Duplicate/Item", line = 5, byteOffset = 40,
                evidence = "static_text", confidence = "candidate"},
            {kind = "require", pathCandidate = "Module", line = 6, byteOffset = 50,
                evidence = "static_text", confidence = "candidate"},
            {kind = "require", pathCandidate = "ReplicatedStorage/Unknown/Thing", line = 7, byteOffset = 60,
                evidence = "static_text", confidence = "candidate"},
            {kind = "require", pathCandidate = "ReplicatedStorage/Named", line = 10, byteOffset = 90,
                evidence = "static_text", confidence = "candidate"},
            {kind = "require", pathCandidate = nil, line = 12, byteOffset = 110,
                evidence = "static_text", confidence = "candidate"},
            {kind = "require", pathCandidate = "PlayerScripts/Caller", line = 13, byteOffset = 120,
                evidence = "static_text", confidence = "candidate"},
            {kind = "require", pathCandidate = nil, assetIdCandidate = "12345", line = 14,
                byteOffset = 130, evidence = "static_text", confidence = "candidate"},
        },
        remoteReferences = {{kind = "FireServer", pathCandidate = "ReplicatedStorage/Events/Ready",
            line = 8, byteOffset = 70, evidence = "static_text", confidence = "candidate"}},
        guiReferences = {{kind = "gui_path", pathCandidate = "PlayerGui/Main/Start",
            line = 9, byteOffset = 80, evidence = "static_text", confidence = "candidate"},
            {kind = "gui_path", pathCandidate = "StarterGui/Homonym/Status",
                line = 11, byteOffset = 100, evidence = "static_text", confidence = "candidate"}},
    }},
})
local observed = relations:addObserved({
    {instanceId = 3, observedScriptLinks = {"s1"}},
}, {
    {remoteInstanceId = 3, scriptId = "s1", direction = "outgoing"},
    {kind = "temporal_association", guiSequence = 201, remoteSequence = 202,
        guiInstanceId = 5, remoteInstanceId = 3, deltaSeconds = 0.35,
        guiEventType = "gui_state_transition", toStateId = 8, causal = false},
})

local byKey = {}
for _, edge in ipairs(observed.edges) do
    byKey[edge.kind .. ":" .. tostring(edge.pathCandidate or edge.property or edge.evidence) .. ":" ..
        tostring(edge.line or "")] = edge
end
local function find(kind, path, line)
    for _, edge in ipairs(observed.edges) do
        if edge.kind == kind and edge.pathCandidate == path and edge.line == line then return edge end
    end
end
assert(find("require", "ReplicatedStorage/Package/Module", 4).resolution == "resolved")
assert(find("require", "ReplicatedStorage/Package/Module", 4).toInstanceId == 2)
assert(find("require", "ReplicatedStorage/Duplicate/Item", 5).resolution == "ambiguous")
assert(find("require", "Module", 6).resolution == "unresolved", "Name-only lookup must never resolve")
assert(find("require", "ReplicatedStorage/Unknown/Thing", 7).resolution == "unresolved")
assert(find("require", "ReplicatedStorage/Named", 10).resolution == "ambiguous",
    "A ~2 sibling filename must remain ambiguous for the unsuffixed static path")
assert(find("require", nil, 12).resolution == "unresolved", "Dynamic references must stay unresolved")
assert(find("require", "PlayerScripts/Caller", 13).resolution == "unresolved",
    "require can resolve only to ModuleScript")
local assetCandidate
for _, edge in ipairs(analyzed.edges) do
    if edge.line == 14 then assetCandidate = edge end
end
assert(assetCandidate and assetCandidate.assetIdCandidate == "12345"
    and assetCandidate.resolution == "unresolved", "Asset ID hints must remain candidates")
assert(find("FireServer", "ReplicatedStorage/Events/Ready", 8).toInstanceId == 3)
assert(find("gui_path", "PlayerGui/Main/Start", 9).resolution == "ambiguous")
assert(find("gui_path", "StarterGui/Homonym/Status", 11).resolution == "resolved",
    "Full paths should disambiguate homonymous names")

local property, externalProperty, unknownProperty, structural, staticRemote, observedRemote, temporal
local worldProperty
for _, edge in ipairs(observed.edges) do
    if edge.kind == "property_reference" and edge.toInstanceId == 3 then property = edge end
    if edge.kind == "property_reference" and edge.toInstanceId == 20 then externalProperty = edge end
    if edge.kind == "property_reference" and edge.toInstanceId == 99 then unknownProperty = edge end
    if edge.kind == "instance_parent" and edge.fromInstanceId == 5 then structural = edge end
    if edge.kind == "FireServer" then staticRemote = edge end
    if edge.kind == "remote_call" then observedRemote = edge end
    if edge.kind == "property_reference" and edge.fromInstanceId == 22 then worldProperty = edge end
    if edge.kind == "temporal_association" then temporal = edge end
end
assert(property and property.resolution == "resolved" and property.toInstanceId == 3)
assert(externalProperty and externalProperty.resolution == "resolved"
    and externalProperty.targetClassName == "Part" and externalProperty.targetOutsideRelationshipCatalog)
assert(unknownProperty and unknownProperty.resolution == "unresolved")
assert(worldProperty and worldProperty.resolution == "resolved" and worldProperty.targetClassName == "Part",
    "Direct InstanceRef properties must be recorded for non-catalog metadata records")
assert(structural and structural.toInstanceId == 4 and structural.evidence == "instance_parent")
assert(staticRemote and staticRemote.evidence == "static_text" and staticRemote.causal == false)
assert(observedRemote and observedRemote.evidence == "cobalt_observed"
    and observedRemote.direction == "outgoing" and observedRemote.causal == false)
assert(temporal and temporal.resolution == "resolved" and temporal.fromInstanceId == 5
    and temporal.toInstanceId == 3 and temporal.guiSequence == 201 and temporal.remoteSequence == 202)
assert(temporal.guiEventType == "gui_state_transition" and temporal.toStateId == 8
    and temporal.evidence == "temporal_association" and temporal.causal == false)
assert(analyzed.summary.unresolved >= 2 and analyzed.summary.ambiguous >= 3)
assert(observed.summary.evidence.static_text and observed.summary.evidence.cobalt_observed)
assert(observed.summary.catalogEntries == 13,
    "World/value records must emit direct references without entering the path catalog")
print("Luau Relations mock OK: exact IDs, exact paths, ambiguity and evidence")
