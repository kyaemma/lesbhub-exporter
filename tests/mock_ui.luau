-- Mock UI contract regression without Roblox; fork-specific rendering is validated live.
local shared, saved = {}, {}
function getgenv() return shared end
function readfile(path)
    assert(saved[path] ~= nil, "file not found")
    return saved[path]
end
function writefile(path, content) saved[path] = content end
function makefolder(_path) end
function isfolder(_path) return true end
UDim = {new = function(scale, offset) return {Scale = scale, Offset = offset} end}

local function signal()
    local sig = {handlers = {}}
    function sig:Connect(callback)
        self.handlers[#self.handlers + 1] = callback
        return {Disconnect = function() end}
    end
    function sig:Fire(...)
        for _, callback in ipairs(self.handlers) do callback(...) end
    end
    return sig
end
local fakeScreen
local created = {}
Instance = {
    new = function(class)
        local obj = {
            ClassName = class, Children = {}, AbsoluteSize = {X = 500, Y = 250},
            InputBegan = signal(), InputChanged = signal(), InputEnded = signal(),
            MouseButton1Click = signal(), AbsolutePosition = {X = 0, Y = 0},
        }
        function obj:Destroy() self.Destroyed = true end
        function obj:FindFirstChildWhichIsA(name, recursive)
            for _, child in ipairs(self.Children) do
                if child.ClassName == name then return child end
                if recursive then
                    local deeper = child:FindFirstChildWhichIsA(name, true)
                    if deeper then return deeper end
                end
            end
            return nil
        end
        function obj:GetChildren() return self.Children end
        setmetatable(obj, {
            __newindex = function(self, key, value)
                rawset(self, key, value)
                if key == "Parent" and value and value.Children then
                    table.insert(value.Children, self)
                end
            end,
        })
        created[#created + 1] = obj
        return obj
    end,
}
UDim2 = {
    fromOffset = function(x, y) return {X = {Scale = 0, Offset = x}, Y = {Scale = 0, Offset = y}} end,
    new = function(xScale, xOffset, yScale, yOffset)
        return {X = {Scale = xScale, Offset = xOffset}, Y = {Scale = yScale, Offset = yOffset}}
    end,
}
Color3 = {fromRGB = function(r, g, b) return {R = r, G = g, B = b} end}
Vector2 = {new = function(x, y) return {X = x, Y = y} end}
TweenInfo = {new = function() return {} end}
Enum = {
    Font = {GothamBold = "GothamBold", Gotham = "Gotham",
        GothamMedium = "GothamMedium", Code = "Code"},
    TextXAlignment = {Left = "Left"}, TextYAlignment = {Top = "Top"},
    AutomaticSize = {Y = "Y"}, ScrollingDirection = {Y = "Y"},
    UserInputType = {MouseButton1 = "MouseButton1", Touch = "Touch",
        MouseMovement = "MouseMovement"},
    EasingStyle = {Linear = "Linear"}, EasingDirection = {InOut = "InOut"},
}
fakeScreen = Instance.new("ScreenGui")
local lastWindow
local function widget(config, kind)
    local item = {config = config, kind = kind, value = config.Value}
    function item:SetTitle(value) self.title = value end
    function item:SetDesc(value) self.desc = value end
    function item:SetCode(value) self.code = value end
    function item:Set(value)
        self.value = value
        if self.config.Callback then self.config.Callback(value) end
    end
    function item:Select(values) self:Set(values) end
    function item:Destroy() self.destroyed = true end
    return item
end
local function createTab(name)
    local tab = {name = name, elements = {}}
    function tab:NewChild(kind, config)
        local e = widget(config or {}, kind)
        table.insert(self.elements, e)
        if kind == "Section" then
            local child = createTab("Advanced")
            e.children = child
            for _, method in ipairs({"Paragraph", "Toggle", "Slider", "Dropdown", "Button", "Input"}) do
                e[method] = function(_, props) return child:NewChild(method, props) end
            end
        end
        return e
    end
    for _, method in ipairs({
        "Paragraph", "Input", "Dropdown", "Toggle", "Button", "Slider",
        "Section", "Code", "ProgressBar", "Keybind",
    }) do
        tab[method] = function(self, config) return self:NewChild(method, config) end
    end
    function tab:find(kind, title)
        for _, e in ipairs(self.elements) do
            if e.kind == kind and (not title or e.config.Title == title) then return e end
        end
    end
    function tab:Select() self.selected = true end
    return tab
end

local windui = {ScreenGui = fakeScreen}
function windui:CreateWindow(options)
    local window = {tabs = {}, options = options, toggleCount = 0}
    function window:Tab(cfg)
        local tab = createTab(cfg.Title)
        self.tabs[cfg.Title] = tab
        return tab
    end
    function window:Dialog(cfg) self.lastDialog = cfg; return cfg end
    function window:OnDestroy(cb) self.onDestroy = cb end
    function window:Open() self.opened = true end
    function window:Toggle() self.toggleCount = self.toggleCount + 1 end
    function window:Close() self.closed = true end
    function window:Destroy()
        self.Destroyed = true
        if self.onDestroy then self.onDestroy() end
    end
    lastWindow = window
    return window
end
function windui:Notify(cfg) self.notice = cfg end
function loadstring(_source) return function() return windui end end
local uis = {InputChanged = signal(), InputEnded = signal()}
local tweenService = {Create = function()
    return {Play = function(self) self.played = true end,
        Cancel = function(self) self.cancelled = true end}
end}
game = {
    HttpGet = function() return "mock WindUI" end,
    GetService = function(_, name)
        if name == "UserInputService" then return uis end
        if name == "TweenService" then return tweenService end
        error("Unexpected service " .. tostring(name))
    end,
}
task = {
    spawn = function(callback) callback() end,
    defer = function(callback) callback() end,
    wait = function() end,
}
local engine = {
    TARGETS = {
        "ReplicatedStorage", "ReplicatedFirst", "StarterGui", "PlayerGui",
        "StarterPlayer", "PlayerScripts", "StarterPack", "Workspace",
        "Lighting", "SoundService", "Teams",
    },
    calls = {},
}
function engine.capture(cfg, onProgress, control)
    table.insert(engine.calls, cfg)
    onProgress({stage = "service_start", service = "PlayerGui", pass = 1,
        visited = 5, discovered = 9, written = 5, pending = 4,
        files = 1, assetReferences = 3, elapsedSeconds = 0.1})
    onProgress({stage = "waiting_gui_pass", service = "PlayerGui", pass = 1,
        visited = 5, discovered = 9, written = 5, pending = 4,
        files = 1, assetReferences = 3, elapsedSeconds = 0.2})
    onProgress({stage = "service_done", service = "PlayerGui", pass = 1,
        visited = 5, discovered = 9, written = 5, pending = 4,
        files = 1, assetReferences = 3, elapsedSeconds = 0.3})
    assert(control.cancelled == false)
    if cfg.continuous then
        onProgress({stage = "monitoring_start", service = "PlayerGui", pass = 1,
            visited = 8, discovered = 11, written = 8, pending = 3,
            files = 1, assetReferences = 3, elapsedSeconds = 1.0,
            monitoring = true, monitorCycles = 0, deltaRecords = 0})
        lastWindow.tabs.Capture:find("Button", "Stop & Save").config.Callback()
        assert(control.stopRequested == true,
            "Stop & Save button must request graceful monitoring termination")
        onProgress({stage = "monitoring_finalizing", service = "PlayerGui", pass = 2,
            visited = 12, discovered = 12, written = 10, pending = 0,
            files = 2, assetReferences = 3, elapsedSeconds = 1.2,
            deltaRecords = 2})
        return {folder = "mock-continuous", manifest = {
            status = "stopped", settings = {continuous = true},
            stats = {written = 10, files = 2, assetReferences = 3,
                deltaRecords = 2, elapsedSeconds = 1.2},
        }}
    end
    return {folder = "mock-dataset", manifest = {status = "complete",
        stats = {written = 100, files = 1, assetReferences = 3, elapsedSeconds = 0.3}}}
end
function engine.savePlace() return true, "mock-save.rbxl" end

local UI = require("../src/ui")
local window = UI.open(engine)
assert(window == lastWindow and shared.LesbhubExporterHandle)
assert(window.options.User and window.options.User.Enabled == false
    and window.options.User.Anonymous == true,
    "Exporter must not require a Roblox LocalPlayer thumbnail")
assert(window.tabs.Home, "Default locale must be English")
assert(window.tabs.Home:find("Button", "Full export + GUI"), "Home quick export absent")
assert(window.tabs.Home:find("Button", "Open activity window"), "Home log shortcut absent")
local dataset = window.tabs.Dataset
local layoutPicker = dataset:find("Dropdown", "File organization")
assert(layoutPicker and layoutPicker.value == "Categorized folders")

local activityWindow
for _, obj in ipairs(fakeScreen.Children) do
    if obj.Name == "LesbhubExporterActivity" then activityWindow = obj end
end
assert(activityWindow and activityWindow.Visible == false, "Detached journal was not created")
window.tabs.Home:find("Button", "Open activity window").config.Callback()
assert(activityWindow.Visible == true, "Journal should open from Home")

local targets = window.tabs.Targets
local picker = targets:find("Dropdown", "Select multiple")
assert(picker and picker.config.Multi and #picker.value == #engine.TARGETS)
assert(#targets.elements < 12, "Targets should not be a wall of toggles")

local options = window.tabs.Options
local modePicker = options:find("Dropdown", "Export preset")
local advanced = options:find("Section", "Advanced")
assert(advanced and advanced.config.Opened == false)
local codeToggle = advanced.children:find("Toggle", "Include reconstructed client script code")
assert(codeToggle and codeToggle.config.Value == true,
    "Reconstructed Luau should start enabled in ordinary export")
assert(modePicker, "Preset dropdown missing")
local capture = window.tabs.Capture
assert(not capture:find("Code"), "Log must not live inside Capture tab")
local fullBtn = capture:find("Button", "Full export + GUI")
assert(fullBtn)
fullBtn.config.Callback()
assert(#engine.calls == 0, "Capture started before consent")
assert(window.lastDialog.Content:find("Do not publish", 1, true))
window.lastDialog.Buttons[2].Callback()
local max = engine.calls[1]
assert(max and max.targets.PlayerGui and max.targets.StarterGui)
assert(max.twoPassGui and max.guiPasses == 4)
assert(max.includeReconstructedCode == true, "Max preset must export Luau by default")
assert(max.organizedOutput == true, "Folder organization should be enabled by default")
layoutPicker:Set("Flat (legacy)")

assert(max.textboxValues and max.stringValues)

modePicker:Set("Fast")
fullBtn.config.Callback()
window.lastDialog.Buttons[2].Callback()
local fast = engine.calls[2]
assert(fast.guiTexts and fast.assets and fast.twoPassGui and fast.guiPasses == 2)
assert(fast.includeReconstructedCode == true, "Fast preset must retain Luau extraction")
assert(fast.organizedOutput == false, "Legacy layout selector did not update the config")

assert(not fast.worldProperties and fast.textboxValues and fast.stringValues)

targets:find("Button", "GUI only").config.Callback()
assert(#picker.value == 2)
fullBtn.config.Callback()
window.lastDialog.Buttons[2].Callback()
local gui = engine.calls[3]
assert(gui.targets.PlayerGui and gui.targets.StarterGui and not gui.targets.Workspace)

local map = window.tabs.Map
map:find("Button", "Export map as JSON").config.Callback()
window.lastDialog.Buttons[2].Callback()
local mapCfg = engine.calls[4]
assert(mapCfg.targets.Workspace and mapCfg.targets.Lighting and not mapCfg.targets.PlayerGui)
assert(activityWindow.Visible == true, "Map capture must keep journal visible")

local continuous = capture:find("Button", "Start continuous capture")
local stop = capture:find("Button", "Stop & Save")
assert(continuous and stop, "Continuous capture actions must exist")
assert(continuous.config.Color and stop.config.Color, "Primary actions must look distinct from text cards")
assert(fullBtn.config.Color, "Full export must have an accent color")
assert(window.tabs.Home:find("Button", "Start continuous capture"), "Home continuous shortcut missing")
continuous.config.Callback()
assert(#engine.calls == 4, "Continuous capture started without privacy consent")
assert(window.lastDialog.Content:find("Continuous mode monitors", 1, true),
    "Continuous mode consent must explain indefinite capture")
window.lastDialog.Buttons[2].Callback()
assert(#engine.calls == 5 and engine.calls[5].continuous == true)
assert(engine.calls[5].includeReconstructedCode == true, "Continuous mode must export Luau by default")
assert(engine.calls[5].targets.PlayerGui and engine.calls[5].targets.StarterGui)
assert(engine.calls[5].continuousInterval == 6, "Fast preset interval missing")


-- A deliberate Advanced opt-out must still work for metadata-only diagnostics.
codeToggle:Set(false)
fullBtn.config.Callback()
window.lastDialog.Buttons[2].Callback()
assert(#engine.calls == 6 and engine.calls[6].includeReconstructedCode == false,
    "Advanced false must disable decompilation")
modePicker:Set("Fast") -- restore selected preset and the default before language checks

local shortcut = window.tabs.Settings:find("Keybind", "Show / hide key")
assert(shortcut and shortcut.config.Value == "RightShift")
shortcut.config.Callback("RightShift")
assert(window.toggleCount == 1)
assert(window.options.ToggleKey == nil, "Duplicate toggle handler installed")

-- Change language, persist it, recreate UI and preserve preset/target selections.
local language = window.tabs.Settings:find("Dropdown", "Language / Langue")
assert(language)
language:Set("Français")
assert(saved["LesbhubExporter/language.txt"] == "fr", "Locale not saved")
local french = lastWindow
assert(french ~= window and french.tabs["Accueil"] and french.tabs["Paramètres"])
assert(french.tabs["Accueil"]:find("Button", "Ouvrir la fenêtre du journal"))
local frPreset = french.tabs.Options:find("Dropdown", "Preset d'export")
assert(frPreset and frPreset.value == "Fast", "Preset lost on localization")
local frPicker = french.tabs["Cibles"]:find("Dropdown", "Sélection multiple")
assert(frPicker and #frPicker.value == 2)
local frenchShortcut = french.tabs["Paramètres"]:find("Keybind", "Touche afficher / masquer")
assert(frenchShortcut)

french.tabs["Paramètres"]:find("Button", "Décharger la GUI").config.Callback()
assert(french.lastDialog.Title:find("Décharger"))
french.lastDialog.Buttons[2].Callback()
assert(french.Destroyed and not shared.LesbhubExporterHandle, "Unload did not clear handle")
assert(activityWindow.Destroyed == true, "Unload must destroy detached journal")

local reloaded = UI.open(engine)
assert(reloaded.tabs["Accueil"], "Persisted French language not loaded")
print("Luau UI mock OK: EN/FR, persistence, Home, privacy, full+GUI, map, keybind, unload")
