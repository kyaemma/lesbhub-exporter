-- Optional Lesbhub Remote Observer plugin for Cobalt by upio.
-- Install separately in Cobalt/Plugins/. This original adapter uses the documented
-- plugin API and contains no Cobalt implementation. Cobalt is Apache-2.0,
-- copyright 2025 upio & devid; see its upstream LICENSE.md.
-- Passive metadata only: no raw arguments, remote replay/blocking, or uploads.
Cobalt.PluginData = {
    Name = "Lesbhub Remote Observer",
    Description = "Summarizes observed incoming/outgoing remotes as local metadata",
    Author = "Lesbhub",
    Version = "0.2.0",
    Game = "*",
}

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local BASE = "LesbhubExporter/cobalt-observations"
local ALLOWED_ROOTS = {
    ReplicatedStorage = true, ReplicatedFirst = true, StarterGui = true,
    PlayerGui = true, StarterPlayer = true, PlayerScripts = true,
    StarterPack = true, Workspace = true, Lighting = true,
    SoundService = true, Teams = true,
}

local running = false
local unsubscribe = nil
local startedAt = nil
local startedUtc = nil
local nextRemoteId = 0
local nextSequence = 0
local records = {}
local ids = setmetatable({}, {__mode = "k"})
local ignored = 0

