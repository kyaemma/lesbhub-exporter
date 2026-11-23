-- Lesbhub Exporter V1 - client-side, read-only capture engine.
-- No script source, remote invocation, executor introspection, or network upload.
local Exporter = {}
Exporter.VERSION = "0.2.1"
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
    ImageButton = {"Image", "HoverImage", "PressedImage", "ImageColor3", "ImageTransparency", "ScaleType", "AutoButtonColor"},
    VideoFrame = {"Video", "Playing", "Looped", "Volume"},
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
    BasePart = {"Size", "Position", "CFrame", "Orientation", "Material", "Transparency", "Anchored", "CanCollide", "Color"},
    MeshPart = {"MeshId", "TextureID"},
    Model = {"WorldPivot", "PrimaryPart"},
    SpecialMesh = {"MeshId", "TextureId", "MeshType", "Scale"},
    Decal = {"Texture", "Transparency", "Color3"},
    Texture = {"Texture", "Transparency", "Color3"},
    Sound = {"SoundId", "Volume", "Looped"},
    Animation = {"AnimationId"},
    ParticleEmitter = {"Texture", "Enabled", "Rate"},
    Beam = {"Texture", "Enabled", "Transparency"},
    Trail = {"Texture", "Enabled", "Transparency"},
    SurfaceAppearance = {"ColorMap", "NormalMap", "MetalnessMap", "RoughnessMap"},
    Shirt = {"ShirtTemplate"},
    Pants = {"PantsTemplate"},
    ShirtGraphic = {"Graphic"},
    Sky = {"SkyboxBk", "SkyboxDn", "SkyboxFt", "SkyboxLf", "SkyboxRt", "SkyboxUp", "SunTextureId", "MoonTextureId"},
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
    if t == "CFrame" then
        -- Flat numeric transform (position + orthonormal 3x3 rotation matrix).
        -- 12 numbers preserve the client-visible map orientation.
        local components = {value:GetComponents()}
        for _, n in ipairs(components) do
            if type(n) ~= "number" or n ~= n or math.abs(n) == math.huge then return nil end
        end
        return components
    end
    if t == "UDim" then return {scale = value.Scale, offset = value.Offset} end
    if t == "UDim2" then
        return {xScale = value.X.Scale, xOffset = value.X.Offset, yScale = value.Y.Scale, yOffset = value.Y.Offset}
    end
    if t == "Rect" then
        return {min = {x = value.Min.X, y = value.Min.Y}, max = {x = value.Max.X, y = value.Max.Y}}
    end
    if t == "NumberRange" then return {min = value.Min, max = value.Max} end
    if t == "BrickColor" then return value.Name end
    -- Intentionally skip Instance references, connections, functions and unbounded tables.
    return nil
end

local function addError(state, code)
    state.errorCount = state.errorCount + 1
    if #state.errors < 40 then table.insert(state.errors, code) end
end

