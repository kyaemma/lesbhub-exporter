-- Lesbhub Exporter V1 - client-side, read-only capture engine.
-- Reconstructed client code defaults on; no remote invocation or uploads.
local Journal = require("./journal")
local Checkpoints = require("./checkpoints")
local DeepScripts = require("./deep_scripts")
local WorkBudget = require("./work_budget")
local SourceAnalysis = require("./source_analysis")
local RuntimeObserver = require("./runtime_observer")
local GuiStates = require("./gui_states")
local ClientMetadata = require("./client_metadata")
local Report = require("./report")
local Relations = require("./relations")
local Exporter = {}
Exporter.VERSION = "0.9.0"
Exporter.SCHEMA_VERSION = 1
Exporter.TARGETS = {
    "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "PlayerGui",
    "StarterPlayer", "PlayerScripts", "StarterPack", "Workspace",
    "Lighting", "SoundService", "Teams",
}

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local hasCharacterLookup, characterLookup = pcall(function() return Players.GetPlayerFromCharacter end)
if not hasCharacterLookup or type(characterLookup) ~= "function" then characterLookup = nil end

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
    local aliases, seen = {}, {}
    local characters = setmetatable({}, {__mode = "k"})
    local watched = setmetatable({}, {__mode = "k"})
    local connections, tracker = {}, {complete = true}
    local function connect(signal, callback)
        local ok, connection = pcall(function() return signal:Connect(callback) end)
        if ok and connection then connections[#connections + 1] = connection; return true end
        return false
    end
    local function addName(name)
        if type(name) ~= "string" or #name < 3 or seen[name:lower()] then return false end
        aliases[#aliases + 1] = name
        seen[name:lower()] = true
        return true
    end
    local function refreshNames(player)
        local okName, name = pcall(function() return player.Name end)
        local okDisplay, display = pcall(function() return player.DisplayName end)
        local added = okName and addName(name) or false
        if okDisplay and addName(display) then added = true end
        if added then table.sort(aliases, function(a, b) return #a > #b end) end
    end
    local function watchPlayer(player)
        if not player or watched[player] then return end
        watched[player] = true
        refreshNames(player)
        local isOther = player ~= Players.LocalPlayer
        if isOther then
            local function rememberCharacter(character)
                if character then characters[character] = true end
            end
            local okSignal, signal = pcall(function() return player.CharacterAdded end)
            if not okSignal or not connect(signal, rememberCharacter) then tracker.complete = false end
            local propertyOk, propertySignal = pcall(function() return player:GetPropertyChangedSignal("Character") end)
            if propertyOk and propertySignal then
                connect(propertySignal, function()
                    local readable, current = pcall(function() return player.Character end)
                    if readable then rememberCharacter(current) end
                end)
            end
            local okCharacter, character = pcall(function() return player.Character end)
            if okCharacter then rememberCharacter(character) else tracker.complete = false end
        end
        for _, property in ipairs({"Name", "DisplayName"}) do
            local okSignal, signal = pcall(function() return player:GetPropertyChangedSignal(property) end)
            if okSignal and signal then connect(signal, function() refreshNames(player) end) end
        end
    end
    local okSignal, added = pcall(function() return Players.PlayerAdded end)
    if not okSignal or not connect(added, watchPlayer) then tracker.complete = false end
    local ok, users = pcall(function() return Players:GetPlayers() end)
    if ok and type(users) == "table" then
        for _, player in ipairs(users) do watchPlayer(player) end
    else tracker.complete = false end
    local function cleanup()
        for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
        table.clear(connections)
    end
    return aliases, characters, cleanup, tracker
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
            return {kind = "InstanceRef", className = className, path = table.concat(path, "/"),
                instanceId = state.identity and state.identity(target) or nil}
        elseif parent == localPlayer then
            if not cfg.targets[segment] then return nil end
            local path = {}
            for i = #parts, 1, -1 do path[#path + 1] = parts[i] end
            return {kind = "InstanceRef", className = className, path = table.concat(path, "/"),
                instanceId = state.identity and state.identity(target) or nil}
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
    local properties = {}
    state.propertyPlans = state.propertyPlans or {}
    local plan = state.propertyPlans[class]
    if not plan then
        local wanted, unique = {}, {}
        local cacheable = true
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
            if not okGui then cacheable = false end
        end
        if cfg.guiProperties or cfg.guiTexts or cfg.assets or cfg.textboxValues then
            include(GUI_CLASSES[class], "gui")
        end
        if cfg.worldProperties or cfg.assets or cfg.stringValues then
            local okPart, isPart = pcall(function() return instance:IsA("BasePart") end)
            if okPart and isPart then include(OTHER_CLASSES.BasePart, "world") end
            if not okPart then cacheable = false end
            include(OTHER_CLASSES[class], "world")
        end

        plan = {wanted = wanted, unique = unique}
        if cacheable then state.propertyPlans[class] = plan end
    end
    local wanted, unique = plan.wanted, plan.unique

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
    if root == "Workspace" and characterLookup then
        local okClass, class = pcall(function() return instance.ClassName end)
        if okClass and class == "Model" then
            local okPlayer, player = pcall(characterLookup, Players, instance)
            if okPlayer and player and player ~= Players.LocalPlayer then
                state.characters[instance] = true
                return true
            end
        end
    end
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
    cfg.observeGuiActions = input.observeGuiActions ~= false
    cfg.observeRemotes = input.observeRemotes ~= false
    cfg.publicGameMetadata = input.publicGameMetadata ~= false
    cfg.runtimeWindowSeconds = clamp(input.runtimeWindowSeconds, 0, 60, 6)
    cfg.frameBudgetMs = math.max(1, math.min(12, tonumber(input.frameBudgetMs) or 6))
    cfg.textboxValues = input.textboxValues == true
    cfg.stringValues = input.stringValues == true
    cfg.twoPassGui = input.twoPassGui == true
    cfg.continuous = input.continuous == true
    -- Continuous monitoring continues until an explicit stop/cancel.
    -- The interval is a cadence, NOT a dataset or duration cap.
    cfg.continuousInterval = clamp(input.continuousInterval, 1, 30, 3)
    cfg.eventQueueLimit = clamp(input.eventQueueLimit, 1, 1000000, 8192)
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
local function stableValue(value, ancestors)
    local kind = type(value)
    if kind ~= "table" then
        local bytes = kind == "number" and string.format("%.17g", value) or tostring(value)
        return kind .. ":" .. #bytes .. ":" .. bytes
    end
    ancestors = ancestors or {}
    assert(not ancestors[value], "cyclic structural value")
    ancestors[value] = true
    local entries = {}
    for key, item in pairs(value) do
        local encodedKey = stableValue(key, ancestors)
        local encodedValue = stableValue(item, ancestors)
        entries[#entries + 1] = #encodedKey .. ":" .. encodedKey .. #encodedValue .. ":" .. encodedValue
    end
    ancestors[value] = nil
    table.sort(entries)
    return "table:" .. #entries .. ":" .. table.concat(entries)
end

local function recordFingerprint(record)
    return stableValue({className = record.className, properties = record.properties or {}})
end

local function capture(options, onProgress, control)
    local cfg = normalizedConfig(options)
    control = type(control) == "table" and control or {}
    local budget = WorkBudget.new(cfg, control)
    if type(writefile) ~= "function" or type(makefolder) ~= "function" then
        return nil, "file APIs writefile/makefolder are required"
    end

    local time = os.date("!%Y%m%dT%H%M%SZ")
    local base = "LesbhubExporter/" .. slug(cfg.category) .. "/" .. slug(cfg.label) .. "/" ..
        slug(cfg.variant) .. "/" .. time .. "-" .. tostring(math.floor(os.clock() * 1000))
    if not createFolders(base) then return nil, "could not create export directory" end

    local aliases, characters, stopPlayerTracking, playerTracker = playerAliases()
    control._lesbhubCleanup = stopPlayerTracking
    local state = {
        aliases = aliases, characters = characters, redactions = 0,
        visited = 0, written = 0, fileCount = 0, bytes = 0, discovered = 0,
        pending = 0, assetReferences = 0, currentPath = "", currentClass = "",
        currentService = "", currentPass = 1, startedAt = os.clock(),
        errors = {}, errorCount = 0, partialReasons = {}, services = {},
        classes = {}, categories = {}, cancelled = false, stopped = false,
        stopRequested = false, monitoring = false, monitorCycles = 0,
        deltaRecords = 0, added = 0, updated = 0, removed = 0, propertyPlans = {},
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
    local liveInstances = setmetatable({}, {__mode = "v"})
    local debugIdentities = setmetatable({}, {__mode = "v"})
    local debugBucketsByInstance = setmetatable({}, {__mode = "k"})
    local nextInstanceId, nextSequence = 0, 0
    local remoteIndex, guiIndex = {}, {}
    local observedLiving={}
    local diagnostics = {guiActions = 0, remoteObservations = 0, writeErrors = 0,
        cobaltAttached = false, knownCallers = 0}
    local artifacts, assets = {}, {}
    local currentArtifactBytes = 0
    local artifactIntegrity=true
    local uniqueRecordIds, uniqueClasses, uniqueCount = {}, {}, 0
    local runtimeObserver, guiGraph
    local relations = Relations.new(cfg, {budget=budget,knownIdentity=function(id)return uniqueRecordIds[id]end})
    local processEvents, eventQueueSize
    local clientMetadata, checkpointWriter, checkpointSidecars
    local signatureRows,signatureIds={},{}
    local durableRemoteCounts={}
    local lastWrittenSequence=0
    local checkpointWrites=0
    local function artifact(path, content, kind)
        local at=os.clock()
        local checksum,algorithm=DeepScripts.checksum(content,nil,budget)
        budget:native("artifact_checksum",os.clock()-at)
        local previous=artifacts[path]
        currentArtifactBytes=currentArtifactBytes-(previous and previous.bytes or 0)+#content
        artifacts[path]={path=path,bytes=#content,checksum=checksum,checksumAlgorithm=algorithm,kind=kind}
    end
    local function writeArtifact(path, content, kind)
        if path:find("..",1,true) or path:find("[\\:%c]") or path:sub(1,1)=="/" then
            artifactIntegrity=false;partial("unsafe_artifact_path");return false
        end
        local at=os.clock()
        local ok=pcall(function()
            local directory=(base.."/"..path):match("^(.*)/[^/]+$")
            if not createdDataFolders[directory] then
                assert(createFolders(directory))
                createdDataFolders[directory]=true
            end
            writefile(base.."/"..path,content)
            if type(readfile)=="function" and type(isfile)=="function" then
                assert(isfile(base.."/"..path) and readfile(base.."/"..path)==content,"artifact readback mismatch")
            else artifactIntegrity=false;partial("metadata_readback_unavailable");error("verified readback APIs unavailable")end
        end)
        budget:native("artifact_write_verify",os.clock()-at)
        if not ok then artifactIntegrity=false;partial("artifact_write_failed:"..path);return false end
        if path:sub(1,12)~="checkpoints/"then artifact(path,content,kind)end
        return true
    end
    local function writeSidecar(path,payload)
        local at=os.clock()
        local ok,content=pcall(function()return HttpService:JSONEncode(payload)end)
        if not ok then
            ok,content=pcall(function()return HttpService:JSONEncode(portableJson(payload))end)
            partial("index_serialization_recovered:"..path)
        end
        budget:native("sidecar_encode",os.clock()-at)
        if not ok then artifactIntegrity=false;partial("index_write_failed:"..path);return false end
        return writeArtifact(path,content,"sidecar")
    end
    local diagnosticConnections, guiWatched = {}, setmetatable({}, {__mode = "k"})
    local guiCallbacksInFlight, acceptingGuiCallbacks = 0, true
    local diagnosticWritten={}
    local streamNames={["gui/actions.jsonl"]="gui-actions",["gui/transitions.jsonl"]="gui-transitions",
        ["remotes/observations.jsonl"]="remote-observations",["relations/temporal.jsonl"]="temporal-relations"}
    -- Cobalt and GUI callbacks only enqueue: filesystem work belongs to the pump.
    local journal=Journal.new({batchSize=256,maxQueued=16384,autoFlush=false},{write=function(path,payload)
        local ok=writeSidecar(path,payload)
        if ok and payload.stream=="remote-observations"then
            for _,row in ipairs(payload.rows)do if row.instanceId ~= nil then
                local counts=durableRemoteCounts[row.instanceId]or{incoming=0,outgoing=0}
                local side=row.direction=="Incoming"and"incoming"or"outgoing"
                counts[side]=counts[side]+1;durableRemoteCounts[row.instanceId]=counts
            end end
        end
        return ok
    end,
        measure=function(value)return #HttpService:JSONEncode(portableJson(value))end,
        onError=function(reason)diagnostics.writeErrors=diagnostics.writeErrors+1;partial(reason)end,
        onOverflow=function()partial("journal_queue_overflow");state.stopped=true end})
    local function diagnosticEvent(path,event)
        if not event.sequence then nextSequence=nextSequence+1;event.sequence=nextSequence end
        event.observedAtUtc=event.observedAtUtc or os.date("!%Y-%m-%dT%H:%M:%SZ")
        event.elapsedSeconds=event.elapsedSeconds or(os.clock()-state.startedAt)
        if not journal:append(assert(streamNames[path]),portableJson(event))then error("journal queue overflow")end
        diagnosticWritten[path]=true
        return event.sequence
    end
    local lastDiagnosticFlush = os.clock()
    local function flushDiagnostics(force)
        if not force and os.clock() - lastDiagnosticFlush < 1 then return true end
        local ok = journal:flush()
        if ok then lastDiagnosticFlush = os.clock() end
        return ok
    end
    local function readRaw(path)
        if type(readfile)~="function"or type(isfile)~="function"then return "error","readback unavailable"end
        local ok,exists=pcall(isfile,base.."/"..path)
        if not ok then return "error","existence check failed"end
        if not exists then return "missing"end
        local readable,value=pcall(readfile,base.."/"..path)
        return readable and"ok"or"error",value
    end
    checkpointWriter=Checkpoints.new({read=readRaw,checksum=function(text)return DeepScripts.checksum(text,nil,budget)end,
        write=function(path,text)return writeArtifact(path,text,"checkpoint")end,writeJson=writeSidecar})
    local deep = DeepScripts.new(base, cfg.includeReconstructedCode, control, function(entry)
        flushDiagnostics()
        state.currentPath = entry.robloxPath
        notify(onProgress, "extracting_script", state, entry.name)
    end,{budget=budget,artifact=artifact,onOverflow=function()
        state.lostScriptSources=(state.lostScriptSources or 0)+1;partial("script_queue_overflow");state.stopped=true
    end,analyze=function(source,entry)
        return portableJson(SourceAnalysis.analyze(source,entry,budget))
    end,pump=function()if processEvents then processEvents(false)end end})
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
                for candidate, candidateId in pairs(previous) do
                    local compared, equal = pcall(compareinstances, instance, candidate)
                    if compared and equal then id = candidateId; break end
                end
            end
            if not id then nextInstanceId = nextInstanceId + 1; id = nextInstanceId end
            instanceIds[instance] = id
            if debugId then
                local bucket = debugIdentities[debugId]
                if not bucket then bucket = setmetatable({}, {__mode = "k"}); debugIdentities[debugId] = bucket end
                bucket[instance] = id
                debugBucketsByInstance[instance] = bucket
            end
        end
        liveInstances[id] = instance
        return id
    end
    state.identity=identity
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
                    if not acceptingGuiCallbacks then return end
                    guiCallbacksInFlight = guiCallbacksInFlight + 1
                    local ok = pcall(function()
                    local event={event = "activated",
                        instanceId = record.instanceId, robloxPath = record.path,
                        evidence = "observed_activation"}
                    diagnosticEvent("gui/actions.jsonl",event)
                    if guiGraph then guiGraph:noteActivation(event)end
                    if runtimeObserver then runtimeObserver:noteGuiAction(event)end
                    diagnostics.guiActions = diagnostics.guiActions + 1
                    end)
                    guiCallbacksInFlight = guiCallbacksInFlight - 1
                    if not ok then diagnostics.writeErrors = diagnostics.writeErrors + 1; partial("gui_callback_failed") end
                end)
            end)
            if ok then guiWatched[instance] = connection; diagnosticConnections[connection] = true end
        end
    end
    local function observeRecord(record, service, mode, instance)
        local snapshot = serviceSnapshots[service]
        if not snapshot then snapshot = {}; serviceSnapshots[service] = snapshot end
        local previous = snapshot[record.instanceId]
        local signature = stableValue({className = record.className, name = record.name,
            category = record.category, path = record.path, parentPath = record.parentPath,
            parentInstanceId = record.parentInstanceId, depth = record.depth, properties = record.properties or {}})
        if mode == "remove" then
            if not previous then return false end
            record.operation = "remove"
            snapshot[record.instanceId] = nil
        else
            if previous and previous.signature == signature then
                state.unchangedRecords = (state.unchangedRecords or 0) + 1
                return false
            end
            record.operation = previous and "update" or (mode ~= "baseline" and "add" or nil)
        end
        if mode == "remove" then
            local watched = instance or liveInstances[record.instanceId]
            local connection = watched and guiWatched[watched]
            if connection then
                pcall(function() connection:Disconnect() end)
                diagnosticConnections[connection] = nil
                guiWatched[watched] = nil
            end
        end
        observedLiving[record.instanceId]=mode~="remove" or nil
        nextSequence = nextSequence + 1
        record.sequence = nextSequence
        record.observedAtUtc = record.observedAtUtc or os.date("!%Y-%m-%dT%H:%M:%SZ")
        record.elapsedSeconds=os.clock()-state.startedAt
        if not uniqueRecordIds[record.instanceId]then
            uniqueRecordIds[record.instanceId]=record.className;uniqueCount=uniqueCount+1
            uniqueClasses[record.className]=(uniqueClasses[record.className]or 0)+1
        end
        if mode ~= "remove" then
            snapshot[record.instanceId] = {signature = signature, name = record.name,
                className = record.className, path = record.path, parentPath = record.parentPath,
                depth = record.depth, category = record.category, instanceId = record.instanceId,
                parentInstanceId = record.parentInstanceId, scriptId = record.scriptId, sequence = record.sequence,
                -- Keep the current Roblox wrapper alive while this object is present.
                -- Removing the snapshot releases it; historical records hold no Instance.
                instance = instance}
        end
        if record.operation then
            state.deltaRecords = state.deltaRecords + 1
            if record.operation == "remove" then state.removed = state.removed + 1
            elseif record.operation == "update" then state.updated = state.updated + 1
            else state.added = state.added + 1 end
        end
        if REMOTE_CLASSES[record.className] then
            local previousRemote = remoteIndex[record.instanceId]
            local debugId = previousRemote and previousRemote.debugId
            if instance and not debugId then
                local ok, value = pcall(function() return instance:GetDebugId() end)
                if ok and type(value) == "string" then debugId = value end
            end
            remoteIndex[record.instanceId] = {instanceId = record.instanceId, name = record.name,
                robloxPath = record.path, className = record.className, service = service,
                evidence = "static_inventory", knownScriptLinks = {},
                operation = record.operation, removed = record.operation == "remove",
                parentInstanceId = record.parentInstanceId, sequence = record.sequence,
                observedAtUtc = record.observedAtUtc, debugId = debugId,
                properties = record.operation == "remove" and previousRemote and previousRemote.properties
                    or record.properties,
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
            elapsedSeconds = record.elapsedSeconds,
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
            local leftOk=flush(left,serviceName,pass,category)
            local rightOk=flush(right,serviceName,pass,category)
            return leftOk and rightOk
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
        if not writeArtifact(filename:sub(#base+2),encoded,"metadata") then
            addError(state, "write_failed:" .. serviceName)
            partial("write_error")
            return false
        end
        chunkIndexes[key] = part
        state.bytes = state.bytes + #encoded
        state.fileCount = state.fileCount + 1
        for _,record in ipairs(records)do lastWrittenSequence=math.max(lastWrittenSequence,record.sequence or 0)end
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
        relations:register(record,serviceName)
        if category=="gui" and guiGraph then
            local last=guiIndex[record.instanceId]
            if not last or not last.sequence or last.sequence<=record.sequence then guiGraph:observe(record)end
        end
        if record.operation~="remove" then
            local refs
            for property,value in pairs(record.properties or {})do
                if ASSET_PROPERTIES[property] and type(value)=="string" and value~="" then
                    refs=refs or {};refs[property]=value
                end
            end
            if refs then assets[record.instanceId]={instanceId=record.instanceId,path=record.path,
                className=record.className,references=refs}end
        elseif assets[record.instanceId]then assets[record.instanceId].removed=true end
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
        local deltaMode = mode == "delta"
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
        state.services[serviceName].passes = math.max(state.services[serviceName].passes,pass)

        -- Lazy DFS frames avoid building paths for thousands of siblings at once.
        -- Each loop processes at most one object OR one child; the yield cadence
        -- applies to both object collection and sibling enumeration.
        local stack = {{
            instance = root, depth = 0, path = serviceName, parent = "",
            entered = false,
        }}
        local buckets, steps, scanComplete = {}, 0, true
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
                    local propertyAt=os.clock()
                    local properties = collectProperties(obj, cfg, state)
                    budget:native("property_collection",os.clock()-propertyAt)
                    local category = categoryFor(obj, serviceName, class)
                    local record = {
                        name = name, className = class, path = frame.path,
                        parentPath = frame.parent, depth = frame.depth, properties = properties,
                        category = category,
                    }
                    identify(record, obj, serviceName)
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
                        scanComplete = false
                        addError(state, "children_unavailable:" .. class)
                        partial("children_unavailable")
                    else
                        frame.children = children
                        frame.nextChild = 1
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
                    stack[#stack + 1] = {
                        instance = child, depth = frame.depth + 1,
                        path = frame.path .. "/" .. segment,
                        parent = frame.path, entered = false,
                    }
                end
            else
                stack[#stack] = nil
            end

            state.pending = math.max(0, state.discovered - state.visited)
            steps = steps + 1
            -- Backpressure the traversal itself before the asynchronous burst
            -- limit is reached. Never drain from DescendantAdded callbacks or
            -- from the event pump used by the script writer.
            if #deep.queue >= 1024 then deep:drain() end
            if steps % cfg.yieldEvery == 0 then
                flushDiagnostics()
                if processEvents then processEvents(false)end
                notify(onProgress, "scanning", state, serviceName)
            end
            budget:checkpoint("scan")
        end

        -- Tombstones preserve the same category as the original instance,
        -- even when that instance no longer exists on the client.
        if deltaMode and scanComplete and not state.stopped then
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
                        scriptId = previous.scriptId,
                    }
                    observeRecord(tombstone, serviceName, "remove")
                    if not bufferRecord(buckets, tombstone, serviceName, pass,
                        previous.category or categoryFor(nil, serviceName, previous.className)) then
                        state.stopped = true; break
                    end
                end
                inspected = inspected + 1
                if inspected % cfg.yieldEvery == 0 then budget:checkpoint("tombstones")end
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
        if processEvents and not processEvents(true) then return false end
        if not flushDiagnostics(true) then return false end
        journal:freeze()
        local checkpointOk,checkpointError=pcall(function()
        local structuralVersion = state.deltaRecords
        local guiActions = diagnostics.guiActions
        local jiBefore = journal:index()
        local durableActions = jiBefore.streams["gui-actions"] and jiBefore.streams["gui-actions"].events or 0
        local durableTransitions = jiBefore.streams["gui-transitions"] and jiBefore.streams["gui-transitions"].events or 0
        if (eventQueueSize and eventQueueSize() > 0) or guiActions ~= durableActions
            or guiGraph:summary().transitions ~= durableTransitions then return false end
        if checkpointSidecars and not checkpointSidecars() then
            partial("checkpoint_sidecar_failed"); return false
        end
        if state.deltaRecords ~= structuralVersion or diagnostics.guiActions ~= guiActions
            or (eventQueueSize and eventQueueSize() > 0) then return false end
        local durableSequence=lastWrittenSequence
        for _,stream in pairs(journal:index().streams)do
            for _,segment in ipairs(stream.segments)do durableSequence=math.max(durableSequence,segment.lastSequence or 0)end
        end
        local payload = {
            schemaVersion = Exporter.SCHEMA_VERSION,
            exporterVersion = Exporter.VERSION, clientOnly = true,
            status = "recording", inspectionVersion=2, captureMode = cfg.continuous and "continuous" or "exhaustive",
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
            identity = {version = 1, scope = "capture_local", ordering = "sequence", pathsMayBeNonUnique=true, lastSequence = durableSequence},
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
        payload.clientMetadata=clientMetadata
        local gi=guiGraph:summary()
        local ji=journal:index();ji.path="journal/index.json";payload.journal=ji
        payload.diagnostics=portableJson(diagnostics)
        payload.diagnostics.remoteObservations=ji.streams["remote-observations"] and ji.streams["remote-observations"].events or 0
        local observer=runtimeObserver:summary()
        observer.observedCalls=ji.streams["remote-observations"]and ji.streams["remote-observations"].events or 0
        payload.runtime={status="partial",observer=observer}
        payload.guiAnalysis={status="complete",counts=gi}
        payload.remoteInventory={status="complete",counts={}}
        payload.relations={status="partial",reason="Capture is still recording; final source analysis has not run.",counts={}}
        payload.report={version=2,path="report.json",markdownPath="report.md"}
        payload.artifactIndex={version=1,path="artifacts/index.json"}
        payload.validation={status="partial",reason="Durable recording checkpoint, not a completed capture.",counts={}}
        payload.continuous={enabled=cfg.continuous,monitorCycles=state.monitorCycles,checkpointIntervalSeconds=60}
        payload.privacy={characterExclusionScope="Known associations at observation time; not anonymized."}
        local summary=journal:summary()
        -- Freeze mutable tables before any checkpoint blob write can yield.
        payload=portableJson(payload)
        local ok,reason=checkpointWriter:save(payload,artifacts,{journalQueued=summary.queued,
            structuralQueued=eventQueueSize and eventQueueSize() or 0,
            pendingRawObservations=runtimeObserver:rawPending(),
            scriptPending=deep:summary().stats.pending,lostEvents=summary.lostEvents+(state.lostStructuralEvents or 0)+runtimeObserver:summary().lostRawObservations,
            observedSequence=nextSequence})
        if ok then checkpointWrites=checkpointWrites+1 else partial(reason or"checkpoint_write_failed");addError(state,"checkpoint_write_failed")end
        local encodedOk,encoded=pcall(function()return HttpService:JSONEncode(portableJson(payload))end)
        if not encodedOk or not pcall(writefile,base.."/manifest.json",encoded)then partial("checkpoint_manifest_failed")end
        return ok
        end)
        journal:thaw()
        if not checkpointOk then partial("checkpoint_exception");addError(state,"checkpoint_exception:"..tostring(checkpointError))end
        return checkpointOk and checkpointError == true
    end

    local monitorConnections = {}
    local watchedRoots = {}
    local roots = {}
    local events = {}
    local eventHead = 1
    local eventTail = 0
    eventQueueSize = function() return math.max(0, eventTail - eventHead + 1) end

    local function disconnectMonitoring()
        for _, pair in pairs(monitorConnections) do
            for _, connection in ipairs(pair) do pcall(function() connection:Disconnect() end) end
        end
        table.clear(monitorConnections)
        table.clear(watchedRoots)
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
        if state.eventQueueOverflow or eventTail - eventHead + 1 >= cfg.eventQueueLimit then
            state.lostStructuralEvents = (state.lostStructuralEvents or 0) + 1
            state.eventQueueOverflow = true
            partial("event_queue_overflow")
            state.stopped = true
            return
        end
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
        if operation == "remove" and not observedLiving[record.instanceId] then
            -- Existing object disappeared before its baseline visit: preserve it
            -- while DescendantRemoving still exposes the original instance.
            enqueue(service, root, instance, "add")
            if state.eventQueueOverflow then return end
            if eventTail - eventHead + 1 >= cfg.eventQueueLimit then
                state.lostStructuralEvents = (state.lostStructuralEvents or 0) + 1
                state.eventQueueOverflow = true; state.stopped = true
                partial("event_queue_overflow")
                return
            end
        end
        if operation ~= "remove" then identify(record, instance, service)
        elseif deep.seen["s" .. record.instanceId] then record.scriptId = "s" .. record.instanceId end
        if not observeRecord(record, service, operation, instance) then return end
        eventTail = eventTail + 1
        events[eventTail] = {service = service, record = record}
        state.eventQueuePeak=math.max(state.eventQueuePeak or 0,eventTail-eventHead+1)
    end

    local function attachListeners()
        for _, service in ipairs(Exporter.TARGETS) do
            if cfg.targets[service] then
                local root = rootInstance(service)
                roots[service] = root
                if watchedRoots[service] and watchedRoots[service] ~= root then
                    for _, connection in ipairs(monitorConnections[service] or {}) do
                        pcall(function() connection:Disconnect() end)
                    end
                    monitorConnections[service] = nil
                    watchedRoots[service] = nil
                end
                if not watchedRoots[service] then
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
                        monitorConnections[service] = {added, removed}
                    else
                        if okAdded then added:Disconnect() end
                        if okRemoved then removed:Disconnect() end
                        partial("event_monitor_unavailable:" .. service)
                    end
                end
                end
            end
        end
    end

    -- Keep partial event chunks between pumps. Captured transient records remain
    -- intact; batching reduces filesystem calls instead of discarding events.
    local eventBuckets, lastEventFlush = {}, os.clock()
    processEvents = function(drain)
        local successful = flushDiagnostics(drain == true)
        if runtimeObserver then
            local remaining = runtimeObserver:rawPending()
            if not drain then remaining = math.min(remaining, cfg.chunkSize, 64) end
            while successful and remaining > 0 do
                if journal:summary().queued > 8192 and not flushDiagnostics(true) then successful = false; break end
                local batch = math.min(remaining, 64)
                if not runtimeObserver:drainRaw(batch) then successful = false; break end
                remaining = remaining - batch
                budget:checkpoint("remote_raw_drain")
            end
        end
        local perService = eventBuckets
        local steps = 0
        local hadGui=false
        local drainTail = eventTail
        while eventHead <= drainTail and (drain or not stopCheck()) and (drain or steps<cfg.chunkSize)do
            local event = events[eventHead]
            events[eventHead] = nil
            eventHead = eventHead + 1
            if event then
                local record = event.record
                local class = record.className
                hadGui=hadGui or record.category=="gui"
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
                        successful = false
                        state.stopped = true
                        break
                    end
                end
            end
            steps = steps + 1
            if steps % cfg.yieldEvery == 0 then
                notify(onProgress, "monitoring", state)
                budget:checkpoint("event_drain")
            end
        end
        -- Empty the queue only after all currently queued items were read.
        if eventHead > eventTail then
            events = {}; eventHead = 1; eventTail = 0
        end
        -- Commit bounded partial chunks at least once per second and at stop.
        if drain or os.clock()-lastEventFlush>=1 then
            for service, buckets in pairs(perService) do
                if not flushBuckets(buckets, service, 2) then state.stopped = true; successful = false end
            end
            eventBuckets={};lastEventFlush=os.clock()
        end
        if hadGui and guiGraph then guiGraph:commit("structural_events")end
        return successful
    end

    for name,selectedTarget in pairs(cfg.targets)do
        if selectedTarget then
            state.services[name]={visited=0,records=0,files=0,passes=0}
            local root=rootInstance(name)
            if root then
                roots[name]=root
            end
        end
    end
    local function resolveInstance(instance)
        if typeof(instance)~="Instance" then return nil end
        for service,root in pairs(roots)do
            local ok,inside=pcall(function()return instance==root or instance:IsDescendantOf(root)end)
            if ok and inside then
                local path=pathFor(instance,service,root)
                if not path then return nil end
                local id=identity(instance)
                return {instanceId=id,robloxPath=path,className=instance.ClassName,
                    scriptId=deep.seen["s"..id] and ("s"..id)or nil}
            end
        end
        return nil
    end
    local observerCfg = {observeRemotes=cfg.observeRemotes,correlationWindowSeconds=cfg.correlationWindowSeconds,
        deferRaw=true,rawQueueLimit=16384}
    runtimeObserver=RuntimeObserver.new(observerCfg,{now=os.clock,startedAt=state.startedAt,resolve=resolveInstance,
        reserve=function()
            nextSequence=nextSequence+1
            return nextSequence,os.date("!%Y-%m-%dT%H:%M:%SZ"),os.clock()-state.startedAt
        end,
        peekRemote=function(instance)
            local id=instanceIds[instance]
            local known=id and remoteIndex[id]
            if known and known.evidence == "static_inventory" and not known.removed then
                return {instanceId=id,robloxPath=known.robloxPath,className=known.className}
            end
            return nil
        end,
        peekCaller=function(instance)
            local id=instanceIds[instance]
            if id and observedLiving[id] and uniqueRecordIds[id] then
                local scriptId="s"..id
                return {instanceId=id,scriptId=deep.seen[scriptId] and scriptId or nil}
            end
            return nil
        end,
        onRawOverflow=function()partial("remote_raw_queue_overflow");state.stopped=true end,
        onRawError=function()partial("remote_raw_admission_error");state.stopped=true end,
        onRawProcessError=function()partial("remote_raw_processing_error");state.stopped=true end,
        canEmit=function()return journal:summary().queued<16384 end,
        emitRelation=function(row)return diagnosticEvent("relations/temporal.jsonl",row)end,
        emit=function(row)
            local key=stableValue({row.argumentCount,row.argumentTypes,row.invokeKind})
            local signatureId=signatureIds[key]
            if not signatureId then
                signatureId=#signatureRows+1;signatureIds[key]=signatureId
                signatureRows[signatureId]={signatureId=signatureId,argumentCount=row.argumentCount,
                    argumentTypes=row.argumentTypes,invokeKind=row.invokeKind}
            end
            if row.identityStatus == "unresolved" then partial("remote_identity_unresolved") end
            if row.instanceId and not remoteIndex[row.instanceId]then remoteIndex[row.instanceId]={instanceId=row.instanceId,
                className=row.className,robloxPath=row.robloxPath,evidence="runtime_observed_definition",knownScriptLinks={},observedScriptLinks={}}end
            local compact={instanceId=row.instanceId,direction=row.direction,signatureId=signatureId,
                scriptId=row.scriptId,callerInstanceId=row.callerInstanceId,evidence=row.evidence,elapsedSeconds=row.elapsedSeconds,
                sequence=row.sequence,observedAtUtc=row.observedAtUtc,identityStatus=row.identityStatus,
                reason=row.reason,pathEvidence=row.pathEvidence,scopeBasis=row.scopeBasis,
                callerPathEvidence=row.callerPathEvidence}
            local seq=diagnosticEvent("remotes/observations.jsonl",compact)
            diagnostics.remoteObservations=diagnostics.remoteObservations+1
            return seq
        end})
    guiGraph=GuiStates.new({}, {now=os.clock,budget=budget,
        read=function(path)
            local status,text=readRaw(path)
            if status~="ok"then return status,text end
            local ok,value=pcall(function()return HttpService:JSONDecode(text)end)
            return ok and"ok"or"error",value
        end,
        digest=function(text)local sum,algorithm=DeepScripts.checksum(text,nil,budget);return algorithm.."-"..sum end,
        measure=function(value)return #HttpService:JSONEncode(portableJson(value))end,
        fingerprint=recordFingerprint,write=writeSidecar,emit=function(row)
            local seq=diagnosticEvent("gui/transitions.jsonl",row)
            return seq
        end})
    control._lesbhubCleanup=function()
        journal:freeze()
        acceptingGuiCallbacks = false
        stopPlayerTracking()
        disconnectMonitoring()
        runtimeObserver:stop()
        for connection in pairs(diagnosticConnections)do pcall(function()connection:Disconnect()end)end
    end
    local observerState=runtimeObserver:start()
    diagnostics.cobaltAttached=observerState=="attached"
    if cfg.observeRemotes and observerState~="attached"then partial("remote_observation_"..observerState)end
    clientMetadata=portableJson(ClientMetadata.capture(cfg,budget))
    checkpointSidecars=function()
        if (deep.dirty or not deep.indexWritten) and not deep:saveIndex() then return false end
        for _,path in ipairs({"scripts/index.json","scripts/progress.jsonl"})do
            local status,text=readRaw(path)
            if status=="ok"then artifact(path,text,"sidecar")
            elseif path=="scripts/index.json" or status=="error" then return false end
        end
        local function orderedRows(map)
            local rows={};for _,value in pairs(map)do rows[#rows+1]=value end
            table.sort(rows,function(a,b)return a.instanceId<b.instanceId end);return rows
        end
        if not writeSidecar("client.json",clientMetadata) then return false end
        if not writeSidecar("gui/index.json",{version=2,elements=orderedRows(guiIndex),stateIndex="gui/states/index.json"}) then return false end
        if not guiGraph:checkpoint() then return false end
        local stats=runtimeObserver:remoteStats(false)
        for _,item in ipairs(stats)do local counts=durableRemoteCounts[item.instanceId]or{}
            item.incoming=counts.incoming or 0;item.outgoing=counts.outgoing or 0
            -- These aggregates may include observations still queued behind the cut.
            item.signatures=nil;item.omittedSignatures=nil;item.observedScriptLinks=nil
        end
        if not writeSidecar("remotes/index.json",{version=3,remotes=orderedRows(remoteIndex),observationStatistics=stats}) then return false end
        if not writeSidecar("remotes/signatures.json",{version=1,signatures=signatureRows}) then return false end
        if not writeSidecar("journal/index.json",journal:index()) then return false end
        if not writeSidecar("assets/index.json",{version=1,objects=orderedRows(assets)}) then return false end
        if not writeSidecar("relations/index.json",relations:index()) then return false end
        local failures={};for _,entry in ipairs(deep.entries)do
            if entry.status~="success"then failures[#failures+1]={scriptId=entry.scriptId,status=entry.status,error=entry.error}end
        end
        if not writeSidecar("errors/index.json",{version=1,metadata=state.errors,scriptFailures=failures}) then return false end
        return true
    end

    if type(onProgress)=="function"then
        local clientProgress=onProgress
        onProgress=function(info)
            local gs=guiGraph:summary();local js=journal:summary();local ss=deep:summary().stats
            info.uniqueInstances=uniqueCount;info.inspected=state.visited;info.structuralChanges=state.deltaRecords
            info.unchangedRecords=state.unchangedRecords or 0;info.scriptSharedReferences=ss.sharedReferences
            info.scriptsReconstructed=ss.succeeded;info.storedBytes=currentArtifactBytes
            info.errors=state.errorCount+diagnostics.writeErrors;info.occurrences=runtimeObserver:summary().observedCalls
            info.guiStates=gs.states;info.guiTransitions=gs.transitions;info.eventsWritten=js.durableEvents
            info.queuedEvents=js.queued+runtimeObserver:rawPending();info.pendingRawObservations=runtimeObserver:rawPending()
            info.queuePeak=math.max(js.queuePeak,state.eventQueuePeak or 0,runtimeObserver:summary().rawPeak or 0)
            info.lostEvents=js.lostEvents+(state.lostStructuralEvents or 0)+runtimeObserver:summary().lostRawObservations
            clientProgress(info)
        end
    end
    -- Subscribe before scanning, including before GUI/operator interactions.
    -- Event records capture properties immediately; no task.spawn per event.
    if cfg.continuous or cfg.runtimeWindowSeconds>0 then attachListeners() end
    local selected = 0
    for _, service in ipairs(Exporter.TARGETS) do
        if cfg.targets[service] then
            selected = selected + 1
            scan(service, 1)
            if state.stopped then break end
        end
    end
    if selected == 0 then partial("no_targets") end
    guiGraph:commit("initial_snapshot")

    if cfg.targets.Workspace then
        local ok, streaming = pcall(function() return workspace.StreamingEnabled end)
        if ok and streaming then partial("workspace_streaming_enabled") end
    end

    if cfg.twoPassGui and not state.stopped
        and (cfg.targets.PlayerGui or cfg.targets.StarterGui) then
        for pass = 2, cfg.guiPasses do
            notify(onProgress, "waiting_gui_pass", state, "PlayerGui")
            local deadline = os.clock() + cfg.secondPassDelay
            while os.clock() < deadline and not stopCheck() do
                processEvents(false);budget:wait(0.1)
            end
            if state.stopped then break end
            for _, service in ipairs({"PlayerGui", "StarterGui"}) do
                if cfg.targets[service] then scan(service, pass) end
                if state.stopped then break end
            end
            guiGraph:commit("guided_snapshot_"..pass)
            if state.stopped then break end
        end
    end

    processEvents(true)
    deep:drain()
    local initialCheckpoint = checkpoint()

    if cfg.runtimeWindowSeconds>0 and not state.stopped then
        notify(onProgress,"runtime_window_start",state)
        local deadline=os.clock()+cfg.runtimeWindowSeconds
        local nextGui=os.clock()
        local pass=cfg.twoPassGui and cfg.guiPasses+1 or 2
        while os.clock()<deadline and not stopCheck()do
            processEvents(false)
            if os.clock()>=nextGui then
                for _,service in ipairs({"PlayerGui","StarterGui"})do
                    if cfg.targets[service]then scan(service,pass,"delta")end
                end
                guiGraph:commit("runtime_refresh")
                nextGui=os.clock()+math.max(.75,cfg.continuousInterval/2)
                pass=pass+1
            end
            budget:wait(.1)
        end
        notify(onProgress,"runtime_window_done",state)
    end

    if cfg.continuous and not state.stopped and selected > 0 then
        -- Event handlers capture transient additions/removals (including Workspace);
        -- periodic delta rescans catch changes to already-existing GUI text/visibility.
        local okMonitor, monitorError = pcall(function()
            attachListeners()
            state.monitoring = true
            state.monitorStartedAt=os.clock()
            notify(onProgress, "monitoring_start", state)
            local lastSharedScan = os.clock()
            local lastCheckpoint = initialCheckpoint and os.clock() or (os.clock() - 60)
            local cyclePass = 1
            while not stopCheck() do
                local deadline = os.clock() + cfg.continuousInterval
                while os.clock() < deadline and not stopCheck() do
                    processEvents()
                    budget:wait(0.15)
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
                guiGraph:commit("continuous_refresh")
                if state.stopped then break end
                -- Reconcile selected non-GUI roots less frequently; signals
                -- preserve short-lived additions/removals between these scans.
                if os.clock() - lastSharedScan >= math.max(60, cfg.continuousInterval * 5) then
                    lastSharedScan = os.clock()
                    for _, service in ipairs(Exporter.TARGETS) do
                        if cfg.targets[service] and service ~= "PlayerGui"
                            and service ~= "StarterGui" then
                            scan(service, cyclePass, "delta")
                        end
                        if state.stopped then break end
                    end
                end
                if state.stopped then break end
                if os.clock() - lastCheckpoint >= 60 and checkpoint() then lastCheckpoint = os.clock() end
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

    journal:freeze()
    acceptingGuiCallbacks = false
    disconnectMonitoring()
    runtimeObserver:stop()
    for connection in pairs(diagnosticConnections)do pcall(function()connection:Disconnect()end)end
    stopPlayerTracking()
    -- A disconnected callback may still be suspended inside a yielding write.
    -- Never publish final indexes while that writer can still commit or update stats.
    local joinDeadline = os.clock() + 10
    while journal:isBusy() or runtimeObserver:inFlight() > 0 or guiCallbacksInFlight > 0 do
        if os.clock() >= joinDeadline then
            partial("finalization_callbacks_timeout")
            return nil, string.format("finalization timed out waiting for active callbacks (journalBusy=%s, remote=%d, gui=%d); recover the last verified checkpoint",
                tostring(journal:isBusy()), runtimeObserver:inFlight(), guiCallbacksInFlight)
        end
        budget:wait(0.05)
    end
    if not processEvents(true) then
        return nil, "finalization could not flush the journal or structural events; recover the last verified checkpoint"
    end
    deep:drain()
    deep:saveIndex()
    if not flushDiagnostics(true) then return nil, "finalization could not flush the journal; recover the last verified checkpoint" end
    guiGraph:commit("final_observation")
    if not flushDiagnostics(true) or journal:summary().queued > 0 then
        return nil, "finalization could not persist all queued journal events; recover the last verified checkpoint"
    end
    local observerSummary=runtimeObserver:summary()
    diagnostics.remoteObservations=observerSummary.observedCalls
    if cfg.observeRemotes and (observerSummary.state~="detached" or observerSummary.reason~="capture_stopped") then
        partial("remote_observation_"..tostring(observerSummary.state))
    end
    if (observerSummary.droppedRelations or 0)>0 then partial("temporal_relation_capacity_reached")end
    if (observerSummary.droppedPendingCallers or 0)>0 then partial("caller_resolution_capacity_reached")end
    diagnostics.cobaltAttached=diagnostics.cobaltAttached or observerSummary.state=="detached"
    local observedRemotes=runtimeObserver:remoteStats()
    for _,item in ipairs(observedRemotes)do
        local record=remoteIndex[item.instanceId]
        if record then record.observed=item;record.observedScriptLinks=item.observedScriptLinks end
    end
    local scriptSummary=deep:summary()
    if not scriptSummary.indexWritten then partial("script_index_write_failed")end
    local scriptStats=scriptSummary.stats
    if cfg.includeReconstructedCode and scriptStats.failed+scriptStats.partial+scriptStats.empty+scriptStats.inaccessible+scriptStats.pending>0 then
        partial("script_extraction_incomplete")
    end
    local function ordered(index)
        local rows={};for _,item in pairs(index)do rows[#rows+1]=item end
        table.sort(rows,function(a,b)return a.instanceId<b.instanceId end)
        return rows
    end
    local relationIndex=relations:analyze(deep.entries)
    relations:addObserved(observedRemotes,runtimeObserver:relations())
    relationIndex=relations:index()
    relationIndex.temporalJournal="journal/index.json"
    relationIndex.summary.temporalAssociations=runtimeObserver:summary().temporalRelations or 0
    local guiSummary=guiGraph:summary()
    if guiSummary.writeErrors+(guiSummary.readErrors or 0)+guiSummary.fingerprintErrors+guiSummary.emitErrors>0 then partial("gui_state_capture_error")end
    writeSidecar("client.json",clientMetadata)
    writeSidecar("remotes/index.json",{version=2,evidence="static_inventory",remotes=ordered(remoteIndex),
        observation=observerSummary,observationStatistics=observedRemotes})
    writeSidecar("gui/index.json",{version=2,scope="latest observed state; state projections and global history are separate",
        elements=ordered(guiIndex),stateIndex="gui/states/index.json"})
    writeSidecar("gui/states/index.json",guiGraph:index())
    writeSidecar("relations/index.json",relationIndex)
    writeSidecar("assets/index.json",{version=1,scope="asset references only; no binary downloads",objects=ordered(assets)})
    local failures={}
    for _,entry in ipairs(deep.entries)do
        if entry.status~="success" then failures[#failures+1]={scriptId=entry.scriptId,status=entry.status,
            error=entry.error,diagnosticPath=entry.diagnosticPath,robloxPath=entry.robloxPath}end
        if entry.verifiedReadback then
            artifacts[entry.outputPath]={path=entry.outputPath,kind="reconstructed_script",bytes=entry.fileByteLength,
                checksum=entry.fileChecksum,checksumAlgorithm=entry.fileChecksumAlgorithm}
        end
        if type(entry.outputPath)=="string" and entry.outputPath~="" and not entry.verifiedReadback and type(readfile)=="function"and type(isfile)=="function"then
            local ok,content=pcall(function()return isfile(base.."/"..entry.outputPath)and readfile(base.."/"..entry.outputPath)end)
            if ok and type(content)=="string"then
                artifact(entry.outputPath,content,"incomplete_script")
            elseif not ok then artifactIntegrity=false;partial("incomplete_script_unverified")end
        end
        if entry.diagnosticPath then
            artifacts[entry.diagnosticPath]={path=entry.diagnosticPath,kind="decompiler_diagnostic",bytes=entry.diagnosticByteLength,
                checksum=entry.diagnosticChecksum,checksumAlgorithm=entry.diagnosticChecksumAlgorithm}
        end
    end
    writeSidecar("errors/index.json",{version=1,metadata=state.errors,scriptFailures=failures})
    writeSidecar("remotes/signatures.json",{version=1,signatures=signatureRows})
    flushDiagnostics(true)
    local journalIndex=journal:index()
    writeSidecar("journal/index.json",journalIndex)
    for _,path in ipairs({"scripts/index.json","scripts/progress.jsonl"})do
        local status,text=readRaw(path)
        if status=="ok"then artifact(path,text,"sidecar")
        elseif path=="scripts/index.json"then artifactIntegrity=false;partial("script_index_unverified")end
    end
    local journalSummary=journal:summary()
    if journalSummary.queued>0 or journalSummary.lostEvents>0 then partial("journal_not_fully_durable")end
    local ledger={version=1,artifacts={}}
    local artifactBytes=0
    for _,item in pairs(artifacts)do ledger.artifacts[#ledger.artifacts+1]=item;artifactBytes=artifactBytes+item.bytes end
    table.sort(ledger.artifacts,function(a,b)return a.path<b.path end)
    ledger.stats={files=#ledger.artifacts,bytes=artifactBytes}
    writeSidecar("artifacts/index.json",ledger)
    if state.errorCount > 0 then partial("read_or_write_errors") end
    if not playerTracker.complete then partial("player_tracking_unavailable") end
    stopCheck()
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
            uniqueObservedInstances=uniqueCount,uniqueClassCounts=uniqueClasses,eventQueuePeak=state.eventQueuePeak or 0,
            elapsedSeconds = os.clock() - state.startedAt,
            monitorCycles = state.monitorCycles, deltaRecords = state.deltaRecords,
            added = state.added, updated = state.updated, removed = state.removed,
        },
        inspectionVersion=2,
        scriptExport=scriptSummary,
        clientMetadata=clientMetadata,
        runtime={status=(not cfg.observeRemotes or (observerSummary.state=="detached"and observerSummary.reason=="capture_stopped"
            and observerSummary.unresolvedCalls==0 and observerSummary.lostRawObservations==0))and"complete"or"partial",
            observer=observerSummary,capabilities=clientMetadata.capabilities},
        guiAnalysis={status=(guiSummary.writeErrors+(guiSummary.readErrors or 0)+guiSummary.fingerprintErrors+guiSummary.emitErrors)>0 and"partial"or"complete",
            counts=guiSummary},
        remoteInventory={status="complete",counts={instances=#ordered(remoteIndex)}},
        relations={status=((observerSummary.droppedRelations or 0)+(observerSummary.droppedPendingCallers or 0))>0 and"partial"or"complete",
            reason=((observerSummary.droppedRelations or 0)+(observerSummary.droppedPendingCallers or 0))>0 and"Bounded runtime association or late-caller capacity was exceeded."or"",
            counts=relationIndex.summary},
        artifactIndex={version=1,path="artifacts/index.json",files=#ledger.artifacts,bytes=artifactBytes},
        report={version=2,path="report.json",markdownPath="report.md"},
        validation={status=artifactIntegrity and type(readfile)=="function"and type(isfile)=="function"and"complete"or"partial",
            reason="capture-local exact readback and checksums; use the standalone validator for an independent check",
            counts={artifactFiles=#ledger.artifacts,artifactBytes=artifactBytes,verifiedSourceFiles=scriptStats.files}},
        profiling=budget:summary(),
        diagnostics=diagnostics,
        journal={version=1,path="journal/index.json",streams=journalIndex.streams},
        continuous={enabled=cfg.continuous,captureMode=cfg.continuous and"continuous"or"full",
            monitorCycles=state.monitorCycles,checkpointIntervalSeconds=60,
            monitorSeconds=state.monitorStartedAt and(os.clock()-state.monitorStartedAt)or 0,
            lastDurableSequence=checkpointWriter:summary().lastSequence},
        dedup={inspected=state.visited,uniqueInstances=uniqueCount,unchangedRecords=state.unchangedRecords or 0,
            structuralChanges=state.deltaRecords,scriptSharedReferences=scriptStats.sharedReferences or 0,
            scriptsReconstructed=scriptStats.succeeded,errors=state.errorCount+diagnostics.writeErrors,
            occurrences=observerSummary.observedCalls,
            guiStateBytes=guiSummary.stateBytes,guiFullSnapshotEquivalentBytes=guiSummary.fullSnapshotEquivalentBytes,
            guiDiskReuses=guiSummary.diskReuses,guiStates=guiSummary.states,guiTransitions=guiSummary.transitions,
            eventsWritten=journalSummary.durableEvents,queuedEvents=journalSummary.queued+observerSummary.pendingRawObservations,
            queuePeak=math.max(journalSummary.queuePeak,state.eventQueuePeak or 0,observerSummary.rawPeak or 0),
            lostEvents=journalSummary.lostEvents+(state.lostStructuralEvents or 0)+observerSummary.lostRawObservations,
            lostRawObservations=observerSummary.lostRawObservations,pendingRawObservations=observerSummary.pendingRawObservations,
            unresolvedCalls=observerSummary.unresolvedCalls,
            checkpointWrites=checkpointWrites,storedBytes=artifactBytes,
            storedByteScope="ledger artifacts; recovery checkpoints and wrapper files excluded",
            lostScriptSources=state.lostScriptSources or 0},
        identity = {version = 1, scope = "capture_local", ordering = "sequence", pathsMayBeNonUnique=true, lastSequence = nextSequence},
        services = state.services,
        categories = state.categories,
        layout = {version = cfg.organizedOutput and 2 or 1,
            id = cfg.organizedOutput and "categorized" or "flat"},
        errors = state.errors,
        settings = {
            format = cfg.format, targets = cfg.targets, guiTexts = cfg.guiTexts,
            guiProperties = cfg.guiProperties, worldProperties = cfg.worldProperties,
            includeReconstructedCode = cfg.includeReconstructedCode,
            observeGuiActions=cfg.observeGuiActions,observeRemotes=cfg.observeRemotes,
            runtimeWindowSeconds=cfg.runtimeWindowSeconds,frameBudgetMs=cfg.frameBudgetMs,
            publicGameMetadata=cfg.publicGameMetadata,
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
            excludesOtherPlayerCharacters = playerTracker.complete,
            characterExclusionScope = "known replicated player-character associations at observation time; not an anonymization guarantee",
            playerTrackingComplete = playerTracker.complete,
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
            "GUI state projections use durable exact-checked lookup and deltas; lazy menus must be opened by the operator.",
            "Categorized output places data in category/service subfolders while preserving original paths.",
            "Script metadata remains in chunks; reconstructed code is enabled by default in scripts/sources with scripts/index.json.",
            "Native Archivable/Enabled/RunContext, attributes, tags and safe client-visible Instance references are collected when readable.",
            "RemoteInfo contains documented class capabilities only; not intercepted traffic, handlers, argument schemas or observed call direction.",
            "Continuous mode: pass 1 is a full snapshot; later records have operations add/update/remove.",
            "Structural signals are reconciled with periodic selected-root rescans; sampling is not a record of every physics frame.",
            "GUI properties are refreshed periodically and unchanged records are not rewritten.",
            "Asset references are exported as property values; binary assets are not downloaded.",
            "Paths and GUI strings can still contain contextual data; review before publishing.",
            "IDs, volatile paths and dynamic player fields must not be used in detection signatures.",
        },
    }
    if clientMetadata.publicMetadata.status=="available"then
        manifest.game.name=clientMetadata.publicMetadata.fields.Name
        manifest.game.placeVersion=clientMetadata.placeVersion
    end
    local report=Report.build(manifest,{artifacts={metadata={"artifacts/index.json"},
        reconstructedScripts={"scripts/index.json"},gui={"gui/index.json","gui/states/index.json"},
        remoteInventory={"remotes/index.json"},remoteObservations={"journal/index.json","remotes/signatures.json"},
        relations={"relations/index.json"},runtime={"client.json"},validation={"artifacts/index.json"}},
        limitations={"Static code hints and temporal associations do not establish runtime causality.",
            "Only observed GUI states are covered; unactivated controls and lazy menus remain unexplored.",
            "Cobalt may filter logs before the adapter; observation counts are not unique network request counts.",
            "Native executor calls cannot be preempted by the cooperative work budget."}})
    local okReport,reportJson=pcall(function()return HttpService:JSONEncode(portableJson(report))end)
    local function writeFinal(path,text)
        return pcall(function()
            writefile(base.."/"..path,text)
            if type(readfile)=="function"and type(isfile)=="function"then
                assert(isfile(base.."/"..path)and readfile(base.."/"..path)==text,"final artifact readback mismatch")
            end
        end)
    end
    if not okReport or not writeFinal("report.json",reportJson)then return nil,"could not verify final report"end
    if not writeFinal("report.md",Report.markdown(report))then return nil,"could not verify final readable report"end
    local okManifest, encoded = pcall(function() return HttpService:JSONEncode(manifest) end)
    if not okManifest or not writeFinal("manifest.json",encoded)then return nil,"could not verify manifest"end
    notify(onProgress, "done", state, manifest.status)
    return {folder=base,manifest=manifest,report=report}
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

function Exporter.search(folder,query,options)
    if not safeCaptureFolder(folder)or type(readfile)~="function"then return nil,"capture is unavailable"end
    query=tostring(query or ""):lower()
    if query==""then return {},""end
    options=type(options)=="table"and options or{}
    local limit=clamp(options.limit,1,200,50)
    local offset=clamp(options.offset,0,1000000,0)
    local matches,total,invalidSources={},0,0
    local searchBudget=WorkBudget.new({frameBudgetMs=6,yieldEvery=100},{})
    local function add(row)
        total=total+1
        if total>offset and #matches<limit then matches[#matches+1]=row end
    end
    if options.mode=="sources"then
        local ok,index=pcall(function()return HttpService:JSONDecode(readfile(folder.."/scripts/index.json"))end)
        if not ok or type(index)~="table"then return nil,"script index is unavailable"end
        for _,entry in ipairs(index.scripts or{})do
            local output=type(entry)=="table" and entry.outputPath or nil
            if type(output)=="string"and output:match("^scripts/sources/[%w_/-]+%.luau$")and not output:find("..",1,true)then
                local readable,content=pcall(readfile,folder.."/"..output)
                local header=entry.headerByteLength
                if readable and type(content)=="string" and type(header)=="number"
                    and header==header and header>=0 and header<=#content and header%1==0 then
                    local body=content:sub(header+1)
                    local haystack=body:lower()
                    local cursor,line=1,1
                    while true do
                        local found,ending=haystack:find(query,cursor,true)
                        if not found then break end
                        local _,newlines=body:sub(cursor,found-1):gsub("\n","")
                        line=line+newlines
                        local endLine=body:find("\n",found,true)or #body
                        local row={kind="source",name=entry.name,robloxPath=entry.robloxPath,outputPath=output,
                            scriptId=entry.scriptId,status=entry.status,line=line,byteOffset=found,
                            preview=portableJson(body:sub(found,math.min(endLine,found+239)))}
                        add(row)
                        local _,within=body:sub(found,ending):gsub("\n","")
                        line=line+within;cursor=ending+1
                        searchBudget:checkpoint("source_search")
                    end
                else
                    invalidSources=invalidSources+1
                end
                searchBudget:checkpoint("source_search")
            end
        end
    else
        for _,item in ipairs({{"scripts/index.json","scripts"},{"remotes/index.json","remotes"},{"gui/index.json","elements"}})do
            local ok,index=pcall(function()return HttpService:JSONDecode(readfile(folder.."/"..item[1]))end)
            if ok and type(index)=="table"then
                for _,row in ipairs(index[item[2]]or{})do
                    if type(row)=="table"then
                        local text=tostring(row.name or"").." "..tostring(row.robloxPath or"").." "..tostring(row.latestObservedPath or"")
                        if text:lower():find(query,1,true)then
                            add({kind=item[2],name=row.name,robloxPath=row.robloxPath,outputPath=row.outputPath,
                                scriptId=row.scriptId,status=row.status})
                        end
                    end
                    searchBudget:checkpoint("index_search")
                end
            end
        end
    end
    local note="page "..(math.floor(offset/limit)+1).."; "..total.." matches"
    if invalidSources>0 then note=note.."; "..invalidSources.." unreadable or invalid source files skipped" end
    return matches,note
end

function Exporter.resumeScripts(folder, onProgress, control)
    if captureRunning then return nil, "a capture is already running" end
    captureRunning = true
    local function runResume()
    if not safeCaptureFolder(folder) or type(readfile) ~= "function" then return nil, "unsafe/unavailable capture" end
    local ok, manifest, index = pcall(function()
        return HttpService:JSONDecode(readfile(folder .. "/manifest.json")),
            HttpService:JSONDecode(readfile(folder .. "/scripts/index.json"))
    end)
    if not ok or type(manifest) ~= "table" or type(index) ~= "table" then return nil, "unreadable capture/index" end
    if type(manifest.scriptExport) ~= "table" or type(manifest.game) ~= "table"
        or type(manifest.settings) ~= "table" or type(manifest.settings.targets) ~= "table"
        or type(index.scripts) ~= "table" or manifest.scriptExport.runtimeToken ~= DeepScripts.runtimeToken
        or manifest.game.placeId ~= game.PlaceId or manifest.game.gameId ~= game.GameId then
        return nil, "resume requires the original Roblox/executor session; instance identities cannot be guessed"
    end
    local inspection = manifest.inspectionVersion == 1
    local budget = WorkBudget.new(manifest.settings, control)
    local oldLedger, oldReport, oldErrors, priorScriptDamage
    local function safeArtifact(path)
        return type(path) == "string" and path ~= "" and path:sub(1, 1) ~= "/"
            and not path:find("\\", 1, true) and not path:find(":", 1, true)
            and not path:find("//", 1, true) and not path:find("..", 1, true)
            and not path:find("[%c<>\"|%?%*]")
            and path ~= "manifest.json" and path ~= "report.json" and path ~= "report.md"
            and path ~= "artifacts/index.json"
    end
    if inspection then
        if type(isfile) ~= "function" or type(writefile) ~= "function" then
            return nil, "resume requires file verification APIs"
        end
        local loaded, ledger, report, errors = pcall(function()
            return HttpService:JSONDecode(readfile(folder .. "/artifacts/index.json")),
                HttpService:JSONDecode(readfile(folder .. "/report.json")),
                HttpService:JSONDecode(readfile(folder .. "/errors/index.json"))
        end)
        if not loaded or type(ledger) ~= "table" or ledger.version ~= 1 or type(ledger.artifacts) ~= "table"
            or type(report) ~= "table" or report.reportVersion ~= 2 or type(errors) ~= "table" then
            return nil, "resume requires readable v0.8 ledger, report and error index"
        end
        oldLedger, oldReport, oldErrors = ledger, report, errors
        for _, item in ipairs(oldLedger.artifacts) do
            local path = type(item) == "table" and item.path or nil
            if not safeArtifact(path) then
                return nil, "unsafe path in artifact ledger"
            end
            local read, content = pcall(readfile, folder .. "/" .. path)
            local valid = false
            if read and type(content) == "string" and type(item.bytes) == "number"
                and type(item.checksum) == "string" and type(item.checksumAlgorithm) == "string" then
                local checksum, algorithm = DeepScripts.checksum(content, item.checksumAlgorithm, budget)
                if algorithm == "unavailable" then return nil, "artifact checksum algorithm unavailable: " .. path end
                valid = #content == item.bytes and checksum == item.checksum and algorithm == item.checksumAlgorithm
            end
            if not valid then
                if path:sub(1, 16) == "scripts/sources/" or path:sub(1, 26) == "errors/script-diagnostics/"
                    or path == "scripts/index.json" or path == "scripts/progress.jsonl" or path == "errors/index.json" then
                    priorScriptDamage = true
                else return nil, "prior artifact integrity mismatch: " .. path end
            end
            budget:checkpoint("resume_preflight")
            if control and control.cancelled then return nil, "cancelled" end
        end
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
    local candidates
    local function resolve(entry)
        if not candidates then
            candidates = {}
            for service, selected in pairs(manifest.settings.targets) do
                local root = selected and table.find(Exporter.TARGETS, service) and rootInstance(service)
                if root then
                    local stack = {root}
                    while #stack > 0 do
                        if control and control.cancelled then return nil end
                        local obj = table.remove(stack)
                        local classOk, class = pcall(function() return obj.ClassName end)
                        if classOk and (class == "LocalScript" or class == "ModuleScript" or class == "Script") then
                            local readable, id = pcall(function() return obj:GetDebugId() end)
                            if readable and type(id) == "string" then
                                if candidates[id] ~= nil and candidates[id] ~= obj then candidates[id] = false
                                elseif candidates[id] == nil then candidates[id] = obj end
                            end
                        end
                        local childrenOk, children = pcall(function() return obj:GetChildren() end)
                        if childrenOk then for _, child in ipairs(children) do stack[#stack + 1] = child end end
                        budget:checkpoint("resume_discovery")
                    end
                end
            end
        end
        local instance = candidates[entry.debugId]
        if not instance then return nil end
        local classOk, class = pcall(function() return instance.ClassName end)
        return classOk and class == entry.className and instance or nil
    end
    local deep = DeepScripts.new(folder, true, control, onProgress, {budget = budget,
        analyze = function(source, entry) return portableJson(SourceAnalysis.analyze(source, entry, budget)) end})
    local resumed, resumeError = pcall(function() deep:resume(index.scripts, function(entry)
        return resolve(entry)
    end) end)
    if not resumed then return nil, "could not resume scripts: " .. tostring(resumeError) end
    manifest.scriptExport = deep:summary()
    manifest.scriptExport.resumed = true
    manifest.settings.includeReconstructedCode = true
    manifest.privacy = manifest.privacy or {}
    manifest.privacy.includesReconstructedCode = true
    local scripts = manifest.scriptExport.stats
    local incomplete = scripts.failed + scripts.partial + scripts.empty + scripts.inaccessible + scripts.pending > 0
    local reasons = {}
    for _, reason in ipairs(manifest.partialReasons) do
        if reason ~= "script_extraction_incomplete" and reason ~= "script_resume_cancelled" then reasons[#reasons + 1] = reason end
    end
    if incomplete then reasons[#reasons + 1] = "script_extraction_incomplete" end
    manifest.partialReasons = reasons
    if manifest.status == "complete" or manifest.status == "partial" then
        manifest.status = #reasons > 0 and "partial" or "complete"
    end
    if inspection then
        if not manifest.scriptExport.indexWritten then return nil, "could not save resumed script index" end
        if priorScriptDamage and not table.find(reasons, "resume_prior_script_artifact_mismatch") then
            reasons[#reasons + 1] = "resume_prior_script_artifact_mismatch"
        end
        local changed = false
        local failures = {}
        for _, entry in ipairs(deep.entries) do
            if entry.attempted and not entry.skipped then changed = true end
            if entry.status ~= "success" then
                failures[#failures + 1] = {scriptId = entry.scriptId, status = entry.status,
                    error = entry.error, diagnosticPath = entry.diagnosticPath, robloxPath = entry.robloxPath}
            end
        end
        if changed then
            if not table.find(reasons, "relations_stale_after_script_resume") then
                reasons[#reasons + 1] = "relations_stale_after_script_resume"
            end
            manifest.relations = manifest.relations or {}
            manifest.relations.status = "partial"
            manifest.relations.reason = "Script extraction changed; existing relationships describe the original capture and were not rebuilt."
        end
        if control and control.cancelled then
            reasons[#reasons + 1] = "script_resume_cancelled"
            manifest.status = "cancelled"
        end
        table.sort(reasons)
        manifest.partialReasons = reasons
        if manifest.status == "complete" or manifest.status == "partial" then
            manifest.status = #reasons > 0 and "partial" or "complete"
        end
        oldErrors.scriptFailures = failures
        local function writeJson(path, payload)
            local encoded, text = pcall(function() return HttpService:JSONEncode(portableJson(payload)) end)
            if not encoded then return false end
            local wrote = pcall(writefile, folder .. "/" .. path, text)
            if not wrote then return false end
            local verified, content = pcall(readfile, folder .. "/" .. path)
            return verified and content == text
        end
        if not writeJson("errors/index.json", oldErrors) then return nil, "could not update error index" end
        -- The prior ledger is the inventory of frozen capture files. Include newly
        -- written outputs and logs, then read and hash every inventoried file again.
        local paths = {}
        for _, item in ipairs(oldLedger.artifacts) do paths[item.path] = item.kind end
        paths["scripts/index.json"] = "sidecar"
        paths["errors/index.json"] = "sidecar"
        for _, path in ipairs({"scripts/progress.jsonl", "gui/actions.jsonl", "gui/transitions.jsonl",
            "remotes/observations.jsonl"}) do
            local exists, found = pcall(isfile, folder .. "/" .. path)
            if exists and found then paths[path] = paths[path] or "sidecar" end
        end
        for _, entry in ipairs(deep.entries) do
            for _, item in ipairs({{entry.outputPath, "reconstructed_script"},
                {entry.diagnosticPath, "decompiler_diagnostic"},
                {"errors/script-diagnostics/" .. entry.scriptId .. ".txt", "decompiler_diagnostic"}}) do
                local path = item[1]
                if type(path) == "string" and path ~= "" then
                    if not safeArtifact(path) then return nil, "unsafe script artifact path" end
                    local exists, found = pcall(isfile, folder .. "/" .. path)
                    if exists and found then paths[path] = paths[path] or item[2] end
                end
            end
        end
        local ledger, total = {version = 1, artifacts = {}}, 0
        for path, kind in pairs(paths) do
            local read, content = pcall(readfile, folder .. "/" .. path)
            if not read or type(content) ~= "string" then return nil, "could not verify artifact: " .. path end
            local checksum, algorithm = DeepScripts.checksum(content, nil, budget)
            ledger.artifacts[#ledger.artifacts + 1] = {path = path, bytes = #content,
                checksum = checksum, checksumAlgorithm = algorithm, kind = kind}
            total = total + #content
            budget:checkpoint("resume_artifact")
        end
        table.sort(ledger.artifacts, function(a, b) return a.path < b.path end)
        ledger.stats = {files = #ledger.artifacts, bytes = total}
        if not writeJson("artifacts/index.json", ledger) then return nil, "could not update artifact ledger" end
        manifest.artifactIndex = {version = 1, path = "artifacts/index.json", files = #ledger.artifacts, bytes = total}
        manifest.validation = {status = priorScriptDamage and "partial" or "complete",
            reason = priorScriptDamage and "At least one script-related artifact differed from the prior ledger; the new ledger records current bytes."
                or "Resume re-read and checksummed the prior ledger inventory and new script files; use the standalone validator for an independent check.",
            counts = {artifactFiles = #ledger.artifacts, artifactBytes = total, verifiedSourceFiles = scripts.files}}
        manifest.resumeProfiling = budget:summary()
        local report = Report.build(manifest, {artifacts = oldReport.artifacts, limitations = oldReport.limitations})
        if not writeJson("report.json", report) then return nil, "could not update resumed report" end
        local markdown = Report.markdown(report)
        local wrote = pcall(writefile, folder .. "/report.md", markdown)
        local verified, actual = pcall(readfile, folder .. "/report.md")
        if not wrote or not verified or actual ~= markdown then return nil, "could not update resumed readable report" end
        if not writeJson("manifest.json", manifest) then return nil, "could not update resumed manifest" end
        return {folder = folder, manifest = manifest, report = report}
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
    local succeeded, result, err = pcall(runResume)
    captureRunning = false
    if not succeeded then return nil, tostring(result) end
    return result, err
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
