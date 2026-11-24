-- Lightweight relationship catalog. Edges describe evidence, never inferred behavior.
local Relations = {}
Relations.__index = Relations

local SCRIPT_CLASSES = {LocalScript = true, ModuleScript = true, Script = true}
local REMOTE_CLASSES = {RemoteEvent = true, RemoteFunction = true, UnreliableRemoteEvent = true}
local GUI_CLASSES = {
    ScreenGui = true, BillboardGui = true, SurfaceGui = true,
    Frame = true, ScrollingFrame = true, TextLabel = true, TextButton = true,
    TextBox = true, ImageLabel = true, ImageButton = true, ViewportFrame = true,
    VideoFrame = true, CanvasGroup = true, UIListLayout = true, UIGridLayout = true,
    UIPadding = true, UIStroke = true, UICorner = true, UIScale = true,
    UIAspectRatioConstraint = true, UISizeConstraint = true, UITextSizeConstraint = true,
}
local ALLOWED_CATEGORIES = {scripts = true, gui = true, remotes = true}

local function idKey(value)
    return value ~= nil and tostring(value) or nil
end

local function classKind(className)
    if className == "ModuleScript" then return "module" end
    if SCRIPT_CLASSES[className] then return "script" end
    if REMOTE_CLASSES[className] then return "remote" end
    if GUI_CLASSES[className] then return "gui" end
    return nil
end

