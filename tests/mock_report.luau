-- Synthetic-only Report v2 contract regression.
local Report = require("../src/report")

local manifest = {
    exporterVersion = "0.9.0", status = "partial", capturedAtUtc = "2026-11-24T10:00:00Z",
    endedReason = "finished", game = {label = "Synthetic", placeId = 1, gameId = 2},
    client = {executor = "Mock"}, settings = {observeRemotes = true},
    stats = {written = 12, files = 3, bytes = 4096}, services = {PlayerGui = {records = 5}},
    categories = {gui = {records = 5}}, scriptExport = {enabled = true, indexPath = "scripts/index.json",
        stats = {discovered = 2, succeeded = 1, empty = 1}},
    diagnostics = {remoteObservations = 1, guiActions = 2},
    dedup = {inspected = 20, uniqueInstances = 8, structuralChanges = 3,
        scriptSharedReferences = 2, guiStates = 2, guiStateBytes = 700,
        guiFullSnapshotEquivalentBytes = 9000, eventsWritten = 5,
        queuedEvents = 0, lostEvents = 0},
    continuous = {enabled = true, captureMode = "continuous", monitorCycles = 12},
    guiAnalysis = {status = "partial", reason = "one inaccessible widget", counts = {states = 4}},
    relations = {status = "complete", counts = {edges = 3}},
    runtime = {status = "partial", reason = "one capability unknown", counts = {available = 4},
        observer = {state = "attached", reason = ""}},
    validation = {status = "complete", counts = {checks = 8, issues = 0}},
    partialReasons = {"empty_script_result", "runtime_capability_unknown"},
    errors = {"synthetic error"},
}
local report = Report.build(manifest, {
    artifacts = {reportJson = "report.json"},
    limitations = {"Synthetic fixture only."},
    layers = {remoteInventory = {status = "complete", reason = "", counts = {remotes = 7},
        artifacts = {"remotes/index.json"}, evidence = {source = "static_inventory"}}},
})
assert(report.reportVersion == 2)
assert(report.dedup.inspected == 20 and report.dedup.guiStates == 2)
assert(report.continuous.enabled == true and report.continuous.monitorCycles == 12)
assert(report.layers.metadata.status == "partial")
assert(report.layers.reconstructedScripts.counts.succeeded == 1)
assert(report.layers.gui.status == "partial")
assert(report.layers.remoteInventory.counts.remotes == 7)
assert(report.layers.remoteObservations.counts.events == 1)
assert(report.layers.runtime.status == "partial")
assert(report.layers.relations.counts.edges == 3)
assert(report.layers.validation.counts.issues == 0)
assert(report.sourceFidelity.originalSourceChecksum == "unavailable")

local markdown = Report.markdown(report)
assert(markdown:find("# Continuous Capture report (v2)", 1, true))
assert(markdown:find("## Continuous capture", 1, true))
assert(markdown:find("guiFullSnapshotEquivalentBytes", 1, true))
assert(markdown:find("empty_script_result", 1, true))
assert(markdown:find("original source is unavailable", 1, true))
assert(markdown:find("remoteObservations", 1, true))
assert(markdown:find("synthetic error", 1, true))

local unavailable = Report.build({status = "complete", settings = {observeRemotes = false}})
assert(unavailable.layers.metadata.status == "unavailable")
assert(unavailable.layers.remoteObservations.status == "disabled")
assert(unavailable.layers.runtime.status == "unavailable")

local noAdapter = Report.build({settings = {observeRemotes = true}, diagnostics = {remoteObservations = 0},
    runtime = {observer = {state = "unavailable", reason = "bridge absent"}}})
assert(noAdapter.layers.remoteObservations.status == "unavailable")
assert(noAdapter.layers.remoteObservations.reason == "bridge absent")

local attachedQuiet = Report.build({settings = {observeRemotes = true}, diagnostics = {remoteObservations = 0},
    runtime = {observer = {state = "attached"}}})
