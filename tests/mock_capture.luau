-- Luau CLI smoke test: mock Roblox Instances and executor file APIs.
-- Runs without Roblox, Potassium, WindUI or a live experience.
local writes = {}
local lastEncoded = nil
local rawWrites,encodedObjects={},{}
local encodedSerial=0
local folders = {}

local function instance(name, className, properties, children)
    local object = {
        Name = name, ClassName = className, Archivable = true,
        _children = children or {},
    }
    for key, value in pairs(properties or {}) do object[key] = value end
    function object:GetChildren() return self._children end
    function object:GetAttributes() return self._attributes or {} end
    function object:GetTags() return self._tags or {} end
    function object:IsA(kind)
        if kind == "GuiObject" then
            return self.ClassName == "Frame" or self.ClassName == "TextLabel"
                or self.ClassName == "TextButton" or self.ClassName == "TextBox"
        end
        if kind == "BasePart" then return self.ClassName == "Part" end
        return self.ClassName == kind
    end
    return object
end

local otherCharacter = instance("Alice", "Model", nil, {
    instance("HumanoidRootPart", "Part"),
})
local label = instance("Title", "TextLabel", {
    Text = "Welcome Alice", Visible = true,
})
local image = instance("Logo", "ImageLabel", {Image = "rbxassetid://1234567"})
local box = instance("UserInput", "TextBox", {
    Text = "private typed message", PlaceholderText = "Enter a code",
})
local chat = instance("Chat", "ScreenGui", nil, {
    instance("Message", "TextLabel", {Text = "do not capture"}),
})
local clientCode = instance("MenuController", "LocalScript", {Enabled = true})
local gameStarted = instance("GameStarted", "RemoteEvent")
gameStarted._attributes = {Tier = "standard", ApiKey = "MUST_NOT_EXPORT"}
gameStarted._tags = {"Network", "GameEvent"}
local gui = instance("PlayerGui", "PlayerGui", nil, {label, box, chat, image, clientCode})
local world = instance("Workspace", "Workspace", {StreamingEnabled = true}, {
    instance("Map", "Folder"), otherCharacter,
})
local storage = instance("ReplicatedStorage", "ReplicatedStorage", nil, {
    instance("Events", "Folder", nil, {
        gameStarted,
    }),
    instance("MinimumPrice", "IntConstrainedValue", {Value = 125, MinValue = 5, MaxValue = 200}),
    instance("AssetSound", "Sound", {SoundId = "rbxassetid://7654321"}),
    instance("APIKey", "StringValue", {Value = "short-secret"}),
    instance("BuildLabel", "StringValue", {Value = "modded-crim"}),
})

local http = {}
function http:JSONEncode(value)
    lastEncoded = value
    encodedSerial=encodedSerial+1
    local token="mock encoded payload "..encodedSerial
    encodedObjects[token]=value
    return token
end
local players = {
    LocalPlayer = {
        FindFirstChild = function(_, name)
            if name == "PlayerGui" then return gui end
            return nil
        end,
    },
}
local syntheticAssociations = {}
function players:GetPlayerFromCharacter(model) return syntheticAssociations[model] end
function players:GetPlayers()
    return {{Name = "Alice", DisplayName = "Alice", Character = otherCharacter}}
end

game = {
    PlaceId = 42, GameId = 11,
    GetService = function(_, name)
        if name == "Players" then return players end
        if name == "HttpService" then return http end
        if name == "Workspace" then return world end
        if name == "ReplicatedStorage" then return storage end
        error("missing mock service " .. tostring(name))
    end,
}
workspace = world
function makefolder(path) folders[path] = true end
function isfolder(path) return folders[path] == true end
function writefile(path, data)
    assert(type(data) == "string")
    writes[path] = lastEncoded
    rawWrites[path]=data
end
function readfile(path)return assert(rawWrites[path],"missing mock file")end
function isfile(path)return rawWrites[path]~=nil end
function http:JSONDecode(text)return assert(encodedObjects[text],"unknown mock JSON")end
task = {wait = function() end}
local realOs = os
local simulatedTime
local os = setmetatable({clock = function() return simulatedTime or realOs.clock() end}, {__index = realOs})

local Exporter = require("../src/engine")
-- Observe windows and public HTTP metadata are exercised in live tests, not
-- wall-clock sleeps in this deterministic, synthetic CLI fixture.
local captureEngine=Exporter.capture
Exporter.capture=function(options,...)
    options.runtimeWindowSeconds=0
    options.publicGameMetadata=false
    return captureEngine(options,...)
end
local capture, err = Exporter.capture({
    label = "Criminality", category = "Criminality", variant = "Test",
    format = "json", targets = {PlayerGui = true, Workspace = true, ReplicatedStorage = true},
    textboxValues = false, stringValues = true,
    maxNodes = 500, chunkSize = 25, yieldEvery = 15,
})
assert(capture, err)
local m = capture.manifest
assert(m.status == "partial", "Workspace streaming must mark partial")
assert(m.privacy.playerTrackingComplete == false and m.privacy.excludesOtherPlayerCharacters == false,
    "missing player signals must not claim complete privacy tracking")
assert(m.stats.written > 0, "No records exported")
assert(m.stats.files >= 6, "Expected separate category/service chunks")
assert(m.layout and m.layout.id == "categorized" and m.layout.version == 2)
assert(m.settings.organizedOutput == true)
assert(m.categories.scripts and m.categories.scripts.services.PlayerGui,
    "A UI LocalScript must be classified under scripts/PlayerGui")
