-- Lesbhub Exporter UI - bilingual WindUI dashboard, with a detached activity window.
-- Default language is English; locale is stored in the executor's local workspace.
local UI = {}
local WINDUI_URL = "https://raw.githubusercontent.com/kyaemma/lesbhub-ui/main/dist/main.lua"
local LANGUAGE_FILE = "LesbhubExporter/language.txt"

local PRESETS = {
    max = {guiTexts = true, guiProperties = true, worldProperties = true, assets = true,
        textboxValues = true, stringValues = true,
        includeAttributes = true, includeTags = true, includeReconstructedCode = true, twoPassGui = true,
        observeGuiActions = true, observeRemotes = true, frameBudgetMs = 6, runtimeWindowSeconds = 6,
        guiPasses = 4, secondPassDelay = 7, continuousInterval = 3,
        yieldEvery = 45, chunkSize = 200},
    smart = {guiTexts = true, guiProperties = true, worldProperties = true, assets = true,
        textboxValues = true, stringValues = true,
        includeAttributes = true, includeTags = true, includeReconstructedCode = true, twoPassGui = true,
        observeGuiActions = true, observeRemotes = true, frameBudgetMs = 6, runtimeWindowSeconds = 6,
        guiPasses = 3, secondPassDelay = 6, continuousInterval = 4,
        yieldEvery = 80, chunkSize = 300},
    fast = {guiTexts = true, guiProperties = false, worldProperties = false, assets = true,
        textboxValues = true, stringValues = true,
        includeAttributes = true, includeTags = true, includeReconstructedCode = true, twoPassGui = true,
        observeGuiActions = true, observeRemotes = true, frameBudgetMs = 6, runtimeWindowSeconds = 6,
        guiPasses = 2, secondPassDelay = 3, continuousInterval = 6,
        yieldEvery = 140, chunkSize = 500},
}

