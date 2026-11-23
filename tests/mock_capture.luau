-- Luau CLI smoke test: mock Roblox Instances and executor file APIs.
-- Runs without Roblox, Potassium, WindUI or a live experience.
local writes = {}
local lastEncoded = nil
local folders = {}

local function instance(name, className, properties, children)
    local object = {Name = name, ClassName = className, _children = children or {}}
    for key, value in pairs(properties or {}) do object[key] = value end
    function object:GetChildren() return self._children end
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
local box = instance("UserInput", "TextBox", {
    Text = "private typed message", PlaceholderText = "Enter a code",
})
local chat = instance("Chat", "ScreenGui", nil, {
    instance("Message", "TextLabel", {Text = "do not capture"}),
})
local gui = instance("PlayerGui", "PlayerGui", nil, {label, box, chat})
local world = instance("Workspace", "Workspace", {StreamingEnabled = true}, {
    instance("Map", "Folder"), otherCharacter,
})
local storage = instance("ReplicatedStorage", "ReplicatedStorage", nil, {
    instance("Events", "Folder", nil, {
        instance("GameStarted", "RemoteEvent"),
    }),
    instance("APIKey", "StringValue", {Value = "short-secret"}),
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
local capture, err = Exporter.capture({
    label = "Criminality", category = "Criminality", variant = "Test",
    format = "json", targets = {PlayerGui = true, Workspace = true, ReplicatedStorage = true},
    textboxValues = false, stringValues = true,
    maxNodes = 500, chunkSize = 25, yieldEvery = 15,
})
assert(capture, err)
local m = capture.manifest
assert(m.status == "partial", "Workspace streaming must mark partial")
assert(m.stats.written > 0, "No records exported")
assert(m.stats.files == 3, "Expected one chunk per service")
assert(m.services.PlayerGui.passes == 1)
assert(m.privacy.excludesScriptSource == true)
local reasonFound = false
for _, r in ipairs(m.partialReasons) do
    if r == "workspace_streaming_enabled" then reasonFound = true end
end
assert(reasonFound, "Streaming limitation was not disclosed")

local seenLabel, seenBox, seenChat, seenCharacter, seenSecret = false, false, false, false, false
for path, value in pairs(writes) do
    if path:find("-p1-", 1, true) then
        for _, record in ipairs(value.records or {}) do
            if record.name == "Title" then
                seenLabel = true
                assert(record.properties.Text == "Welcome [player]", "Player alias not masked")
            elseif record.name == "UserInput" then
                seenBox = true
                assert(record.properties.Text == nil, "TextBox input leaked")
                assert(record.properties.PlaceholderText == "Enter a code")
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
assert(seenLabel and seenBox and seenSecret)
assert(not seenChat and not seenCharacter, "Chat or other players' character included")
print("Luau smoke test OK: " .. m.stats.written .. " records, " .. m.stats.files .. " chunks")
