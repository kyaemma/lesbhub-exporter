-- Lesbhub Exporter UI - streamlined WindUI client, capture engine stays independent.
local UI = {}
local WINDUI_URL = "https://raw.githubusercontent.com/kyaemma/lesbhub-ui/main/dist/main.lua"

local PRESETS = {
    ["Max informations"] = {
        guiTexts = true, guiProperties = true, worldProperties = true, assets = true,
        textboxValues = true, stringValues = true, twoPassGui = true,
        guiPasses = 4, secondPassDelay = 7, yieldEvery = 45, chunkSize = 200,
    },
    Smart = {
        guiTexts = true, guiProperties = true, worldProperties = true, assets = true,
        textboxValues = true, stringValues = true, twoPassGui = true,
        guiPasses = 3, secondPassDelay = 6, yieldEvery = 80, chunkSize = 300,
    },
    Fast = {
        guiTexts = true, guiProperties = false, worldProperties = false, assets = true,
        textboxValues = true, stringValues = true, twoPassGui = true,
        guiPasses = 2, secondPassDelay = 3, yieldEvery = 140, chunkSize = 500,
    },
}
local PRESET_DESCRIPTIONS = {
    ["Max informations"] = "Toutes les propriétés disponibles, textes et valeurs, 4 captures GUI. Le plus détaillé.",
    Smart = "Toutes les structures, textes, propriétés et assets, avec 3 captures GUI. Équilibré.",
    Fast = "Tous les objets, textes et assets, mais moins de propriétés et 2 captures GUI. Plus rapide.",
}

local function optionName(value)
    return type(value) == "table" and tostring(value.Title or value.Value or "") or tostring(value)
end

local function countText(value)
    local n = math.max(0, tonumber(value) or 0)
    if n >= 1000000 then
        return string.format("%.2fM", n / 1000000)
    elseif n >= 1000 then
        return string.format("%.1fK", n / 1000)
    end
    return tostring(math.floor(n))
end

local function shortPath(path)
    local s = tostring(path or "")
    return #s > 106 and ("..." .. s:sub(-103)) or s
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local output = {}
    for key, item in pairs(value) do output[key] = copy(item) end
    return output
end

