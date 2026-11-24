-- Stable, human-readable summary contract for Full Export captures.
local Report = {}

local LAYER_NAMES = {
    "metadata", "reconstructedScripts", "gui", "remoteInventory",
    "remoteObservations", "runtime", "relations", "validation",
}

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function status(value, fallback)
    if type(value) == "table" and type(value.status) == "string" then return value.status end
    if type(value) == "string" then return value end
    return fallback
end

local function layer(state, reason, counts, artifacts, evidence)
    return {
        status = state,
        reason = reason or "",
        counts = type(counts) == "table" and copy(counts) or {},
        artifacts = type(artifacts) == "table" and copy(artifacts) or {},
        evidence = type(evidence) == "table" and copy(evidence) or {},
    }
end

function Report.build(manifest, extras)
    manifest = type(manifest) == "table" and manifest or {}
    extras = type(extras) == "table" and extras or {}
    local stats = type(manifest.stats) == "table" and manifest.stats or {}
    local settings = type(manifest.settings) == "table" and manifest.settings or {}
    local scriptExport = type(manifest.scriptExport) == "table" and manifest.scriptExport or {}
    local scriptStats = type(scriptExport.stats) == "table" and scriptExport.stats or {}
    local diagnostics = type(manifest.diagnostics) == "table" and manifest.diagnostics or {}
    local runtime = type(manifest.runtime) == "table" and manifest.runtime or {}
    local observer = type(runtime.observer) == "table" and runtime.observer or nil
    local observedCalls = diagnostics.remoteObservations or 0
    if type(observedCalls) == "table" then observedCalls = observedCalls.events or observedCalls.count or 0 end
    observedCalls = tonumber(observedCalls) or tonumber(observer and observer.observedCalls) or 0
    local skippedCalls = tonumber(observer and observer.skipped) or 0
    local droppedRelations = tonumber(observer and observer.droppedRelations) or 0
    local droppedCallers = tonumber(observer and observer.droppedPendingCallers) or 0
    local relationCounts = manifest.relations and type(manifest.relations) == "table"
        and copy(manifest.relations.counts or manifest.relations) or {}
    if type(relationCounts) ~= "table" then relationCounts = {} end
    relationCounts.droppedTemporalRelations = droppedRelations
    relationCounts.droppedPendingCallers = droppedCallers
    local artifacts = type(extras.artifacts) == "table" and extras.artifacts or {}
    local limits = type(extras.limitations) == "table" and extras.limitations or {}
    local metadataPartial = (tonumber(stats.errors) or 0) > 0
        or (type(manifest.errors) == "table" and #manifest.errors > 0)
    for _, reason in ipairs(type(manifest.partialReasons) == "table" and manifest.partialReasons or {}) do
        if type(reason) == "string" and (reason:find("record_serialization", 1, true)
            or reason:find("property_serialization", 1, true)
            or reason:find("read_or_write_errors", 1, true)) then
            metadataPartial = true
        end
    end

    local scriptState, scriptReason
    if scriptExport.enabled == false then
        scriptState, scriptReason = "disabled", "Reconstructed script extraction was disabled."
    elseif scriptExport.enabled ~= true then
        scriptState, scriptReason = "unavailable", "No script extraction summary was recorded."
    else
        local failures = (tonumber(scriptStats.failed) or 0) + (tonumber(scriptStats.inaccessible) or 0)
            + (tonumber(scriptStats.empty) or 0) + (tonumber(scriptStats.partial) or 0)
            + (tonumber(scriptStats.pending) or 0)
        scriptState = failures > 0 and "partial" or "complete"
        scriptReason = failures > 0 and "One or more discovered scripts failed, were empty, inaccessible, partial, or pending." or ""
    end

    local observationState, observationReason
    local observerState = observer and observer.state or "unavailable"
    if settings.observeRemotes == false or observerState == "disabled" then
        observationState, observationReason = "disabled", "Remote observation was disabled."
    elseif observerState == "unavailable" then
        observationState, observationReason = "unavailable",
            (observer and observer.reason) or "The optional Cobalt observer adapter is unavailable."
    elseif observerState == "attached" then
        if observedCalls > 0 then observationState, observationReason = "complete", ""
        else observationState, observationReason = "not_observed", "Observer attached; no calls were observed during this capture." end
    elseif observerState == "cleanup_failed" then
        observationState = "partial"
        observationReason = observer.reason or "Observer cleanup failed at capture end."
    elseif observerState == "detached" or observerState == "unloaded" or observerState == "subscribe_failed" then
        if observedCalls > 0 and observerState == "detached" and observer.reason == "capture_stopped" then
            observationState, observationReason = "complete", "Observer detached after normal capture stop."
        elseif observedCalls > 0 then observationState = "partial"
        else observationState = "not_observed" end
        observationReason = observationReason or observer.reason
            or ("Observer state: " .. observerState .. "; no complete observation interval.")
    else
        observationState, observationReason = "unavailable", "Observer availability was not recorded."
    end

    local layers = {
        metadata = layer(status(manifest.metadata, manifest.services
                and (metadataPartial and "partial" or "complete") or "unavailable"),
            manifest.metadata and (manifest.metadata.reason or "")
                or (manifest.services and (metadataPartial and "Metadata capture contains errors or recovered records." or "")
                    or "No service inventory was recorded."),
            manifest.metadata and (manifest.metadata.counts or manifest.metadata) or
                {records = stats.written or 0, files = stats.files or 0, bytes = stats.bytes or 0,
                services = manifest.services or {}, categories = manifest.categories or {}},
            artifacts.metadata or {"manifest.json"}, {scope = "client-visible selected services"}),
        reconstructedScripts = layer(scriptState, scriptReason,
            scriptStats, artifacts.reconstructedScripts or {scriptExport.indexPath or "scripts/index.json"},
            {method = "executor decompile", fidelity = "returned reconstructed bytes; original source unavailable"}),
        gui = layer(status(manifest.guiAnalysis, manifest.guiAnalysis and "partial" or "unavailable"),
            manifest.guiAnalysis and (manifest.guiAnalysis.reason or "") or "No GUI analysis summary was recorded.",
            manifest.guiAnalysis and (manifest.guiAnalysis.counts or manifest.guiAnalysis) or {},
            artifacts.gui or {"gui/index.json"}, {source = "client GUI snapshots"}),
        remoteInventory = layer(status(manifest.remoteInventory, manifest.remoteInventory and "complete" or "unavailable"),
            manifest.remoteInventory and (manifest.remoteInventory.reason or "") or "No remote inventory summary was recorded.",
            manifest.remoteInventory and (manifest.remoteInventory.counts or manifest.remoteInventory) or {},
            artifacts.remoteInventory or {"remotes/index.json"}, {source = "static class inventory"}),
        remoteObservations = layer(observationState, observationReason,
            {events = observedCalls, skipped = skippedCalls, droppedRelations = droppedRelations,
                droppedPendingCallers = droppedCallers}, artifacts.remoteObservations or {},
            {source = "optional passive Cobalt observations", observerState = observerState,
                observerReason = observer and observer.reason or "", argumentValues = "not recorded"}),
        runtime = layer(status(manifest.runtime, manifest.runtime and "complete" or "unavailable"),
            manifest.runtime and (manifest.runtime.reason or "") or "Runtime capability information was not recorded.",
            manifest.runtime and (manifest.runtime.counts or manifest.runtime) or {},
            artifacts.runtime or {}, {source = "executor capability checks"}),
        relations = layer((droppedRelations > 0 or droppedCallers > 0) and "partial"
                or status(manifest.relations, manifest.relations and "complete" or "unavailable"),
            (droppedRelations > 0 or droppedCallers > 0)
                and ("Observer relation capacity was exceeded; dropped " .. droppedRelations
                    .. " temporal relations and " .. droppedCallers .. " pending callers.")
                or (manifest.relations and (manifest.relations.reason or "")
                    or "No relationship analysis summary was recorded."),
            relationCounts,
            artifacts.relations or {"relations/index.json"}, {source = "explicitly evidenced instance links"}),
        validation = layer(status(manifest.validation, manifest.validation and "complete" or "unavailable"),
            manifest.validation and (manifest.validation.reason or "") or "No validation result was recorded.",
            manifest.validation and (manifest.validation.counts or manifest.validation) or {},
            artifacts.validation or {}, {source = "capture-time validation"}),
    }
    for _, name in ipairs(LAYER_NAMES) do
        if type(extras.layers) == "table" and extras.layers[name] then
            layers[name] = copy(extras.layers[name])
        end
    end

    local report = {
        reportVersion = 2,
        exporterVersion = manifest.exporterVersion,
        status = manifest.status or "unknown",
        capturedAtUtc = manifest.capturedAtUtc,
        endedReason = manifest.endedReason,
        game = copy(manifest.game or {}),
        client = copy(manifest.client or manifest.clientMetadata or {}),
        settings = copy(settings),
        stats = copy(stats),
        scriptExport = copy(scriptExport),
        diagnostics = copy(diagnostics),
        partialReasons = copy(manifest.partialReasons or {}),
        errors = copy(manifest.errors or {}),
        layers = layers,
        artifacts = copy(artifacts),
        limitations = copy(limits),
        sourceFidelity = {
            kind = "reconstructed_client_output",
            description = "Checksums cover exact bytes returned by the executor decompiler and the saved file. They do not verify original Roblox source; original source is unavailable.",
            originalSourceChecksum = "unavailable",
        },
    }
    return report
end

local function safe(value)
    if type(value) == "table" then return "structured data in report.json" end
    if value == nil then return "unavailable" end
    return tostring(value):gsub("[\r\n|]", " ")
end

local function display(value)
    if type(value) ~= "table" then return safe(value) end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, key in ipairs(keys) do
        local item = value[key]
        if item ~= nil and type(item) ~= "table" then
            parts[#parts + 1] = (type(key) == "number" and "" or tostring(key) .. "=") .. safe(item)
        end
    end
    return #parts > 0 and table.concat(parts, ", ") or "see report.json"
end

function Report.markdown(report)
    report = type(report) == "table" and report or {}
    local lines = {
        "# Full Export report (v" .. safe(report.reportVersion) .. ")", "",
        "- Status: " .. safe(report.status),
        "- Exporter: " .. safe(report.exporterVersion),
        "- Captured: " .. safe(report.capturedAtUtc),
        "- Game: " .. safe(type(report.game) == "table" and report.game.label or report.game),
        "- Place ID: " .. safe(type(report.game) == "table" and report.game.placeId),
        "", "## Layers", "", "| Layer | Status | Reason | Counts | Artifacts | Evidence |",
        "|---|---|---|---|---|---|",
    }
    for _, name in ipairs(LAYER_NAMES) do
        local item = type(report.layers) == "table" and report.layers[name] or {}
        local counts = display(item.counts)
        local files = display(item.artifacts)
        local evidence = display(item.evidence)
        lines[#lines + 1] = "| " .. name .. " | " .. safe(item.status) .. " | " .. safe(item.reason)
            .. " | " .. counts .. " | " .. safe(files) .. " | " .. safe(evidence) .. " |"
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Script source fidelity"
    lines[#lines + 1] = ""
    lines[#lines + 1] = safe(type(report.sourceFidelity) == "table" and report.sourceFidelity.description)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Partial reasons"
    lines[#lines + 1] = ""
    local reasons = type(report.partialReasons) == "table" and report.partialReasons or {}
    if #reasons == 0 then lines[#lines + 1] = "None recorded." end
    for _, reason in ipairs(reasons) do lines[#lines + 1] = "- " .. safe(reason) end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Errors"
    lines[#lines + 1] = ""
    local errors = type(report.errors) == "table" and report.errors or {}
    if #errors == 0 then lines[#lines + 1] = "None recorded." end
    for _, err in ipairs(errors) do lines[#lines + 1] = "- " .. safe(err) end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "## Limitations"
    lines[#lines + 1] = ""
    local limitations = type(report.limitations) == "table" and report.limitations or {}
    if #limitations == 0 then lines[#lines + 1] = "See layer reasons and source fidelity above." end
    for _, limitation in ipairs(limitations) do lines[#lines + 1] = "- " .. safe(limitation) end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Full structured counts, evidence, errors and artifact metadata are in `report.json`."
    return table.concat(lines, "\n") .. "\n"
end

return Report
