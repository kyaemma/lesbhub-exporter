-- Lesbhub Exporter V1.1 UI. Uses our public WindUI fork, not the upstream library.
local UI = {}
local WINDUI_URL = "https://raw.githubusercontent.com/kyaemma/lesbhub-ui/main/dist/main.lua"

local function optionName(value)
    if type(value) == "table" then return tostring(value.Title or value.Value or "") end
    return tostring(value)
end

local function shortPath(path)
    local value = tostring(path or "")
    if #value > 128 then return "..." .. value:sub(-125) end
    return value
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
        format = "json", targets = {},
        guiTexts = true, guiProperties = true, worldProperties = true,
        assets = true, textboxValues = false, stringValues = false,
        twoPassGui = true, guiPasses = 3, secondPassDelay = 6,
        yieldEvery = 60, chunkSize = 200,
    }
    -- Exhaustive is the default. A target is omitted only by explicit selection.
    for _, service in ipairs(Engine.TARGETS) do config.targets[service] = true end
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
    local map = Window:Tab({Title = "Map", Icon = "map"})

    setup:Paragraph({
        Title = "Complete client-visible snapshot",
        Desc = "No object count, depth, size or text-length cap. Output remains local. Roblox server-only data is not accessible.",
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
        Desc = "JSON / JSONL / CSV are split into small files. Always includes manifest.json.",
        Values = {"JSON", "JSONL", "CSV"}, Value = "JSON",
        Callback = function(value)
            local choice = optionName(value):lower()
            if choice == "json" or choice == "jsonl" or choice == "csv" then
                config.format = choice
            end
        end,
    })

    targets:Paragraph({
        Title = "Full client selected by default",
        Desc = "Deselect unwanted services. PlayerGui refers to your local UI. Other players' characters, chat and CoreGui are excluded.",
    })
    local toggles = {}
    for _, service in ipairs(Engine.TARGETS) do
        toggles[service] = targets:Toggle({
            Title = service, Value = true,
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
    targets:Button({Title = "Full client (default)", Callback = function() setPreset("full") end})
    targets:Button({Title = "GUI only", Callback = function() setPreset("gui") end})
    targets:Button({Title = "Structures only", Callback = function() setPreset("structures") end})

    options:Paragraph({
        Title = "Exhaustive does not mean unsafe",
        Desc = "There are no global export caps. Chunk size and yield cadence protect frame time without limiting what is collected.",
    })
    options:Toggle({
        Title = "GUI texts and placeholders", Value = true,
        Callback = function(value) config.guiTexts = value end,
    })
    options:Toggle({
        Title = "GUI layout and colors", Value = true,
        Callback = function(value) config.guiProperties = value end,
    })
    options:Toggle({
        Title = "World/config properties", Value = true,
        Callback = function(value) config.worldProperties = value end,
    })
    options:Toggle({
        Title = "Asset IDs (not binary downloads)", Value = true,
        Callback = function(value) config.assets = value end,
    })
    options:Toggle({
        Title = "TextBox.Text (privacy risk)", Value = false,
        Desc = "Normally avoid: may contain player-entered messages and codes.",
        Callback = function(value) config.textboxValues = value end,
    })
    options:Toggle({
        Title = "StringValue.Value (privacy risk)", Value = false,
        Desc = "Normally avoid: may contain identifiers or private values.",
        Callback = function(value) config.stringValues = value end,
    })
    options:Toggle({
        Title = "Guided dynamic-menu snapshots", Value = true,
        Desc = "Open game menus yourself between captures; no simulated purchases or remote calls.",
        Callback = function(value) config.twoPassGui = value end,
    })
    options:Slider({
        Title = "Total GUI snapshots", Step = 1,
        Value = {Min = 2, Max = 8, Default = 3},
        Callback = function(value) config.guiPasses = value end,
    })
    options:Slider({
        Title = "Seconds between GUI snapshots", Step = 1,
        Value = {Min = 2, Max = 25, Default = 6},
        Callback = function(value) config.secondPassDelay = value end,
    })
    options:Slider({
        Title = "Objects per yield", Step = 10,
        Value = {Min = 10, Max = 250, Default = 60},
        Callback = function(value) config.yieldEvery = value end,
    })
    options:Slider({
        Title = "Records per file (not export limit)", Step = 25,
        Value = {Min = 25, Max = 800, Default = 200},
        Callback = function(value) config.chunkSize = value end,
    })

    capture:Paragraph({
        Title = "Exhaustive scan, with live feedback",
        Desc = "Every accessible object is visited. Records are written incrementally; the progress ratio represents nodes discovered so far, not a fixed total.",
    })
    local progress = nil
    local okProgress, progressResult = pcall(function()
        return capture:ProgressBar({
            Title = "Adaptive progress (total not known)",
            Value = {Min = 0, Max = 1000, Default = 0},
            DisplayMode = "Fraction", Animate = false,
        })
    end)
    if okProgress then progress = progressResult end

    local status = capture:Paragraph({
        Title = "Idle",
        Desc = "Choose Start full export, or open a menu and use Capture GUI now.",
    })
    local log = nil
    local okLog, logResult = pcall(function()
        return capture:Code({
            Title = "Live capture feed",
            Code = "Ready. Waiting for a capture...",
            Height = 170,
            CanCopied = true,
        })
    end)
    if okLog then log = logResult end

    local function alert(title, content)
        local ok = pcall(function()
            windui:Notify({Title = title, Content = tostring(content), Duration = 6})
        end)
        if not ok then warn("[Lesbhub Exporter] " .. title .. ": " .. tostring(content)) end
    end

    local function startCapture(mode)
        local guiOnly = mode == "gui"
        local mapOnly = mode == "map"
        if running then alert("Already capturing", "Cancel the existing capture first.") return end
        if type(writefile) ~= "function" or type(makefolder) ~= "function" then
            alert("Missing file APIs", "writefile and makefolder are required.")
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
        if guiOnly then
            runConfig.targets = {PlayerGui = true, StarterGui = true}
            runConfig.twoPassGui = false
        elseif mapOnly then
            runConfig.targets = {Workspace = true, Lighting = true, SoundService = true}
            runConfig.twoPassGui = false
            runConfig.variant = tostring(config.variant) .. "-map"
        end

        local events, lastRender, progressCeiling = {}, -math.huge, 1000
        local function event(value)
            events[#events + 1] = value
            if #events > 14 then table.remove(events, 1) end
            print("[Lesbhub Exporter] " .. value)
        end
        local function present(info, force)
            local now = os.clock()
            if not force and now - lastRender < 0.18 then return end
            lastRender = now
            local discovered = math.max(info.discovered or 0, 0)
            local visited = math.max(info.visited or 0, 0)
            -- The final number of client nodes is unknowable until traversal
            -- finishes. Grow the scale as needed; never clamp at 100k.
            progressCeiling = math.max(progressCeiling, math.ceil((discovered + 250) / 1000) * 1000)
            if info.stage == "done" then progressCeiling = math.max(visited, 1) end
            if progress then
                pcall(function()
                    progress:SetRange(0, progressCeiling)
                    progress:Set(math.min(visited, progressCeiling))
                end)
            end
            if status then
                pcall(function()
                    status:SetTitle(string.format("%s  /  pass %d",
                        tostring(info.service or "Export"), tonumber(info.pass) or 1))
                    status:SetDesc(string.format(
                        "Visited: %d | Discovered: %d+ | Waiting: %d | Written: %d | Files: %d | Assets: %d | %.1fs",
                        info.visited or 0, info.discovered or 0, info.pending or 0,
                        info.written or 0, info.files or 0, info.assetReferences or 0,
                        info.elapsedSeconds or 0))
                end)
            end
            if log then
                local lines = {
                    "LIVE  " .. tostring(info.stage or "scan"),
                    "Class: " .. tostring(info.currentClass or "-"),
                    "Path: " .. shortPath(info.currentPath),
                    "Bytes: " .. tostring(info.bytes or 0),
                    "--- Recent events ---",
                }
                for _, message in ipairs(events) do lines[#lines + 1] = message end
                pcall(function() log:SetCode(table.concat(lines, "\n")) end)
            end
        end

        if progress then
            pcall(function() progress:SetRange(0, 1000); progress:Set(0) end)
        end
        if status then pcall(function() status:SetTitle("Starting...") end) end
        event(guiOnly and "Starting manual GUI snapshot"
            or (mapOnly and "Starting Workspace map geometry export"
                or "Starting exhaustive client capture"))
        if not guiOnly and not mapOnly and runConfig.twoPassGui then
            alert("Guided menu capture",
                "After the initial scan, open STORE for pass 2, then SKINS for pass 3.")
        end
        task.spawn(function()
            local ok, data, err = pcall(Engine.capture, runConfig, function(info)
                if info.stage == "service_start" then
                    event(string.format("Start %s (pass %s)", tostring(info.service), tostring(info.pass)))
                elseif info.stage == "service_done" then
                    event(string.format("Saved %s (pass %s): %d objects visited",
                        tostring(info.service), tostring(info.pass), info.visited or 0))
                elseif info.stage == "file_written" then
                    event(string.format("File #%d written (%d records total)",
                        info.files or 0, info.written or 0))
                elseif info.stage == "waiting_gui_pass" then
                    local nextPass = (tonumber(info.pass) or 1) + 1
                    local suggested = nextPass == 2 and "STORE" or (nextPass == 3 and "SKINS" or "another menu")
                    event("Open " .. suggested .. " now for next GUI snapshot")
                    alert("Open a game menu", "Open " .. suggested ..
                        " in the game before the next GUI snapshot (" .. tostring(runConfig.secondPassDelay) .. "s).")
                elseif info.stage == "missing_root" then
                    event("Missing accessible root: " .. tostring(info.service))
                elseif info.stage == "done" then
                    event("Capture finished: " .. tostring(info.service))
                end
                present(info, info.stage ~= "scanning")
            end, runControl)
            running = false
            if not ok then
                event("Export crashed: " .. tostring(data))
                alert("Export failed", "Capture crashed; see console and live log.")
            elseif not data then
                event("Export failed: " .. tostring(err))
                alert("Export failed", tostring(err))
            else
                local m = data.manifest
                event(string.format("Done: %d records, %d data files, %d asset references",
                    m.stats.written, m.stats.files, m.stats.assetReferences or 0))
                if status then
                    pcall(function()
                        status:SetTitle("Finished: " .. m.status)
                        status:SetDesc(data.folder .. "/manifest.json")
                    end)
                end
                alert("Export " .. m.status,
                    string.format("%d objects, %d files. Folder: %s",
                        m.stats.written, m.stats.files, data.folder))
                print("[Lesbhub Exporter] Output: " .. data.folder .. "/manifest.json")
            end
        end)
    end

    capture:Button({
        Title = "Start full export", Icon = "download",
        Callback = function() startCapture("full") end,
    })
    capture:Button({
        Title = "Capture GUI now", Icon = "monitor",
        Desc = "Open STORE, SKINS or another menu yourself, then click this button.",
        Callback = function() startCapture("gui") end,
    })
    capture:Button({
        Title = "Cancel capture", Icon = "square",
        Callback = function()
            if running and control then
                control.cancelled = true
                alert("Cancellation requested", "Remaining buffered records will be flushed and a partial manifest written.")
            end
        end,
    })
    map:Paragraph({
        Title = "Map geometry (JSON)",
        Desc = "Exports Workspace, Lighting and SoundService with part positions, rotations, sizes, materials and asset references. Client-visible only; Terrain voxels and binary assets are not included.",
    })
    map:Button({
        Title = "Export map geometry", Icon = "box",
        Desc = "Works with the existing read-only exporter and chunked files.",
        Callback = function() startCapture("map") end,
    })
    map:Paragraph({
        Title = "Native place file (Infinite Yield-style)",
        Desc = "IY's savegame command calls the executor's saveinstance(). This is optional and may include more than geometry or unfiltered contents. Review any resulting file before sharing.",
    })
    local nativeAllowed, nativeBusy = false, false
    map:Toggle({
        Title = "I authorize executor-native saveinstance()",
        Value = false,
        Desc = "Separate from Lesbhub's privacy-filtered JSON. Requires a supported executor.",
        Callback = function(value) nativeAllowed = value == true end,
    })
    map:Button({
        Title = "Save native Roblox place", Icon = "save",
        Desc = "Only available if the current executor implements saveinstance().",
        Callback = function()
            if not nativeAllowed then
                alert("Confirmation required", "Enable the native export toggle first.")
                return
            end
            if running or nativeBusy then
                alert("Exporter busy", "Wait for the current operation to finish.")
                return
            end
            nativeBusy = true
            alert("Native export requested", "The executor controls the output and location.")
            task.spawn(function()
                local ok, supported, result = pcall(Engine.savePlace)
                nativeBusy = false
                if not ok then
                    alert("Native export failed", tostring(supported))
                elseif not supported then
                    alert("Native export unavailable", tostring(result))
                else
                    alert("Native export returned", "Check your executor's workspace; a place file is not guaranteed.")
                    print("[Lesbhub Exporter] saveinstance returned: " .. tostring(result))
                end
            end)
        end,
    })

    capture:Paragraph({
        Title = "Privacy reminder",
        Desc = "Captures may contain GUI text. Review before publishing. Player-name and token redaction is best-effort.",
    })
    return Window
end

return UI