local function safePath(instance)
    local names, seen = {}, {}
    local current = instance
    local player = Players.LocalPlayer
    while current and current ~= game do
        if seen[current] then return nil end
        seen[current] = true
        local ok, name, parent = pcall(function()
            return current.Name, current.Parent
        end)
        if not ok or type(name) ~= "string" or #name == 0 then return nil end
        -- Paths can include player names or volatile session strings. Only
        -- accept conservative alphanumeric structural names.
        if #name > 64 or name:find("[^%w_%-%s]") then return nil end
        names[#names + 1] = name:gsub("%s+", "_")
        if parent == game or (player and parent == player) then
            local root = names[#names]
            if not ALLOWED_ROOTS[root] then return nil end
            local forward = {}
            for i = #names, 1, -1 do forward[#forward + 1] = names[i] end
            return table.concat(forward, "/")
        end
        if player and (current == player or current == player.Character) then
            return nil
        end
        current = parent
    end
    return nil
end

local function topLevelTypes(args)
    if type(args) ~= "table" then return {}, 0 end
    local count = tonumber(args.n) or #args
    count = math.max(0, math.floor(count))
    local types = {}
    -- Only inspect top-level types; never retain values or inspect nested fields.
    local limit = math.min(count, 32)
    for i = 1, limit do
        local ok, kind = pcall(typeof, args[i])
        types[#types + 1] = ok and kind or "unknown"
    end
    if count > limit then types[#types + 1] = "..." end
    return types, count
end

local function observe(info, instance, direction)
    if not running then return end
    if direction ~= "Incoming" and direction ~= "Outgoing" then return end
    local okClass, class = pcall(function() return instance.ClassName end)
    if not okClass then return end
    local allowed = {
        RemoteEvent = true, RemoteFunction = true,
        UnreliableRemoteEvent = true, BindableEvent = true, BindableFunction = true,
    }
    if not allowed[class] then return end
    local path = safePath(instance)
    if not path then
        ignored = ignored + 1
        return
    end
    local id = ids[instance]
    local record
    if not id then
        nextRemoteId = nextRemoteId + 1
        id = nextRemoteId
        ids[instance] = id
        record = {
            id = id, path = path, className = class,
            incoming = 0, outgoing = 0,
            firstSequence = 0, lastSequence = 0,
            firstSeenUtc = "", lastSeenUtc = "",
            signatures = {}, signatureCount = 0, additionalSignatures = 0,
        }
        records[id] = record
    else
        record = records[id]
    end
    nextSequence = nextSequence + 1
    local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
    local key = direction == "Incoming" and "incoming" or "outgoing"
    record[key] = record[key] + 1
    if record.firstSequence == 0 then
        record.firstSequence = nextSequence
        record.firstSeenUtc = now
    end
    record.lastSequence = nextSequence
    record.lastSeenUtc = now
    local types, count = topLevelTypes(info and info.Arguments)
    local signature = direction .. "(" .. table.concat(types, ",") .. ")"
    local previous = record.signatures[signature]
    if previous then
        previous.count = previous.count + 1
    elseif record.signatureCount < 48 then
        record.signatures[signature] = {count = 1, direction = direction,
            argumentCount = count, argumentTypes = types}
        record.signatureCount = record.signatureCount + 1
    else
        record.additionalSignatures = record.additionalSignatures + 1
    end
end

local function ensureFolder(path)
    if type(makefolder) ~= "function" then return false end
    local current = ""
    for part in path:gmatch("[^/]+") do
        current = current == "" and part or current .. "/" .. part
        local exists = false
        if type(isfolder) == "function" then
            local ok, value = pcall(isfolder, current)
            exists = ok and value == true
        end
        if not exists then
            local ok = pcall(makefolder, current)
            if not ok then
                local found, value = pcall(function()
                    return type(isfolder) == "function" and isfolder(current)
                end)
                if not (found and value) then return false end
            end
        end
    end
    return true
end

local function writeSummary()
    if type(writefile) ~= "function" or not ensureFolder(BASE) then
        return false, "writefile/makefolder unavailable"
    end
    local list = {}
    for _, record in pairs(records) do
        local signatures = {}
        for _, item in pairs(record.signatures) do
            signatures[#signatures + 1] = item
        end
        table.sort(signatures, function(a, b)
            if a.direction ~= b.direction then return a.direction < b.direction end
            return a.argumentCount < b.argumentCount
        end)
        list[#list + 1] = {
            id = record.id, path = record.path, className = record.className,
            incoming = record.incoming, outgoing = record.outgoing,
            firstSequence = record.firstSequence, lastSequence = record.lastSequence,
            firstSeenUtc = record.firstSeenUtc, lastSeenUtc = record.lastSeenUtc,
            signatures = signatures,
            unclassifiedSignatureOccurrences = record.additionalSignatures,
        }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    local summary = {
        schemaVersion = 1,
        source = "cobalt_plugin",
        captureMode = "passive_summary",
        startedAtUtc = startedUtc,
        endedAtUtc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        durationSeconds = startedAt and (os.clock() - startedAt) or 0,
        game = {placeId = game.PlaceId, gameId = game.GameId},
        stats = {
            observedCalls = nextSequence,
            remoteInstances = #list,
            pathsSkipped = ignored,
        },
        capabilities = {
            incoming = true, outgoing = true,
            capturedArgumentValues = false,
            capturedNestedArgumentData = false,
            interceptedCallBehavior = false,
            replayedCalls = false,
            sentNetworkData = false,
        },
        notes = {
            "Only calls observed while this optional plugin was enabled are included.",
            "Names and paths are conservative; paths that could contain private data are skipped.",
            "Argument signatures are shallow type summaries, never actual values.",
            "This does not describe a remote's real server handler or complete parameter schema.",
        },
        remotes = list,
    }
    local ok, encoded = pcall(function() return HttpService:JSONEncode(summary) end)
    if not ok then return false, "could not encode metadata summary" end
    local stamp = os.date("!%Y%m%dT%H%M%SZ")
    local filename = BASE .. "/cobalt-" .. stamp .. "-" .. tostring(math.floor(os.clock() * 1000)) .. ".json"
    if not pcall(writefile, filename, encoded) then return false, "writefile failed" end
    return true, filename
end

local function stopAndSave()
    if not running then return false, "not recording" end
    running = false
    if unsubscribe then pcall(unsubscribe) end
    unsubscribe = nil
    return writeSummary()
end

local function start()
    if running then return false, "already recording" end
    if type(Cobalt.Spy) ~= "table"
        or type(Cobalt.Spy.InterceptExecutedCalls) ~= "function" then
        return false, "Cobalt spy API unavailable"
    end
    ids = setmetatable({}, {__mode = "k"})
    records = {}
    nextRemoteId, nextSequence, ignored = 0, 0, 0
    startedUtc = os.date("!%Y-%m-%dT%H:%M:%SZ")
    startedAt = os.clock()
    -- Cobalt owns executor compatibility; our callback does not suppress
    -- logs, block calls, alter arguments or invoke any remotes.
    local ok, cleanup = pcall(function()
        return Cobalt.Spy:InterceptExecutedCalls("All", function(info, instance, direction)
            pcall(observe, info, instance, direction)
            -- No return value. Let Cobalt and the game behave normally.
        end)
    end)
    if not ok or type(cleanup) ~= "function" then
        return false, "unable to subscribe to Cobalt spy"
    end
    unsubscribe = cleanup
    running = true
    return true, "recording"
end

-- A bridge owned by this plugin, not an upstream Cobalt global API. Each
-- subscription owns its interceptor; the standalone summary remains independent.
local env = (type(getgenv) == "function" and getgenv()) or _G
local adapterAlive = true
local subscriptions = {}
local adapter = {version = 1}
function adapter.subscribe(callback, onUnavailable)
    assert(adapterAlive, "Cobalt adapter unloaded")
    assert(type(callback) == "function", "callback required")
    assert(type(Cobalt.Spy) == "table" and type(Cobalt.Spy.InterceptExecutedCalls) == "function", "Cobalt spy API unavailable")
    local active = true
    local function handler(info, instance, direction)
        if not active then return end
        local types, count = topLevelTypes(type(info) == "table" and info.Arguments or nil)
        local invokeKind = type(info) == "table" and info.InvokeKind or nil
        if invokeKind ~= "Request" and invokeKind ~= "Callback" then invokeKind = nil end
        local origin = type(info) == "table" and info.Origin or nil
        if typeof(origin) ~= "Instance" then origin = nil end
        pcall(callback, {argumentTypes = types, argumentCount = count, invokeKind = invokeKind}, instance, direction, origin)
        -- Returning nothing preserves Cobalt's logging behavior.
    end
    local unsubscribe = Cobalt.Spy:InterceptExecutedCalls("All", handler)
    assert(type(unsubscribe) == "function", "Cobalt subscription failed")
    local function cleanup()
        if not active then return end
        active = false
        subscriptions[cleanup] = nil
        pcall(unsubscribe)
        -- Keep handler strongly reachable until cleanup, including weak registries.
        handler = nil
    end
    subscriptions[cleanup] = onUnavailable or false
    return cleanup
end
env.LesbhubCobaltAdapter = adapter

local controls = Cobalt.UI:CreatePluginSettings()
controls:AddLabel("Passive remote metadata (no argument values)", 15)
controls:AddLabel("Standalone summary is off until Start; exports subscribe automatically.", 13)
controls:CreateButton("Start observing", function()
    local ok, message = start()
    if ok then Cobalt.Sonner.success("Remote metadata recording started")
    else Cobalt.Sonner.error(message) end
end)
controls:CreateButton("Stop and save summary", function()
    local ok, message = stopAndSave()
    if ok then Cobalt.Sonner.success("Saved: " .. message)
    else Cobalt.Sonner.error(message) end
end)
Cobalt:BindToUnload(function()
    adapterAlive = false
    if env.LesbhubCobaltAdapter == adapter then env.LesbhubCobaltAdapter = nil end
    local pending = {}
    for cleanup, notify in pairs(subscriptions) do pending[#pending + 1] = {cleanup, notify} end
    for _, item in ipairs(pending) do
        item[1]()
        if type(item[2]) == "function" then pcall(item[2], "cobalt_unloaded") end
    end
    if running then
        local ok, message = stopAndSave()
        if not ok then warn("[Lesbhub Cobalt] Unable to save: " .. tostring(message)) end
    end
end)