local ASSET_PROPERTIES = {
    Image = true, Texture = true, TextureId = true, TextureID = true,
    MeshId = true, SoundId = true, AnimationId = true, HoverImage = true,
    PressedImage = true, Video = true, ColorMap = true, NormalMap = true,
    MetalnessMap = true, RoughnessMap = true, ShirtTemplate = true,
    PantsTemplate = true, Graphic = true, SkyboxBk = true, SkyboxDn = true,
    SkyboxFt = true, SkyboxLf = true, SkyboxRt = true, SkyboxUp = true,
    SunTextureId = true, MoonTextureId = true,
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
                local encoded
                if ASSET_PROPERTIES[property] and typeof(value) == "string" then
                    -- Normalize public Roblox asset URL IDs; never preserve arbitrary signed URLs.
                    local publicId = value:match("^https?://[%w%.%-]*roblox%.com/asset/%?id=(%d+)")
                    if publicId then
                        encoded = "rbxassetid://" .. publicId
                    else
                        encoded = serialize(value, cfg, state)
                    end
                else
                    encoded = serialize(value, cfg, state)
                end
                if encoded ~= nil then
                    properties[property] = encoded
                    if ASSET_PROPERTIES[property] and type(encoded) == "string" and encoded ~= "" then
                        state.assetReferences = state.assetReferences + 1
                    end
                end
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
        for _, record in ipairs(records) do
            local encoded = HttpService:JSONEncode(record)
            -- Roblox encodes an empty Lua table as [] instead of {}.
            table.insert(lines, (encoded:gsub('"properties":%[%]', '"properties":{}')))
        end
        return table.concat(lines, "\n") .. "\n"
    end
    if format == "csv" then
        local lines = {"path,parentPath,name,className,depth,properties_json"}
        for _, record in ipairs(records) do
            local values = {record.path, record.parentPath, record.name, record.className,
                record.depth, HttpService:JSONEncode(record.properties) == "[]"
                    and "{}" or HttpService:JSONEncode(record.properties)}
            for i, value in ipairs(values) do values[i] = csvEscape(value) end
            table.insert(lines, table.concat(values, ","))
        end
        return table.concat(lines, "\n") .. "\n"
    end
    local encoded = HttpService:JSONEncode({
        schemaVersion = Exporter.SCHEMA_VERSION,
        service = service, pass = pass, records = records,
    })
    return (encoded:gsub('"properties":%[%]', '"properties":{}'))
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
        -- No implicit omissions: start from a full client-visible snapshot.
        for _, service in ipairs(Exporter.TARGETS) do cfg.targets[service] = true end
    end
    cfg.guiTexts = input.guiTexts ~= false
    cfg.guiProperties = input.guiProperties ~= false
    cfg.worldProperties = input.worldProperties ~= false
    cfg.assets = input.assets ~= false
    cfg.textboxValues = input.textboxValues == true
    cfg.stringValues = input.stringValues == true
    cfg.twoPassGui = input.twoPassGui == true
    cfg.guiPasses = clamp(input.guiPasses, 2, 12, 3)
    cfg.secondPassDelay = clamp(input.secondPassDelay, 1, 30, 6)
    -- Chunk size and yield cadence bound *per-step* work, not the exported dataset.
    cfg.yieldEvery = clamp(input.yieldEvery, 10, 250, 60)
    cfg.chunkSize = clamp(input.chunkSize, 25, 800, 200)
    -- No global maxNodes, maxDepth, maxBytes, or maxString. These silently
    -- truncated the dataset and prevented structural comparisons.
    return cfg
end

local function notify(callback, stage, state, extra)
    if type(callback) == "function" then
        pcall(callback, {
            stage = stage, visited = state.visited, written = state.written,
            files = state.fileCount, bytes = state.bytes,
            service = extra or state.currentService, pass = state.currentPass,
            discovered = state.discovered, pending = state.pending,
            currentPath = state.currentPath, currentClass = state.currentClass,
            assetReferences = state.assetReferences,
            elapsedSeconds = os.clock() - state.startedAt,
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
        visited = 0, written = 0, fileCount = 0, bytes = 0, discovered = 0,
        pending = 0, assetReferences = 0, currentPath = "", currentClass = "",
        currentService = "", currentPass = 1, startedAt = os.clock(),
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

    local chunkIndexes = {}

    local function asciiFallback(value)
        -- Preserve UTF-8 bytes reversibly when an executor's JSON encoder
        -- rejects a particular string (e.g. malformed UTF-8).
        return (tostring(value or ""):gsub("[^ -~]", function(char)
            return string.format("~%02X", string.byte(char))
        end))
    end

    local function safeText(value)
        local ok = pcall(function() return HttpService:JSONEncode(tostring(value or "")) end)
        return ok and tostring(value or "") or asciiFallback(value)
    end

    local function repairRecord(record)
        local fixed = {
            name = safeText(record.name),
            className = safeText(record.className),
            path = safeText(record.path),
            parentPath = safeText(record.parentPath),
            depth = record.depth,
            properties = {},
        }
        for key, value in pairs(record.properties or {}) do
            local safeKey = safeText(key)
            local ok = pcall(function()
                HttpService:JSONEncode({[safeKey] = value})
            end)
            if not ok then
                if typeof(value) == "string" then
                    value = asciiFallback(value)
                    ok = pcall(function() HttpService:JSONEncode({[safeKey] = value}) end)
                end
                if not ok then
                    value = "[serialization-unavailable]"
                    partial("property_serialization_error")
                    addError(state, "property_encode_failed:" .. tostring(record.className) .. "." .. tostring(key))
                end
            end
            fixed.properties[safeKey] = value
        end
        return fixed
    end

    local function flush(records, serviceName, pass)
        if #records == 0 then return true end
        local okEncode, encoded = pcall(encodeChunk, records, cfg.format, serviceName, pass)
        if not okEncode and #records > 1 then
            -- A single invalid record must not kill all following services.
            -- Binary split also helps with executor-specific chunk size limits.
            local half = math.floor(#records / 2)
            local left, right = {}, {}
            for i = 1, half do left[#left + 1] = records[i] end
            for i = half + 1, #records do right[#right + 1] = records[i] end
            local okLeft = flush(left, serviceName, pass)
            local okRight = okLeft and flush(right, serviceName, pass)
            return okLeft and okRight
        end
        if not okEncode then
            local fixed = repairRecord(records[1])
            okEncode, encoded = pcall(encodeChunk, {fixed}, cfg.format, serviceName, pass)
            if not okEncode then
                fixed.properties = {}
                okEncode, encoded = pcall(encodeChunk, {fixed}, cfg.format, serviceName, pass)
            end
            if not okEncode then
                addError(state, "record_encode_failed:" .. serviceName)
                partial("encoding_error")
                return false
            end
            partial("record_serialization_recovered")
            addError(state, "record_serialization_recovered:" .. serviceName)
        end

        local key = serviceName .. "/p" .. tostring(pass)
        local part = (chunkIndexes[key] or 0) + 1
        local ext = cfg.format == "json" and "json" or cfg.format
        local filename = string.format("%s/%s-p%d-%04d.%s", base, serviceName, pass, part, ext)
        if not pcall(writefile, filename, encoded) then
            addError(state, "write_failed:" .. serviceName)
            partial("write_error")
            return false
        end
        chunkIndexes[key] = part
        state.bytes = state.bytes + #encoded
        state.fileCount = state.fileCount + 1
        state.written = state.written + #records
        state.services[serviceName].records = state.services[serviceName].records + #records
        state.services[serviceName].files = state.services[serviceName].files + 1
        notify(onProgress, "file_written", state, serviceName)
        return true
    end

    local function scan(serviceName, pass)
        if stopCheck() then return end
        local root = rootInstance(serviceName)
        if not root then
            partial("missing_root:" .. serviceName)
            notify(onProgress, "missing_root", state, serviceName)
            return
        end
        state.services[serviceName] = state.services[serviceName] or
            {visited = 0, records = 0, files = 0, passes = 0}
        state.services[serviceName].passes = state.services[serviceName].passes + 1

        -- Lazy DFS frames avoid building paths for thousands of siblings at once.
        -- Each loop processes at most one object OR one child; the yield cadence
        -- applies to both object collection and sibling enumeration.
        local stack = {{
            instance = root, depth = 0, path = serviceName, parent = "",
            entered = false,
        }}
        local records, steps = {}, 0
        local seen = setmetatable({}, {__mode = "k"})
        state.currentService = serviceName
        state.currentPass = pass
        state.discovered = state.discovered + 1
        state.pending = math.max(0, state.discovered - state.visited)
        notify(onProgress, "service_start", state, serviceName)

        while #stack > 0 do
            if stopCheck() then break end
            local frame = stack[#stack]

            if not frame.entered then
                frame.entered = true
                local obj = frame.instance
                if seen[obj] then
                    -- Object moved during traversal; do not count a duplicate.
                    state.discovered = state.discovered - 1
                    stack[#stack] = nil
                else
                    seen[obj] = true
                    state.visited = state.visited + 1
                    state.services[serviceName].visited = state.services[serviceName].visited + 1

                    local okClass, class = pcall(function() return obj.ClassName end)
                    if not okClass then class = "Unknown" end
                    local name = frame.depth == 0 and serviceName or readName(obj, cfg, state)
                    state.currentPath = frame.path
                    state.currentClass = class
                    local properties = collectProperties(obj, cfg, state)
                    table.insert(records, {
                        name = name, className = class, path = frame.path,
                        parentPath = frame.parent, depth = frame.depth, properties = properties,
                    })
                    state.classes[class] = (state.classes[class] or 0) + 1
                    if #records >= cfg.chunkSize then
                        if not flush(records, serviceName, pass) then
                            state.stopped = true
                            break
                        end
                        records = {}
                    end

                    local okChildren, children = pcall(function() return obj:GetChildren() end)
                    if not okChildren then
                        addError(state, "children_unavailable:" .. class)
                        partial("children_unavailable")
                    else
                        frame.children = children
                        frame.nextChild = 1
                        frame.siblingCounts = {}
                        state.discovered = state.discovered + #children
                    end
                end
            elseif frame.children and frame.nextChild <= #frame.children then
                local child = frame.children[frame.nextChild]
                frame.nextChild = frame.nextChild + 1
                if isForbidden(child, serviceName, state) then
                    state.discovered = state.discovered - 1
                else
                    local segment = readName(child, cfg, state):gsub("[./\\]", "_")
                    local counts = frame.siblingCounts
                    counts[segment] = (counts[segment] or 0) + 1
                    local suffix = counts[segment] > 1 and ("~" .. counts[segment]) or ""
                    stack[#stack + 1] = {
                        instance = child, depth = frame.depth + 1,
                        path = frame.path .. "/" .. segment .. suffix,
                        parent = frame.path, entered = false,
                    }
                end
            else
                stack[#stack] = nil
            end

            state.pending = math.max(0, state.discovered - state.visited)
            steps = steps + 1
            if steps % cfg.yieldEvery == 0 then
                notify(onProgress, "scanning", state, serviceName)
                task.wait()
            end
        end

        -- A manual cancellation still preserves pending buffered records.
        if #records > 0 and (not state.stopped or state.cancelled) then
            if not flush(records, serviceName, pass) then state.stopped = true end
        end
        state.pending = 0
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

    if cfg.twoPassGui and not state.stopped
        and (cfg.targets.PlayerGui or cfg.targets.StarterGui) then
        for pass = 2, cfg.guiPasses do
            notify(onProgress, "waiting_gui_pass", state, "PlayerGui")
            local deadline = os.clock() + cfg.secondPassDelay
            while os.clock() < deadline and not stopCheck() do task.wait(0.1) end
            if state.stopped then break end
            for _, service in ipairs({"PlayerGui", "StarterGui"}) do
                if cfg.targets[service] then scan(service, pass) end
                if state.stopped then break end
            end
            if state.stopped then break end
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
            assetReferences = state.assetReferences, classCounts = state.classes,
            elapsedSeconds = os.clock() - state.startedAt,
        },
        services = state.services,
        errors = state.errors,
        settings = {
            format = cfg.format, targets = cfg.targets, guiTexts = cfg.guiTexts,
            guiProperties = cfg.guiProperties, worldProperties = cfg.worldProperties,
            assets = cfg.assets, textboxValues = cfg.textboxValues,
            stringValues = cfg.stringValues, twoPassGui = cfg.twoPassGui,
            guiPasses = cfg.guiPasses, secondPassDelay = cfg.secondPassDelay,
            chunkSize = cfg.chunkSize, yieldEvery = cfg.yieldEvery,
            captureMode = "exhaustive",
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
            "No global node, depth, total byte, or string-length limit is applied.",
            "GUI snapshots are not merged; lazy menus must be opened by the operator.",
            "Asset references are exported as property values; binary assets are not downloaded.",
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

-- Optional native place export, only after an explicit UI action.
-- Like Infinite Yield's savegame command, this delegates to the executor.
-- It is intentionally separate from the read-only JSON capture and can
-- include data outside our privacy-filtered allowlist.
function Exporter.savePlace()
    if type(saveinstance) ~= "function" then
        return false, "saveinstance() is not available in this executor"
    end
    local ok, result = pcall(saveinstance)
    if not ok then return false, tostring(result) end
    return true, result
end

return Exporter
