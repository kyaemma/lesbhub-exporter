-- Cobalt plugin compatibility test, with no Roblox executor or live remotes.
local seenCallbacks = {}
local unloadedCallback
local spyCallback
local spyCleanup = false
local active = false
local summary

local settings = {}
function settings:AddLabel(text) table.insert(seenCallbacks, {"label", text}) end
function settings:CreateButton(text, callback)
    seenCallbacks[text] = callback
end
Cobalt = {
    Spy = {
        InterceptExecutedCalls = function(_, direction, callback)
            assert(direction == "All")
            spyCallback = callback
            active = true
            return function()
                active = false
                spyCleanup = true
            end
        end,
    },
    UI = {CreatePluginSettings = function() return settings end},
    Sonner = {success = function() end, error = function(msg) error(msg) end},
    BindToUnload = function(_, callback) unloadedCallback = callback end,
}

local storage = {Name = "ReplicatedStorage", ClassName = "ReplicatedStorage"}
local privatePlayer = {Name = "Visitor", ClassName = "Player"}
local players = {LocalPlayer = privatePlayer}
local http = {}
function http:JSONEncode(obj)
    summary = obj
    return "{}"
end
game = {
    PlaceId = 100, GameId = 200,
    GetService = function(_, name)
        if name == "Players" then return players end
        if name == "HttpService" then return http end
        error(name)
    end,
}
storage.Parent = game
local remote = {Name = "Signal", ClassName = "RemoteEvent", Parent = storage}
local exotic = {Name = "Action_With_Player", ClassName = "UnreliableRemoteEvent",
    Parent = storage}
local hidden = {Name = "Visitor.Token", ClassName = "RemoteEvent", Parent = storage}
function makefolder(_path) end
function isfolder(_path) return true end
local written = {}
function writefile(path, data) written[path] = data end

local plugin = require("../integrations/cobalt/LesbhubRemoteObserver")
assert(Cobalt.PluginData.Game == "*" and Cobalt.PluginData.Name == "Lesbhub Remote Observer")
assert(type(unloadedCallback) == "function")
assert(not active and spyCallback == nil, "plugin must remain off until user consent")
assert(type(seenCallbacks["Start observing"]) == "function")
assert(type(seenCallbacks["Stop and save summary"]) == "function")
seenCallbacks["Start observing"]()
assert(active and type(spyCallback) == "function")
local secret = "SECRET_USER_DATA_SHOULD_NEVER_BE_EXPORTED"
local args = {12, secret, {userId = 123, password = "hidden"}, n = 3}
spyCallback({Arguments = args, Origin = "private-script", Function = "secret-source"},
    remote, "Outgoing")
spyCallback({Arguments = {true, n = 1}}, remote, "Incoming")
spyCallback({Arguments = {n = 0}}, exotic, "Outgoing")
spyCallback({Arguments = {secret, n = 1}}, hidden, "Outgoing")
assert(active)
seenCallbacks["Stop and save summary"]()
assert(not active and spyCleanup and summary)
assert(summary.source == "cobalt_plugin" and summary.captureMode == "passive_summary")
assert(summary.stats.observedCalls == 3, "Only public-root observations are counted")
assert(summary.stats.remoteInstances == 2)
assert(summary.stats.pathsSkipped == 1)
assert(summary.remotes[1].path == "ReplicatedStorage/Signal")
assert(summary.remotes[1].incoming == 1 and summary.remotes[1].outgoing == 1)
assert(summary.remotes[2].className == "UnreliableRemoteEvent")
assert(summary.remotes[1].signatures[1].argumentCount > 0)
local function containsSecret(node, depth)
    if depth > 20 then return false end
    if type(node) == "string" then
        return node:find(secret, 1, true) ~= nil or
            node:find("private-script", 1, true) ~= nil or
            node:find("hidden", 1, true) ~= nil
    end
    if type(node) == "table" then
        for k, value in pairs(node) do
            if containsSecret(k, depth + 1) or containsSecret(value, depth + 1) then
                return true
            end
        end
    end
    return false
end
assert(not containsSecret(summary, 0), "Raw argument values must never reach output")
assert(summary.capabilities.replayedCalls == false)
assert(summary.capabilities.capturedArgumentValues == false)
unloadedCallback()
assert(not active, "unload must not re-enable monitoring")
print("Cobalt plugin smoke test OK: passive counts, safe schema, cleanup")
