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

local windui = {}
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
game = {HttpGet = function() return "mock WindUI" end}
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
    return {folder = "mock-dataset", manifest = {status = "complete",
        stats = {written = 100, files = 1, assetReferences = 3, elapsedSeconds = 0.3}}}
end
function engine.savePlace() return true, "mock-save.rbxl" end

local UI = require("../src/ui")
local window = UI.open(engine)
assert(window == lastWindow and shared.LesbhubExporterHandle)
assert(window.tabs.Home, "Default locale must be English")
assert(window.tabs.Home:find("Button", "Full export + GUI"), "Home quick export absent")
assert(window.tabs.Home:find("Button", "Open activity window"), "Home log shortcut absent")
local targets = window.tabs.Targets
local picker = targets:find("Dropdown", "Select multiple")
assert(picker and picker.config.Multi and #picker.value == #engine.TARGETS)
assert(#targets.elements < 12, "Targets should not be a wall of toggles")

local options = window.tabs.Options
local modePicker = options:find("Dropdown", "Export preset")
local advanced = options:find("Section", "Advanced")
assert(advanced and advanced.config.Opened == false)
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
assert(max.textboxValues and max.stringValues)

modePicker:Set("Fast")
fullBtn.config.Callback()
window.lastDialog.Buttons[2].Callback()
local fast = engine.calls[2]
assert(fast.guiTexts and fast.assets and fast.twoPassGui and fast.guiPasses == 2)
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

local reloaded = UI.open(engine)
assert(reloaded.tabs["Accueil"], "Persisted French language not loaded")
print("Luau UI mock OK: EN/FR, persistence, Home, privacy, full+GUI, map, keybind, unload")