assert(m.categories.gui and m.categories.gui.services.PlayerGui)
assert(m.categories.remotes and m.categories.remotes.services.ReplicatedStorage)
assert(m.categories.assets and m.categories.assets.services.ReplicatedStorage)
assert(m.categories.world and m.categories.world.services.Workspace)
local categoryFiles = 0
local categoryRecords = 0
for category, info in pairs(m.categories) do
    categoryFiles = categoryFiles + info.files
    categoryRecords = categoryRecords + info.records
end
assert(categoryFiles == m.stats.files and categoryRecords == m.stats.written,
    "Category totals must reconcile with manifest")
assert(m.services.PlayerGui.passes == 1)
assert(m.privacy.excludesScriptSource == true)
local reasonFound = false
for _, r in ipairs(m.partialReasons) do
    if r == "workspace_streaming_enabled" then reasonFound = true end
end
assert(reasonFound, "Streaming limitation was not disclosed")

local seenLabel, seenBox, seenChat, seenCharacter, seenSecret = false, false, false, false, false
local seenAsset = false
local seenGuiScript = false
local sawNestedGui = false
local seenRemoteInfo, seenTypedValue = false, false
for path, value in pairs(writes) do
    if path:find("-p1-", 1, true) or path:find("/p1-", 1, true) then
        for _, record in ipairs(value.records or {}) do
            if record.name == "Title" then
                seenLabel = true
                assert(record.properties.Text == "Welcome [player]", "Player alias not masked")
                sawNestedGui = path:find("/gui/PlayerGui/p1-", 1, true) ~= nil
            elseif record.name == "UserInput" then
                seenBox = true
                assert(record.properties.Text == nil, "TextBox input leaked")
                assert(record.properties.PlaceholderText == "Enter a code")
            elseif record.name == "Logo" then
                seenAsset = true
                assert(record.properties.Image == "rbxassetid://1234567")
            elseif record.name == "GameStarted" then
                seenRemoteInfo = true
                local props = record.properties
                assert(props.Archivable == true)
                assert(props.RemoteInfo.family == "remote")
                assert(props.RemoteInfo.boundary == "client_server")
                assert(props.RemoteInfo.metadataSource == "roblox_class")
                assert(props.RemoteInfo.observedCalls == false)
                assert(props.Attributes.Tier == "standard")
                assert(props.Attributes.ApiKey == nil)
                assert(#props.Tags == 2)
            elseif record.name == "MinimumPrice" then
                seenTypedValue = true
                assert(record.properties.Value == 125)
                assert(record.properties.MinValue == 5)
                assert(record.properties.MaxValue == 200)
            elseif record.name == "MenuController" then
                seenGuiScript = path:find("/scripts/PlayerGui/p1-", 1, true) ~= nil
                assert(record.className == "LocalScript" and record.properties.Source == nil)
                assert(record.properties.Archivable == true)
                assert(record.properties.Enabled == true)
                assert(record.path == "PlayerGui/MenuController")
            elseif record.name == "Chat" then
                seenChat = true
            elseif record.name == "Alice" then
                seenCharacter = true
            elseif record.name == "APIKey" or record.name == "[sensitive]" then
                seenSecret = true
                assert(record.properties.Value == nil, "Sensitive StringValue leaked")
            end
            assert(record.properties.Source == nil, "Script Source leaked")
        end
    end
end
assert(seenLabel and seenBox and seenSecret and seenAsset)
assert(seenGuiScript and sawNestedGui, "GUI metadata and GUI scripts not split correctly")
assert(seenRemoteInfo and seenTypedValue, "Remote metadata or constrained values missing")
assert(m.stats.assetReferences >= 1, "Asset references not counted")
assert(not seenChat and not seenCharacter, "Chat or other players' character included")
local stringOnly, stringOnlyError = Exporter.capture({
    targets = {ReplicatedStorage = true}, worldProperties = false,
    stringValues = true, twoPassGui = false,
})
assert(stringOnly, stringOnlyError)
local foundBuildLabel = false
for filename, chunk in pairs(writes) do
    if filename:find(stringOnly.folder, 1, true) and (filename:find("-p1-", 1, true) or filename:find("/p1-", 1, true)) then
        for _, record in ipairs(chunk.records or {}) do
            if record.name == "BuildLabel" then
                foundBuildLabel = true
                assert(record.properties.Value == "modded-crim",
                    "Fast preset should keep explicitly allowed StringValue data")
            end
        end
    end
end
assert(foundBuildLabel, "Fixture StringValue was not captured")
-- Legacy budget keys are ignored. Deep hierarchies and >500 nodes must be
-- captured even when an older caller includes obsolete caps.
local chain = instance("RootChain", "Folder")
local cursor = chain
for i = 1, 46 do
    local nextNode = instance("Nested" .. tostring(i), "Folder")
    cursor._children = {nextNode}
    cursor = nextNode
end
local many = {chain}
for i = 1, 550 do
    table.insert(many, instance("Item" .. tostring(i), "Folder"))
end
world._children = many
local extra, extraErr = Exporter.capture({
    label = "LargeFixture",
    targets = {Workspace = true},
    twoPassGui = false,
    maxNodes = 500, maxDepth = 3, maxBytes = 1024,
    chunkSize = 25, yieldEvery = 25,
})
assert(extra, extraErr)
assert(extra.manifest.stats.visited >= 598, "A legacy node/depth cap truncated the export")
assert(extra.manifest.stats.written == extra.manifest.stats.visited)
assert(extra.manifest.settings.captureMode == "exhaustive")
print("Luau smoke test OK: uncapped traversal, " .. extra.manifest.stats.visited .. " records")

-- A single invalid text byte used to abort a full ReplicatedStorage export.
-- The engine now recursively isolates the bad chunk and repairs the record.
local function hasInvalidByte(value)
    if type(value) == "string" then
        return value:find(string.char(255), 1, true) ~= nil
    end
    if type(value) == "table" then
        for k, v in pairs(value) do
            if hasInvalidByte(k) or hasInvalidByte(v) then return true end
        end
    end
    return false
end
local previousEncode = http.JSONEncode
function http:JSONEncode(value)
    if hasInvalidByte(value) then error("JSON encode rejects invalid UTF-8") end
    return previousEncode(self, value)
end
table.insert(gui._children, instance("BadText", "TextLabel", {
    Text = "Invalid" .. string.char(255) .. "UTF8",
}))
local repaired, repairedError = Exporter.capture({
    targets = {PlayerGui = true}, twoPassGui = false,
    chunkSize = 25, yieldEvery = 20,
})
assert(repaired, repairedError)
assert(repaired.manifest.stats.written == repaired.manifest.stats.visited,
    "JSON recovery dropped objects")
assert(repaired.manifest.status == "partial",
    "Repaired encoding should be acknowledged in manifest")
local foundRecovery = false
for _, reason in ipairs(repaired.manifest.partialReasons) do
    if reason == "record_serialization_recovered" then foundRecovery = true end
end
assert(foundRecovery, "Encoding recovery not reported")
local savedBadText = false
for path, value in pairs(writes) do
    if path:find(repaired.folder, 1, true) and (path:find("-p1-", 1, true) or path:find("/p1-", 1, true)) then
        for _, record in ipairs(value.records or {}) do
            if record.name == "BadText" then
                savedBadText = true
                assert(record.properties.Text:find("~FF", 1, true) ~= nil,
                    "Invalid UTF-8 not escaped")
            end
        end
    end
end
assert(savedBadText, "The recovered record was lost")

-- Native saveinstance() must remain opt-in and executor-dependent.
local nativeOk, nativeError = Exporter.savePlace()
assert(nativeOk == false and type(nativeError) == "string")
saveinstance = function() return "mock-executor-place.rbxl" end
local savedNative, nativePath = Exporter.savePlace()
assert(savedNative and nativePath == "mock-executor-place.rbxl")
print("Luau smoke test OK: adaptive capture, JSON recovery and optional native save")

-- Universal continuous mode: a dynamically created menu appears after the
-- initial snapshot. Explicit Stop & Save triggers one final delta sweep.
local monitorControl = {cancelled = false, stopRequested = false}
local monitorStarted = false
local genericMenu = instance("InventoryPanel", "ScreenGui", nil, {
    instance("ConfirmAction", "TextButton", {Text = "Continue"}),
})
local monitored, monitorError = Exporter.capture({
    label = "GenericMenuFixture",
    targets = {PlayerGui = true},
    continuous = true, continuousInterval = 1,
    textboxValues = false, twoPassGui = true, chunkSize = 25,
}, function(info)
    if info.stage == "monitoring_start" then
        monitorStarted = true
        table.insert(gui._children, genericMenu)
        label.Text = "Updated during monitoring"
        for i, child in ipairs(gui._children) do
            if child == image then table.remove(gui._children, i); break end
        end
        monitorControl.stopRequested = true
    end
end, monitorControl)
assert(monitored, monitorError)
assert(monitorStarted, "Monitoring stage was never entered")
assert(monitored.manifest.status == "stopped", "User stop must not be a cancellation")
assert(monitored.manifest.endedReason == "user_stopped")
assert(monitored.manifest.settings.continuous == true)
assert(monitored.manifest.settings.captureMode == "continuous")
assert(monitored.manifest.stats.deltaRecords >= 4,
    "New, changed and removed GUI records should all produce deltas")
assert(monitored.manifest.stats.added >= 2)
assert(monitored.manifest.stats.updated >= 1)
assert(monitored.manifest.stats.removed >= 1)
assert(monitored.manifest.services.PlayerGui.passes >= 2)
local foundMenu = false
local foundButton = false
local foundUpdated = false
local foundRemoved = false
for filename, chunk in pairs(writes) do
    if filename:find(monitored.folder, 1, true) and (filename:find("-p2-", 1, true) or filename:find("/p2-", 1, true)) then
        for _, record in ipairs(chunk.records or {}) do
            if record.name == "InventoryPanel" and record.operation == "add" then
                foundMenu = true
            elseif record.name == "ConfirmAction" and record.operation == "add" then
                foundButton = record.properties.Text == "Continue"
            elseif record.name == "Title" and record.operation == "update" then
                foundUpdated = record.properties.Text == "Updated during monitoring"
            elseif record.name == "Logo" and record.operation == "remove" then
                foundRemoved = true
            end
        end
    end
end
assert(foundMenu and foundButton and foundUpdated and foundRemoved,
    "Final delta must capture added, updated and removed GUI objects")
assert(not monitorControl.cancelled, "Stop & Save must not trigger Cancel")
print("Luau continuous smoke OK: generic menu deltas, no hardcoded names, stopped manifest")

-- Legacy flat mode must preserve its original naming and must not overwrite
-- chunks from different categories in the same service/pass.
local flat, flatError = Exporter.capture({
    label = "LegacyFixture", organizedOutput = false,
    targets = {PlayerGui = true, ReplicatedStorage = true},
    chunkSize = 25, yieldEvery = 20,
})
assert(flat, flatError)
assert(flat.manifest.layout.id == "flat")
assert(flat.manifest.settings.organizedOutput == false)
local flatFiles = 0
for filename in pairs(writes) do
    if filename:find(flat.folder, 1, true)
        and filename:match("/%w+%-p1%-%d+%.json$") then
        flatFiles = flatFiles + 1
        assert(not filename:find("/gui/", 1, true) and not filename:find("/scripts/", 1, true))
    end
end
assert(flatFiles == flat.manifest.stats.files)
assert(flat.manifest.stats.written == flat.manifest.stats.visited)
print("Luau categorized layout OK: UI scripts, categorized files, flat compatibility")

-- v0.7: event identity must survive duplicate names, renames, same-path
-- replacement and objects that disappear before the baseline can visit them.
local function eventSignal()
    local callbacks = {}
    return {
        Connect = function(_, callback)
            callbacks[callback] = true
            return {Disconnect = function() callbacks[callback] = nil end}
        end,
        Fire = function(_, obj) for callback in pairs(callbacks) do callback(obj) end end,
        Count = function() local n = 0; for _ in pairs(callbacks) do n = n + 1 end; return n end,
    }
end
gui.DescendantAdded, gui.DescendantRemoving = eventSignal(), eventSignal()
local a = instance("Same", "NumberValue", {Value = 1})
local b = instance("Same", "NumberValue", {Value = 2})
a.Parent, b.Parent = gui, gui
gui._children = {a, b}
local replacement = instance("Same", "NumberValue", {Value = 4})
replacement.Parent = gui
local stopIdentity = {}
local timeline, timelineError = Exporter.capture({label = "IdentityFixture",
    targets = {PlayerGui = true}, continuous = true}, function(info)
    if info.stage == "service_start" and info.pass == 1 then
        local short = instance("Transient", "NumberValue", {Value = 17})
        short.Parent = gui
        gui.DescendantAdded:Fire(short)
        gui.DescendantRemoving:Fire(short)
        short.Parent = nil
    elseif info.stage == "monitoring_start" then
        a.Name = "Renamed"; a.Value = 3
        gui.DescendantRemoving:Fire(b)
        gui._children = {a, replacement}
        gui.DescendantAdded:Fire(replacement)
        stopIdentity.stopRequested = true
    end
end, stopIdentity)
assert(timeline, timelineError)
assert(gui.DescendantAdded:Count() == 0 and gui.DescendantRemoving:Count() == 0, "event listeners leaked")
local sequence, sameIds, shortOps = {}, {}, {}
local renamedId, originalId
for filename, chunk in pairs(writes) do
    if filename:find(timeline.folder, 1, true) and type(chunk) == "table" then
        for _, record in ipairs(chunk.records or {}) do
            assert(not sequence[record.sequence], "duplicate global sequence")
            sequence[record.sequence] = true
            if record.name == "Transient" then shortOps[record.operation] = record end
            if record.name == "Same" then
                sameIds[record.instanceId] = true
                if record.properties.Value == 1 then originalId = record.instanceId end
            elseif record.name == "Renamed" then renamedId = record.instanceId end
        end
    end
end
local sameCount = 0; for _ in pairs(sameIds) do sameCount = sameCount + 1 end
assert(sameCount == 3, "same names or same-path replacement conflated")
assert(renamedId == originalId, "rename changed Instance identity")
assert(shortOps.add and shortOps.remove and shortOps.add.sequence < shortOps.remove.sequence,
    "transient event disappeared during baseline")
assert(shortOps.add.properties.Value == 17, "transient properties read too late")
print("Luau identity OK: duplicate names, rename, replacement, short events, global order and cleanup")




-- A transient GUI in a later target must survive an earlier service's scan.
local crossControl={}
local cross,crossError=Exporter.capture({label="CrossServiceFixture",continuous=true,
    targets={ReplicatedStorage=true,PlayerGui=true},yieldEvery=10,chunkSize=25},function(info)
    if info.stage=="service_start" and info.service=="ReplicatedStorage" then
        local transient=instance("LaterServiceTransient","TextLabel",{Text="kept"})
        transient.Parent=gui
        gui.DescendantAdded:Fire(transient)
        gui.DescendantRemoving:Fire(transient)
        transient.Parent=nil
    elseif info.stage=="monitoring_start" then crossControl.stopRequested=true end
end,crossControl)
assert(cross,crossError)
local crossOps={}
for filename,chunk in pairs(writes)do
    if filename:find(cross.folder,1,true)and type(chunk)=="table"then
        for _,record in ipairs(chunk.records or{})do
            if record.name=="LaterServiceTransient"then crossOps[record.operation]=record end
        end
    end
end
assert(crossOps.add and crossOps.remove,"later-service transient events were discarded")
assert(crossOps.add.properties.Text=="kept")
print("Luau event batching OK: later-service transient records preserved")

-- A late root and an event from that service cannot change the service of
-- scripts subsequently visited in the active ReplicatedStorage scan.
local savedChildren = storage._children
storage._children = {}
for i = 1, 15 do storage._children[i] = instance("Padding" .. i, "Folder") end
local crossScript = instance("CrossServiceScript", "LocalScript", {Enabled = true})
function crossScript:GetDebugId() return "cross-service-script" end
storage._children[#storage._children + 1] = crossScript
local savedFind = players.LocalPlayer.FindFirstChild
local guiQueries = 0
players.LocalPlayer.FindFirstChild = function(_, name)
    if name ~= "PlayerGui" then return nil end
    guiQueries = guiQueries + 1
    if guiQueries == 1 then return nil end
    return gui
end
local lateControl = {}
local late, lateError = Exporter.capture({label = "LateRootFixture", continuous = true,
    targets = {ReplicatedStorage = true, PlayerGui = true}, yieldEvery = 10,
    chunkSize = 25, includeReconstructedCode = false}, function(info)
    if info.stage == "service_start" and info.service == "ReplicatedStorage" then
        local transient = instance("LateRootRemote", "RemoteEvent")
        transient._attributes = {Synthetic = "preserved"}
        function transient:GetDebugId() return "late-root-remote" end
        transient.Parent = gui
        gui.DescendantAdded:Fire(transient)
        gui.DescendantRemoving:Fire(transient)
        transient.Parent = nil
    elseif info.stage == "monitoring_start" then lateControl.stopRequested = true end
end, lateControl)
assert(late, lateError)
assert(guiQueries > 1 and late.manifest.services.PlayerGui.records > 0,
    "late root events were dropped before its baseline")
local scriptsIndex = writes[late.folder .. "/scripts/index.json"]
local discovered
for _, entry in ipairs(scriptsIndex.scripts) do
    if entry.name == "CrossServiceScript" then discovered = entry end
end
assert(discovered and discovered.service == "ReplicatedStorage",
    "cross-service events changed the scanned script's service")
local remoteIndex = writes[late.folder .. "/remotes/index.json"]
local removedRemote
for _, remote in ipairs(remoteIndex.remotes) do
    if remote.name == "LateRootRemote" then removedRemote = remote end
end
assert(removedRemote and removedRemote.removed and removedRemote.operation == "remove"
    and removedRemote.debugId == "late-root-remote"
    and removedRemote.properties.Attributes.Synthetic == "preserved"
    and removedRemote.properties.RemoteInfo.family == "remote",
    "removed remote must retain its last observed metadata")
assert(gui.DescendantAdded:Count() == 0 and gui.DescendantRemoving:Count() == 0)
storage._children = savedChildren
players.LocalPlayer.FindFirstChild = savedFind
print("Luau late-root OK: cross-service scripts and removed remote metadata")

local replacementGui = instance("PlayerGui", "PlayerGui", nil, {})
replacementGui.DescendantAdded, replacementGui.DescendantRemoving = eventSignal(), eventSignal()
local activeGui, switched, replacementControl = gui, false, {}
players.LocalPlayer.FindFirstChild = function(_, name) return name == "PlayerGui" and activeGui or nil end
local replacementCapture, replacementError = Exporter.capture({label = "RootReplacementFixture",
    continuous = true, continuousInterval = 1, targets = {PlayerGui = true}}, function(info)
    if info.stage == "monitoring_start" then activeGui = replacementGui; switched = true
    elseif switched and info.stage == "service_start" and info.service == "PlayerGui" then
        local transient = instance("ReplacementRootTransient", "TextLabel", {Text = "observed"})
        transient.Parent = replacementGui
        replacementGui.DescendantAdded:Fire(transient)
        replacementGui.DescendantRemoving:Fire(transient)
        transient.Parent = nil
        replacementControl.stopRequested = true
    end
end, replacementControl)
assert(replacementCapture, replacementError)
local replacementOps = {}
for filename, chunk in pairs(writes) do
    if filename:find(replacementCapture.folder, 1, true) and type(chunk) == "table" then
        for _, record in ipairs(chunk.records or {}) do
            if record.name == "ReplacementRootTransient" then replacementOps[record.operation] = true end
        end
    end
end
assert(replacementOps.add and replacementOps.remove, "replacement root events disappeared")
assert(gui.DescendantAdded:Count() == 0 and gui.DescendantRemoving:Count() == 0
    and replacementGui.DescendantAdded:Count() == 0 and replacementGui.DescendantRemoving:Count() == 0,
    "root replacement leaked listeners")
players.LocalPlayer.FindFirstChild = savedFind
print("Luau replacement-root OK: events retained and listeners disconnected")

-- Track players added and characters respawned after capture starts.
local savedGetPlayers, savedWorldChildren, savedPlayerAdded = players.GetPlayers, world._children, players.PlayerAdded
local initialCharacter = instance("InitialCharacter", "Model", nil, {instance("HiddenInitial", "Folder")})
local respawnedCharacter = instance("RespawnedCharacter", "Model", nil, {instance("HiddenRespawn", "Folder")})
local joinedCharacter = instance("JoinedCharacter", "Model", nil, {instance("HiddenJoined", "Folder")})
local earlyCharacter = instance("EarlyCharacter", "Model", nil, {instance("HiddenEarly", "Folder")})
local localCharacter = instance("LocalCharacter", "Model", nil, {instance("VisibleLocal", "Folder")})
local existingPlayer = {Name = "ExistingPerson", DisplayName = "ExistingPerson", Character = initialCharacter,
    CharacterAdded = eventSignal()}
local joinedPlayer = {Name = "JoinedPerson", DisplayName = "JoinedDisplay", Character = nil,
    CharacterAdded = eventSignal()}
local nameChanges = {Name = eventSignal(), DisplayName = eventSignal(), Character = eventSignal()}
function joinedPlayer:GetPropertyChangedSignal(name) return nameChanges[name] end
local playerAdded = eventSignal()
players.PlayerAdded = playerAdded
players.GetPlayers = function() return {players.LocalPlayer, existingPlayer} end
players.LocalPlayer.Character = localCharacter
world._children = {initialCharacter, respawnedCharacter, joinedCharacter, earlyCharacter, localCharacter,
    instance("JoinedPersonPublicObject", "Folder"), instance("UpdatedDisplayPublicObject", "Folder")}
local privacyControl = {}
local privacyCapture, privacyError = Exporter.capture({label = "DynamicPrivacyFixture", continuous = true,
    targets = {Workspace = true}}, function(info)
    if info.stage == "service_start" and info.service == "Workspace" then
        existingPlayer.Character = respawnedCharacter
        existingPlayer.CharacterAdded:Fire(respawnedCharacter)
        players.PlayerAdded:Fire(joinedPlayer)
        syntheticAssociations[earlyCharacter] = joinedPlayer
        joinedPlayer.Character = joinedCharacter
        nameChanges.Character:Fire()
        joinedPlayer.DisplayName = "UpdatedDisplay"
        nameChanges.DisplayName:Fire()
    elseif info.stage == "monitoring_start" then privacyControl.stopRequested = true end
end, privacyControl)
assert(privacyCapture, privacyError)
local sawLocal, redactedCount = false, 0
for filename, chunk in pairs(writes) do
    if filename:find(privacyCapture.folder, 1, true) and type(chunk) == "table" then
        for _, record in ipairs(chunk.records or {}) do
            assert(record.name ~= "HiddenInitial" and record.name ~= "HiddenRespawn"
                and record.name ~= "HiddenJoined" and record.name ~= "HiddenEarly",
                "another player's character was exported")
            if record.name == "VisibleLocal" then sawLocal = true end
            if record.name == "[player]PublicObject" then redactedCount = redactedCount + 1 end
        end
    end
end
assert(sawLocal and redactedCount >= 2 and privacyCapture.manifest.privacy.excludesOtherPlayerCharacters,
    "local character or newly joined player redaction is incorrect")
assert(playerAdded:Count() == 0 and existingPlayer.CharacterAdded:Count() == 0
    and joinedPlayer.CharacterAdded:Count() == 0 and nameChanges.Character:Count() == 0
    and nameChanges.DisplayName:Count() == 0, "privacy listeners leaked on normal completion")
local oldWait = task.wait
task.wait = function() error("synthetic capture failure") end
local failed = Exporter.capture({targets = {Workspace = true}, yieldEvery = 10}, nil, {})
task.wait = oldWait
assert(not failed and playerAdded:Count() == 0 and existingPlayer.CharacterAdded:Count() == 0,
    "privacy listeners leaked after capture error")
players.PlayerAdded = savedPlayerAdded
players.GetPlayers = savedGetPlayers
players.LocalPlayer.Character = nil
world._children = savedWorldChildren
table.clear(syntheticAssociations)
print("Luau privacy tracking OK: joins, respawns, aliases, local character and cleanup")

-- One hour of simulated wall time, with no injected changes or observations.
local savedChildren, savedWait = gui._children, task.wait
local scriptFixture = instance("OneHourScript", "ModuleScript")
scriptFixture.Parent = gui
gui._children = {scriptFixture, instance("Idle", "TextLabel", {Text = "unchanged", Visible = true})}
gui._children[2].Parent = gui
local decompileCount = 0
decompile = function() decompileCount = decompileCount + 1; return "" end
simulatedTime = 100
task.wait = function(seconds) simulatedTime = simulatedTime + math.max(seconds or 0, 0.01) end
local hourStart, hourControl, startCount = nil, {}, 0
local idle, idleError = Exporter.capture({label = "OneHourIdle", targets = {PlayerGui = true},
    continuous = true, continuousInterval = 3, includeReconstructedCode = true}, function(info)
    if info.stage == "monitoring_start" then hourStart = simulatedTime; startCount = decompileCount end
    if info.stage == "monitoring" and hourStart and simulatedTime - hourStart >= 3600 then
        hourControl.stopRequested = true
    end
end, hourControl)
assert(idle, idleError)
assert(hourStart and simulatedTime - hourStart >= 3600 and startCount == 1 and decompileCount == startCount)
assert(idle.manifest.stats.deltaRecords == 0, "unchanged hour produced structural changes")
local idleRecords = 0
for filename, chunk in pairs(writes) do
    if filename:find(idle.folder, 1, true) and type(chunk) == "table" then
        for _, record in ipairs(chunk.records or {}) do
            idleRecords = idleRecords + 1
            assert(not record.operation, "unchanged hour emitted an operation")
        end
    end
end
assert(idleRecords == 3, "unchanged hour duplicated baseline records")
assert(gui.DescendantAdded:Count() == 0 and gui.DescendantRemoving:Count() == 0)
task.wait = savedWait; gui._children = savedChildren; simulatedTime = nil; decompile = nil
print("Luau simulated idle hour OK: three baseline records, zero changes and no repeat decompile")

-- A failed tree enumeration is not evidence that previously seen children vanished.
local originalGetChildren = gui.GetChildren
gui._children = {instance("Retained", "TextLabel", {Text = "before failure"})}
gui._children[1].Parent = gui
simulatedTime = 100
task.wait = function(seconds) simulatedTime = simulatedTime + math.max(seconds or 0, 0.01) end
local failureControl = {}
local failedScan, failedScanError = Exporter.capture({label = "IncompleteScan", targets = {PlayerGui = true},
    continuous = true, continuousInterval = 1}, function(info)
    if info.stage == "monitoring_start" then gui.GetChildren = function() error("synthetic enumeration failure") end end
    if info.stage == "monitoring" then failureControl.stopRequested = true end
end, failureControl)
assert(failedScan, failedScanError)
for filename, chunk in pairs(writes) do
    if filename:find(failedScan.folder, 1, true) and type(chunk) == "table" then
        for _, record in ipairs(chunk.records or {}) do
            assert(record.operation ~= "remove", "incomplete scan invented a removal")
        end
    end
end
gui.GetChildren = originalGetChildren

-- A saturated event queue stops explicitly and retains the already queued records.
gui._children = {}
local overflow, overflowError = Exporter.capture({label = "QueueOverflow", targets = {PlayerGui = true},
    continuous = true, eventQueueLimit = 2}, function(info)
    if info.stage == "monitoring_start" then
        for i = 1, 3 do
            local item = instance("Burst" .. i, "NumberValue", {Value = i})
            item.Parent = gui
            gui.DescendantAdded:Fire(item)
        end
    end
end, {})
assert(overflow, overflowError)
assert(table.find(overflow.manifest.partialReasons, "event_queue_overflow"), "overflow not reported")
local retained = 0
for filename, chunk in pairs(writes) do
    if filename:find(overflow.folder, 1, true) and type(chunk) == "table" then
        for _, record in ipairs(chunk.records or {}) do
            if record.name:match("^Burst") then retained = retained + 1 end
        end
    end
end
assert(retained == 2, "queue overflow lost already accepted events")
task.wait = savedWait; gui._children = savedChildren; simulatedTime = nil
print("Luau incomplete scan and bounded event queue OK")

-- Simulate executor wrappers interned only weakly outside the capture.
local wrapperCache = setmetatable({}, {__mode = "v"})
local backing = instance("WeakWrapper", "NumberValue", {Value = 9})
backing.Parent = gui
local present = true
gui.GetChildren = function()
    if not present then return {} end
    local wrapper = wrapperCache[1]
    if not wrapper then
        wrapper = setmetatable({}, {__index = backing})
        wrapperCache[1] = wrapper
    end
    return {wrapper}
end
simulatedTime = 100
task.wait = function(seconds) simulatedTime = simulatedTime + math.max(seconds or 0, 0.01) end
local wrapperControl, wrapperCycles = {}, 0
local anchoredAtStart, anchoredAfterScan, releasedAfterRemove
local wrapperResult, wrapperError = Exporter.capture({label = "WeakWrapperFixture", targets = {PlayerGui = true},
    continuous = true, continuousInterval = 1}, function(info)
    if info.stage == "monitoring_start" then
        collectgarbage("collect")
        anchoredAtStart = wrapperCache[1] ~= nil
    elseif info.stage == "monitoring" then
        wrapperCycles = wrapperCycles + 1
        if wrapperCycles == 1 then
            collectgarbage("collect")
            anchoredAfterScan = wrapperCache[1] ~= nil
            present = false
        elseif wrapperCycles == 2 then
            collectgarbage("collect")
            releasedAfterRemove = wrapperCache[1] == nil
            wrapperControl.stopRequested = true
        end
    end
end, wrapperControl)
assert(wrapperResult, wrapperError)
assert(anchoredAtStart and anchoredAfterScan, "live wrapper was not anchored")
assert(releasedAfterRemove, "removed wrapper retained after tombstone")
local wrapperIds, wrapperAdds, wrapperRemoves = {}, 0, 0
for filename, chunk in pairs(writes) do
    if filename:find(wrapperResult.folder, 1, true) and type(chunk) == "table" then
        for _, record in ipairs(chunk.records or {}) do
            if record.name == "WeakWrapper" then
                wrapperIds[record.instanceId] = true
                if record.operation == "add" then wrapperAdds = wrapperAdds + 1 end
                if record.operation == "remove" then wrapperRemoves = wrapperRemoves + 1 end
            end
        end
    end
end
local wrapperIdCount = 0; for _ in pairs(wrapperIds) do wrapperIdCount = wrapperIdCount + 1 end
assert(wrapperIdCount == 1 and wrapperAdds == 0 and wrapperRemoves == 1,
    "weak wrapper GC created duplicate identity or structural changes")
gui.GetChildren = originalGetChildren; task.wait = savedWait; gui._children = savedChildren; simulatedTime = nil
print("Luau weak-wrapper identity OK: stable while live, released after removal")

-- Structural signal while sidecars are being written must defer publication.
local realWritefile = writefile
local checkpointControl, injected, checkpointAtStart = {}, false, false
local checkpointChild = instance("CheckpointArrival", "TextLabel", {Text = "new"})
checkpointChild.Parent = gui
gui._children = {}
simulatedTime = 100
task.wait = function(seconds) simulatedTime = simulatedTime + math.max(seconds or 0, 0.01) end
writefile = function(path, data)
    if not injected and path:find("checkpointarrival", 1, true) and path:match("/client%.json$") then
        injected = true
        gui._children = {checkpointChild}
        gui.DescendantAdded:Fire(checkpointChild)
    end
    return realWritefile(path, data)
end
local reentrantResult, reentrantError = Exporter.capture({label = "CheckpointArrival", targets = {PlayerGui = true},
    continuous = true, continuousInterval = 3}, function(info)
    if info.stage == "monitoring_start" then
        for path in pairs(rawWrites) do
            if path:find("checkpointarrival", 1, true) and path:match("/checkpoints/c%d+%.json$") then
                checkpointAtStart = true
            end
        end
    elseif info.stage == "monitoring" and simulatedTime >= 165 then checkpointControl.stopRequested = true end
end, checkpointControl)
writefile = realWritefile
assert(reentrantResult, reentrantError)
assert(injected and not checkpointAtStart, "published a checkpoint with a structural event still queued")
local checkpointPath = reentrantResult.folder .. "/checkpoints/c000001.json"
local checkpointPayload = http:JSONDecode(assert(rawWrites[checkpointPath], "checkpoint was not retried"))
assert(checkpointPayload.pending.structuralQueued == 0)
local savedGui
for _, snapshot in ipairs(checkpointPayload.snapshots) do
    if snapshot.path == "gui/index.json" then savedGui = http:JSONDecode(rawWrites[reentrantResult.folder .. "/" .. snapshot.snapshotPath]) end
end
local recordedArrival, arrivalSequence = false, nil
for _, item in ipairs(savedGui and savedGui.elements or {}) do
    if item.name == "CheckpointArrival" then
        recordedArrival = true
        arrivalSequence = item.sequence
        assert(item.sequence <= checkpointPayload.lastSequence)
    end
end
assert(recordedArrival, "retry omitted the admitted structural change")
local arrivalDurable = false
for _, artifact in ipairs(checkpointPayload.artifacts) do
    local raw = rawWrites[reentrantResult.folder .. "/" .. artifact.path]
    local chunk = raw and encodedObjects[raw]
    if type(chunk) == "table" then
        for _, record in ipairs(chunk.records or {}) do
            if record.name == "CheckpointArrival" and record.sequence == arrivalSequence then arrivalDurable = true end
        end
    end
end
assert(arrivalDurable, "checkpoint sidecar included a structural event missing from durable chunks")

-- A failed sidecar write must not publish a checkpoint until a successful retry.
local failOnce, checkpointAfterFailure, failureRetry = true, false, {}
gui._children = {}
simulatedTime = 100
writefile = function(path, data)
    if failOnce and path:find("checkpointfail", 1, true) and path:match("/client%.json$") then
        failOnce = false
        error("synthetic checkpoint sidecar failure")
    end
    return realWritefile(path, data)
end
local failedCheckpointResult, failedCheckpointError = Exporter.capture({label = "CheckpointFail", targets = {PlayerGui = true},
    continuous = true, continuousInterval = 3}, function(info)
    if info.stage == "monitoring_start" then
        for path in pairs(rawWrites) do
            if path:find("checkpointfail", 1, true) and path:match("/checkpoints/c%d+%.json$") then
                checkpointAfterFailure = true
            end
        end
    elseif info.stage == "monitoring" and simulatedTime >= 165 then failureRetry.stopRequested = true end
end, failureRetry)
writefile = realWritefile
assert(failedCheckpointResult, failedCheckpointError)
assert(not failOnce and not checkpointAfterFailure, "checkpoint published despite sidecar failure")
assert(rawWrites[failedCheckpointResult.folder .. "/checkpoints/c000001.json"], "failed checkpoint not retried")

local failJournal, journalFailureSeen, checkpointWithFailedFlush, flushRetry = true, false, false, {}
local flushButton = instance("FlushButton", "TextButton", {Text = "Run"})
flushButton.Parent = gui; flushButton.Activated = eventSignal(); gui._children = {flushButton}
simulatedTime = 100
writefile = function(path, data)
    if failJournal and path:find("checkpointflush", 1, true) and path:find("/journal/gui-actions/", 1, true) then
        journalFailureSeen = true
        error("synthetic journal write failure")
    end
    return realWritefile(path, data)
end
local flushedResult, flushedError = Exporter.capture({label = "CheckpointFlush", targets = {PlayerGui = true},
    continuous = true, continuousInterval = 3}, function(info)
    if info.stage == "service_done" and not journalFailureSeen then
        flushButton.Activated:Fire()
    elseif info.stage == "monitoring_start" then
        for path in pairs(rawWrites) do
            if path:find("checkpointflush", 1, true) and path:match("/checkpoints/c%d+%.json$") then
                checkpointWithFailedFlush = true
            end
        end
        failJournal = false
    elseif info.stage == "monitoring" and simulatedTime >= 110 then flushRetry.stopRequested = true end
end, flushRetry)
writefile = realWritefile
assert(flushedResult, flushedError)
assert(journalFailureSeen and not checkpointWithFailedFlush, "checkpoint published after journal flush failure")
assert(rawWrites[flushedResult.folder .. "/checkpoints/c000001.json"], "failed journal flush was not retried promptly")
task.wait = savedWait; gui._children = savedChildren; simulatedTime = nil
print("Luau checkpoint cut OK: reentrant event, failed sidecar and failed journal deferred")