assert(attachedQuiet.layers.remoteObservations.status == "not_observed")

local detachedQuiet = Report.build({settings = {observeRemotes = true}, diagnostics = {remoteObservations = 0},
    runtime = {observer = {state = "detached"}}})
assert(detachedQuiet.layers.remoteObservations.status == "not_observed")

local observed = Report.build({settings = {observeRemotes = true}, diagnostics = {remoteObservations = 2},
    runtime = {observer = {state = "attached"}}})
assert(observed.layers.remoteObservations.status == "complete")

local normalStop = Report.build({settings = {observeRemotes = true}, diagnostics = {remoteObservations = 2},
    runtime = {observer = {state = "detached", reason = "capture_stopped"}}})
assert(normalStop.layers.remoteObservations.status == "complete",
    "Normal capture stop after observing events is complete")

local interrupted = Report.build({settings = {observeRemotes = true}, diagnostics = {remoteObservations = 2},
    runtime = {observer = {state = "unloaded", reason = "executor_unloaded"}}})
assert(interrupted.layers.remoteObservations.status == "partial",
    "Interrupted observer with events must report a partial interval")

local cleanupFailed = Report.build({settings = {observeRemotes = true}, diagnostics = {remoteObservations = 5},
    runtime = {observer = {state = "cleanup_failed", reason = "cobalt_unsubscribe_failed",
        observedCalls = 5, skipped = 2, droppedRelations = 3, droppedPendingCallers = 4}},
    relations = {status = "complete", counts = {relations = 9}}})
assert(cleanupFailed.layers.remoteObservations.status == "partial",
    "Observer cleanup failure must be partial, not unavailable")
assert(cleanupFailed.layers.remoteObservations.counts.events == 5
    and cleanupFailed.layers.remoteObservations.counts.skipped == 2)
assert(cleanupFailed.layers.remoteObservations.counts.droppedRelations == 3
    and cleanupFailed.layers.remoteObservations.counts.droppedPendingCallers == 4)
assert(cleanupFailed.layers.relations.status == "partial")
assert(cleanupFailed.layers.relations.counts.droppedTemporalRelations == 3
    and cleanupFailed.layers.relations.counts.droppedPendingCallers == 4)
assert(cleanupFailed.layers.relations.reason:find("capacity was exceeded", 1, true))

local scriptPartial = Report.build({status = "complete", scriptExport = {enabled = true,
    stats = {succeeded = 10, empty = 1}}})
assert(scriptPartial.layers.reconstructedScripts.status == "partial",
    "Script layer must follow its own counters, not global capture status")
local scriptComplete = Report.build({status = "partial", scriptExport = {enabled = true,
    stats = {discovered = 10, attempted = 10, succeeded = 10, failed = 0, inaccessible = 0,
        empty = 0, partial = 0, pending = 0}}})
assert(scriptComplete.layers.reconstructedScripts.status == "complete",
    "Unrelated global partial status must not taint successful script extraction")
local overflowed = Report.build({status="stopped", services={}, partialReasons={"event_queue_overflow", "journal_queue_overflow"},
    settings={observeRemotes=true}, diagnostics={remoteObservations=5},
    runtime={observer={state="detached", reason="capture_stopped"}}})
assert(overflowed.layers.metadata.status=="partial", "structural overflow falsely reported complete")
assert(overflowed.layers.remoteObservations.status=="partial", "journal loss falsely reported complete")
local unresolved = Report.build({settings={observeRemotes=true}, diagnostics={remoteObservations=2},
    runtime={observer={state="detached",reason="capture_stopped",unresolvedCalls=1,lostRawObservations=0}}})
assert(unresolved.layers.remoteObservations.status=="partial"
    and unresolved.layers.remoteObservations.counts.events==2
    and unresolved.layers.remoteObservations.counts.unresolvedCalls==1,
    "unresolved occurrence was hidden or falsely reported fully resolved")
print("Luau Report mock OK: report v2 layers, unavailable states, reasons, fidelity")