local function canonicalPath(path)
    if type(path) ~= "string" then return nil end
    local parts = {}
    for part in path:gmatch("[^/]+") do
        parts[#parts + 1] = part:gsub("~%d+$", "")
    end
    return #parts > 0 and table.concat(parts, "/") or nil
end

local function sortedValues(map)
    local keys, values = {}, {}
    for key, value in pairs(map) do keys[#keys + 1] = key; values[key] = value end
    table.sort(keys)
    local result = {}
    for _, key in ipairs(keys) do result[#result + 1] = values[key] end
    return result
end

function Relations.new(cfg, context)
    cfg = type(cfg) == "table" and cfg or {}
    context = type(context) == "table" and context or {}
    return setmetatable({
        budget = context.budget or cfg.budget,
        knownIdentity = context.knownIdentity,
        catalog = {}, paths = {}, scriptIds = {}, edges = {}, edgeKeys = {},
        registered = 0, analyzed = 0,
    }, Relations)
end

function Relations:_checkpoint(stage)
    if self.budget and type(self.budget.checkpoint) == "function" then
        self.budget:checkpoint(stage or "relations")
    end
end

function Relations:_add(edge)
    local key = table.concat({idKey(edge.fromInstanceId) or "", idKey(edge.fromScriptId) or "",
        idKey(edge.toInstanceId) or "", idKey(edge.toScriptId) or "", edge.kind or "",
        edge.evidence or "", tostring(edge.line or ""), tostring(edge.property or ""),
        tostring(edge.pathCandidate or ""), tostring(edge.direction or ""),
        tostring(edge.guiSequence or ""), tostring(edge.remoteSequence or "")}, "|")
    if self.edgeKeys[key] then return end
    self.edgeKeys[key] = true
    edge.causal = edge.causal == true
    self.edges[#self.edges + 1] = edge
end

function Relations:register(record, service)
    if type(record) ~= "table" then return false end
    local instanceId = record.instanceId
    local key = idKey(instanceId)
    if not key then return false end
    -- Serialized Roblox Instance references are direct property values. Avoid
    -- walking nested Vector/CFrame/attribute payloads across the full dataset.
    local properties = type(record.properties) == "table" and record.properties or {}
    local propertyCount = 0
    for property, value in pairs(properties) do
        if type(value) == "table" and value.kind == "InstanceRef" and value.instanceId ~= nil then
            self:_add({fromInstanceId = instanceId, toInstanceId = value.instanceId,
                kind = "property_reference", property = tostring(property),
                evidence = "serialized_instance_reference", confidence = "exact_instance_id",
                resolution = "pending", causal = false})
        end
        propertyCount = propertyCount + 1
        if propertyCount % 128 == 0 then self:_checkpoint("relations_register") end
    end
    local kind = classKind(record.className)
    if not ALLOWED_CATEGORIES[record.category] or not kind then return false end
    local path = type(record.path) == "string" and record.path or ""
    if path ~= "" and type(service) == "string" and not path:match("^[^/]+/") then
        path = service .. "/" .. path
    end
    local scriptId = record.scriptId or ((kind == "script" or kind == "module") and ("s" .. tostring(instanceId)) or nil)
    local item = {
        instanceId = instanceId, scriptId = scriptId, className = record.className,
        category = record.category, kind = kind, service = service,
        robloxPath = path, parentPath = record.parentPath, name = record.name,
        parentInstanceId = record.parentInstanceId,
    }
    local previous = self.catalog[key]
    if previous then
        for _, oldPath in ipairs(previous.pathKeys or {}) do
            local oldMatches = self.paths[oldPath]
            if oldMatches then
                for index = #oldMatches, 1, -1 do
                    if idKey(oldMatches[index].instanceId) == key then table.remove(oldMatches, index) end
                end
                if #oldMatches == 0 then self.paths[oldPath] = nil end
            end
        end
    end
    self.catalog[key] = item
    if (kind == "script" or kind == "module") and scriptId then self.scriptIds[scriptId] = item end
    if path ~= "" then
        local pathKeys, seenPaths = {}, {}
        local function addPath(value)
            if type(value) == "string" and value ~= "" and not seenPaths[value] then
                seenPaths[value] = true
                pathKeys[#pathKeys + 1] = value
            end
        end
        addPath(path)
        addPath(canonicalPath(path))
        local parentPath = type(record.parentPath) == "string" and record.parentPath or ""
        local name = type(record.name) == "string" and record.name:gsub("[./\\]", "_") or ""
        if parentPath ~= "" and name ~= "" then
            local literalPath = parentPath .. "/" .. name
            addPath(literalPath)
            addPath(canonicalPath(literalPath))
        end
        item.pathKeys = pathKeys
        for _, indexPath in ipairs(pathKeys) do
            local matches = self.paths[indexPath]
            if not matches then matches = {}; self.paths[indexPath] = matches end
            matches[#matches + 1] = item
        end
    end
    self.registered = self.registered + 1

    if record.parentInstanceId ~= nil and (kind == "script" or kind == "module" or kind == "gui") then
        self:_add({fromInstanceId = instanceId,
            fromScriptId = (kind == "script" or kind == "module") and scriptId or nil,
            toInstanceId = record.parentInstanceId, kind = "instance_parent", evidence = "instance_parent",
            confidence = "exact_instance_id", resolution = "pending", structural = true, causal = false})
    end
    return true
end

local function expectedTarget(kind)
    if kind == "require" then return "module" end
    if kind == "remoteReferences" or kind == "FireServer" or kind == "InvokeServer"
        or kind == "OnClientEvent" or kind == "OnClientInvoke" or kind == "Fire"
        or kind == "Invoke" or kind == "Event" or kind == "OnInvoke" then return "remote" end
    if kind == "guiReferences" or kind == "gui_path" then return "gui" end
    return nil
end

function Relations:analyze(entries)
    if type(entries) ~= "table" then return self:index() end
    local steps = 0
    for _, entry in ipairs(entries) do
        if type(entry) == "table" and type(entry.analysis) == "table" then
            local analysis = entry.analysis
            local sourceId = entry.instanceId or analysis.instanceId
            local scriptId = entry.scriptId
            if not scriptId and sourceId ~= nil then scriptId = "s" .. tostring(sourceId) end
            for _, group in ipairs({
                {name = "imports", kind = "require"},
                {name = "remoteReferences", kind = "remoteReferences"},
                {name = "guiReferences", kind = "guiReferences"},
            }) do
                for _, reference in ipairs(type(analysis[group.name]) == "table" and analysis[group.name] or {}) do
                    steps = steps + 1
                    if steps % 128 == 0 then self:_checkpoint("relations_analyze") end
                    local kind = reference.kind or group.kind
                    local edge = {
                        fromScriptId = scriptId, fromInstanceId = sourceId,
                        pathCandidate = reference.pathCandidate, line = reference.line,
                        byteOffset = reference.byteOffset, kind = kind,
                        assetIdCandidate = reference.assetIdCandidate,
                        evidence = reference.evidence or "static_text",
                        confidence = reference.confidence or "candidate", causal = false,
                    }
                    local path = reference.pathCandidate
                    local matches = type(path) == "string" and self.paths[path] or nil
                    local targetKind = expectedTarget(kind) or expectedTarget(group.kind)
                    if matches and #matches == 1 and targetKind and matches[1].kind == targetKind then
                        edge.toInstanceId = matches[1].instanceId
                        edge.toScriptId = matches[1].scriptId
                        edge.resolution = "resolved"
                    elseif matches and #matches > 1 then
                        edge.resolution = "ambiguous"
                        edge.reason = "path is not unique in the client catalog"
                    else
                        edge.resolution = "unresolved"
                        edge.reason = matches and "target class is not appropriate for this reference" or "no exact full-path match"
                    end
                    self:_add(edge)
                end
            end
            self.analyzed = self.analyzed + 1
        end
    end
    self:_resolveIdentityEdges()
    return self:index()
end

function Relations:addObserved(remoteStats, temporalRelations)
    local function addRemote(remoteId, scriptLinks, direction)
        local remote = self.catalog[idKey(remoteId)]
        if not remote or remote.kind ~= "remote" then return end
        for _, scriptId in ipairs(type(scriptLinks) == "table" and scriptLinks or {}) do
            local source = self.scriptIds[scriptId]
            if source then
                self:_add({fromScriptId = source.scriptId, fromInstanceId = source.instanceId,
                    toInstanceId = remote.instanceId, kind = "remote_call", direction = direction,
                    evidence = "cobalt_observed", confidence = "observed_instance_identity",
                    resolution = "resolved", causal = false})
            end
        end
    end
    if type(remoteStats) == "table" then
        for _, item in pairs(remoteStats) do
            if type(item) == "table" then
                addRemote(item.instanceId, item.observedScriptLinks or {}, item.direction)
            end
        end
    end
    if type(temporalRelations) == "table" then
        for _, item in ipairs(temporalRelations) do
            if type(item) == "table" and item.kind == "temporal_association"
                and item.guiInstanceId ~= nil and item.remoteInstanceId ~= nil then
                self:_add({fromInstanceId = item.guiInstanceId, toInstanceId = item.remoteInstanceId,
                    kind = "temporal_association", evidence = "temporal_association",
                    confidence = "temporal_proximity_only", guiSequence = item.guiSequence,
                    remoteSequence = item.remoteSequence, deltaSeconds = item.deltaSeconds,
                    guiEventType = item.guiEventType, toStateId = item.toStateId,
                    resolution = "pending", causal = false})
            elseif type(item) == "table" and item.instanceId and item.scriptId then
                addRemote(item.instanceId, {item.scriptId}, item.direction)
            elseif type(item) == "table" and item.remoteInstanceId and item.scriptId then
                addRemote(item.remoteInstanceId, {item.scriptId}, item.direction)
            end
        end
    end
    self:_resolveIdentityEdges()
    return self:index()
end

function Relations:_resolveIdentityEdges()
    for index, edge in ipairs(self.edges) do
        if index % 128 == 0 then self:_checkpoint("relations_resolve") end
        if edge.resolution == "pending" then
            local target = self.catalog[idKey(edge.toInstanceId)]
            if edge.kind == "temporal_association" then
                local source = self.catalog[idKey(edge.fromInstanceId)]
                local sourceClass = source and source.className
                local targetClass = target and target.className
                if not sourceClass and type(self.knownIdentity) == "function" then
                    local ok, value = pcall(self.knownIdentity, edge.fromInstanceId)
                    if ok and type(value) == "string" and value ~= "" then
                        sourceClass = value; edge.sourceOutsideRelationshipCatalog = true
                    end
                end
                if not targetClass and type(self.knownIdentity) == "function" then
                    local ok, value = pcall(self.knownIdentity, edge.toInstanceId)
                    if ok and type(value) == "string" and value ~= "" then
                        targetClass = value; edge.targetOutsideRelationshipCatalog = true
                    end
                end
                if sourceClass and targetClass then
                    edge.resolution = "resolved"
                    edge.sourceClassName, edge.targetClassName = sourceClass, targetClass
                else
                    edge.resolution = "unresolved"
                    edge.reason = "temporal endpoint identity is not in the client metadata"
                end
            elseif target then
                edge.resolution = "resolved"
                edge.toScriptId = target.scriptId
                edge.targetClassName = target.className
            elseif (edge.kind == "property_reference" or edge.kind == "instance_parent")
                and type(self.knownIdentity) == "function" then
                local ok, className = pcall(self.knownIdentity, edge.toInstanceId)
                if ok and type(className) == "string" and className ~= "" then
                    edge.resolution = "resolved"
                    edge.targetClassName = className
                    edge.targetOutsideRelationshipCatalog = true
                else
                    edge.resolution = "unresolved"
                    edge.reason = "target identity is not in the client metadata"
                end
            else
                edge.resolution = "unresolved"
                edge.reason = "target instance ID is not in the client catalog"
            end
        end
    end
end

function Relations:summary()
    local result = {relations = #self.edges, resolved = 0, unresolved = 0, ambiguous = 0,
        directions = {}, evidence = {}, kinds = {}, scripts = self.analyzed, catalogEntries = self.registered}
    for index, edge in ipairs(self.edges) do
        if index % 128 == 0 then self:_checkpoint("relations_summary") end
        if edge.resolution == "resolved" then result.resolved = result.resolved + 1
        elseif edge.resolution == "ambiguous" then result.ambiguous = result.ambiguous + 1
        else result.unresolved = result.unresolved + 1 end
        if edge.direction then result.directions[edge.direction] = (result.directions[edge.direction] or 0) + 1 end
        result.evidence[edge.evidence] = (result.evidence[edge.evidence] or 0) + 1
        result.kinds[edge.kind] = (result.kinds[edge.kind] or 0) + 1
    end
    return result
end

function Relations:index()
    self:_resolveIdentityEdges()
    return {version = 1, evidenceScope = "explicit identity links and unique exact full-path static candidates; no causal inference",
        summary = self:summary(), edges = sortedValues(self.edges)}
end

return Relations
