-- Lesbhub Exporter V1 - client-side, read-only capture engine.
-- No script source, remote invocation, executor introspection, or network upload.
local Exporter = {}
Exporter.VERSION = "0.1.0"
Exporter.SCHEMA_VERSION = 1
Exporter.TARGETS = {
    "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "PlayerGui",
    "StarterPlayer", "PlayerScripts", "StarterPack", "Workspace",
    "Lighting", "SoundService", "Teams",
}

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local GUI_COMMON = {
    "Visible", "Position", "Size", "AnchorPoint", "LayoutOrder", "ZIndex",
    "BackgroundColor3", "BackgroundTransparency", "BorderSizePixel",
    "ClipsDescendants", "AutomaticSize", "Rotation",
}
local GUI_CLASSES = {
    ScreenGui = {"Enabled", "DisplayOrder", "IgnoreGuiInset", "ResetOnSpawn"},
    BillboardGui = {"Enabled", "AlwaysOnTop", "Size", "StudsOffset", "MaxDistance"},
    SurfaceGui = {"Enabled", "AlwaysOnTop", "CanvasSize", "PixelsPerStud"},
    ScrollingFrame = {"CanvasSize", "ScrollingEnabled", "ScrollBarThickness"},
    TextLabel = {"Text", "TextSize", "TextColor3", "TextTransparency", "Font", "RichText", "TextScaled", "TextWrapped"},
    TextButton = {"Text", "TextSize", "TextColor3", "TextTransparency", "Font", "RichText", "TextScaled", "TextWrapped", "AutoButtonColor"},
    TextBox = {"Text", "PlaceholderText", "PlaceholderColor3", "TextColor3", "TextSize", "Font", "ClearTextOnFocus", "MultiLine", "TextEditable"},
    ImageLabel = {"Image", "ImageColor3", "ImageTransparency", "ScaleType"},
    ImageButton = {"Image", "ImageColor3", "ImageTransparency", "ScaleType", "AutoButtonColor"},
    UIListLayout = {"FillDirection", "HorizontalAlignment", "VerticalAlignment", "SortOrder", "Padding"},
    UIGridLayout = {"CellSize", "CellPadding", "FillDirection", "SortOrder"},
    UICorner = {"CornerRadius"},
    UIPadding = {"PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom"},
    UIStroke = {"Color", "Thickness", "Transparency"},
    UIGradient = {"Color", "Rotation", "Transparency", "Enabled"},
    UIScale = {"Scale"},
    UIAspectRatioConstraint = {"AspectRatio", "AspectType", "DominantAxis"},
    UITextSizeConstraint = {"MaxTextSize", "MinTextSize"},
    UISizeConstraint = {"MaxSize", "MinSize"},
}
local OTHER_CLASSES = {
    Workspace = {"StreamingEnabled", "Gravity"},
    BasePart = {"Size", "Material", "Transparency", "Anchored", "CanCollide", "Color"},
    MeshPart = {"MeshId", "TextureID"},
    SpecialMesh = {"MeshId", "TextureId", "MeshType", "Scale"},
    Decal = {"Texture", "Transparency", "Color3"},
    Texture = {"Texture", "Transparency", "Color3"},
    Sound = {"SoundId", "Volume", "Looped"},
    Animation = {"AnimationId"},
    ParticleEmitter = {"Texture", "Enabled", "Rate"},
    ProximityPrompt = {"ActionText", "ObjectText", "Enabled", "HoldDuration", "MaxActivationDistance"},
    ClickDetector = {"MaxActivationDistance"},
    BoolValue = {"Value"},
    IntValue = {"Value"},
    NumberValue = {"Value"},
    StringValue = {"Value"},
    ObjectValue = {}, -- never traverse Value references
    Configuration = {},
}

local function clamp(value, lo, hi, default)
    local n = tonumber(value)
    if not n or n ~= n then n = default end
    return math.floor(math.max(lo, math.min(hi, n)))
end

local function slug(value)
    local s = tostring(value or ""):lower():gsub("[^%w%-_]", "-"):gsub("%-+", "-")
    s = s:gsub("^%-+", ""):gsub("%-+$", "")
    return s:sub(1, 48) ~= "" and s:sub(1, 48) or "uncategorized"
