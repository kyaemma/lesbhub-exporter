-- WindUI mock smoke test: validate real UI callback wiring without Roblox.
local shared = {}
function getgenv() return shared end
UDim = {new = function(scale, offset) return {Scale = scale, Offset = offset} end}
local pending
local lastWindow

local function element(config, kind)
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

local function makeTab(name)
    local tab = {name = name, elements = {}}
    function tab:NewChild(kind, config)
        local e = element(config or {}, kind)
        table.insert(self.elements, e)
        if kind == "Section" then
            local child = makeTab("Advanced")
            e.children = child
            for _, method in ipairs({"Paragraph", "Toggle", "Slider", "Dropdown", "Button", "Input"}) do
                e[method] = function(_, props) return child:NewChild(method, props) end
            end
        end
        return e
    end
    for _, method in ipairs({
        "Paragraph", "Input", "Dropdown", "Toggle", "Button",
        "Slider", "Section", "Code", "ProgressBar", "Keybind",
    }) do
        tab[method] = function(self, config) return self:NewChild(method, config) end
    end
    function tab:find(kind, title)
        for _, e in ipairs(self.elements) do
            if e.kind == kind and (not title or e.config.Title == title) then return e end
        end
        return nil
    end
    return tab
end

local windui = {}
function windui:CreateWindow(options)
    local window = {tabs = {}, options = options, toggleCount = 0}
    function window:Tab(props)
        local tab = makeTab(props.Title)
        self.tabs[props.Title] = tab
        return tab
    end
    function window:Dialog(props)
        self.lastDialog = props
        return props
    end
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
function windui:Notify(cfg) pending = cfg end
function loadstring(_source) return function() return windui end end
game = {HttpGet = function(_, _) return "WindUI mock" end}
function writefile(_path, _data) end
function makefolder(_path) end
task = {spawn = function(callback) callback() end}
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
    onProgress({
        stage = "service_start", service = "PlayerGui", pass = 1,
        visited = 5, discovered = 9, written = 5, pending = 4,
        files = 1, assetReferences = 3, elapsedSeconds = 0.1,
    })
    onProgress({
        stage = "waiting_gui_pass", service = "PlayerGui", pass = 1,
        visited = 5, discovered = 9, written = 5, pending = 4,
        files = 1, assetReferences = 3, elapsedSeconds = 0.2,
    })
    onProgress({
        stage = "service_done", service = "PlayerGui", pass = 1,
        visited = 5, discovered = 9, written = 5, pending = 4,
        files = 1, assetReferences = 3, elapsedSeconds = 0.3,
    })
    assert(control.cancelled == false)
    return {
        folder = "mock",
        manifest = {status = "complete",
            stats = {written = 100, files = 1, assetReferences = 3, elapsedSeconds = 0.3}},
    }
end
function engine.savePlace() return true, "mock" end

local UI = require("../src/ui")
local window = UI.open(engine)
assert(window == lastWindow and shared.LesbhubExporterHandle)
local targetTab = window.tabs.Targets
local picker = targetTab:find("Dropdown", "Sélection multiple")
assert(picker and picker.config.Multi == true)
assert(#picker.value == #engine.TARGETS, "Targets should all be selected")
assert(#targetTab.elements < 12, "Targets UI must not be one toggle per service")

local optionsTab = window.tabs.Options
local modePicker = optionsTab:find("Dropdown", "Mode d'export")
local advanced = optionsTab:find("Section", "Advanced")
assert(advanced and advanced.config.Opened == false, "Advanced should be collapsed")
assert(modePicker, "Missing preset select")
local capture = window.tabs.Capture
local journal = capture:find("Code", "Journal")
assert(journal and type(journal.config.Height) == "table"
    and journal.config.Height.Scale == 0 and journal.config.Height.Offset == 180,
    "WindUI Code.Height must be a UDim, not a number")
local fullBtn = capture:find("Button", "Full export + GUI")
assert(fullBtn, "Missing single Full export + GUI action")

fullBtn.config.Callback()
assert(#engine.calls == 0, "Capture must not start before privacy consent")
assert(window.lastDialog and window.lastDialog.Content:find("Ne publie pas"), "Privacy notice missing")
window.lastDialog.Buttons[2].Callback()
local config = engine.calls[1]
assert(config and config.targets.PlayerGui and config.targets.StarterGui)
assert(config.textboxValues == true and config.stringValues == true)
assert(config.twoPassGui == true and config.guiPasses == 4)
local progress = capture:find("ProgressBar")
assert(progress and progress.config.Indeterminate == true and progress.destroyed,
    "Unknown-total progress should animate only while scanning")

modePicker:Set("Fast")
fullBtn.config.Callback()
window.lastDialog.Buttons[2].Callback()
local fast = engine.calls[2]
assert(fast.guiTexts and fast.assets and fast.twoPassGui and fast.guiPasses == 2)
assert(fast.worldProperties == false and fast.textboxValues and fast.stringValues)

targetTab:find("Button", "GUI uniquement").config.Callback()
assert(#picker.value == 2)
fullBtn.config.Callback()
window.lastDialog.Buttons[2].Callback()
local gui = engine.calls[3]
assert(gui.targets.PlayerGui and gui.targets.StarterGui and not gui.targets.Workspace)

local shortcut = window.tabs.Settings:find("Keybind", "Afficher / masquer")
assert(shortcut and shortcut.config.Value == "RightShift")
shortcut.config.Callback("RightShift")
assert(window.toggleCount == 1, "Keybind must toggle exactly once")
assert(window.options.ToggleKey == nil, "Built-in toggle handler would cause double toggle")

window.tabs.Settings:find("Button", "Unload GUI").config.Callback()
assert(window.lastDialog.Title:find("Décharger"))
window.lastDialog.Buttons[2].Callback()
assert(window.Destroyed and not shared.LesbhubExporterHandle, "Unload did not clean UI handle")
print("Luau WindUI mock smoke test OK: targets, presets, privacy, progress, bind, unload")
