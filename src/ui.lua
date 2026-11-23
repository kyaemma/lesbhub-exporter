-- Lesbhub Exporter V1 UI. Requires the public Lesbhub WindUI fork.
local UI = {}
local WINDUI_URL = "https://raw.githubusercontent.com/kyaemma/lesbhub-ui/main/dist/main.lua"

local function optionName(value)
    if type(value) == "table" then return tostring(value.Title or value.Value or "") end
    return tostring(value)
end

function UI.open(Engine)
    local loaded, windui = pcall(function()
        local source = game:HttpGet(WINDUI_URL)
        return assert(loadstring(source), "WindUI source failed to compile")()
    end)
    if not loaded or type(windui) ~= "table" then
        error("Could not load Lesbhub WindUI fork: " .. tostring(windui), 0)
    end

    local config = {
        label = "Unlabeled", category = "Other", variant = "Default",
        format = "json",
        targets = {
            ReplicatedStorage = true, ReplicatedFirst = true,
            StarterGui = true, PlayerGui = true, StarterPlayer = true,
        },
        guiTexts = true, guiProperties = true, worldProperties = true,
        assets = true, textboxValues = false, stringValues = false,
        twoPassGui = false, secondPassDelay = 3,
        maxNodes = 15000, maxDepth = 28, yieldEvery = 80,
        chunkSize = 200, maxString = 256, maxBytes = 16 * 1024 * 1024,
    }
    local running, control = false, nil

    local Window = windui:CreateWindow({
        Title = "Lesbhub Exporter",
        Folder = "lesbhub-exporter",
        Icon = "database",
        NewElements = true,
        HideSearchBar = true,
        OpenButton = {Enabled = true, Title = "Lesbhub Exporter"},
    })
    local setup = Window:Tab({Title = "Dataset", Icon = "folder"})
    local targets = Window:Tab({Title = "Targets", Icon = "layers"})
    local options = Window:Tab({Title = "Options", Icon = "settings"})
    local capture = Window:Tab({Title = "Capture", Icon = "scan"})

    setup:Paragraph({
        Title = "Local client snapshot",
        Desc = "Read-only. Output stays on your device. No script Source, remote invocation or uploads. Check exports before sharing.",
    })
    setup:Input({
        Title = "Game label", Value = config.label,
        Placeholder = "Criminality",
        Callback = function(value) config.label = tostring(value) end,
    })
    setup:Input({
        Title = "Category", Value = config.category,
        Placeholder = "Criminality / Universal / Other",
        Callback = function(value) config.category = tostring(value) end,
    })
    setup:Input({
        Title = "Variant", Value = config.variant,
        Placeholder = "Variant A",
        Callback = function(value) config.variant = tostring(value) end,
    })
    setup:Dropdown({
        Title = "Export format",
        Desc = "All formats are chunked; manifest.json is always created.",
        Values = {"JSON", "JSONL", "CSV"}, Value = "JSON",
        Callback = function(value)
            local choice = optionName(value):lower()
            if choice == "json" or choice == "jsonl" or choice == "csv" then
                config.format = choice
            end
        end,
    })

    targets:Paragraph({
        Title = "Choose only what you need",
        Desc = "PlayerGui captures local GUI only. Players, CoreGui, private server identifiers and other players' characters are excluded.",
    })
    local toggles = {}
    for _, service in ipairs(Engine.TARGETS) do
        toggles[service] = targets:Toggle({
            Title = service, Value = config.targets[service] == true,
            Callback = function(value) config.targets[service] = value == true end,
        })
    end

    local function setPreset(which)
        local presets = {
            gui = {StarterGui = true, PlayerGui = true},
            structures = {
                ReplicatedStorage = true, ReplicatedFirst = true,
                StarterPlayer = true, PlayerScripts = true, StarterPack = true,
            },
        }
        for _, service in ipairs(Engine.TARGETS) do
            local enabled = which == "full" or (presets[which] and presets[which][service] == true)
            config.targets[service] = enabled
            if toggles[service] then toggles[service]:Set(enabled, false) end
        end
    end
    targets:Button({Title = "Preset: GUI only", Callback = function() setPreset("gui") end})
    targets:Button({Title = "Preset: Structures only", Callback = function() setPreset("structures") end})
    targets:Button({Title = "Preset: Full client", Callback = function() setPreset("full") end})

    options:Toggle({
        Title = "GUI text", Value = config.guiTexts,
        Desc = "TextLabel/TextButton text and TextBox placeholders.",
        Callback = function(value) config.guiTexts = value end,
    })
    options:Toggle({
        Title = "GUI layout and colors", Value = config.guiProperties,
        Callback = function(value) config.guiProperties = value end,
    })
    options:Toggle({
        Title = "World/config properties", Value = config.worldProperties,
        Callback = function(value) config.worldProperties = value end,
    })
    options:Toggle({
        Title = "Asset IDs", Value = config.assets,
        Callback = function(value) config.assets = value end,
    })
    options:Toggle({
        Title = "TextBox.Text (privacy risk)", Value = false,
        Desc = "Disabled by default: may contain text typed by users.",
        Callback = function(value) config.textboxValues = value end,
    })
    options:Toggle({
        Title = "StringValue.Value (privacy risk)", Value = false,
        Desc = "Disabled by default: may contain keys, identifiers or player data.",
        Callback = function(value) config.stringValues = value end,
    })
    options:Toggle({
        Title = "Second GUI pass", Value = false,
        Desc = "A single delayed extra snapshot of PlayerGui/StarterGui. No background loop.",
        Callback = function(value) config.twoPassGui = value end,
    })
    options:Slider({
        Title = "Extra pass delay (seconds)", Step = 1,
        Value = {Min = 1, Max = 10, Default = 3},
        Callback = function(value) config.secondPassDelay = value end,
    })
    options:Slider({
        Title = "Max objects", Step = 500,
        Value = {Min = 500, Max = 50000, Default = 15000},
        Callback = function(value) config.maxNodes = value end,
    })
    options:Slider({
        Title = "Max depth", Step = 1,
        Value = {Min = 2, Max = 80, Default = 28},
        Callback = function(value) config.maxDepth = value end,
    })
    options:Slider({
        Title = "Objects per yield", Step = 5,
        Value = {Min = 15, Max = 500, Default = 80},
        Callback = function(value) config.yieldEvery = value end,
    })
    options:Slider({
        Title = "Objects per file", Step = 25,
        Value = {Min = 25, Max = 800, Default = 200},
        Callback = function(value) config.chunkSize = value end,
    })
    options:Dropdown({
        Title = "Total size limit",
        Values = {"8 MiB", "16 MiB", "32 MiB", "64 MiB"},
        Value = "16 MiB",
        Callback = function(value)
            local size = tonumber(optionName(value):match("%d+"))
            if size then config.maxBytes = size * 1024 * 1024 end
        end,
    })

    capture:Paragraph({
        Title = "Start a bounded capture",
        Desc = "Every service is exported in small files. A manifest records partial captures, errors and limits. No detector in V1.",
    })
    local progress = nil
    local okProgress, result = pcall(function()
        return capture:ProgressBar({
            Title = "Objects visited (budget)",
            Value = {Min = 0, Max = 50000, Default = 0},
            DisplayMode = "Value", Animate = false,
        })
    end)
    if okProgress then progress = result end

    local function alert(title, content)
        local ok = pcall(function()
            windui:Notify({Title = title, Content = tostring(content), Duration = 6})
        end)
        if not ok then warn("[Lesbhub Exporter] " .. title .. ": " .. tostring(content)) end
    end
    capture:Button({
        Title = "Start export", Icon = "download",
        Callback = function()
            if running then alert("Already capturing", "Use Cancel first.") return end
            if type(writefile) ~= "function" or type(makefolder) ~= "function" then
                alert("Missing executor APIs", "writefile and makefolder are required.")
                return
            end
            running = true
            control = {cancelled = false}
            local runControl = control
            local runConfig = {}
            for key, value in pairs(config) do
                if key == "targets" then
                    runConfig.targets = {}
                    for service, enabled in pairs(value) do runConfig.targets[service] = enabled end
                else
                    runConfig[key] = value
                end
            end
            if progress and progress.Set then pcall(function() progress:Set(0) end) end
            alert("Export started", "Capturing selected services. Roblox may be slower while traversing.")
            task.spawn(function()
                local ok, data, err = pcall(Engine.capture, runConfig, function(info)
                    if progress and progress.Set then
                        pcall(function() progress:Set(info.visited) end)
                    end
                    if info.stage == "service_done" then
                        print(string.format("[Lesbhub Exporter] %s: %d objects visited, %d files",
                            tostring(info.service), info.visited, info.files))
                    end
                end, runControl)
                running = false
                if not ok then
                    alert("Export failed", "Capture crashed; see executor console.")
                    warn("[Lesbhub Exporter] " .. tostring(data))
                elseif not data then
                    alert("Export failed", tostring(err))
                else
                    local m = data.manifest
                    alert("Export " .. m.status,
                        string.format("%d objects, %d files. Folder: %s",
                            m.stats.written, m.stats.files, data.folder))
                    print("[Lesbhub Exporter] Output: " .. data.folder .. "/manifest.json")
                end
            end)
        end,
    })
    capture:Button({
        Title = "Cancel capture", Icon = "square",
        Callback = function()
            if running and control then
                control.cancelled = true
                alert("Cancel requested", "The exporter will stop at its next yield and write a partial manifest.")
            end
        end,
    })
    capture:Paragraph({
        Title = "Privacy reminder",
        Desc = "Exports may contain game interface text. Never publish unreviewed captures. Player names and known sensitive tokens are redacted best-effort, not guaranteed.",
    })
    return Window
end

return UI
