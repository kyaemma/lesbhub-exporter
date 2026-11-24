-- Lesbhub Exporter V1 - client-side, read-only capture engine.
-- Reconstructed client code is explicit opt-in; no remote invocation or uploads.
local DeepScripts = require("./deep_scripts")
local Exporter = {}
Exporter.VERSION = "0.7.0"
Exporter.SCHEMA_VERSION = 1
Exporter.TARGETS = {
    "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "PlayerGui",
    "StarterPlayer", "PlayerScripts", "StarterPack", "Workspace",
    "Lighting", "SoundService", "Teams",
}

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local function portableJson(value)
    if type(value) == "string" then
        local ok, length = pcall(utf8.len, value)
        if ok and length then return value end
        return (value:gsub("[^ -~]", function(c) return string.format("~%02X", c:byte()) end))
    elseif type(value) == "table" then
        local copy = {}
        for key, item in pairs(value) do copy[portableJson(key)] = portableJson(item) end
        return copy
    end
    return value
end

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
    Script = {"Enabled", "RunContext"},
    LocalScript = {"Enabled"},
    ModuleScript = {},
    RemoteEvent = {},
    RemoteFunction = {},
    UnreliableRemoteEvent = {},
    BindableEvent = {},
    BindableFunction = {},
    IntConstrainedValue = {"Value", "MinValue", "MaxValue"},
    DoubleConstrainedValue = {"Value", "MinValue", "MaxValue"},
    Vector3Value = {"Value"},
    Color3Value = {"Value"},
    CFrameValue = {"Value"},
    BrickColorValue = {"Value"},
    RayValue = {"Value"},
    Motor6D = {"Part0", "Part1", "C0", "C1", "Transform", "Enabled"},
    Weld = {"Part0", "Part1", "C0", "C1", "Enabled"},
    ManualWeld = {"Part0", "Part1", "C0", "C1", "Enabled"},
    WeldConstraint = {"Part0", "Part1", "Enabled"},
    Attachment = {"CFrame", "Position", "Orientation", "Visible"},
    Humanoid = {"Health", "MaxHealth", "WalkSpeed", "JumpPower", "HipHeight", "RigType", "AutoRotate"},
    Camera = {"CFrame", "Focus", "FieldOfView", "CameraType", "CameraSubject"},
    Lighting = {"ClockTime", "Brightness", "FogEnd", "FogStart", "Ambient", "OutdoorAmbient", "ExposureCompensation"},
    PointLight = {"Enabled", "Color", "Brightness", "Range", "Shadows"},
    SpotLight = {"Enabled", "Color", "Brightness", "Range", "Angle", "Shadows"},
    SurfaceLight = {"Enabled", "Color", "Brightness", "Range", "Angle", "Shadows"},
    BlurEffect = {"Enabled", "Size"},
    BloomEffect = {"Enabled", "Intensity", "Size", "Threshold"},
    ColorCorrectionEffect = {"Enabled", "TintColor", "Brightness", "Contrast", "Saturation"},
    SunRaysEffect = {"Enabled", "Intensity", "Spread"},
    Atmosphere = {"Density", "Offset", "Color", "Decay", "Glare", "Haze"},
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
    ObjectValue = {"Value"}, -- serialize as an inert reference, never traverse target children
    Configuration = {},
}

-- The file layout is independent of the original Roblox hierarchy.
-- Every record keeps its original path and parentPath for tree reconstruction.
-- A script nested inside PlayerGui is stored under scripts/PlayerGui/, never
-- mixed with rendered GUI objects or mistaken for its source code.
local CATEGORIES = {
    scripts = true, gui = true, remotes = true, values = true,
    world = true, assets = true, structures = true, other = true,
}
local REMOTE_CLASSES = {
    RemoteEvent = true, RemoteFunction = true, UnreliableRemoteEvent = true,
    BindableEvent = true, BindableFunction = true,
}
-- These are documented class capabilities, not observations of live traffic.
-- Do not imply that a particular game uses either possible network direction.
local REMOTE_INFO = {
    RemoteEvent = {
        family = "remote", boundary = "client_server", style = "event",
        asynchronous = true, requiresResponse = false,
        delivery = "reliable_ordered",
    },
    UnreliableRemoteEvent = {
        family = "remote", boundary = "client_server", style = "event",
        asynchronous = true, requiresResponse = false,
        delivery = "unreliable_unordered",
    },
    RemoteFunction = {
        family = "remote", boundary = "client_server", style = "function",
        asynchronous = false, requiresResponse = true,
        delivery = "request_response",
    },
    BindableEvent = {
        family = "bindable", boundary = "same_side", style = "event",
        asynchronous = true, requiresResponse = false,
        delivery = "local_event",
    },
    BindableFunction = {
        family = "bindable", boundary = "same_side", style = "function",
        asynchronous = false, requiresResponse = true,
        delivery = "local_request_response",
    },
}
local ASSET_CLASSES = {
    Sound = true, Animation = true, Decal = true, Texture = true,
    SurfaceAppearance = true, SpecialMesh = true, ParticleEmitter = true,
    Beam = true, Trail = true, Shirt = true, ShirtGraphic = true,
    Pants = true, Sky = true, PointLight = true, SpotLight = true,
    SurfaceLight = true, Fire = true, Smoke = true, Sparkles = true,
}
local STRUCTURE_CLASSES = {
    Folder = true, Configuration = true, Model = true,
    ReplicatedStorage = true, ReplicatedFirst = true,
    StarterGui = true, PlayerGui = true, StarterPlayer = true,
    PlayerScripts = true, StarterPack = true, Teams = true,
}
local function categoryFor(instance, service, class)
    if class == "Script" or class == "LocalScript" or class == "ModuleScript" then
        return "scripts"
    end
    if REMOTE_CLASSES[class] then return "remotes" end
    if class:match("Value$") or class:match("ConstrainedValue$") then return "values" end
    if class == "ScreenGui" or class == "BillboardGui" or class == "SurfaceGui"
        or class == "VideoFrame" or GUI_CLASSES[class] then
        return "gui"
    end
    if instance then
        local ok, isGui = pcall(function()
            return instance:IsA("GuiObject") or instance:IsA("GuiBase2d")
                or instance:IsA("UIComponent") or instance:IsA("UIConstraint")
        end)
        if ok and isGui then return "gui" end
    end
    if ASSET_CLASSES[class] then return "assets" end
    if service == "Workspace" or service == "Lighting" then return "world" end
    if service == "SoundService" then return "assets" end
    if STRUCTURE_CLASSES[class] then return "structures" end
    return "other"
end

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

