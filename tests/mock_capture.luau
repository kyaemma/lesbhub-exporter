-- Luau CLI smoke test: mock Roblox Instances and executor file APIs.
-- Runs without Roblox, Potassium, WindUI or a live experience.
local writes = {}
local lastEncoded = nil
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
    return "mock encoded payload"
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
end
task = {wait = function() end}

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