-- All visible strings are routed through this dictionary. Names of Roblox
-- services, export fields and file paths are deliberately never translated.
local WORDS = {
    deep_code = {"Include reconstructed client script code", "Inclure le code reconstruit des scripts clients"},
    deep_code_desc = {"Enabled by default: writes verified .luau files and a script index; disable for metadata-only exports.",
        "Activé par défaut : écrit les fichiers .luau et un index ; désactivable pour exporter seulement les métadonnées."},
    deep_code_notice = {"Reconstructed client scripts (.luau) will be saved locally if supported. They may differ from original sources.",
        "Les scripts clients reconstruits (.luau) seront enregistrés localement si disponibles. Ils peuvent différer des sources originales."},
    deep_result = {"Reconstructed scripts: %d saved, %d partial, %d failed/inaccessible/empty. Index: %s",
        "Scripts reconstruits : %d sauvés, %d partiels, %d échoués/inaccessibles/vides. Index : %s"},
    copy_report = {"Copy latest export report", "Copier le dernier rapport d'export"},
    search_index = {"Search latest scripts / remotes / GUI", "Rechercher dans les scripts / remotes / GUI"},
    search_index_desc = {"Type a name or path; matches are written to the activity journal.",
        "Saisir un nom ou chemin ; les résultats apparaissent dans le journal."},
    search_button = {"Search indexes", "Rechercher dans les index"},
    search_sources = {"Search reconstructed source", "Rechercher dans le code reconstruit"},
    search_mode = {"Search in", "Rechercher dans"},
    search_index_mode = {"Indexes", "Index"},
    search_source_mode = {"Source code", "Code source"},
    search_more = {"Next results", "Résultats suivants"},
    search_page = {"Page %d (up to %d matches)", "Page %d (jusqu’à %d résultats)"},
    frame_budget = {"Frame budget (milliseconds)", "Budget par frame (millisecondes)"},
    runtime_window = {"Passive runtime observation (seconds)", "Observation passive du runtime (secondes)"},
    report_layers = {"GUI: %s  •  Relations: %s  •  Remote inventory: %s  •  Calls: %s",
        "GUI : %s  •  Relations : %s  •  Inventaire remote : %s  •  Observations : %s"},
    report_layer_missing = {"unavailable", "indisponible"},
    gui_actions = {"Observe GUI activations", "Observer les activations GUI"},
    gui_actions_desc = {"Record operator button activations during capture; never clicks automatically.",
        "Enregistrer les activations de boutons pendant la capture ; aucun clic automatique."},
    remote_observation = {"Accept optional Cobalt observations", "Accepter les observations Cobalt optionnelles"},
    remote_observation_desc = {"Requires the separately enabled observer plugin. Captures types, never argument values.",
        "Nécessite le plugin d'observation activé séparément. Types uniquement, sans valeurs d'arguments."},
    home = {"Home", "Accueil"}, dataset = {"Dataset", "Données"},
    targets = {"Targets", "Cibles"}, options = {"Options", "Options"},
    capture = {"Capture", "Capture"}, map = {"Map", "Carte"},
    continuous = {"Start continuous capture", "Démarrer la capture continue"},
    continuous_desc = {"Full snapshot, then monitor new objects and GUI changes until Stop & Save.",
        "Capture initiale complète, puis surveillance des nouveaux objets et des changements GUI jusqu'à Arrêter."},
    continuous_help = {"Interact with the game while monitoring runs. Only changes are saved after the first scan.",
        "Interagis avec le jeu pendant la surveillance. Seules les modifications sont écrites après le premier scan."},
    continuous_interval = {"GUI check interval (seconds)", "Intervalle GUI (secondes)"},
    stop_save = {"Stop & Save", "Arrêter et sauvegarder"},
    stop_save_desc = {"Stops continuous monitoring and finalizes its manifest without deleting data.",
        "Arrête la surveillance et finalise le manifeste sans effacer les données."},
    stop_requested = {"Finalizing: saving remaining changes and writing the manifest...",
        "Finalisation : sauvegarde des derniers changements et écriture du manifeste..."},
    stop_unavailable = {"No continuous capture is running.", "Aucune capture continue n'est en cours."},
    continuous_consent = {"Continuous mode monitors client objects and interfaces until you stop it; local files may grow.",
        "Le mode continu surveille les objets et interfaces jusqu'à ton arrêt ; les fichiers locaux peuvent grossir."},
    stopped = {"Stopped and saved", "Arrêté et sauvegardé"},
    stopped_partial = {"Stopped and saved (partial)", "Arrêté et sauvegardé (partiel)"},
    monitor_started = {"Watching changes — explore the game at your own pace.",
        "Surveillance active — explore le jeu à ton rythme."},
    monitor_finalizing = {"Taking the final GUI snapshot", "Dernière capture GUI"},
    monitor_cycles = {"Checks", "Vérifications"},
    monitor_deltas = {"Changes saved", "Modifications enregistrées"},
    continuous_metrics = {"Inspected %s • Unique %s • Changes %s • GUI states %s • Events written %s • Occurrences %s • Queue %s",
        "Inspectés %s • Uniques %s • Modifications %s • États GUI %s • Évts écrits %s • Occurrences %s • File %s"},
    continuous_details = {"Scripts %s • Shared contents %s • Transitions %s • Unchanged writes avoided %s • Stored %s bytes • Errors %s • Lost %s",
        "Scripts %s • Contenus mutualisés %s • Transitions %s • Écritures inchangées évitées %s • Stockage %s octets • Erreurs %s • Perdus %s"},
    metric_unavailable = {"—", "—"},
    monitoring_status = {"Monitoring active", "Surveillance active"},
    action_group = {"Capture actions", "Actions de capture"},
    open_any_interface = {"Open any game menu or interact with the interface before the next snapshot (%d s).",
        "Ouvre n'importe quel menu ou interagis avec l'interface avant la prochaine capture (%d s)."},

    settings = {"Settings", "Paramètres"},
    welcome = {"Welcome to Lesbhub Exporter", "Bienvenue dans Lesbhub Exporter"},
    welcome_desc = {"Inspect the Roblox client in one guided export. Choose a preset, then start. No API upload.",
        "Analyse le client Roblox en une seule capture guidée. Choisis un preset puis lance l'export. Aucun envoi vers l'API."},
    home_status = {"Latest capture", "Dernière capture"},
    home_no_capture = {"No capture yet", "Aucune capture effectuée"},
    quick_actions = {"Quick actions", "Raccourcis"},
    full = {"Full export + GUI", "Export complet + GUI"},
    full_desc = {"Structures, GUI snapshots and reconstructed Luau scripts in one operation.",
        "Structures, captures GUI et scripts Luau reconstruits en une seule opération."},
    quick_gui = {"Capture GUI now", "Capturer la GUI maintenant"},
    quick_gui_desc = {"Take an extra snapshot after manually opening a menu.",
        "Prends une capture supplémentaire après avoir ouvert un menu."},
    quick_map = {"Export map", "Exporter la carte"},
    journal = {"Activity log", "Journal d'activité"},
    open_journal = {"Open activity window", "Ouvrir la fenêtre du journal"},
    open_journal_desc = {"The log floats independently of the selected tab.", "Le journal flotte indépendamment de l'onglet sélectionné."},
    choose_targets = {"Choose targets", "Choisir les cibles"},
    choose_options = {"Export options", "Options d'export"},
    dataset_intro = {"Dataset information", "Informations du dataset"},
    dataset_desc = {"Labels help organize local captures. They are not game signatures.",
        "Ces libellés servent à classer les captures locales, pas à reconnaître le jeu."},
    game = {"Game label", "Nom du jeu"},
    category = {"Category", "Catégorie"},
    variant = {"Variant", "Variante"},
    format = {"Format", "Format"},
    output_layout = {"File organization", "Organisation des fichiers"},
    layout_categorized = {"Categorized folders", "Dossiers classés par type"},
    layout_flat = {"Flat (legacy)", "À plat (ancien format)"},
    layout_desc = {"Groups metadata by type and service. Reconstructed code is included by default.",
        "Classe les métadonnées par type et service. Le code reconstruit est inclus par défaut."},
    target_intro = {"Roblox services", "Services Roblox"},
    target_desc = {"All available targets are selected by default. Search and select several in one menu.",
        "Toutes les cibles sont sélectionnées par défaut. Recherche et sélectionne plusieurs services dans un seul menu."},
    target_count = {"%d / %d services selected", "%d / %d services sélectionnés"},
    target_all_desc = {"All selected", "Tout est sélectionné"},
    target_none_desc = {"No target selected", "Aucune cible sélectionnée"},
    target_custom_desc = {"Custom selection", "Sélection personnalisée"},
    multiselect = {"Select multiple", "Sélection multiple"},
    multiselect_desc = {"Search, check and uncheck services.", "Recherche, coche et décoche les services."},
    select_all = {"Select all", "Tout sélectionner"},
    only_gui = {"GUI only", "GUI uniquement"},
    only_structure = {"Game structure", "Structure du jeu"},
    options_intro = {"Export presets", "Préréglages d'export"},
    options_desc = {"All presets include GUI snapshots and text values. Advanced is optional.",
        "Tous les presets incluent les captures GUI et les textes. Advanced est facultatif."},
    preset_max = {"Max information", "Max informations"},
    preset_smart = {"Smart", "Smart"},
    preset_fast = {"Fast", "Fast"},
    preset_custom = {"Custom", "Personnalisé"},
    preset_max_desc = {"Full allowlisted information, four guided GUI passes. Detailed capture.",
        "Toutes les informations autorisées et quatre passes GUI guidées. Capture détaillée."},
    preset_smart_desc = {"Complete structures and properties with three GUI passes. Balanced.",
        "Structures et propriétés complètes, avec trois passes GUI. Équilibré."},
    preset_fast_desc = {"All objects and text, fewer visual/world properties, two GUI passes.",
        "Tous les objets et textes, moins de propriétés visuelles, deux passes GUI."},
    preset_custom_desc = {"Advanced settings have been modified.", "Les réglages avancés ont été modifiés."},
    preset_menu = {"Export preset", "Preset d'export"},
    advanced = {"Advanced", "Avancé"},
    advanced_desc = {"Detailed controls (collapsed by default)", "Réglages détaillés (fermé par défaut)"},
    gui_texts = {"GUI labels & placeholders", "Textes et placeholders GUI"},
    gui_texts_desc = {"Text on buttons, labels and placeholders.", "Textes des boutons, labels et placeholders."},
    gui_props = {"GUI presentation", "Présentation des interfaces"},
    gui_props_desc = {"Colors, sizes, visibility and layout.", "Couleurs, tailles, visibilité et disposition."},
    world_props = {"Map & object properties", "Propriétés de la carte et des objets"},
    world_props_desc = {"Geometry, transforms, materials and values.", "Géométrie, positions, matériaux et valeurs."},
    assets = {"Asset references", "Références d'assets"},
    assets_desc = {"IDs only, not downloaded media.", "Identifiants uniquement, pas de médias téléchargés."},
    attributes = {"Instance attributes", "Attributs des objets"},
    attributes_desc = {"Read client-visible GetAttributes() values.", "Récupère les valeurs GetAttributes() accessibles au client."},
    tags = {"CollectionService tags", "Tags CollectionService"},
    tags_desc = {"Read available GetTags() labels.", "Récupère les étiquettes GetTags() disponibles."},
    textbox = {"TextBox.Text", "TextBox.Text"},
    textbox_desc = {"Potential user input. Private dataset only.", "Saisies utilisateur possibles. Dataset privé uniquement."},
    stringvalue = {"StringValue.Value", "StringValue.Value"},
    stringvalue_desc = {"May include private/session values.", "Peut contenir des données privées ou de session."},
    gui_passes_enabled = {"Guided GUI snapshots", "Captures GUI guidées"},
    gui_passes_desc = {"Included automatically in Full export.", "Incluses automatiquement dans l'export complet."},
    pass_count = {"Number of GUI passes", "Nombre de passes GUI"},
    pass_wait = {"Seconds between GUI passes", "Secondes entre les passes GUI"},
    yield = {"Operations between yields", "Opérations entre les pauses"},
    chunk = {"Records per file", "Enregistrements par fichier"},
    unlimited = {"No global capture limits", "Aucune limite globale d'export"},
    unlimited_desc = {"Chunking controls file sizes only; the overall dataset is not capped.",
        "Le découpage limite les fichiers individuels, jamais le volume total exporté."},
    capture_intro = {"One-click capture", "Capture en un clic"},
    capture_desc = {"Full export includes GUI and reconstructed Luau scripts by default. Continuous monitoring is also available.",
        "L'export complet inclut les GUI et les scripts Luau reconstruits par défaut. La surveillance continue reste disponible."},
    ready = {"Ready", "Prêt"},
    ready_desc = {"The exact object total is not known before the scan.", "Le nombre final d'objets est inconnu avant le scan."},
    last_export = {"Last export", "Dernier export"},
    no_export = {"No export yet", "Aucun export pour le moment"},
    cancel = {"Cancel capture", "Annuler la capture"},
    map_intro = {"Map export", "Export de la carte"},
    map_desc = {"Save client-visible buildings, objects and positions to local JSON files.",
        "Enregistre les bâtiments, objets et positions visibles par le client en JSON local."},
    map_json = {"Export map as JSON", "Exporter la carte en JSON"},
    native_intro = {"Native Roblox place backup", "Sauvegarde native Roblox"},
    native_desc = {"Uses the executor's saveinstance(), if supported. It may also decompile scripts.",
        "Utilise saveinstance() de l'exécuteur, si disponible. Peut aussi décompiler des scripts."},
    native_allow = {"Enable native backup", "Autoriser l'export natif"},
    native_save = {"Save native place", "Sauvegarder le jeu"},
    setting_intro = {"Interface & preferences", "Interface et préférences"},
    setting_desc = {"Changing language saves it locally and reopens the interface.",
        "Changer de langue l'enregistre localement et recharge l'interface."},
    language = {"Language / Langue", "Langue / Language"},
    language_desc = {"English by default; French is optional.", "Anglais par défaut ; français facultatif."},
    keybind = {"Show / hide key", "Touche afficher / masquer"},
    keybind_desc = {"Right Shift by default.", "Maj droite par défaut."},
    hide_ui = {"Hide window", "Masquer la fenêtre"},
    hide_desc = {"Use the keybind to reopen it.", "Utilise le raccourci pour la rouvrir."},
    unload = {"Unload GUI", "Décharger la GUI"},
    unload_desc = {"Removes the window and activity log. Requests scan cancellation.",
        "Supprime l'interface et le journal. Demande l'annulation du scan."},
    title_unload = {"Unload Lesbhub Exporter?", "Décharger Lesbhub Exporter ?"},
    unload_warning = {"The interface and activity window will be removed. An ongoing scan will be cancelled; already-written files remain intact.",
        "L'interface et le journal seront supprimés. Une capture en cours sera annulée ; les fichiers déjà écrits resteront présents."},
    confirm = {"Confirm", "Confirmer"},
    confirm_export = {"Confirm export", "Confirmer l'export"},
    confirm_native = {"Confirm native backup", "Confirmer la sauvegarde native"},
    data_local = {"Files are saved on your device only.", "Les fichiers sont enregistrés uniquement sur ton appareil."},
    data_risk = {"WARNING: TextBox.Text and StringValue.Value can contain sensitive or session information.",
        "ATTENTION : TextBox.Text et StringValue.Value peuvent contenir des informations sensibles ou de session."},
    data_safer = {"Optional sensitive fields are disabled.", "Les champs sensibles facultatifs sont désactivés."},
    do_not_publish = {"Do not publish unreviewed archives on GitHub, Discord or other public services.",
        "Ne publie pas d'archives non vérifiées sur GitHub, Discord ou d'autres services publics."},
    no_upload = {"Lesbhub Exporter does not upload the archive. Start?",
        "Lesbhub Exporter n'envoie pas l'archive sur Internet. Démarrer ?"},
    native_warning = {"The executor controls this backup. It can include scripts or other data outside the privacy-filtered JSON export. Review it before sharing.",
        "L'exécuteur contrôle cette sauvegarde. Elle peut inclure des scripts ou d'autres données hors des filtres JSON. Vérifie-la avant tout partage."},
    back = {"Cancel", "Annuler"}, start = {"Start export", "Exporter"},
    native_confirm_button = {"Save locally", "Sauvegarder"},
    missing_file_api = {"Local file APIs unavailable", "API fichiers indisponibles"},
    missing_file_api_desc = {"writefile and makefolder are required for exports.", "writefile et makefolder sont nécessaires à l'export."},
    busy = {"An export is already running.", "Un export est déjà en cours."},
    empty_targets = {"Select at least one service in Targets.", "Sélectionne au moins un service dans Cibles."},
    cancelled = {"Cancellation requested. Already-written chunks will be kept.",
        "Annulation demandée. Les fichiers déjà écrits seront conservés."},
    export_started = {"Export started", "Export commencé"},
    export_failed = {"Export failed", "Échec de l'export"},
    export_done = {"Export finished", "Export terminé"},
    completed = {"Complete", "Complet"}, partial = {"Partial", "Partiel"},
    cancelled_status = {"Cancelled", "Annulé"},
    scanned = {"%s visited", "%s visités"}, written = {"%s written", "%s écrits"},
    files = {"%s files", "%s fichiers"}, asset_count = {"%s assets", "%s assets"},
    elapsed = {"%.1f s", "%.1f s"},
    brief_line = {"%s objects • %s files • %s assets • %.1f s",
        "%s objets • %s fichiers • %s assets • %.1f s"},
    stage = {"Service: %s • pass %d", "Service : %s • passe %d"},
    scanning = {"Scanning...", "Analyse en cours..."},
    waiting = {"Waiting for next GUI snapshot", "Attente de la prochaine capture GUI"},
    progress_unknown = {"Scanning • final total unknown", "Analyse • total final inconnu"},
    open_menu = {"Interact with the game's interface before the next snapshot (%d s).",
        "Interagis avec l'interface du jeu avant la prochaine capture (%d s)."},
    missing_root = {"Unavailable service: %s", "Service inaccessible : %s"},
    event_scan = {"Scanning %s (pass %d)", "Analyse %s (passe %d)"},
    event_done = {"Finished %s: %s visited", "Fin %s : %s visités"},
    event_written = {"%s files written", "%s fichiers écrits"},
    event_start = {"Started %s", "Début : %s"},
    event_error = {"Error: %s", "Erreur : %s"},
    event_end = {"Done: %s", "Terminé : %s"},
    events = {"Recent events", "Événements récents"},
    current_path = {"Current path", "Chemin actuel"},
    service_label = {"Service", "Service"},
    class_label = {"Class", "Classe"},
    visited_label = {"Visited", "Parcourus"},
    discovered_label = {"Discovered", "Découverts"},
    pending_label = {"Pending", "En attente"},
    written_label = {"Written", "Écrits"},
    copied = {"Log copied", "Journal copié"},
    copy = {"Copy log", "Copier le journal"},
    close = {"Close", "Fermer"},
    journal_idle = {"Ready • no capture running", "Prêt • aucune capture en cours"},
    journal_finished = {"Finished • results saved locally", "Terminé • résultats enregistrés localement"},
    lang_saved_failed = {"Language changed for this session, but could not be saved (writefile unavailable).",
        "Langue modifiée pour cette session, mais sauvegarde impossible (writefile indisponible)."},
    lang_busy = {"Finish or cancel the capture before changing language.",
        "Termine ou annule la capture avant de changer la langue."},
    native_enable = {"Enable native export first.", "Active d'abord l'export natif."},
    native_busy = {"Wait for the current export to finish.", "Attends la fin de l'export en cours."},
    native_unavailable = {"Native export unavailable", "Export natif indisponible"},
    native_finished = {"Check the executor's workspace for its output.", "Consulte le dossier workspace de l'exécuteur."},
}