function UI.open(Engine)
    local shared = (type(getgenv) == "function" and getgenv()) or _G
    -- Re-running the loader while the UI is open focuses the existing window.
    local existing = shared.LesbhubExporterHandle
    if type(existing) == "table" and not existing.destroyed and existing.window
        and not existing.window.Destroyed then
        pcall(function() existing.window:Open() end)
        return existing.window
    end

    local loaded, windui = pcall(function()
        local source = game:HttpGet(WINDUI_URL)
        return assert(loadstring(source), "Lesbhub WindUI failed to compile")()
    end)
    if not loaded or type(windui) ~= "table" then
        error("Could not load Lesbhub WindUI fork: " .. tostring(windui), 0)
    end

    local config = copy(PRESETS["Max informations"])
    config.label, config.category, config.variant = "Unlabeled", "Other", "Default"
    config.format = "json"
    config.targets = {}
    for _, service in ipairs(Engine.TARGETS) do config.targets[service] = true end

    local running, control, destroyed = false, nil, false
    local selectedPreset = "Max informations"
    local Window = windui:CreateWindow({
        Title = "Lesbhub Exporter",
        Folder = "lesbhub-exporter",
        Icon = "database",
        NewElements = true,
        HideSearchBar = true,
        ToggleKey = Enum.KeyCode.RightShift,
        OpenButton = {Enabled = true, Title = "Lesbhub Exporter"},
    })

    local function alert(title, message)
        if destroyed then return end
        local ok = pcall(function()
            windui:Notify({Title = title, Content = tostring(message), Duration = 6})
        end)
        if not ok then warn("[Lesbhub Exporter] " .. title .. ": " .. tostring(message)) end
    end

    local function unload()
        if destroyed then return end
        destroyed = true
        if control then control.cancelled = true end
        if shared.LesbhubExporterHandle then
            shared.LesbhubExporterHandle.destroyed = true
            shared.LesbhubExporterHandle = nil
        end
        -- WindUI removes the ScreenGuis and disconnects registered listeners.
        -- The capture engine is asked to cancel at its next safe yield.
        pcall(function() Window:Destroy() end)
    end

    shared.LesbhubExporterHandle = {window = Window, Unload = unload, destroyed = false}
    Window:OnDestroy(function()
        destroyed = true
        if control then control.cancelled = true end
        if shared.LesbhubExporterHandle
            and shared.LesbhubExporterHandle.window == Window then
            shared.LesbhubExporterHandle.destroyed = true
            shared.LesbhubExporterHandle = nil
        end
    end)

    local dataset = Window:Tab({Title = "Dataset", Icon = "folder"})
    local targets = Window:Tab({Title = "Targets", Icon = "layers"})
    local options = Window:Tab({Title = "Options", Icon = "settings"})
    local capture = Window:Tab({Title = "Capture", Icon = "scan"})
    local map = Window:Tab({Title = "Map", Icon = "map"})
    local settings = Window:Tab({Title = "Settings", Icon = "keyboard"})

    dataset:Paragraph({
        Title = "Export local et complet",
        Desc = "Une capture structurée des objets visibles sur le client. JSON, JSONL ou CSV. Les sources des scripts ne sont pas lues.",
    })
    dataset:Input({
        Title = "Jeu", Value = config.label, Placeholder = "Criminality",
        Callback = function(value) config.label = tostring(value) end,
    })
    dataset:Input({
        Title = "Catégorie", Value = config.category, Placeholder = "Criminality / Other",
        Callback = function(value) config.category = tostring(value) end,
    })
    dataset:Input({
        Title = "Variante", Value = config.variant, Placeholder = "Officiel / Modded A",
        Callback = function(value) config.variant = tostring(value) end,
    })
    dataset:Dropdown({
        Title = "Format", Values = {"JSON", "JSONL", "CSV"}, Value = "JSON",
        Callback = function(value)
            local choice = optionName(value):lower()
            if choice == "json" or choice == "jsonl" or choice == "csv" then
                config.format = choice
            end
        end,
    })

    targets:Paragraph({
        Title = "Services Roblox",
        Desc = "Tous les services sont sélectionnés par défaut. Clique sur la sélection pour cocher ou décocher plusieurs services.",
    })
    local chosenNames = copy(Engine.TARGETS)
    local chosenStatus = targets:Paragraph({
        Title = tostring(#chosenNames) .. " services sélectionnés",
        Desc = "Full export inclut PlayerGui et StarterGui par défaut.",
    })
    local targetPicker
    local function updateTargets(selected)
        local allowed = {}
        for _, service in ipairs(Engine.TARGETS) do allowed[service] = true end
        local names, updated = {}, {}
        for _, item in ipairs(type(selected) == "table" and selected or {}) do
            local name = optionName(item)
            if allowed[name] and not updated[name] then
                names[#names + 1] = name
                updated[name] = true
            end
        end
        config.targets = updated
        chosenNames = names
        if chosenStatus then
            pcall(function()
                chosenStatus:SetTitle(string.format("%d / %d services", #names, #Engine.TARGETS))
                chosenStatus:SetDesc(#names == #Engine.TARGETS
                    and "Tout est sélectionné."
                    or (#names == 0 and "Aucune cible : choisis au moins un service."
                    or "Sélection personnalisée prête pour l'export."))
            end)
        end
    end
    targetPicker = targets:Dropdown({
        Title = "Sélection multiple",
        Desc = "Recherche et coche plusieurs services.",
        Values = copy(Engine.TARGETS),
        Value = copy(Engine.TARGETS),
        Multi = true, AllowNone = true, SearchBarEnabled = true, MenuWidth = 250,
        Callback = updateTargets,
    })
    local function useTargets(list)
        updateTargets(list)
        if targetPicker and targetPicker.Select then
            pcall(function() targetPicker:Select(copy(list)) end)
        end
    end
    targets:Button({
        Title = "Tout sélectionner", Icon = "check-check",
        Callback = function() useTargets(copy(Engine.TARGETS)) end,
    })
    targets:Button({
        Title = "GUI uniquement", Icon = "monitor",
        Callback = function() useTargets({"PlayerGui", "StarterGui"}) end,
    })
    targets:Button({
        Title = "Structure du jeu", Icon = "boxes",
        Callback = function() useTargets({
            "ReplicatedStorage", "ReplicatedFirst", "StarterPlayer",
            "PlayerScripts", "StarterPack",
        }) end,
    })

    options:Paragraph({
        Title = "Préréglages",
        Desc = "Max informations = le plus complet. Smart = équilibré. Fast = propriétés simplifiées. Tous gardent les objets, les textes et la capture GUI.",
    })
    local presetSummary = options:Paragraph({
        Title = "Max informations",
        Desc = PRESET_DESCRIPTIONS["Max informations"],
    })
    local advanced = options:Section({
        Title = "Advanced",
        Desc = "Réglages détaillés (fermé par défaut)",
        Box = true, Opened = false,
    })
    local controls = {}
    local applyingPreset = false
    local function markAdvanced()
        if applyingPreset then return end
        selectedPreset = "Personnalisé"
        pcall(function()
            presetSummary:SetTitle("Personnalisé")
            presetSummary:SetDesc("Réglages modifiés dans Advanced.")
        end)
    end
    local function addToggle(key, title, desc)
        controls[key] = advanced:Toggle({
            Title = title, Desc = desc, Value = config[key],
            Callback = function(value)
                config[key] = value == true
                markAdvanced()
            end,
        })
    end
    local function addSlider(key, title, min, max, step)
        controls[key] = advanced:Slider({
            Title = title, Step = step,
            Value = {Min = min, Max = max, Default = config[key]},
            Callback = function(value)
                config[key] = math.floor(tonumber(value) or config[key])
                markAdvanced()
            end,
        })
    end
    addToggle("guiTexts", "Textes GUI", "Labels, boutons et placeholders.")
    addToggle("guiProperties", "Propriétés GUI", "Tailles, positions et couleurs.")
    addToggle("worldProperties", "Propriétés du monde", "Géométrie, valeurs, matériaux.")
    addToggle("assets", "Références d'assets", "Images, sons, animations, modèles (IDs uniquement).")
    addToggle("textboxValues", "Contenu des champs TextBox", "Peut contenir du texte saisi par l'utilisateur.")
    addToggle("stringValues", "Valeurs StringValue", "Peut contenir des identifiants ou données de session.")
    addToggle("twoPassGui", "Captures GUI supplémentaires", "Incluses dans Full export si activées.")
    addSlider("guiPasses", "Passes GUI (total)", 2, 8, 1)
    addSlider("secondPassDelay", "Intervalle GUI (secondes)", 2, 25, 1)
    addSlider("yieldEvery", "Opérations entre pauses", 10, 250, 10)
    addSlider("chunkSize", "Enregistrements par fichier", 25, 800, 25)
    advanced:Paragraph({
        Title = "Pas de limites globales",
        Desc = "La profondeur, le nombre total d'objets et le volume d'export ne sont pas limités. Chunk et yield ne limitent que le travail par étape.",
    })

    local function applyPreset(name)
        local chosen = PRESETS[name]
        if not chosen then return end
        applyingPreset = true
        for key, value in pairs(chosen) do
            config[key] = value
            local widget = controls[key]
            if widget and widget.Set then
                pcall(function() widget:Set(value, false) end)
            end
        end
        applyingPreset = false
        selectedPreset = name
        pcall(function()
            presetSummary:SetTitle(name)
            presetSummary:SetDesc(PRESET_DESCRIPTIONS[name])
        end)
    end
    options:Dropdown({
        Title = "Mode d'export",
        Values = {"Max informations", "Smart", "Fast"},
        Value = "Max informations",
        Callback = function(value) applyPreset(optionName(value)) end,
    })

    capture:Paragraph({
        Title = "Full export + GUI en une fois",
        Desc = "Le scan inclut les GUI et leurs captures successives. Ouvre STORE, SKINS ou d'autres menus pendant les intervalles pour récupérer leurs textes.",
    })
    local stageStatus = capture:Paragraph({
        Title = "Prêt à exporter",
        Desc = "Démarre la capture. Le total exact d'objets sera connu seulement à la fin.",
    })
    local activityBar = nil
    local latestLog = capture:Code({
        Title = "Journal",
        Code = "Aucune capture active.",
        Height = 180,
        CanCopied = true,
    })
    local lastSummary = capture:Paragraph({
        Title = "Aucun export",
        Desc = "Les résultats apparaîtront ici.",
    })

    local function startCapture(mode)
        if destroyed then return end
        if running then alert("Export déjà en cours", "Annule-le avant de recommencer.") return end
        if type(writefile) ~= "function" or type(makefolder) ~= "function" then
            alert("API fichiers indisponible", "writefile et makefolder sont nécessaires.")
            return
        end
        local runConfig = copy(config)
        if mode == "gui" then
            runConfig.targets = {PlayerGui = true, StarterGui = true}
            runConfig.twoPassGui = false
        elseif mode == "map" then
            runConfig.targets = {Workspace = true, Lighting = true, SoundService = true}
            runConfig.twoPassGui = false
            runConfig.variant = tostring(config.variant) .. "-map"
        elseif not next(runConfig.targets) then
            alert("Aucune cible", "Sélectionne au moins un service dans Targets.")
            return
        end

        running = true
        control = {cancelled = false}
        local runControl = control
        local history, lastDraw = {}, -math.huge
        local stageNames = {}
        for _, name in ipairs(Engine.TARGETS) do
            if runConfig.targets[name] then stageNames[#stageNames + 1] = name end
        end
        local finishedServices = 0
        if activityBar then
            pcall(function() activityBar:Destroy() end)
            activityBar = nil
        end
        local okProgress, spinner = pcall(function()
            return capture:ProgressBar({
                Title = "Capture en cours • total inconnu",
                Indeterminate = true, ShowValue = false, Speed = 0.9,
                Animate = false,
            })
        end)
        if okProgress then activityBar = spinner end

        local function event(text)
            history[#history + 1] = text
            if #history > 11 then table.remove(history, 1) end
            print("[Lesbhub Exporter] " .. text)
        end
        local function draw(info, important)
            if destroyed then return end
            local now = os.clock()
            if not important and now - lastDraw < 0.25 then return end
            lastDraw = now
            pcall(function()
                stageStatus:SetTitle(string.format("%s • passe %d",
                    tostring(info.service or "Export"), tonumber(info.pass) or 1))
                stageStatus:SetDesc(string.format(
                    "%s vus | %s écrits | %s en attente | %s fichiers | %s assets | %.1f s",
                    countText(info.visited), countText(info.written),
                    countText(info.pending), countText(info.files),
                    countText(info.assetReferences), info.elapsedSeconds or 0))
            end)
            local lines = {
                string.format("ACTIF  -  %s / %s services (passe 1)", finishedServices, #stageNames),
                "Étape : " .. tostring(info.stage or "scan"),
                "Classe : " .. tostring(info.currentClass or "-"),
                "Chemin : " .. shortPath(info.currentPath),
                "Découverts : " .. countText(info.discovered),
                "Données : " .. countText((info.bytes or 0) / 1024) .. " KB",
                "---------",
            }
            for _, line in ipairs(history) do lines[#lines + 1] = line end
            pcall(function() latestLog:SetCode(table.concat(lines, "\n")) end)
        end

        event("Début : " .. (mode == "full" and "Full export" or mode))
        task.spawn(function()
            local ok, result, err = pcall(Engine.capture, runConfig, function(info)
                if destroyed then return end
                if info.stage == "service_start" then
                    event(string.format("Scan %s • passe %d",
                        tostring(info.service), info.pass or 1))
                elseif info.stage == "service_done" then
                    if info.pass == 1 then finishedServices = finishedServices + 1 end
                    event(string.format("Fin %s • %s objets",
                        tostring(info.service), countText(info.visited)))
                elseif info.stage == "file_written" then
                    -- Keep event log readable on 100k+ object captures.
                    if (info.files or 0) % 25 == 0 then
                        event(countText(info.files) .. " fichiers écrits")
                    end
                elseif info.stage == "waiting_gui_pass" then
                    local pass = (tonumber(info.pass) or 1) + 1
                    local suggested = pass == 2 and "STORE" or (pass == 3 and "SKINS" or "un autre menu")
                    event("Ouvre " .. suggested .. " pour la prochaine capture GUI")
                    alert("Capture GUI à venir", "Ouvre " .. suggested ..
                        " pendant les " .. tostring(runConfig.secondPassDelay) .. " prochaines secondes.")
                elseif info.stage == "missing_root" then
                    event("Service inaccessible : " .. tostring(info.service))
                end
                draw(info, info.stage ~= "scanning")
            end, runControl)
            running = false
            control = nil
            if destroyed then return end
            if activityBar then
                pcall(function() activityBar:Destroy() end)
                activityBar = nil
            end
            if not ok or not result then
                local reason = not ok and tostring(result) or tostring(err)
                event("Erreur : " .. reason)
                pcall(function()
                    stageStatus:SetTitle("Capture interrompue")
                    stageStatus:SetDesc(reason)
                end)
                alert("Capture échouée", reason)
            else
                local manifest = result.manifest
                local summary = string.format("%s objets • %s fichiers • %s assets • %.1f s",
                    countText(manifest.stats.written), countText(manifest.stats.files),
                    countText(manifest.stats.assetReferences), manifest.stats.elapsedSeconds or 0)
                event("Terminé : " .. summary)
                pcall(function()
                    stageStatus:SetTitle("Terminé : " .. manifest.status)
                    stageStatus:SetDesc(summary)
                    lastSummary:SetTitle("Export : " .. manifest.status)
                    lastSummary:SetDesc(result.folder .. "/manifest.json")
                    latestLog:SetCode(table.concat(history, "\n"))
                end)
                alert("Export " .. manifest.status, summary)
                print("[Lesbhub Exporter] " .. result.folder .. "/manifest.json")
            end
        end)
    end

    local function confirmCapture(mode)
        if destroyed or running then return end
        local risky = config.textboxValues or config.stringValues
        local kind = mode == "full" and "Full export + GUI"
            or (mode == "gui" and "Capture GUI" or "Export de carte")
        Window:Dialog({
            Title = "Confirmer : " .. kind,
            Width = 390,
            Content = "Les fichiers sont enregistrés localement.\n\n"
                .. (risky and
                    "ATTENTION : les valeurs TextBox.Text et StringValue.Value peuvent contenir des données privées, identifiants ou données de session.\n\n"
                    or "Les propriétés sensibles sont désactivées.\n\n")
                .. "Ne publie pas cette archive sur GitHub, Discord ou un site public sans contrôle et nettoyage préalable.\n\n"
                .. "Aucune donnée n'est téléversée par Lesbhub Exporter. Confirmer le lancement ?",
            Buttons = {
                {Title = "Annuler", Variant = "Secondary", Callback = function() end},
                {Title = "J'ai compris • Exporter", Variant = "Primary",
                    Callback = function() startCapture(mode) end},
            },
        })
    end

    capture:Button({
        Title = "Full export + GUI", Icon = "download",
        Desc = "Une seule action, avec toutes les cibles sélectionnées.",
        Callback = function() confirmCapture("full") end,
    })
    capture:Button({
        Title = "Capture GUI maintenant", Icon = "monitor",
        Desc = "Facultatif : instantané supplémentaire après ouverture d'un menu.",
        Callback = function() confirmCapture("gui") end,
    })
    capture:Button({
        Title = "Annuler la capture", Icon = "square",
        Callback = function()
            if control and running then
                control.cancelled = true
                alert("Annulation demandée", "Les fichiers déjà écrits seront conservés.")
            end
        end,
    })

    map:Paragraph({
        Title = "Exporter la carte",
        Desc = "Sauvegarde la carte visible côté client : bâtiments, objets et leurs positions. Les fichiers JSON sont créés localement.",
    })
    map:Button({
        Title = "Exporter la carte en JSON", Icon = "map",
        Callback = function() confirmCapture("map") end,
    })
    map:Paragraph({
        Title = "Sauvegarde Roblox native",
        Desc = "Disponible uniquement si ton exécuteur prend en charge saveinstance(). Ce format peut contenir davantage de données que notre JSON.",
    })
    local nativeAllowed, nativeBusy = false, false
    map:Toggle({
        Title = "Autoriser l'export natif", Value = false,
        Callback = function(value) nativeAllowed = value == true end,
    })
    map:Button({
        Title = "Sauvegarder le jeu (format natif)", Icon = "save",
        Callback = function()
            if not nativeAllowed then
                alert("Activation requise", "Active d'abord l'autorisation d'export natif.")
                return
            end
            if running or nativeBusy then
                alert("Export déjà en cours", "Termine la capture avant cette opération.")
                return
            end
            Window:Dialog({
                Title = "Export natif : confirmation",
                Width = 390,
                Content = "Cette action utilise saveinstance() de l'exécuteur. Elle peut récupérer des objets ou scripts hors des filtres de confidentialité de notre JSON.\n\n"
                    .. "Conserve le fichier en privé et vérifie son contenu. Continuer ?",
                Buttons = {
                    {Title = "Annuler", Variant = "Secondary", Callback = function() end},
                    {Title = "Sauvegarder localement", Variant = "Primary", Callback = function()
                        nativeBusy = true
                        task.spawn(function()
                            local ok, supported, value = pcall(Engine.savePlace)
                            nativeBusy = false
                            if destroyed then return end
                            if not ok then alert("Échec", tostring(supported))
                            elseif not supported then alert("Non disponible", tostring(value))
                            else alert("Commande terminée", "Consulte le dossier workspace de l'exécuteur.") end
                        end)
                    end},
                },
            })
        end,
    })

    settings:Paragraph({
        Title = "Interface",
        Desc = "Masquer conserve l'outil actif. Unload ferme l'interface et annule toute capture en cours.",
    })
    settings:Keybind({
        Title = "Afficher / masquer", Value = "RightShift",
        Desc = "Touche par défaut : Maj droite.",
        Blacklist = {"Unknown", "Escape"},
        Callback = function(value)
            if destroyed then return end
            local key = Enum.KeyCode[value]
            if key and key ~= Enum.KeyCode.Unknown then
                Window:SetToggleKey(key)
            end
        end,
    })
    settings:Button({
        Title = "Masquer la fenêtre", Icon = "eye-off",
        Desc = "Utilise le raccourci choisi pour la rouvrir.",
        Callback = function() if not destroyed then Window:Close() end end,
    })
    settings:Button({
        Title = "Unload GUI", Icon = "trash-2",
        Desc = "Ferme WindUI, nettoie ses événements et annule le scan.",
        Callback = function()
            if destroyed then return end
            Window:Dialog({
                Title = "Décharger Lesbhub Exporter ?",
                Content = "La fenêtre sera détruite. Si une capture est en cours, son annulation sera demandée ; les fichiers déjà enregistrés resteront sur le disque.",
                Buttons = {
                    {Title = "Annuler", Variant = "Secondary", Callback = function() end},
                    {Title = "Unload", Variant = "Primary", Callback = unload},
                },
            })
        end,
    })
    return Window
end

return UI