local function serializeReference(target, cfg, state)
    -- Only expose references inside selected client-visible service trees.
    -- Never copy a raw GetFullName() containing unrelated player paths.
    local parts, seen = {}, {}
    local current = target
    local localPlayer = Players.LocalPlayer
    local className
    local okClass, class = pcall(function() return target.ClassName end)
    if okClass then className = class end
    while current and current ~= game do
        if seen[current] or state.characters[current] then return nil end
        seen[current] = true
        local okParent, parent = pcall(function() return current.Parent end)
        if not okParent then return nil end
        local segment = readName(current, cfg, state):gsub("[./\\]", "_")
        parts[#parts + 1] = segment
        if parent == game then
            if not cfg.targets[segment] then return nil end
            local path = {}
            for i = #parts, 1, -1 do path[#path + 1] = parts[i] end
            return {kind = "InstanceRef", className = className, path = table.concat(path, "/")}
        elseif parent == localPlayer then
            if not cfg.targets[segment] then return nil end
            local path = {}
            for i = #parts, 1, -1 do path[#path + 1] = parts[i] end
            return {kind = "InstanceRef", className = className, path = table.concat(path, "/")}
        end
        current = parent
    end
    return nil
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
    if t == "NumberSequence" then
        local points = {}
        for _, p in ipairs(value.Keypoints) do
            points[#points + 1] = {time = p.Time, value = p.Value, envelope = p.Envelope}
        end
        return points
    end
    if t == "ColorSequence" then
        local points = {}
        for _, p in ipairs(value.Keypoints) do
            points[#points + 1] = {
                time = p.Time,
                color = {r = math.floor(p.Value.R * 255 + 0.5),
                    g = math.floor(p.Value.G * 255 + 0.5),
                    b = math.floor(p.Value.B * 255 + 0.5)},
            }
        end
        return points
    end
    if t == "Instance" then return serializeReference(value, cfg, state) end
    if t == "BrickColor" then return value.Name end
    -- Intentionally skip connections, functions and unbounded tables.
    -- Instance references above are metadata only, never traversed.
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
    -- Archivable is inherited by every Roblox Instance. It provides useful
    -- context for scripts and remotes that have few native readable fields.
    local function includeMetadata()
        wanted[#wanted + 1] = "Archivable"
        unique.Archivable = "metadata"
    end
    includeMetadata()
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
        elseif property == "Archivable" then
            allowed = true
        elseif property == "Enabled" and
            (class == "Script" or class == "LocalScript") then
            allowed = true
        elseif property == "RunContext" and class == "Script" then
            allowed = true
        elseif property == "Value" then
            if class == "StringValue" then
                -- Text values have their own privacy setting, independently
                -- of world geometry/layout property collection.
                allowed = cfg.stringValues and not sensitiveStringValue
            else
                allowed = cfg.worldProperties
            end
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

    -- A remote's callable methods and server-side handlers are not native
    -- readable properties. Add only verified class-level capabilities, never
    -- pretend to know arguments, listeners, invocations, or actual direction.
    if REMOTE_CLASSES[class] then
        local info = REMOTE_INFO[class]
        properties.RemoteInfo = {
            family = info.family,
            boundary = info.boundary,
            style = info.style,
            asynchronous = info.asynchronous,
            requiresResponse = info.requiresResponse,
            delivery = info.delivery,
            metadataSource = "roblox_class",
            observedCalls = false,
            parameterSchema = "unavailable",
        }
    end

    -- Roblox attributes and tags are accessible on the client without any
    -- script decompilation. Keep names/values sanitized and skip sensitive keys.
    if cfg.includeAttributes then
        local ok, attributes = pcall(function() return instance:GetAttributes() end)
        if ok and type(attributes) == "table" then
            local cleaned = {}
            for key, value in pairs(attributes) do
                if type(key) == "string" and not suspiciousName(key) then
                    local safeKey = sanitizedString(key, cfg, state)
                    local serialized = serialize(value, cfg, state)
                    if safeKey and serialized ~= nil then cleaned[safeKey] = serialized end
                elseif type(key) == "string" then
                    state.redactions = state.redactions + 1
                end
            end
            if next(cleaned) then properties.Attributes = cleaned end
        end
    end
    if cfg.includeTags then
        local ok, tags = pcall(function() return instance:GetTags() end)
        if ok and type(tags) == "table" then
            local cleaned = {}
            for _, tag in ipairs(tags) do
                if type(tag) == "string" and not suspiciousName(tag) then
                    local name = sanitizedString(tag, cfg, state)
                    if name then cleaned[#cleaned + 1] = name end
                end
            end
            if #cleaned > 0 then
                table.sort(cleaned)
                properties.Tags = cleaned
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

local function encodeChunk(records, format, service, pass, category)
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
        local lines = {"path,parentPath,name,className,depth,properties_json,instanceId,parentInstanceId,sequence,scriptId,operation,observedAtUtc"}
        for _, record in ipairs(records) do
            local values = {record.path, record.parentPath, record.name, record.className,
                record.depth, HttpService:JSONEncode(record.properties) == "[]"
                    and "{}" or HttpService:JSONEncode(record.properties),
                record.instanceId or "", record.parentInstanceId or "", record.sequence or "",
                record.scriptId or "", record.operation or "", record.observedAtUtc or ""}
            for i, value in ipairs(values) do values[i] = csvEscape(value) end
            table.insert(lines, table.concat(values, ","))
        end
        return table.concat(lines, "\n") .. "\n"
    end
    local encoded = HttpService:JSONEncode({
        schemaVersion = Exporter.SCHEMA_VERSION,
        service = service, pass = pass, category = category, records = records,
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
    cfg.organizedOutput = input.organizedOutput ~= false
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
    cfg.includeAttributes = input.includeAttributes ~= false
    cfg.includeTags = input.includeTags ~= false
    cfg.includeReconstructedCode = input.includeReconstructedCode ~= false
    cfg.observeGuiActions = input.observeGuiActions == true
    cfg.observeRemotes = input.observeRemotes == true
    cfg.textboxValues = input.textboxValues == true
    cfg.stringValues = input.stringValues == true
    cfg.twoPassGui = input.twoPassGui == true
    cfg.continuous = input.continuous == true
    -- Continuous monitoring continues until an explicit stop/cancel.
    -- The interval is a cadence, NOT a dataset or duration cap.
    cfg.continuousInterval = clamp(input.continuousInterval, 1, 30, 3)
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
            monitoring = state.monitoring or false,
            monitorCycles = state.monitorCycles or 0,
            deltaRecords = state.deltaRecords or 0,
            added = state.added or 0,
            updated = state.updated or 0,
            removed = state.removed or 0,
            elapsedSeconds = os.clock() - state.startedAt,
        })
    end
end

-- Stable, order-independent fingerprint for selected public/allowlisted fields.
-- It is deliberately independent of JSON object-key iteration order.
local function stableValue(value, depth)
    if depth > 7 then return "<depth>" end
    if type(value) ~= "table" then return type(value) .. ":" .. tostring(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) ~= type(b) then return type(a) < type(b) end
        return tostring(a) < tostring(b)
    end)
    local parts = {"{"}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = tostring(key)
        parts[#parts + 1] = "="
        parts[#parts + 1] = stableValue(value[key], depth + 1)
        parts[#parts + 1] = ";"
    end
    parts[#parts + 1] = "}"
    return table.concat(parts)
end

local function recordFingerprint(record)
    return tostring(record.className) .. "|" .. stableValue(record.properties or {}, 0)
end

local function capture(options, onProgress, control)
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
        classes = {}, categories = {}, cancelled = false, stopped = false,
        stopRequested = false, monitoring = false, monitorCycles = 0,
        deltaRecords = 0, added = 0, updated = 0, removed = 0,
    }
    local function partial(reason)
        if not state.partialReasons[reason] then state.partialReasons[reason] = true end
    end
    local function stopCheck()
        if control.cancelled then
            state.cancelled = true
            state.stopped = true
            partial("user_cancelled")
        elseif cfg.continuous and control.stopRequested then
            -- Expected user action, not an error or a failed capture.
            state.stopRequested = true
            state.stopped = true
        end
        return state.stopped
    end

    local chunkIndexes = {}
    local createdDataFolders = {}
    local serviceSnapshots = {}
    local instanceIds = setmetatable({}, {__mode = "k"})
    local debugIdentities = {}
    local nextInstanceId, nextSequence = 0, 0
    local remoteIndex, guiIndex = {}, {}
    local diagnostics = {guiActions = 0, remoteObservations = 0, writeErrors = 0,
        cobaltAttached = false, knownCallers = 0}
    local diagnosticConnections, guiWatched = {}, setmetatable({}, {__mode = "k"})
    local diagnosticBuffers = { ["gui/actions.jsonl"] = {}, ["remotes/observations.jsonl"] = {} }
    local diagnosticWritten = {}
    local flushDiagnostics
    local function diagnosticEvent(path, event)
        nextSequence = nextSequence + 1
        event.sequence = nextSequence
        event.observedAtUtc = os.date("!%Y-%m-%dT%H:%M:%SZ")
        diagnosticBuffers[path][#diagnosticBuffers[path] + 1] = event
    end
    flushDiagnostics = function()
        for path, rows in pairs(diagnosticBuffers) do
            if #rows > 0 then
                local ok = pcall(function()
                    assert(createFolders((base .. "/" .. path):match("^(.*)/[^/]+$")))
                    local parts = {}
                    for _, row in ipairs(rows) do parts[#parts + 1] = HttpService:JSONEncode(portableJson(row)) end
                    local content = table.concat(parts, "\n") .. "\n"
                    if type(appendfile) == "function" then
                        if not diagnosticWritten[path] then writefile(base .. "/" .. path, "") end
                        appendfile(base .. "/" .. path, content)
                    else
                        local previous = diagnosticWritten[path] and readfile(base .. "/" .. path) or ""
                        writefile(base .. "/" .. path, previous .. content)
                    end
                    diagnosticWritten[path] = true
                end)
                if ok then table.clear(rows)
                else diagnostics.writeErrors = diagnostics.writeErrors + 1; partial("diagnostic_write_failed") end
            end
        end
    end
    local deep = DeepScripts.new(base, cfg.includeReconstructedCode, control, function(entry)
        flushDiagnostics()
        state.currentPath = entry.robloxPath
        notify(onProgress, "extracting_script", state, entry.name)
    end)
    local function identity(instance)
        if not instance then return nil end
        local id = instanceIds[instance]
        if not id then
            local debugId
            local ok, class = pcall(function() return instance.ClassName end)
            if ok and (REMOTE_CLASSES[class] or class == "LocalScript" or class == "ModuleScript" or class == "Script") then
                local readable, value = pcall(function() return instance:GetDebugId() end)
                if readable then debugId = class .. ":" .. value end
            end
            local previous = debugId and debugIdentities[debugId]
            if previous and type(compareinstances) == "function" then
                local compared, equal = pcall(compareinstances, instance, previous.instance)
                if compared and equal then id = previous.id end
            end
            if not id then nextInstanceId = nextInstanceId + 1; id = nextInstanceId end
            instanceIds[instance] = id
            if debugId then debugIdentities[debugId] = {id = id, instance = instance} end
        end
        return id
    end
    local function identify(record, instance, service)
        record.instanceId = identity(instance)
        local ok, parent = pcall(function() return instance.Parent end)
        record.parentInstanceId = ok and parent and identity(parent) or nil
        if record.category == "scripts" or record.className == "LocalScript"
            or record.className == "ModuleScript" or record.className == "Script" then
            deep:discover(instance, record, service or state.currentService)
        end
        if cfg.observeGuiActions and not guiWatched[instance]
            and (record.className == "TextButton" or record.className == "ImageButton") then
            local ok, connection = pcall(function()
                return instance.Activated:Connect(function()
                    diagnosticEvent("gui/actions.jsonl", {event = "activated",
                        instanceId = record.instanceId, robloxPath = record.path,
                        evidence = "operator_activation"})
                    diagnostics.guiActions = diagnostics.guiActions + 1
                end)
            end)
            if ok then guiWatched[instance] = true; diagnosticConnections[#diagnosticConnections + 1] = connection end
        end
    end
    local function observeRecord(record, service, mode, instance)
        local snapshot = serviceSnapshots[service]
        if not snapshot then snapshot = {}; serviceSnapshots[service] = snapshot end
        local previous = snapshot[record.instanceId]
        local signature = cfg.continuous and (recordFingerprint(record) .. "|" .. record.path
            .. "|" .. tostring(record.parentInstanceId)) or nil
        if cfg.continuous then
            if mode == "remove" then
                if not previous then return false end
                record.operation = "remove"
                snapshot[record.instanceId] = nil
            else
                if previous and previous.signature == signature then return false end
                record.operation = previous and "update" or (mode ~= "baseline" and "add" or nil)
            end
        end
        nextSequence = nextSequence + 1
        record.sequence = nextSequence
        record.observedAtUtc = record.observedAtUtc or os.date("!%Y-%m-%dT%H:%M:%SZ")
        if cfg.continuous and mode ~= "remove" then
            snapshot[record.instanceId] = {signature = signature, name = record.name,
                className = record.className, path = record.path, parentPath = record.parentPath,
                depth = record.depth, category = record.category, instanceId = record.instanceId,
                parentInstanceId = record.parentInstanceId, sequence = record.sequence, instance = instance}
        end
        if record.operation then
            state.deltaRecords = state.deltaRecords + 1
            if record.operation == "remove" then state.removed = state.removed + 1
            elseif record.operation == "update" then state.updated = state.updated + 1
            else state.added = state.added + 1 end
        end
        if REMOTE_CLASSES[record.className] then
            local previousRemote = remoteIndex[record.instanceId]
            remoteIndex[record.instanceId] = {instanceId = record.instanceId, name = record.name,
                robloxPath = record.path, className = record.className, service = service,
                evidence = "static_inventory", knownScriptLinks = {},
                observedScriptLinks = previousRemote and previousRemote.observedScriptLinks or {}}
        elseif record.category == "gui" then
            guiIndex[record.instanceId] = {instanceId = record.instanceId, name = record.name,
                robloxPath = record.path, className = record.className, service = service,
                parentInstanceId = record.parentInstanceId, sequence = record.sequence,
                visible = record.properties.Visible, enabled = record.properties.Enabled,
                text = record.properties.Text, operation = record.operation}
        end
        return true
    end
    local function targetDirectory(category, service)
        if not cfg.organizedOutput then return base end
        return base .. "/" .. category .. "/" .. service
    end

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
            category = record.category,
            operation = record.operation,
            observedAtUtc = record.observedAtUtc,
            instanceId = record.instanceId, parentInstanceId = record.parentInstanceId,
            sequence = record.sequence, scriptId = record.scriptId,
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

    local function flush(records, serviceName, pass, category)
        if #records == 0 then return true end
        category = (CATEGORIES[category] and category) or "other"
        local okEncode, encoded = pcall(encodeChunk, records, cfg.format, serviceName, pass, category)
        if not okEncode and #records > 1 then
            -- Keep all valid records if one item has an invalid JSON value.
            local half = math.floor(#records / 2)
            local left, right = {}, {}
            for i = 1, half do left[#left + 1] = records[i] end
            for i = half + 1, #records do right[#right + 1] = records[i] end
            return flush(left, serviceName, pass, category)
                and flush(right, serviceName, pass, category)
        end
        if not okEncode then
            local fixed = repairRecord(records[1])
            okEncode, encoded = pcall(encodeChunk, {fixed}, cfg.format, serviceName, pass, category)
            if not okEncode then
                fixed.properties = {}
                okEncode, encoded = pcall(encodeChunk, {fixed}, cfg.format, serviceName, pass, category)
            end
            if not okEncode then
                addError(state, "record_encode_failed:" .. serviceName)
                partial("encoding_error")
                return false
            end
            partial("record_serialization_recovered")
            addError(state, "record_serialization_recovered:" .. serviceName)
        end

        local directory = targetDirectory(category, serviceName)
        if not createdDataFolders[directory] then
            if not createFolders(directory) then
                addError(state, "directory_create_failed:" .. serviceName .. ":" .. category)
                partial("write_error")
                return false
            end
            createdDataFolders[directory] = true
        end

        -- Flat mode has one index namespace per service/pass to avoid
        -- category A overwriting category B's p1-0001 chunk.
        local key = cfg.organizedOutput
            and (category .. "/" .. serviceName .. "/p" .. tostring(pass))
            or (serviceName .. "/p" .. tostring(pass))
        local part = (chunkIndexes[key] or 0) + 1
        local ext = cfg.format == "json" and "json" or cfg.format
        local filename
        if cfg.organizedOutput then
            filename = string.format("%s/p%d-%04d.%s", directory, pass, part, ext)
        else
            filename = string.format("%s/%s-p%d-%04d.%s", base, serviceName, pass, part, ext)
        end
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
        local summary = state.categories[category]
        if not summary then
            summary = {records = 0, files = 0, services = {}}
            state.categories[category] = summary
        end
        summary.records = summary.records + #records
        summary.files = summary.files + 1
        local byService = summary.services[serviceName]
        if not byService then
            byService = {records = 0, files = 0}
            summary.services[serviceName] = byService
        end
        byService.records = byService.records + #records
        byService.files = byService.files + 1
        notify(onProgress, "file_written", state, serviceName)
        return true
    end

    -- Category-aware buffering bounds memory without dropping references to
    -- object parents that happen to be stored in a different folder.
    local function bufferRecord(buckets, record, serviceName, pass, category)
        category = (CATEGORIES[category] and category) or "other"
        record.category = category
        local bucket = buckets[category]
        if not bucket then
            bucket = {}
            buckets[category] = bucket
        end
        bucket[#bucket + 1] = record
        if #bucket >= cfg.chunkSize then
            if not flush(bucket, serviceName, pass, category) then return false end
            buckets[category] = {}
        end
        return true
    end

    local function flushBuckets(buckets, serviceName, pass)
        for category, bucket in pairs(buckets) do
            if #bucket > 0 and not flush(bucket, serviceName, pass, category) then
                return false
            end
        end
        return true
    end

    local function scan(serviceName, pass, mode)
        if stopCheck() then return end
        local deltaMode = cfg.continuous and mode == "delta"
        local previousSnapshot = serviceSnapshots[serviceName] or {}
        local seenIds = {}
        local scanStartSequence = nextSequence
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
        local buckets, steps = {}, 0
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
                    local category = categoryFor(obj, serviceName, class)
                    local record = {
                        name = name, className = class, path = frame.path,
                        parentPath = frame.parent, depth = frame.depth, properties = properties,
                        category = category,
                    }
                    identify(record, obj)
                    seenIds[record.instanceId] = true
                    local include = observeRecord(record, serviceName,
                        deltaMode and "delta" or "baseline", obj)
                    if include and not bufferRecord(buckets, record, serviceName, pass, category) then
                        state.stopped = true
                        break
                    end
                    state.classes[class] = (state.classes[class] or 0) + 1

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
                flushDiagnostics()
                notify(onProgress, "scanning", state, serviceName)
                task.wait()
            end
        end

        -- Tombstones preserve the same category as the original instance,
        -- even when that instance no longer exists on the client.
        if deltaMode and not state.stopped then
            local inspected = 0
            for id, previous in pairs(previousSnapshot) do
                if stopCheck() then break end
                if not seenIds[id] and previous.sequence <= scanStartSequence then
                    local tombstone = {
                        operation = "remove", observedAtUtc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
                        name = previous.name, className = previous.className,
                        path = previous.path, parentPath = previous.parentPath,
                        depth = previous.depth, properties = {}, category = previous.category,
                        instanceId = previous.instanceId, parentInstanceId = previous.parentInstanceId,
                    }
                    observeRecord(tombstone, serviceName, "remove")
                    if not bufferRecord(buckets, tombstone, serviceName, pass,
                        previous.category or categoryFor(nil, serviceName, previous.className)) then
                        state.stopped = true; break
                    end
                end
                inspected = inspected + 1
                if inspected % cfg.yieldEvery == 0 then task.wait() end
            end
        end
        -- A manual stop preserves records already inspected in every category.
        if not state.stopped or state.cancelled or state.stopRequested then
            if not flushBuckets(buckets, serviceName, pass) then state.stopped = true end
        end
        state.pending = 0
        notify(onProgress, "service_done", state, serviceName)
    end

    -- A provisional manifest makes long-running sessions inspectable and
    -- recoverable even if Roblox/executor exits without an orderly Stop.
    local function checkpoint()
        flushDiagnostics()
        local payload = {
            schemaVersion = Exporter.SCHEMA_VERSION,
            exporterVersion = Exporter.VERSION, clientOnly = true,
            status = "recording", captureMode = cfg.continuous and "continuous" or "exhaustive",
            capturedAtUtc = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            game = {
                label = sanitizedString(cfg.label, cfg, state),
                category = sanitizedString(cfg.category, cfg, state),
                variant = sanitizedString(cfg.variant, cfg, state),
                placeId = game.PlaceId, gameId = game.GameId,
            },
            stats = {
                visited = state.visited, written = state.written, files = state.fileCount,
                bytes = state.bytes, assetReferences = state.assetReferences,
                classCounts = state.classes, redactions = state.redactions,
                errors = state.errorCount, elapsedSeconds = os.clock() - state.startedAt,
                monitorCycles = state.monitorCycles, deltaRecords = state.deltaRecords,
                added = state.added, updated = state.updated, removed = state.removed,
            },
            services = state.services,
            scriptExport = deep:summary(),
            diagnostics = diagnostics,
            identity = {version = 1, scope = "capture_local", ordering = "sequence", lastSequence = nextSequence},
            categories = state.categories,
            layout = {version = cfg.organizedOutput and 2 or 1,
                id = cfg.organizedOutput and "categorized" or "flat"},
            errors = state.errors,
            partialReasons = {},
            settings = {format = cfg.format, chunkSize = cfg.chunkSize,
                continuous = cfg.continuous, continuousInterval = cfg.continuousInterval,
                captureMode = cfg.continuous and "continuous" or "exhaustive", targets = cfg.targets,
                includeReconstructedCode = cfg.includeReconstructedCode,
                organizedOutput = cfg.organizedOutput,
                includeAttributes = cfg.includeAttributes,
                includeTags = cfg.includeTags},
        }
        local ok, encoded = pcall(function() return HttpService:JSONEncode(payload) end)
        if not ok or not pcall(writefile, base .. "/manifest.json", encoded) then
            partial("checkpoint_write_failed")
            addError(state, "checkpoint_write_failed")
        end
    end

    local monitorConnections = {}
    local watchedRoots = {}
    local events = {}
    local eventHead = 1
    local eventTail = 0

    local function disconnectMonitoring()
        for _, connection in ipairs(monitorConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(monitorConnections)
    end

    local function pathFor(instance, service, root)
        local names, depth = {}, 0
        local obj = instance
        local seenParents = {}
        while obj and obj ~= root do
            if seenParents[obj] then return nil end
            seenParents[obj] = true
            if state.characters[obj] or isForbidden(obj, service, state) then return nil end
            names[#names + 1] = readName(obj, cfg, state):gsub("[./\\]", "_")
            local okParent, parent = pcall(function() return obj.Parent end)
            if not okParent then return nil end
            obj = parent
            depth = depth + 1
        end
        if obj ~= root then return nil end
        local parts = {service}
        for i = #names, 1, -1 do parts[#parts + 1] = names[i] end
        local path = table.concat(parts, "/")
        local parentPath = #parts > 1 and table.concat(parts, "/", 1, #parts - 1) or ""
        return path, parentPath, depth
    end

    local function enqueue(service, root, instance, operation)
        local path, parent, depth = pathFor(instance, service, root)
        if not path then return end
        local okClass, class = pcall(function() return instance.ClassName end)
        if not okClass then return end
        local category = categoryFor(instance, service, class)
        local record = {name = readName(instance, cfg, state), className = class,
            path = path, parentPath = parent, depth = depth, category = category,
            properties = operation == "remove" and {} or collectProperties(instance, cfg, state)}
        record.instanceId = identity(instance)
        local okParent, parentInstance = pcall(function() return instance.Parent end)
        record.parentInstanceId = okParent and identity(parentInstance) or nil
        if operation == "remove" and not (serviceSnapshots[service] or {})[record.instanceId] then
            -- Existing object disappeared before its baseline visit: preserve it
            -- while DescendantRemoving still exposes the original instance.
            enqueue(service, root, instance, "add")
        end
        if not observeRecord(record, service, operation, instance) then return end
        identify(record, instance, service)
        eventTail = eventTail + 1
        events[eventTail] = {service = service, record = record}
    end

    local function attachListeners()
        for _, service in ipairs(Exporter.TARGETS) do
            if cfg.targets[service] and not watchedRoots[service] then
                local root = rootInstance(service)
                if root and root.DescendantAdded and root.DescendantRemoving then
                    local okAdded, added = pcall(function()
                        return root.DescendantAdded:Connect(function(obj)
                            enqueue(service, root, obj, "add")
                        end)
                    end)
                    local okRemoved, removed = pcall(function()
                        return root.DescendantRemoving:Connect(function(obj)
                            enqueue(service, root, obj, "remove")
                        end)
                    end)
                    if okAdded and okRemoved then
                        watchedRoots[service] = root
                        monitorConnections[#monitorConnections + 1] = added
                        monitorConnections[#monitorConnections + 1] = removed
                    else
                        if okAdded then added:Disconnect() end
                        if okRemoved then removed:Disconnect() end
                        partial("event_monitor_unavailable:" .. service)
                    end
                end
            end
        end
    end

    local function processEvents(drain)
        flushDiagnostics()
        local perService = {}
        local steps = 0
        while eventHead <= eventTail and (drain or not stopCheck()) do
            local event = events[eventHead]
            events[eventHead] = nil
            eventHead = eventHead + 1
            if event then
                local record = event.record
                local class = record.className
                state.visited = state.visited + 1
                state.discovered = state.discovered + 1
                state.currentService = event.service
                state.currentPath = record.path
                state.currentClass = class
                state.currentPass = 2
                state.classes[class] = (state.classes[class] or 0) + 1
                local serviceStats = state.services[event.service]
                if serviceStats then
                    serviceStats.visited = serviceStats.visited + 1
                    serviceStats.passes = math.max(serviceStats.passes, 2)
                    local buckets = perService[event.service]
                    if not buckets then
                        buckets = {}
                        perService[event.service] = buckets
                    end
                    if not bufferRecord(buckets, record, event.service, 2,
                        record.category) then
                        state.stopped = true
                        break
                    end
                end
            end
            steps = steps + 1
            if steps % cfg.yieldEvery == 0 then
                notify(onProgress, "monitoring", state)
                task.wait()
            end
        end
        -- Empty the queue only after all currently queued items were read.
        if eventHead > eventTail then
            events = {}; eventHead = 1; eventTail = 0
        end
        -- Flush small batches too: a menu may be opened only briefly.
        for service, buckets in pairs(perService) do
            if not flushBuckets(buckets, service, 2) then state.stopped = true end
        end
    end

    local shared = (type(getgenv) == "function" and getgenv()) or {}
    local bridge
    control._lesbhubCleanup = function()
        disconnectMonitoring()
        for _, connection in ipairs(diagnosticConnections) do pcall(function() connection:Disconnect() end) end
        if bridge and shared.LesbhubExporterObserveRemote == bridge then shared.LesbhubExporterObserveRemote = nil end
    end
    if cfg.observeRemotes then
        local selectedRoots = {}
        for name in pairs(cfg.targets) do
            local root = rootInstance(name)
            if root then selectedRoots[name] = root end
        end
        bridge = function(info, remote, direction)
            if direction ~= "Incoming" and direction ~= "Outgoing" then return end
            local service, root
            for name, candidate in pairs(selectedRoots) do
                local ok, inside = pcall(function() return remote:IsDescendantOf(candidate) end)
                if candidate and ok and inside then service, root = name, candidate; break end
            end
            if not root then return end
            local path = pathFor(remote, service, root)
            if not path or not REMOTE_CLASSES[remote.ClassName] then return end
            local id = identity(remote)
            -- Cobalt documents info.Origin. Accept an actual Instance only;
            -- never infer a caller from a string, script name or similar path.
            local caller = type(info) == "table" and info.Origin or nil
            local scriptId
            if typeof(caller) == "Instance" then
                local callerId = identity(caller)
                if callerId and deep.seen["s" .. callerId] then scriptId = "s" .. callerId end
            end
            local args = type(info) == "table" and info.Arguments or nil
            local types, count = {}, type(args) == "table" and (tonumber(args.n) or #args) or 0
            for i = 1, math.min(count, 32) do types[#types + 1] = typeof(args[i]) end
            if count > 32 then types[#types + 1] = "additional_arguments_omitted" end
            diagnosticEvent("remotes/observations.jsonl", {instanceId = id, robloxPath = path,
                className = remote.ClassName, direction = direction, argumentTypes = types,
                argumentCount = count, scriptId = scriptId, evidence = "cobalt_observed"})
            local item = remoteIndex[id]
            if not item then
                item = {instanceId = id, name = readName(remote, cfg, state), robloxPath = path,
                    className = remote.ClassName, service = service, evidence = "cobalt_observed",
                    knownScriptLinks = {}, observedScriptLinks = {}}
                remoteIndex[id] = item
            end
            if scriptId and not table.find(item.observedScriptLinks, scriptId) then
                item.observedScriptLinks[#item.observedScriptLinks + 1] = scriptId
                diagnostics.knownCallers = diagnostics.knownCallers + 1
            end
            diagnostics.remoteObservations = diagnostics.remoteObservations + 1
            diagnostics.cobaltAttached = true
        end
        shared.LesbhubExporterObserveRemote = bridge
    end

    -- Subscribe before scanning, including before GUI/operator interactions.
    -- Event records capture properties immediately; no task.spawn per event.
    if cfg.continuous then attachListeners() end
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

    if not cfg.continuous and cfg.twoPassGui and not state.stopped
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

    if cfg.continuous then processEvents(true) end
    deep:saveIndex()
    checkpoint()
    deep:drain()

    if cfg.continuous and not state.stopped and selected > 0 then
        -- Event handlers capture transient additions/removals (including Workspace);
        -- periodic delta rescans catch changes to already-existing GUI text/visibility.
        local okMonitor, monitorError = pcall(function()
            attachListeners()
            checkpoint()
            state.monitoring = true
            notify(onProgress, "monitoring_start", state)
            local lastSharedScan = os.clock()
            local cyclePass = 1
            while not stopCheck() do
                local deadline = os.clock() + cfg.continuousInterval
                while os.clock() < deadline and not stopCheck() do
                    processEvents()
                    task.wait(0.15)
                end
                if stopCheck() then break end
                attachListeners()
                processEvents()
                deep:drain()
                cyclePass = cyclePass + 1
                state.monitorCycles = state.monitorCycles + 1
                for _, service in ipairs({"PlayerGui", "StarterGui"}) do
                    if cfg.targets[service] then scan(service, cyclePass, "delta") end
                    if state.stopped then break end
                end
                if state.stopped then break end
                -- Less frequent structural refresh. Workspace is event-driven
                -- because polling hundreds of thousands of map parts is wasteful.
                if os.clock() - lastSharedScan >= math.max(15, cfg.continuousInterval * 5) then
                    lastSharedScan = os.clock()
                    for _, service in ipairs(Exporter.TARGETS) do
                        if cfg.targets[service] and service ~= "PlayerGui"
                            and service ~= "StarterGui" and service ~= "Workspace" then
                            scan(service, cyclePass, "delta")
                        end
                        if state.stopped then break end
                    end
                end
                if state.stopped then break end
                if state.monitorCycles % 3 == 0 then checkpoint() end
                notify(onProgress, "monitoring", state)
            end
            disconnectMonitoring()
            processEvents(true)
            if state.stopRequested and not state.cancelled
                and (cfg.targets.PlayerGui or cfg.targets.StarterGui) then
                -- One last sweep catches the GUI state at the instant Stop
                -- was pressed, even if the scheduled interval was not due.
                -- Do not mistake this deliberate last sweep for a background loop.
                notify(onProgress, "monitoring_finalizing", state)
                control.stopRequested = false
                state.stopped = false
                cyclePass = cyclePass + 1
                for _, service in ipairs({"PlayerGui", "StarterGui"}) do
                    if cfg.targets[service] then scan(service, cyclePass, "delta") end
                    if state.stopped then break end
                end
                control.stopRequested = true
                state.stopped = true
            end
        end)
        state.monitoring = false
        disconnectMonitoring()
        if not okMonitor then
            partial("monitoring_error")
            addError(state, "monitoring_error:" .. tostring(monitorError):sub(1, 130))
            state.stopped = true
        end
        notify(onProgress, "monitoring_stopped", state)
    end

    deep:drain()
    deep:saveIndex()
    for _, connection in ipairs(diagnosticConnections) do pcall(function() connection:Disconnect() end) end
    if bridge and shared.LesbhubExporterObserveRemote == bridge then shared.LesbhubExporterObserveRemote = nil end
    flushDiagnostics()
    local scriptSummary = deep:summary()
    if not scriptSummary.indexWritten then partial("script_index_write_failed") end
    if cfg.includeReconstructedCode then
        local stats = scriptSummary.stats
        if stats.failed + stats.partial + stats.empty + stats.inaccessible > 0 then
            partial("script_extraction_incomplete")
        end
    end
    local function ordered(index)
        local rows = {}
        for _, item in pairs(index) do rows[#rows + 1] = item end
        table.sort(rows, function(a, b) return a.instanceId < b.instanceId end)
        return rows
    end
    local function writeIndex(path, payload)
        local ok = pcall(function()
            assert(createFolders((base .. "/" .. path):match("^(.*)/[^/]+$")))
            local encoded, text = pcall(function() return HttpService:JSONEncode(payload) end)
            if not encoded then
                text = HttpService:JSONEncode(portableJson(payload))
                partial("index_serialization_recovered:" .. path)
            end
            writefile(base .. "/" .. path, text)
        end)
        if not ok then partial("index_write_failed:" .. path) end
    end
    writeIndex("remotes/index.json", {version = 1, evidence = "static_inventory", remotes = ordered(remoteIndex)})
    writeIndex("gui/index.json", {version = 1, scope = "latest observed state; history is in chunks", elements = ordered(guiIndex)})
    writeIndex("report.json", {version = 1, scriptExport = scriptSummary,
        diagnostics = diagnostics, dataRecords = state.written, dataFiles = state.fileCount,
        scriptIndex = "scripts/index.json", remoteIndex = "remotes/index.json", guiIndex = "gui/index.json"})
    local report = {"# Deep Export " .. Exporter.VERSION, "", "Client-visible reconstructed pseudocode only.",
        "", "Script index: scripts/index.json", "Remote index: remotes/index.json", "GUI index: gui/index.json",
        "", "Discovered: " .. scriptSummary.stats.discovered,
        "Succeeded: " .. scriptSummary.stats.succeeded, "Partial: " .. scriptSummary.stats.partial,
        "Failed: " .. scriptSummary.stats.failed, "Inaccessible: " .. scriptSummary.stats.inaccessible,
        "Empty: " .. scriptSummary.stats.empty, "", "## Failures and limitations"}
    for _, entry in ipairs(deep.entries) do
        if entry.status ~= "success" then
            report[#report + 1] = entry.scriptId .. " | " .. entry.robloxPath .. " | " .. entry.status .. " | " .. entry.error
        end
    end
    if not pcall(writefile, base .. "/report.md", table.concat(report, "\n") .. "\n") then partial("report_write_failed") end
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
        status = state.cancelled and "cancelled" or
            (state.stopRequested and "stopped" or (#reasons > 0 and "partial" or "complete")),
        endedReason = state.cancelled and "cancelled" or
            (state.stopRequested and "user_stopped" or "finished"),
        partialReasons = reasons,
        stats = {
            visited = state.visited, written = state.written, files = state.fileCount,
            bytes = state.bytes, redactions = state.redactions, errors = state.errorCount,
            assetReferences = state.assetReferences, classCounts = state.classes,
            elapsedSeconds = os.clock() - state.startedAt,
            monitorCycles = state.monitorCycles, deltaRecords = state.deltaRecords,
            added = state.added, updated = state.updated, removed = state.removed,
        },
        scriptExport = scriptSummary,
        diagnostics = diagnostics,
        identity = {version = 1, scope = "capture_local", ordering = "sequence", lastSequence = nextSequence},
        services = state.services,
        categories = state.categories,
        layout = {version = cfg.organizedOutput and 2 or 1,
            id = cfg.organizedOutput and "categorized" or "flat"},
        errors = state.errors,
        settings = {
            format = cfg.format, targets = cfg.targets, guiTexts = cfg.guiTexts,
            guiProperties = cfg.guiProperties, worldProperties = cfg.worldProperties,
            includeReconstructedCode = cfg.includeReconstructedCode,
            observeGuiActions = cfg.observeGuiActions, observeRemotes = cfg.observeRemotes,
            assets = cfg.assets, includeAttributes = cfg.includeAttributes,
            includeTags = cfg.includeTags, textboxValues = cfg.textboxValues,
            stringValues = cfg.stringValues, twoPassGui = cfg.twoPassGui,
            guiPasses = cfg.guiPasses, secondPassDelay = cfg.secondPassDelay,
            chunkSize = cfg.chunkSize, yieldEvery = cfg.yieldEvery,
            organizedOutput = cfg.organizedOutput,
            continuous = cfg.continuous, continuousInterval = cfg.continuousInterval,
            captureMode = cfg.continuous and "continuous" or "exhaustive",
        },
        privacy = {
            excludesOtherPlayerCharacters = true,
            redactsKnownPlayerNames = true,
            excludesChatGui = true,
            excludesScriptSource = true,
            includesReconstructedCode = cfg.includeReconstructedCode,
            excludesTextboxValuesByDefault = true,
            includesSessionOrPrivateServerIds = false,
        },
        notes = {
            "Client view only: server-only objects are unavailable.",
            "StreamingEnabled can result in missing Workspace descendants.",
            "No global node, depth, total byte, or string-length limit is applied.",
            "GUI snapshots are not merged; lazy menus must be opened by the operator.",
            "Categorized output places data in category/service subfolders while preserving original paths.",
            "Script metadata remains in chunks; opted-in reconstructed code is in scripts/sources with scripts/index.json.",
            "Native Archivable/Enabled/RunContext, attributes, tags and safe client-visible Instance references are collected when readable.",
            "RemoteInfo contains documented class capabilities only; not intercepted traffic, handlers, argument schemas or observed call direction.",
            "Continuous mode: pass 1 is a full snapshot; later records have operations add/update/remove.",
            "Workspace changes are captured through client DescendantAdded/DescendantRemoving events.",
            "GUI properties are refreshed periodically and unchanged records are not rewritten.",
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

local captureRunning = false
function Exporter.capture(options, onProgress, control)
    if captureRunning then return nil, "a capture is already running" end
    captureRunning = true
    control = type(control) == "table" and control or {}
    local ok, result, err = pcall(capture, options, onProgress, control)
    if type(control._lesbhubCleanup) == "function" then pcall(control._lesbhubCleanup) end
    control._lesbhubCleanup = nil
    captureRunning = false
    if not ok then return nil, tostring(result) end
    return result, err
end

local function safeCaptureFolder(folder)
    if type(folder) ~= "string" or folder:sub(1, 16) ~= "LesbhubExporter/"
        or folder:find("[\\:%c]") or folder:find("//", 1, true) then return false end
    for part in folder:gmatch("[^/]+") do if part == "." or part == ".." then return false end end
    return true
end

function Exporter.search(folder, query)
    if not safeCaptureFolder(folder) or type(readfile) ~= "function" then return nil, "capture is unavailable" end
    query = tostring(query or ""):lower()
    if query == "" then return {}, "" end
    local matches = {}
    for _, item in ipairs({{"scripts/index.json", "scripts"}, {"remotes/index.json", "remotes"}, {"gui/index.json", "elements"}}) do
        local ok, index = pcall(function() return HttpService:JSONDecode(readfile(folder .. "/" .. item[1])) end)
        if ok and type(index) == "table" then
            for _, row in ipairs(index[item[2]] or {}) do
                local text = tostring(row.name or "") .. " " .. tostring(row.robloxPath or "")
                    .. " " .. tostring(row.latestObservedPath or "")
                if text:lower():find(query, 1, true) then
                    matches[#matches + 1] = {kind = item[2], name = row.name, robloxPath = row.robloxPath,
                        outputPath = row.outputPath, scriptId = row.scriptId, status = row.status}
                    if #matches >= 50 then return matches, "first 50 matches" end
                end
            end
        end
    end
    return matches, ""
end

function Exporter.resumeScripts(folder, onProgress, control)
    if not safeCaptureFolder(folder) or type(readfile) ~= "function" then return nil, "unsafe/unavailable capture" end
    local ok, manifest, index = pcall(function()
        return HttpService:JSONDecode(readfile(folder .. "/manifest.json")),
            HttpService:JSONDecode(readfile(folder .. "/scripts/index.json"))
    end)
    if not ok or type(manifest) ~= "table" or type(index) ~= "table" then return nil, "unreadable capture/index" end
    if not manifest.scriptExport or manifest.scriptExport.runtimeToken ~= DeepScripts.runtimeToken
        or manifest.game.placeId ~= game.PlaceId or manifest.game.gameId ~= game.GameId then
        return nil, "resume requires the original Roblox/executor session; instance identities cannot be guessed"
    end
    local progressOk, progress = pcall(readfile, folder .. "/scripts/progress.jsonl")
    if progressOk then
        local byId = {}
        for i, entry in ipairs(index.scripts) do byId[entry.scriptId] = i end
        for line in progress:gmatch("[^\r\n]+") do
            local decoded, entry = pcall(function() return HttpService:JSONDecode(line) end)
            if decoded and type(entry) == "table" and byId[entry.scriptId] then
                index.scripts[byId[entry.scriptId]] = entry
            end
        end
    end
    local candidates = {}
    for service, selected in pairs(manifest.settings.targets) do
        local root = selected and table.find(Exporter.TARGETS, service) and rootInstance(service)
        if root then
            local stack = {root}
            local steps = 0
            while #stack > 0 do
                if control and control.cancelled then return nil, "cancelled" end
                local obj = table.remove(stack)
                if obj.ClassName == "LocalScript" or obj.ClassName == "ModuleScript" or obj.ClassName == "Script" then
                    local readable, id = pcall(function() return obj:GetDebugId() end)
                    if readable then candidates[id] = obj end
                end
                local childrenOk, children = pcall(function() return obj:GetChildren() end)
                if childrenOk then for _, child in ipairs(children) do stack[#stack + 1] = child end end
                steps = steps + 1
                if steps % 100 == 0 then task.wait() end
            end
        end
    end
    local deep = DeepScripts.new(folder, true, control, onProgress)
    local resumed, resumeError = pcall(function() deep:resume(index.scripts, function(entry)
        local instance = candidates[entry.debugId]
        return instance and instance.ClassName == entry.className and instance or nil
    end) end)
    if not resumed then return nil, "could not resume scripts: " .. tostring(resumeError) end
    manifest.scriptExport = deep:summary()
    manifest.scriptExport.resumed = true
    manifest.settings.includeReconstructedCode = true
    manifest.privacy = manifest.privacy or {}
    manifest.privacy.includesReconstructedCode = true
    local scripts = manifest.scriptExport.stats
    local incomplete = scripts.failed + scripts.partial + scripts.empty + scripts.inaccessible > 0
    local reasons = {}
    for _, reason in ipairs(manifest.partialReasons) do
        if reason ~= "script_extraction_incomplete" then reasons[#reasons + 1] = reason end
    end
    if incomplete then reasons[#reasons + 1] = "script_extraction_incomplete" end
    manifest.partialReasons = reasons
    if manifest.status == "complete" or manifest.status == "partial" then
        manifest.status = #reasons > 0 and "partial" or "complete"
    end
    local reportOk, report = pcall(function() return HttpService:JSONDecode(readfile(folder .. "/report.json")) end)
    if reportOk and type(report) == "table" then
        report.scriptExport = manifest.scriptExport
        pcall(function() writefile(folder .. "/report.json", HttpService:JSONEncode(report)) end)
    end
    local reportLines = {"# Deep Export " .. Exporter.VERSION .. " (script extraction resumed)", "",
        "The structural snapshots were not recaptured.", "", "Script index: scripts/index.json", "",
        "Succeeded: " .. scripts.succeeded, "Partial: " .. scripts.partial,
        "Failed: " .. scripts.failed, "Inaccessible: " .. scripts.inaccessible, "Empty: " .. scripts.empty}
    for _, entry in ipairs(deep.entries) do
        if entry.status ~= "success" then reportLines[#reportLines + 1] = entry.scriptId .. " | " .. entry.error end
    end
    pcall(writefile, folder .. "/report.md", table.concat(reportLines, "\n") .. "\n")
    local saved = pcall(function() writefile(folder .. "/manifest.json", HttpService:JSONEncode(manifest)) end)
    if not saved then return nil, "could not update resumed manifest" end
    return {folder = folder, manifest = manifest}
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