end

local function suspiciousName(value)
    local s = tostring(value):lower():gsub("[^%w]", "")
    return s:find("password", 1, true) or s:find("accesstoken", 1, true)
        or s:find("apikey", 1, true) or s:find("privatekey", 1, true)
        or s:find("credential", 1, true) or s:find("authtoken", 1, true)
        or s:find("sessiontoken", 1, true) or s:find("clientsecret", 1, true)
        or s:find("cookie", 1, true)
end

local function playerAliases()
    local aliases, characters, seen = {}, {}, {}
    local ok, users = pcall(function() return Players:GetPlayers() end)
    if not ok then return aliases, characters end
    for _, player in ipairs(users) do
        for _, name in ipairs({player.Name, player.DisplayName}) do
            if type(name) == "string" and #name >= 3 and not seen[name:lower()] then
                table.insert(aliases, name)
                seen[name:lower()] = true
            end
        end
        if player.Character then characters[player.Character] = true end
    end
    table.sort(aliases, function(a, b) return #a > #b end)
    return aliases, characters
end

local function scrubPlayers(value, aliases)
    local output = value
    for _, alias in ipairs(aliases) do
        local from = 1
        local lower = output:lower()
        local needle = alias:lower()
        local replacements = 0
        while replacements < 10 do
            local i, j = lower:find(needle, from, true)
            if not i then break end
            output = output:sub(1, i - 1) .. "[player]" .. output:sub(j + 1)
            lower = output:lower()
            from = i + 8
            replacements = replacements + 1
        end
    end
    return output
end

local function sanitizedString(value, cfg, state)
    if type(value) ~= "string" then return nil end
    local s = value
    if suspiciousName(s:sub(1, 64)) or s:lower():find("bearer ", 1, true) then
        state.redactions = state.redactions + 1
        return "[redacted]"
    end
    local before = s
    s = s:gsub("[%w%.%+%-_]+@[%w%.%-]+%.[%a]+", "[email]")
    s = s:gsub("discord%.gg/[%w%-_]+", "discord.gg/[invite]")
    s = s:gsub("discord%.com/invite/[%w%-_]+", "discord.com/invite/[invite]")
    s = s:gsub("https?://[^%s<>\"']+", "[url]")
    s = s:gsub("%d+%.%d+%.%d+%.%d+", "[ip]")
    s = s:gsub("[%w_%-]+", function(token)
        if #token > 48 then return "[long-id]" end
        return token
    end)
    s = scrubPlayers(s, state.aliases)
    if #s > cfg.maxString then s = s:sub(1, cfg.maxString) .. "[truncated]" end
    if s ~= before then state.redactions = state.redactions + 1 end
    return s
end

local function readName(instance, cfg, state)
    local ok, value = pcall(function() return instance.Name end)
    if not ok then return "[unreadable]" end
    if suspiciousName(value) then
        state.redactions = state.redactions + 1
        return "[sensitive]"
    end
    return sanitizedString(value, cfg, state) or "[invalid]"
end

local function serialize(value, cfg, state)
    local t = typeof(value)
    if t == "string" then return sanitizedString(value, cfg, state) end
    if t == "boolean" then return value end
    if t == "number" then
        return value == value and math.abs(value) ~= math.huge and value or nil
    end
    if t == "EnumItem" then return tostring(value) end
    if t == "Color3" then
        return {r = math.floor(value.R * 255 + 0.5), g = math.floor(value.G * 255 + 0.5), b = math.floor(value.B * 255 + 0.5)}
    end
    if t == "Vector2" then return {x = value.X, y = value.Y} end
    if t == "Vector3" then return {x = value.X, y = value.Y, z = value.Z} end
    if t == "UDim" then return {scale = value.Scale, offset = value.Offset} end
    if t == "UDim2" then
        return {xScale = value.X.Scale, xOffset = value.X.Offset, yScale = value.Y.Scale, yOffset = value.Y.Offset}
    end
    if t == "Rect" then
        return {min = {x = value.Min.X, y = value.Min.Y}, max = {x = value.Max.X, y = value.Max.Y}}
    end
    if t == "NumberRange" then return {min = value.Min, max = value.Max} end
    if t == "BrickColor" then return value.Name end
    -- Intentionally skip Instance, CFrame, connections, functions and unbounded tables.
    return nil
end

local function addError(state, code)
    state.errorCount = state.errorCount + 1
    if #state.errors < 40 then table.insert(state.errors, code) end
end

local ASSET_PROPERTIES = {
    Image = true, Texture = true, TextureId = true, TextureID = true,
    MeshId = true, SoundId = true, AnimationId = true, HoverImage = true,
}
local TEXT_PROPERTIES = {Text = true, PlaceholderText = true}

local function collectProperties(instance, cfg, state)
    local okClass, class = pcall(function() return instance.ClassName end)
    if not okClass then
        addError(state, "class_unavailable")
        return {}
    end
    local properties, wanted, unique = {}, {}, {}
    local function include(list, origin)
        for _, property in ipairs(list or {}) do
            if not unique[property] then
                unique[property] = origin
                table.insert(wanted, property)
            end
        end
    end

    if cfg.guiProperties then
        local okGui, isGui = pcall(function() return instance:IsA("GuiObject") end)
        if okGui and isGui then include(GUI_COMMON, "gui") end
    end
    if cfg.guiProperties or cfg.guiTexts or cfg.assets or cfg.textboxValues then
        include(GUI_CLASSES[class], "gui")
    end
    if cfg.worldProperties or cfg.assets or cfg.stringValues then
        local okPart, isPart = pcall(function() return instance:IsA("BasePart") end)
        if okPart and isPart then include(OTHER_CLASSES.BasePart, "world") end
        include(OTHER_CLASSES[class], "world")
    end

    local sensitiveStringValue = false
    if class == "StringValue" then
        local okName, name = pcall(function() return instance.Name end)
        sensitiveStringValue = not okName or suspiciousName(name) ~= nil
    end
    for _, property in ipairs(wanted) do
        local allowed
        if class == "TextBox" and property == "Text" then
            allowed = cfg.textboxValues
        elseif TEXT_PROPERTIES[property] then
            allowed = cfg.guiTexts
        elseif ASSET_PROPERTIES[property] then
            allowed = cfg.assets
        elseif property == "Value" then
            allowed = cfg.worldProperties and
                (class ~= "StringValue" or (cfg.stringValues and not sensitiveStringValue))
        elseif unique[property] == "gui" then
            allowed = cfg.guiProperties
        else
            allowed = cfg.worldProperties
        end
        if allowed then
            local ok, value = pcall(function() return instance[property] end)
            if not ok then
                addError(state, "property_unavailable:" .. class .. "." .. property)
            else
                local encoded = serialize(value, cfg, state)
                if encoded ~= nil then properties[property] = encoded end
            end
        end
    end
    return properties
end

local function isForbidden(instance, root, state)
    if state.characters[instance] then return true end
    if root == "PlayerGui" then
        local okName, rawName = pcall(function() return instance.Name end)
        local low = okName and tostring(rawName):lower() or ""
        if low == "chat" or low == "textchat" or low == "bubblechat" or low == "playerlist"
            or low == "lesbhub exporter" or low == "lesbhubexporter" then
            return true
        end
    end
    return false
end

local function rootInstance(serviceName)
    local localPlayer = Players.LocalPlayer
    if serviceName == "PlayerGui" or serviceName == "PlayerScripts" then
        if not localPlayer then return nil end
        return localPlayer:FindFirstChild(serviceName)
    end
    local ok, service = pcall(function() return game:GetService(serviceName) end)
    return ok and service or nil
end

local function createFolders(path)
    if type(makefolder) ~= "function" then return false end
    local partial = ""
    for part in path:gmatch("[^/]+") do
        partial = partial == "" and part or (partial .. "/" .. part)
        local exists = false
        if type(isfolder) == "function" then
            local ok, result = pcall(isfolder, partial)
            exists = ok and result == true
        end
        if not exists then
            local ok = pcall(makefolder, partial)
            if not ok then
                -- Some executors error on existing directories without isfolder.
                local okKnown, known = false, false
                if type(isfolder) == "function" then
                    okKnown, known = pcall(isfolder, partial)
                end
                if not (okKnown and known) then return false end
            end
        end
    end
    return true
end

local function csvEscape(value)
    local s = tostring(value or ""):gsub("\r", " "):gsub("\n", " ")
    return '"' .. s:gsub('"', '""') .. '"'
end

local function encodeChunk(records, format, service, pass)
    if format == "jsonl" then
        local lines = {}
        for _, record in ipairs(records) do table.insert(lines, HttpService:JSONEncode(record)) end
        return table.concat(lines, "\n") .. "\n"
    end
    if format == "csv" then
        local lines = {"path,parentPath,name,className,depth,properties_json"}
        for _, record in ipairs(records) do
            local values = {record.path, record.parentPath, record.name, record.className,
                record.depth, HttpService:JSONEncode(record.properties)}
            for i, value in ipairs(values) do values[i] = csvEscape(value) end
            table.insert(lines, table.concat(values, ","))
        end
        return table.concat(lines, "\n") .. "\n"
    end
    return HttpService:JSONEncode({
        schemaVersion = Exporter.SCHEMA_VERSION,
        service = service, pass = pass, records = records,
    })
end

local function normalizedConfig(input)
    local cfg = {}
    input = type(input) == "table" and input or {}
    cfg.label = tostring(input.label or "Unlabeled"):sub(1, 80)
    cfg.category = tostring(input.category or "Other"):sub(1, 80)
    cfg.variant = tostring(input.variant or "Default"):sub(1, 80)
    cfg.format = ({json = true, jsonl = true, csv = true})[input.format] and input.format or "json"
    cfg.targets = {}
    for _, service in ipairs(Exporter.TARGETS) do
        if type(input.targets) == "table" and input.targets[service] == true then
            cfg.targets[service] = true
        end
    end
    if type(input.targets) ~= "table" then
        for _, service in ipairs({"ReplicatedStorage", "ReplicatedFirst", "StarterGui", "PlayerGui", "StarterPlayer"}) do
            cfg.targets[service] = true
        end
    end
    cfg.guiTexts = input.guiTexts ~= false
    cfg.guiProperties = input.guiProperties ~= false
    cfg.worldProperties = input.worldProperties ~= false
    cfg.assets = input.assets ~= false
    cfg.textboxValues = input.textboxValues == true
    cfg.stringValues = input.stringValues == true
    cfg.twoPassGui = input.twoPassGui == true
    cfg.secondPassDelay = clamp(input.secondPassDelay, 1, 10, 3)
    cfg.maxNodes = clamp(input.maxNodes, 500, 50000, 15000)
    cfg.maxDepth = clamp(input.maxDepth, 2, 80, 28)
    cfg.yieldEvery = clamp(input.yieldEvery, 15, 500, 80)
    cfg.chunkSize = clamp(input.chunkSize, 25, 800, 200)
    cfg.maxString = clamp(input.maxString, 32, 1024, 256)
    cfg.maxBytes = clamp(input.maxBytes, 1024 * 1024, 64 * 1024 * 1024, 16 * 1024 * 1024)
    return cfg
end

local function notify(callback, stage, state, extra)
    if type(callback) == "function" then
        pcall(callback, {
            stage = stage, visited = state.visited, written = state.written,
            files = state.fileCount, bytes = state.bytes, service = extra,
        })
    end
end

function Exporter.capture(options, onProgress, control)
    local cfg = normalizedConfig(options)
    control = type(control) == "table" and control or {}
    if type(writefile) ~= "function" or type(makefolder) ~= "function" then
        return nil, "file APIs writefile/makefolder are required"
    end

    local time = os.date("!%Y%m%dT%H%M%SZ")
    local base = "LesbhubExporter/" .. slug(cfg.category) .. "/" .. slug(cfg.label) .. "/" ..
        slug(cfg.variant) .. "/" .. time .. "-" .. tostring(math.floor(os.clock() * 1000))
    if not createFolders(base) then return nil, "could not create export directory" end

    local aliases, characters = playerAliases()
    local state = {
        aliases = aliases, characters = characters, redactions = 0,
        visited = 0, written = 0, fileCount = 0, bytes = 0,
        errors = {}, errorCount = 0, partialReasons = {}, services = {},
        classes = {}, cancelled = false, stopped = false,
    }
    local function partial(reason)
        if not state.partialReasons[reason] then state.partialReasons[reason] = true end
    end
    local function stopCheck()
        if control.cancelled then
            state.cancelled = true
            state.stopped = true
            partial("user_cancelled")
        end
        return state.stopped
    end

    local function flush(records, serviceName, pass, part)
        if #records == 0 then return true end
        local okEncode, encoded = pcall(encodeChunk, records, cfg.format, serviceName, pass)
        if not okEncode then
            addError(state, "json_encode_failed:" .. serviceName)
            partial("encoding_error")
            return false
        end
        if state.bytes + #encoded > cfg.maxBytes then
            partial("byte_limit")
            return false
        end
        local ext = cfg.format == "json" and "json" or cfg.format
        local filename = string.format("%s/%s-p%d-%04d.%s", base, serviceName, pass, part, ext)
        local ok = pcall(writefile, filename, encoded)
        if not ok then
            addError(state, "write_failed:" .. serviceName)
            partial("write_error")
            return false
        end
        state.bytes = state.bytes + #encoded
        state.fileCount = state.fileCount + 1
        state.written = state.written + #records
        state.services[serviceName].records = state.services[serviceName].records + #records
        state.services[serviceName].files = state.services[serviceName].files + 1
        return true
    end

    local function scan(serviceName, pass)
        if stopCheck() then return end
        local root = rootInstance(serviceName)
        if not root then
            partial("missing_root:" .. serviceName)
            return
        end
        state.services[serviceName] = state.services[serviceName] or
            {visited = 0, records = 0, files = 0, passes = 0}
        state.services[serviceName].passes = state.services[serviceName].passes + 1
        local queue = {{instance = root, depth = 0, path = serviceName, parent = ""}}
        local head, enqueued, part = 1, 1, 1
        local records = {}
        local seen = setmetatable({}, {__mode = "k"})

        notify(onProgress, "scanning", state, serviceName)
        while head <= #queue do
            if stopCheck() then break end
            if state.visited >= cfg.maxNodes then partial("node_limit"); state.stopped = true; break end
            local entry = queue[head]
            queue[head] = false
            head = head + 1
            local obj = entry.instance
            if not seen[obj] then
                seen[obj] = true
                state.visited = state.visited + 1
                state.services[serviceName].visited = state.services[serviceName].visited + 1
                local okClass, class = pcall(function() return obj.ClassName end)
                if not okClass then class = "Unknown" end
                local name = entry.depth == 0 and serviceName or readName(obj, cfg, state)
                local properties = collectProperties(obj, cfg, state)
                table.insert(records, {
                    name = name, className = class, path = entry.path,
                    parentPath = entry.parent, depth = entry.depth, properties = properties,
                })
                state.classes[class] = (state.classes[class] or 0) + 1

                if #records >= cfg.chunkSize then
                    if not flush(records, serviceName, pass, part) then state.stopped = true; break end
                    records = {}
                    part = part + 1
                end

                local okChildren, children = pcall(function() return obj:GetChildren() end)
                if not okChildren then
                    addError(state, "children_unavailable:" .. class)
                    partial("children_unavailable")
                elseif entry.depth >= cfg.maxDepth then
                    if #children > 0 then partial("depth_limit") end
                else
                    local counts = {}
                    for _, child in ipairs(children) do
                        if not isForbidden(child, serviceName, state) then
                            local segment = readName(child, cfg, state)
                            local safeSegment = segment:gsub("[./\\]", "_")
                            local key = safeSegment -- disambiguate same-name siblings, regardless of ClassName
                            counts[key] = (counts[key] or 0) + 1
                            if enqueued < cfg.maxNodes then
                                local suffix = counts[key] > 1 and ("~" .. counts[key]) or ""
                                table.insert(queue, {
                                    instance = child, depth = entry.depth + 1,
                                    path = entry.path .. "/" .. safeSegment .. suffix,
                                    parent = entry.path,
                                })
                                enqueued = enqueued + 1
                            else
                                partial("queue_limit")
                            end
                        end
                    end
                end
            end
            if state.visited % cfg.yieldEvery == 0 then
                notify(onProgress, "scanning", state, serviceName)
                task.wait()
            end
        end
        if not state.stopped and #records > 0 then
            if not flush(records, serviceName, pass, part) then state.stopped = true end
        end
        notify(onProgress, "service_done", state, serviceName)
    end

    local selected = 0
    for _, service in ipairs(Exporter.TARGETS) do
        if cfg.targets[service] then
            selected = selected + 1
            scan(service, 1)
            if state.stopped then break end
        end
    end
    if selected == 0 then partial("no_targets") end

    if cfg.targets.Workspace then
        local ok, streaming = pcall(function() return workspace.StreamingEnabled end)
        if ok and streaming then partial("workspace_streaming_enabled") end
    end

    if cfg.twoPassGui and not state.stopped then
        notify(onProgress, "waiting_second_pass", state, "PlayerGui")
        local delayEnd = os.clock() + cfg.secondPassDelay
        while os.clock() < delayEnd and not stopCheck() do task.wait(0.1) end
        if not state.stopped then
            for _, service in ipairs({"PlayerGui", "StarterGui"}) do
                if cfg.targets[service] then scan(service, 2) end
                if state.stopped then break end
            end
        end
    end

    if state.errorCount > 0 then partial("read_or_write_errors") end
    local reasons = {}
    for reason in pairs(state.partialReasons) do table.insert(reasons, reason) end
    table.sort(reasons)
    local manifest = {
        schemaVersion = Exporter.SCHEMA_VERSION,
        exporterVersion = Exporter.VERSION,
        clientOnly = true,
        game = {
            label = sanitizedString(cfg.label, cfg, state),
            category = sanitizedString(cfg.category, cfg, state),
            variant = sanitizedString(cfg.variant, cfg, state),
            placeId = game.PlaceId, gameId = game.GameId,
        },
        capturedAtUtc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        status = state.cancelled and "cancelled" or (#reasons > 0 and "partial" or "complete"),
        partialReasons = reasons,
        stats = {
            visited = state.visited, written = state.written, files = state.fileCount,
            bytes = state.bytes, redactions = state.redactions, errors = state.errorCount,
            classCounts = state.classes,
        },
        services = state.services,
        errors = state.errors,
        settings = {
            format = cfg.format, targets = cfg.targets, guiTexts = cfg.guiTexts,
            guiProperties = cfg.guiProperties, worldProperties = cfg.worldProperties,
            assets = cfg.assets, textboxValues = cfg.textboxValues,
            stringValues = cfg.stringValues, twoPassGui = cfg.twoPassGui,
            maxNodes = cfg.maxNodes, maxDepth = cfg.maxDepth,
            chunkSize = cfg.chunkSize, maxString = cfg.maxString,
            maxBytes = cfg.maxBytes,
        },
        privacy = {
            excludesOtherPlayerCharacters = true,
            redactsKnownPlayerNames = true,
            excludesChatGui = true,
            excludesScriptSource = true,
            excludesTextboxValuesByDefault = true,
            includesSessionOrPrivateServerIds = false,
        },
        notes = {
            "Client view only: server-only objects are unavailable.",
            "StreamingEnabled can result in missing Workspace descendants.",
            "Paths and GUI strings can still contain contextual data; review before publishing.",
            "IDs, volatile paths and dynamic player fields must not be used in detection signatures.",
        },
    }
    local okManifest, encoded = pcall(function() return HttpService:JSONEncode(manifest) end)
    if not okManifest or not pcall(writefile, base .. "/manifest.json", encoded) then
        return nil, "could not write manifest"
    end
    notify(onProgress, "done", state, manifest.status)
    return {folder = base, manifest = manifest}
end

return Exporter