local function chooseLanguage(saved)
    if saved == "en" or saved == "fr" then return saved end
    if type(readfile) == "function" then
        local ok, result = pcall(readfile, LANGUAGE_FILE)
        if ok and (result == "en" or result == "fr") then return result end
    end
    return "en"
end

local function saveLanguage(lang)
    if type(writefile) ~= "function" then return false end
    if type(makefolder) == "function" then
        local present = false
        if type(isfolder) == "function" then
            local ok, exists = pcall(isfolder, "LesbhubExporter")
            present = ok and exists == true
        end
        if not present then pcall(makefolder, "LesbhubExporter") end
    end
    return pcall(writefile, LANGUAGE_FILE, lang)
end

local function optionName(value)
    return type(value) == "table" and tostring(value.Title or value.Value or "") or tostring(value)
end
local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = clone(v) end
    return result
end
local function shortCount(value)
    local n = math.max(0, tonumber(value) or 0)
    if n >= 1000000 then return string.format("%.2fM", n / 1000000) end
    if n >= 1000 then return string.format("%.1fK", n / 1000) end
    return tostring(math.floor(n))
end

local function shorten(value, length)
    local s = tostring(value or "")
    return #s <= length and s or ("..." .. s:sub(-(length - 3)))
end

-- Detached non-modal journal. It is parented to the same ScreenGui as WindUI,
-- not to any individual tab. It can stay visible while the main window is hidden.
local function makeJournal(windui, t, alert)
    local noop = function() end
    if type(Instance) ~= "table" or type(Instance.new) ~= "function" or not windui.ScreenGui then
        return {show = noop, hide = noop, destroy = noop, setText = noop,
            setStats = noop, setActive = noop, isVisible = function() return false end}
    end
    local connections = {}
    local function on(signal, callback)
        local con = signal:Connect(callback)
        connections[#connections + 1] = con
    end
    local function make(class, props, parent)
        local obj = Instance.new(class)
        for key, val in pairs(props or {}) do obj[key] = val end
        obj.Parent = parent
        return obj
    end
    local function round(parent, radius)
        make("UICorner", {CornerRadius = UDim.new(0, radius)}, parent)
    end
    local panel = make("Frame", {
        Name = "LesbhubExporterActivity", Size = UDim2.fromOffset(536, 376),
        Position = UDim2.new(1, -28, 0, 108), AnchorPoint = Vector2.new(1, 0),
        BackgroundColor3 = Color3.fromRGB(27, 27, 30), BackgroundTransparency = 0,
        BorderSizePixel = 0, ZIndex = 9000, Visible = false,
    }, windui.ScreenGui)
    round(panel, 17)
    make("UIStroke", {Color = Color3.fromRGB(77, 77, 82), Transparency = 0.35, Thickness = 1}, panel)
    local header = make("Frame", {
        Name = "DragHeader", Size = UDim2.new(1, 0, 0, 52),
        BackgroundColor3 = Color3.fromRGB(19, 19, 22), BorderSizePixel = 0,
        ZIndex = 9001, Active = true,
    }, panel)
    round(header, 17)
    make("TextLabel", {
        Name = "HeaderTitle", Position = UDim2.fromOffset(17, 11),
        Size = UDim2.new(1, -104, 0, 30), Text = t("journal"), TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold, TextSize = 17,
        BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(241, 241, 245),
        ZIndex = 9002,
    }, header)
    local close = make("TextButton", {
        Name = "CloseJournal", Text = "×", Font = Enum.Font.GothamBold, TextSize = 25,
        Position = UDim2.new(1, -45, 0, 10), Size = UDim2.fromOffset(34, 32),
        BackgroundColor3 = Color3.fromRGB(51, 51, 55), TextColor3 = Color3.fromRGB(238, 238, 241),
        BorderSizePixel = 0, ZIndex = 9003,
    }, header)
    round(close, 9)
    local stats = make("TextLabel", {
        Name = "Counters", Position = UDim2.fromOffset(17, 65),
        Size = UDim2.new(1, -34, 0, 42), Text = t("journal_idle"),
        TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true,
        Font = Enum.Font.Gotham, TextSize = 14,
        BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(218, 218, 223),
        ZIndex = 9002,
    }, panel)
    local track = make("Frame", {
        Name = "ActivityTrack", Size = UDim2.new(1, -34, 0, 4),
        Position = UDim2.fromOffset(17, 113), BorderSizePixel = 0,
        BackgroundColor3 = Color3.fromRGB(57, 57, 61),
        ClipsDescendants = true, ZIndex = 9002,
    }, panel)
    round(track, 3)
    local fill = make("Frame", {
        Name = "ActivityFill", Size = UDim2.new(0.25, 0, 1, 0),
        Position = UDim2.new(-0.25, 0, 0, 0),
        BackgroundColor3 = Color3.fromRGB(83, 156, 251),
        BorderSizePixel = 0, ZIndex = 9003, Visible = false,
    }, track)
    round(fill, 3)
    local scrolling = make("ScrollingFrame", {
        Name = "LogScroll", Position = UDim2.fromOffset(17, 132),
        Size = UDim2.new(1, -34, 1, -194), BackgroundColor3 = Color3.fromRGB(36, 36, 40),
        BorderSizePixel = 0, ScrollBarThickness = 4,
        AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.fromOffset(0, 0),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 9002,
    }, panel)
    round(scrolling, 9)
    make("UIPadding", {
        PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12),
        PaddingTop = UDim.new(0, 9), PaddingBottom = UDim.new(0, 9),
    }, scrolling)
    local text = make("TextLabel", {
        Name = "LogText", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1, Text = t("journal_idle"),
        Font = Enum.Font.Code, TextSize = 14, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
        TextColor3 = Color3.fromRGB(211, 219, 236),
        ZIndex = 9003,
    }, scrolling)
    local footer = make("Frame", {
        Name = "Footer", Position = UDim2.new(0, 17, 1, -49),
        Size = UDim2.new(1, -34, 0, 37), BackgroundTransparency = 1, ZIndex = 9002,
    }, panel)
    local copyButton = make("TextButton", {
        Name = "CopyJournal", Text = t("copy"), Size = UDim2.fromOffset(136, 36),
        BackgroundColor3 = Color3.fromRGB(61, 61, 67), TextColor3 = Color3.fromRGB(247, 247, 250),
        Font = Enum.Font.GothamMedium, TextSize = 14, BorderSizePixel = 0, ZIndex = 9003,
    }, footer)
    round(copyButton, 9)
    local dismiss = make("TextButton", {
        Name = "HideJournal", Text = t("close"), Size = UDim2.fromOffset(100, 36),
        Position = UDim2.new(1, -100, 0, 0),
        BackgroundColor3 = Color3.fromRGB(61, 61, 67), TextColor3 = Color3.fromRGB(247, 247, 250),
        Font = Enum.Font.GothamMedium, TextSize = 14, BorderSizePixel = 0, ZIndex = 9003,
    }, footer)
    round(dismiss, 9)

    local rawLog = t("journal_idle")
    local anim = nil
    local function animate(active)
        if anim then anim:Cancel(); anim = nil end
        fill.Visible = active == true
        fill.Position = UDim2.new(-0.25, 0, 0, 0)
        if active then
            local ts = game:GetService("TweenService")
            anim = ts:Create(fill, TweenInfo.new(1.5, Enum.EasingStyle.Linear,
                Enum.EasingDirection.InOut, -1, false),
                {Position = UDim2.new(1, 0, 0, 0)})
            anim:Play()
        end
    end
    on(close.MouseButton1Click, function() panel.Visible = false end)
    on(dismiss.MouseButton1Click, function() panel.Visible = false end)
    on(copyButton.MouseButton1Click, function()
        local clipboard = setclipboard or toclipboard
        if type(clipboard) == "function" then
            local ok = pcall(clipboard, rawLog)
            if ok then alert(t("copied"), t("copied")) end
        end
    end)

    local uis = game:GetService("UserInputService")
    local dragging = false
    local startPointer, startPosition
    on(header.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            startPointer = input.Position
            startPosition = panel.Position
        end
    end)
    on(uis.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
    end)
    on(uis.InputChanged, function(input)
        if not dragging then return end
        if input.UserInputType ~= Enum.UserInputType.MouseMovement
            and input.UserInputType ~= Enum.UserInputType.Touch then return end
        local delta = input.Position - startPointer
        panel.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
    end)

    return {
        show = function() panel.Visible = true end,
        hide = function() panel.Visible = false end,
        isVisible = function() return panel.Visible end,
        setText = function(value)
            rawLog = tostring(value)
            text.Text = rawLog
            scrolling.CanvasPosition = Vector2.new(0, math.max(0, text.AbsoluteSize.Y - scrolling.AbsoluteSize.Y))
        end,
        setStats = function(value) stats.Text = tostring(value) end,
        setActive = animate,
        destroy = function()
            animate(false)
            for _, connection in ipairs(connections) do pcall(function() connection:Disconnect() end) end
            panel:Destroy()
        end,
    }
end

function UI.open(Engine, restore)
    restore = type(restore) == "table" and restore or {}
    local shared = (type(getgenv) == "function" and getgenv()) or _G
    local existing = shared.LesbhubExporterHandle
    if type(existing) == "table" and not existing.destroyed
        and existing.window and not existing.window.Destroyed then
        pcall(function() existing.window:Open() end)
        return existing.window
    end

    local language = chooseLanguage(restore.language)
    local function t(key)
        local entry = WORDS[key]
        return entry and entry[language == "fr" and 2 or 1] or key
    end
    local function tf(key, ...)
        return string.format(t(key), ...)
    end
    local function continuousMetrics(source, fallbackStats, occurrenceStats)
        source = type(source) == "table" and source or {}
        fallbackStats = type(fallbackStats) == "table" and fallbackStats or {}
        occurrenceStats = type(occurrenceStats) == "table" and occurrenceStats or {}
        local function pick(...)
            for index = 1, select("#", ...) do
                local key = select(index, ...)
                local value = source[key]
                if value == nil then value = fallbackStats[key] end
                if value == nil then value = occurrenceStats[key] end
                if value ~= nil then return shortCount(value) end
            end
            return t("metric_unavailable")
        end
        return tf("continuous_metrics",
            pick("inspected", "inspectedInstances"),
            pick("uniqueInstances", "unique", "uniqueDiscovered"),
            pick("structuralChanges", "changes"),
            pick("guiStates", "uniqueGuiStates", "stateCount"),
            pick("eventsWritten", "writes"),
            pick("occurrences", "remoteOccurrences", "observedCalls", "events"),
            pick("queuedEvents", "queueDepth", "pending", "pendingEvents"))
    end
    local function continuousDetails(source)
        source = type(source) == "table" and source or {}
        local function metric(key)
            return type(source[key]) == "number" and shortCount(source[key]) or t("metric_unavailable")
        end
        return tf("continuous_details", metric("scriptsReconstructed"), metric("scriptSharedReferences"),
            metric("guiTransitions"), metric("unchangedRecords"), metric("storedBytes"), metric("errors"), metric("lostEvents"))
    end

    local loaded, windui = pcall(function()
        local source = game:HttpGet(WINDUI_URL)
        return assert(loadstring(source), "Lesbhub WindUI failed to compile")()
    end)
    if not loaded or type(windui) ~= "table" then
        error("Could not load Lesbhub WindUI fork: " .. tostring(windui), 0)
    end

    local config = clone(restore.config or PRESETS.max)
    if not restore.config then
        config.label, config.category, config.variant = "Unlabeled", "Other", "Default"
        config.format = "json"
        config.organizedOutput = true
        config.targets = {}
        for _, service in ipairs(Engine.TARGETS) do config.targets[service] = true end
    end
    if config.organizedOutput == nil then config.organizedOutput = true end
    if config.includeAttributes == nil then config.includeAttributes = true end
    if config.includeTags == nil then config.includeTags = true end
    if config.includeReconstructedCode == nil then config.includeReconstructedCode = true end
    if config.observeGuiActions == nil then config.observeGuiActions = true end
    if config.observeRemotes == nil then config.observeRemotes = true end
    if config.frameBudgetMs == nil then config.frameBudgetMs = 6 end
    if config.runtimeWindowSeconds == nil then config.runtimeWindowSeconds = 6 end
    local presetKey = restore.preset or "max"
    local running, control, destroyed, nativeBusy = false, nil, false, false
    local runningMode = nil
    local latestFolder, searchQuery = nil, ""

    local Window = windui:CreateWindow({
        Title = "Lesbhub Exporter", Folder = "lesbhub-exporter", Icon = "database",
        NewElements = true, HideSearchBar = true,
        -- The exporter does not need a Roblox profile/thumbnail.
        -- Avoid the optional user widget reading LocalPlayer during startup.
        User = {Enabled = false, Anonymous = true},
        OpenButton = {Enabled = true, Title = "Lesbhub Exporter"},
    })
    local function alert(title, message)
        if destroyed then return end
        local ok = pcall(function()
            windui:Notify({Title = title, Content = tostring(message), Duration = 5})
        end)
        if not ok then warn("[Lesbhub Exporter] " .. tostring(title) .. ": " .. tostring(message)) end
    end

    local journal = makeJournal(windui, t, alert)
    local function release()
        if destroyed then return end
        destroyed = true
        if control then control.cancelled = true end
        journal.destroy()
        local h = shared.LesbhubExporterHandle
        if h and h.window == Window then h.destroyed = true; shared.LesbhubExporterHandle = nil end
    end
    local function unload()
        release()
        pcall(function() Window:Destroy() end)
    end
    shared.LesbhubExporterHandle = {window = Window, Unload = unload, destroyed = false}
    Window:OnDestroy(release)

    local home = Window:Tab({Title = t("home"), Icon = "house"})
    local dataset = Window:Tab({Title = t("dataset"), Icon = "folder"})
    local targets = Window:Tab({Title = t("targets"), Icon = "layers"})
    local options = Window:Tab({Title = t("options"), Icon = "settings"})
    local capture = Window:Tab({Title = t("capture"), Icon = "scan"})
    local map = Window:Tab({Title = t("map"), Icon = "map"})
    local settings = Window:Tab({Title = t("settings"), Icon = "keyboard"})

    local homeSummary, captureSummary
    local confirmCapture
    home:Paragraph({Title = t("welcome"), Desc = t("welcome_desc")})
    homeSummary = home:Paragraph({Title = t("home_status"), Desc = t("home_no_capture")})
    home:Section({Title = t("quick_actions")})
    home:Button({Title = t("full"), Icon = "download",
        Color = Color3.fromRGB(48, 109, 204), Size = "Large",
        Justify = "Center", IconAlign = "Left",
        Callback = function() if confirmCapture then confirmCapture("full") end end})
    home:Button({Title = t("continuous"), Icon = "radio-tower",
        Color = Color3.fromRGB(33, 129, 103), Size = "Large",
        Justify = "Center", IconAlign = "Left",
        Callback = function() if confirmCapture then confirmCapture("continuous") end end})
    home:Button({Title = t("quick_gui"), Icon = "monitor",
        Callback = function() if confirmCapture then confirmCapture("gui") end end})
    home:Button({Title = t("quick_map"), Icon = "map",
        Callback = function() if confirmCapture then confirmCapture("map") end end})
    home:Button({Title = t("open_journal"), Icon = "scroll-text",
        Callback = journal.show})
    home:Button({Title = t("choose_targets"), Icon = "layers",
        Callback = function() targets:Select() end})
    home:Button({Title = t("choose_options"), Icon = "settings",
        Callback = function() options:Select() end})

    dataset:Paragraph({Title = t("dataset_intro"), Desc = t("dataset_desc")})
    dataset:Input({Title = t("game"), Value = config.label, Placeholder = "My Roblox Experience",
        Callback = function(value) config.label = tostring(value) end})
    dataset:Input({Title = t("category"), Value = config.category, Placeholder = "Adventure / Obby / Other",
        Callback = function(value) config.category = tostring(value) end})
    dataset:Input({Title = t("variant"), Value = config.variant, Placeholder = "Variant A / Original",
        Callback = function(value) config.variant = tostring(value) end})
    dataset:Dropdown({
        Title = t("format"), Values = {"JSON", "JSONL", "CSV"},
        Value = string.upper(config.format or "json"),
        Callback = function(value)
            local name = optionName(value):lower()
            if name == "json" or name == "jsonl" or name == "csv" then config.format = name end
        end,
    })
    dataset:Dropdown({
        Title = t("output_layout"), Desc = t("layout_desc"),
        Values = {t("layout_categorized"), t("layout_flat")},
        Value = config.organizedOutput ~= false and t("layout_categorized") or t("layout_flat"),
        Callback = function(value)
            config.organizedOutput = optionName(value) ~= t("layout_flat")
        end,
    })

    targets:Paragraph({Title = t("target_intro"), Desc = t("target_desc")})
    local selectedServices = {}
    for _, service in ipairs(Engine.TARGETS) do
        if config.targets[service] then selectedServices[#selectedServices + 1] = service end
    end
    local targetsStatus = targets:Paragraph({
        Title = tf("target_count", #selectedServices, #Engine.TARGETS),
        Desc = #selectedServices == #Engine.TARGETS and t("target_all_desc") or t("target_custom_desc"),
    })
    local targetPicker
    local function changeTargets(items)
        local valid = {}
        for _, service in ipairs(Engine.TARGETS) do valid[service] = true end
        local names, chosen = {}, {}
        for _, item in ipairs(type(items) == "table" and items or {}) do
            local name = optionName(item)
            if valid[name] and not chosen[name] then
                names[#names + 1] = name
                chosen[name] = true
            end
        end
        config.targets = chosen
        pcall(function()
            targetsStatus:SetTitle(tf("target_count", #names, #Engine.TARGETS))
            targetsStatus:SetDesc(#names == #Engine.TARGETS and t("target_all_desc")
                or (#names == 0 and t("target_none_desc") or t("target_custom_desc")))
        end)
    end
    targetPicker = targets:Dropdown({
        Title = t("multiselect"), Desc = t("multiselect_desc"),
        Values = clone(Engine.TARGETS), Value = selectedServices,
        Multi = true, AllowNone = true, SearchBarEnabled = true,
        MenuWidth = 240, Callback = changeTargets,
    })
    local function setTargets(list)
        changeTargets(list)
        if targetPicker and targetPicker.Select then
            pcall(function() targetPicker:Select(clone(list)) end)
        end
    end
    targets:Button({Title = t("select_all"), Icon = "check-check",
        Callback = function() setTargets(clone(Engine.TARGETS)) end})
    targets:Button({Title = t("only_gui"), Icon = "monitor",
        Callback = function() setTargets({"PlayerGui", "StarterGui"}) end})
    targets:Button({Title = t("only_structure"), Icon = "boxes",
        Callback = function() setTargets({
            "ReplicatedStorage", "ReplicatedFirst", "StarterPlayer", "PlayerScripts", "StarterPack",
        }) end})

    local function presetName(key)
        return t("preset_" .. key)
    end
    options:Paragraph({Title = t("options_intro"), Desc = t("options_desc")})
    local presetStatus = options:Paragraph({
        Title = presetName(presetKey),
        Desc = t("preset_" .. presetKey .. "_desc"),
    })
    local controls, changingPreset = {}, false
    local applyPreset
    options:Dropdown({
        Title = t("preset_menu"),
        Values = {presetName("max"), presetName("smart"), presetName("fast")},
        Value = PRESETS[presetKey] and presetName(presetKey) or presetName("max"),
        Callback = function(value)
            local selection = optionName(value)
            for _, key in ipairs({"max", "smart", "fast"}) do
                if presetName(key) == selection and applyPreset then applyPreset(key) end
            end
        end,
    })
    local advanced = options:Section({
        Title = t("advanced"), Desc = t("advanced_desc"),
        Box = true, Opened = false,
    })
    local function markCustom()
        if changingPreset then return end
        presetKey = "custom"
        pcall(function()
            presetStatus:SetTitle(presetName("custom"))
            presetStatus:SetDesc(t("preset_custom_desc"))
        end)
    end
    local function addToggle(key, titleKey, descKey)
        controls[key] = advanced:Toggle({
            Title = t(titleKey), Desc = t(descKey), Value = config[key],
            Callback = function(value) config[key] = value == true; markCustom() end,
        })
    end
    local function addSlider(key, titleKey, min, max, step)
        controls[key] = advanced:Slider({
            Title = t(titleKey), Step = step,
            Value = {Min = min, Max = max, Default = config[key]},
            Callback = function(value)
                config[key] = math.floor(tonumber(value) or config[key])
                markCustom()
            end,
        })
    end
    addToggle("guiTexts", "gui_texts", "gui_texts_desc")
    addToggle("guiProperties", "gui_props", "gui_props_desc")
    addToggle("worldProperties", "world_props", "world_props_desc")
    addToggle("assets", "assets", "assets_desc")
    addToggle("includeAttributes", "attributes", "attributes_desc")
    addToggle("includeTags", "tags", "tags_desc")
    addToggle("includeReconstructedCode", "deep_code", "deep_code_desc")
    addToggle("observeGuiActions", "gui_actions", "gui_actions_desc")
    addToggle("observeRemotes", "remote_observation", "remote_observation_desc")
    addSlider("frameBudgetMs", "frame_budget", 1, 12, 1)
    addSlider("runtimeWindowSeconds", "runtime_window", 1, 20, 1)
    addToggle("textboxValues", "textbox", "textbox_desc")
    addToggle("stringValues", "stringvalue", "stringvalue_desc")
    addToggle("twoPassGui", "gui_passes_enabled", "gui_passes_desc")
    addSlider("guiPasses", "pass_count", 2, 8, 1)
    addSlider("secondPassDelay", "pass_wait", 2, 25, 1)
    addSlider("continuousInterval", "continuous_interval", 1, 20, 1)
    addSlider("yieldEvery", "yield", 10, 250, 10)
    addSlider("chunkSize", "chunk", 25, 800, 25)
    advanced:Paragraph({Title = t("unlimited"), Desc = t("unlimited_desc")})
    applyPreset = function(key)
        local selected = PRESETS[key]
        if not selected then return end
        changingPreset = true
        for name, val in pairs(selected) do
            config[name] = val
            local widget = controls[name]
            if widget and widget.Set then pcall(function() widget:Set(val, false) end) end
        end
        changingPreset = false
        presetKey = key
        pcall(function()
            presetStatus:SetTitle(presetName(key))
            presetStatus:SetDesc(t("preset_" .. key .. "_desc"))
        end)
    end

    capture:Paragraph({Title = t("capture_intro"), Desc = t("capture_desc")})
    capture:Paragraph({Title = t("action_group"), Desc = t("continuous_help")})
    local captureStatus = capture:Paragraph({Title = t("ready"), Desc = t("ready_desc")})
    captureSummary = capture:Paragraph({Title = t("last_export"), Desc = t("no_export")})
    local searchMode, searchOffset = "index", 0
    local function runSearch(reset)
        if not latestFolder or running then return end
        if reset then searchOffset = 0 else searchOffset = searchOffset + 50 end
        local matches, reason = Engine.search(latestFolder, searchQuery, {
            mode = searchMode, offset = searchOffset, limit = 50,
        })
        local lines = {tf("search_page", math.floor(searchOffset / 50) + 1, 50), reason or ""}
        for _, row in ipairs(matches or {}) do
            lines[#lines + 1] = row.kind .. " | " .. row.robloxPath .. " | " .. (row.outputPath or row.status or "")
                .. (row.line and (":"..tostring(row.line))or "")
            if row.preview then lines[#lines+1]=row.preview end
        end
        journal.setText(table.concat(lines, "\n")); journal.show()
    end
    capture:Input({Title = t("search_index"), Desc = t("search_index_desc"), Value = "",
        Callback = function(value) searchQuery = tostring(value); searchOffset = 0 end})
    capture:Dropdown({Title = t("search_mode"), Values = {t("search_index_mode"), t("search_source_mode")},
        Value = t("search_index_mode"), Callback = function(value)
            searchMode = optionName(value) == t("search_source_mode") and "sources" or "index"
            searchOffset = 0
        end})
    capture:Button({Title = t("search_button"), Icon = "search", Callback = function() runSearch(true) end})
    capture:Button({Title = t("search_more"), Icon = "arrow-down", Callback = function() runSearch(false) end})
    capture:Button({Title = t("copy_report"), Icon = "copy", Callback = function()
        if not latestFolder or type(readfile) ~= "function" then return end
        local ok, text = pcall(readfile, latestFolder .. "/report.md")
        if ok and type(setclipboard) == "function" then pcall(setclipboard, text) end
    end})
    capture:Button({
        Title = t("full"), Icon = "download",
        Color = Color3.fromRGB(48, 109, 204), Size = "Large",
        Justify = "Center", IconAlign = "Left",
        Callback = function() if confirmCapture then confirmCapture("full") end end,
    })
    capture:Button({
        Title = t("continuous"), Icon = "radio-tower",
        Color = Color3.fromRGB(33, 129, 103), Size = "Large",
        Justify = "Center", IconAlign = "Left",
        Callback = function() if confirmCapture then confirmCapture("continuous") end end,
    })
    capture:Button({
        Title = t("stop_save"), Desc = t("stop_save_desc"), Icon = "save",
        Color = Color3.fromRGB(179, 117, 34), Size = "Large",
        Justify = "Center", IconAlign = "Left",
        Callback = function()
            if running and runningMode == "continuous" and control then
                control.stopRequested = true
                alert(t("stop_save"), t("stop_requested"))
            else
                alert(t("stop_save"), t("stop_unavailable"))
            end
        end,
    })
    capture:Button({Title = t("quick_gui"), Icon = "monitor",
        Color = Color3.fromRGB(61, 67, 76),
        Callback = function() if confirmCapture then confirmCapture("gui") end end})
    capture:Button({Title = t("open_journal"), Desc = t("open_journal_desc"),
        Icon = "scroll-text", Color = Color3.fromRGB(61, 67, 76), Callback = journal.show})
    capture:Button({Title = t("cancel"), Icon = "square",
        Color = Color3.fromRGB(119, 48, 53),
        Callback = function()
            if running and control then control.cancelled = true; alert(t("cancel"), t("cancelled")) end
        end})

    map:Paragraph({Title = t("map_intro"), Desc = t("map_desc")})
    map:Button({Title = t("map_json"), Icon = "map",
        Callback = function() if confirmCapture then confirmCapture("map") end end})
    map:Button({Title = t("open_journal"), Icon = "scroll-text", Callback = journal.show})
    map:Paragraph({Title = t("native_intro"), Desc = t("native_desc")})
    local nativeAllowed = false
    map:Toggle({Title = t("native_allow"), Value = false,
        Callback = function(value) nativeAllowed = value == true end})
    map:Button({Title = t("native_save"), Icon = "save",
        Callback = function()
            if not nativeAllowed then alert(t("native_intro"), t("native_enable")); return end
            if running or nativeBusy then alert(t("native_intro"), t("native_busy")); return end
            Window:Dialog({
                Title = t("confirm_native"), Width = 390,
                Content = t("native_warning") .. "\n\n" .. t("do_not_publish"),
                Buttons = {
                    {Title = t("back"), Variant = "Secondary", Callback = function() end},
                    {Title = t("native_confirm_button"), Variant = "Primary", Callback = function()
                        nativeBusy = true
                        task.spawn(function()
                            local ok, supported, result = pcall(Engine.savePlace)
                            nativeBusy = false
                            if destroyed then return end
                            if not ok then alert(t("export_failed"), tostring(supported))
                            elseif not supported then alert(t("native_unavailable"), tostring(result))
                            else alert(t("native_intro"), t("native_finished")) end
                        end)
                    end},
                },
            })
        end})

    settings:Paragraph({Title = t("setting_intro"), Desc = t("setting_desc")})
    local shortcutWidget
    settings:Dropdown({
        Title = t("language"), Desc = t("language_desc"),
        Values = {"English", "Français"},
        Value = language == "fr" and "Français" or "English",
        Callback = function(value)
            local nextLang = optionName(value) == "Français" and "fr" or "en"
            if running or nativeBusy then alert(t("language"), t("lang_busy")); return end
            if nextLang == language then return end
            local saved = saveLanguage(nextLang)
            if not saved then alert(t("language"), t("lang_saved_failed")) end
            local preserved = {
                language = nextLang, config = clone(config), preset = presetKey,
                shortcut = shortcutWidget and shortcutWidget.Value or "RightShift",
            }
            release()
            pcall(function() Window:Destroy() end)
            task.spawn(function()
                task.wait(0.55) -- wait for WindUI's asynchronous destroy
                UI.open(Engine, preserved)
            end)
        end,
    })
    shortcutWidget = settings:Keybind({
        Title = t("keybind"), Value = restore.shortcut or "RightShift",
        Desc = t("keybind_desc"), Blacklist = {"Unknown", "Escape"},
        Callback = function()
            if not destroyed and not Window.Destroyed then Window:Toggle() end
        end,
    })
    settings:Button({Title = t("hide_ui"), Desc = t("hide_desc"), Icon = "eye-off",
        Callback = function() if not destroyed then Window:Close() end end})
    settings:Button({Title = t("open_journal"), Icon = "scroll-text", Callback = journal.show})
    settings:Button({
        Title = t("unload"), Desc = t("unload_desc"), Icon = "trash-2",
        Callback = function()
            Window:Dialog({
                Title = t("title_unload"), Content = t("unload_warning"), Width = 390,
                Buttons = {
                    {Title = t("back"), Variant = "Secondary", Callback = function() end},
                    {Title = t("unload"), Variant = "Primary", Callback = function()
                        release()
                        pcall(function() Window:Destroy() end)
                    end},
                },
            })
        end,
    })

    local function startCapture(mode)
        if destroyed then return end
        if running or nativeBusy then alert(t("capture"), t("busy")); return end
        if type(writefile) ~= "function" or type(makefolder) ~= "function" then
            alert(t("missing_file_api"), t("missing_file_api_desc"))
            return
        end
        local runConfig = clone(config)
        if mode == "gui" then
            runConfig.targets = {PlayerGui = true, StarterGui = true}
            runConfig.twoPassGui = false
        elseif mode == "map" then
            runConfig.targets = {Workspace = true, Lighting = true, SoundService = true}
            runConfig.twoPassGui = false
            runConfig.variant = tostring(config.variant) .. "-map"
        elseif mode == "full" or mode == "continuous" then
            -- Both full modes always include the standard client GUI roots.
            runConfig.targets.PlayerGui = true
            runConfig.targets.StarterGui = true
            runConfig.continuous = mode == "continuous"
        end
        if not next(runConfig.targets) then alert(t("capture"), t("empty_targets")); return end

        running = true
        runningMode = mode
        control = {cancelled = false, stopRequested = false}
        local runControl = control
        local events, lastDraw = {}, -math.huge
        local stageNames = {}
        for _, name in ipairs(Engine.TARGETS) do
            if runConfig.targets[name] then stageNames[#stageNames + 1] = name end
        end
        local finishedServices = 0
        journal.show()
        journal.setActive(true)
        alert(t("export_started"), t("progress_unknown"))
        local function event(message)
            events[#events + 1] = message
            if #events > 24 then table.remove(events, 1) end
            print("[Lesbhub Exporter] " .. message)
        end
        local function draw(info, important)
            if destroyed then return end
            local now = os.clock()
            if not important and now - lastDraw < 0.22 then return end
            lastDraw = now
            local desc = tf("brief_line", shortCount(info.visited),
                shortCount(info.files), shortCount(info.assetReferences), info.elapsedSeconds or 0)
            local activeMonitoring = mode == "continuous"
                and info.monitoring == true
            local monitorSource = info.dedup or info.continuous or info
            local monitorSummary = activeMonitoring
                and ("  |  " .. t("monitor_cycles") .. ": " .. shortCount(info.monitorCycles)
                    .. "  |  " .. t("monitor_deltas") .. ": " .. shortCount(info.deltaRecords)
                    .. "\n" .. continuousMetrics(monitorSource, info.stats, info.remoteObservations))
                or ""
            pcall(function()
                captureStatus:SetTitle(activeMonitoring and t("monitoring_status")
                    or tf("stage", tostring(info.service or "-"), tonumber(info.pass) or 1))
                captureStatus:SetDesc(desc .. monitorSummary)
            end)
            journal.setStats(desc .. "  |  " .. t("pending_label") .. ": "
                .. shortCount(info.pending)
                .. (activeMonitoring and ("  |  " .. t("monitor_deltas") .. ": " .. shortCount(info.deltaRecords)) or ""))
            local textLines = {
                tf("stage", tostring(info.service or "-"), tonumber(info.pass) or 1),
                t("class_label") .. ": " .. tostring(info.currentClass or "-"),
                t("current_path") .. ": " .. shorten(info.currentPath, 110),
                t("discovered_label") .. ": " .. shortCount(info.discovered),
                t("written_label") .. ": " .. shortCount(info.written),
                mode == "continuous" and
                    (t("monitor_deltas") .. ": " .. shortCount(info.deltaRecords) .. "\n"
                        .. continuousMetrics(monitorSource, info.stats, info.remoteObservations)
                        .. "\n" .. continuousDetails(monitorSource)) or "",
                "---------------------------------------",
                t("events") .. ":",
            }
            for _, value in ipairs(events) do textLines[#textLines + 1] = value end
            journal.setText(table.concat(textLines, "\n"))
        end
        event(tf("event_start", mode == "continuous" and t("continuous")
            or mode == "full" and t("full")
            or mode == "gui" and t("quick_gui") or t("map_json")))
        task.spawn(function()
            local ok, result, err = pcall(Engine.capture, runConfig, function(info)
                if destroyed then return end
                if info.stage == "service_start" then
                    event(tf("event_scan", tostring(info.service), tonumber(info.pass) or 1))
                elseif info.stage == "service_done" then
                    if info.pass == 1 then finishedServices = finishedServices + 1 end
                    event(tf("event_done", tostring(info.service), shortCount(info.visited)))
                elseif info.stage == "file_written" then
                    if (info.files or 0) % 25 == 0 then event(tf("event_written", shortCount(info.files))) end
                elseif info.stage == "waiting_gui_pass" then
                    local message = tf("open_menu", runConfig.secondPassDelay)
                    event(message)
                    alert(t("waiting"), message)
                elseif info.stage == "monitoring_start" then
                    event(t("monitor_started"))
                    pcall(function() captureStatus:SetTitle(t("monitoring_status")) end)
                elseif info.stage == "monitoring_finalizing" then
                    event(t("monitor_finalizing"))
                elseif info.stage == "monitoring_stopped" then
                    event(t("stop_requested"))
                elseif info.stage == "missing_root" then
                    event(tf("missing_root", tostring(info.service)))
                end
                draw(info, info.stage ~= "scanning")
            end, runControl)
            running, control, runningMode = false, nil, nil
            journal.setActive(false)
            if destroyed then return end
            if not ok or not result then
                local reason = not ok and tostring(result) or tostring(err)
                event(tf("event_error", reason))
                pcall(function() captureStatus:SetTitle(t("export_failed")); captureStatus:SetDesc(reason) end)
                journal.setStats(t("export_failed") .. ": " .. reason)
                journal.setText(table.concat(events, "\n"))
                alert(t("export_failed"), reason)
            else
                local manifest = result.manifest
                latestFolder = result.folder
                local statusLabel = t(manifest.status == "complete" and "completed"
                    or manifest.status == "stopped" and
                        ((type(manifest.partialReasons) == "table" and #manifest.partialReasons > 0) and "stopped_partial" or "stopped")
                    or manifest.status == "cancelled" and "cancelled_status" or "partial")
                local summary = tf("brief_line",
                    shortCount(manifest.stats.written), shortCount(manifest.stats.files),
                    shortCount(manifest.stats.assetReferences), manifest.stats.elapsedSeconds or 0)
                if manifest.settings and manifest.settings.continuous then
                    summary = summary .. "  |  " .. t("monitor_deltas") .. ": "
                        .. shortCount(manifest.stats.deltaRecords or 0)
                    summary = summary .. "\n" .. continuousMetrics(
                        manifest.dedup or manifest.continuous,
                        manifest.stats,
                        manifest.runtime and manifest.runtime.observer)
                    summary = summary .. "\n" .. continuousDetails(manifest.dedup)
                end
                if manifest.scriptExport and manifest.scriptExport.enabled then
                    local scripts = manifest.scriptExport.stats
                    summary = summary .. "\n" .. tf("deep_result", scripts.succeeded,
                        scripts.partial, scripts.failed + scripts.inaccessible + scripts.empty,
                        result.folder .. "/scripts/index.json")
                end
                local function layerStatus(value, fallback)
                    if type(value) == "table" and type(value.status) == "string" then return value.status end
                    if type(fallback) == "table" and type(fallback.status) == "string" then return fallback.status end
                    if type(fallback) == "table" and type(fallback.state) == "string" then return fallback.state end
                    return t("report_layer_missing")
                end
                local layers = result.report and result.report.layers or manifest.report and manifest.report.layers
                local guiState = layerStatus(layers and layers.gui, manifest.guiAnalysis)
                local relationState = layerStatus(layers and layers.relations, manifest.relations)
                local inventoryState = layerStatus(layers and layers.remoteInventory, manifest.remoteInventory)
                local observerState = layerStatus(layers and layers.remoteObservations,
                    manifest.runtime and manifest.runtime.observer)
                summary = summary .. "\n" .. tf("report_layers", guiState, relationState,
                    inventoryState, observerState)
                event(tf("event_end", summary))
                if type(manifest.partialReasons) == "table" and #manifest.partialReasons > 0 then
                    event("Notes: " .. table.concat(manifest.partialReasons, ", "))
                end
                pcall(function()
                    captureStatus:SetTitle(t("export_done") .. " • " .. statusLabel)
                    captureStatus:SetDesc(summary)
                    captureSummary:SetTitle(t("last_export") .. ": " .. statusLabel)
                    captureSummary:SetDesc(result.folder .. "/manifest.json")
                    homeSummary:SetTitle(t("home_status") .. ": " .. statusLabel)
                    homeSummary:SetDesc(summary)
                end)
                journal.setStats(statusLabel .. " • " .. tf("brief_line",
                    shortCount(manifest.stats.written), shortCount(manifest.stats.files),
                    shortCount(manifest.stats.assetReferences), manifest.stats.elapsedSeconds or 0))
                journal.setText(table.concat(events, "\n") .. "\n" .. result.folder .. "/manifest.json")
                alert(t("export_done"), summary)
                print("[Lesbhub Exporter] " .. result.folder .. "/manifest.json")
            end
        end)
    end

    confirmCapture = function(mode)
        if destroyed or running then return end
        local kind = mode == "full" and t("full")
            or mode == "continuous" and t("continuous")
            or (mode == "gui" and t("quick_gui") or t("map_json"))
        Window:Dialog({
            Title = t("confirm_export") .. " • " .. kind, Width = 390,
            Content = t("data_local") .. "\n\n"
                .. ((config.textboxValues or config.stringValues) and t("data_risk") or t("data_safer"))
                .. (config.includeReconstructedCode and ("\n\n" .. t("deep_code_notice")) or "")
                .. "\n\n" .. (mode == "continuous" and (t("continuous_consent") .. "\n\n") or "")
                .. t("do_not_publish") .. "\n\n" .. t("no_upload"),
            Buttons = {
                {Title = t("back"), Variant = "Secondary", Callback = function() end},
                {Title = t("start"), Variant = "Primary", Callback = function() startCapture(mode) end},
            },
        })
    end

    task.defer(function()
        if not destroyed then pcall(function() home:Select() end) end
    end)
    return Window
end

return UI
