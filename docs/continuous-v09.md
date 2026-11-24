# Continuous Capture v0.9: data and recovery

This document describes the v0.9 implementation (`inspectionVersion = 2`).
Continuous Capture starts with the normal selected-service export and then
records observations until Stop & Save. Full Export remains available without
continuous monitoring. Both describe the client-visible data available at the
time of capture; they cannot recover server-only objects or changes that were
not observed. Successful reconstruction or validation does not establish
completeness of the game view.

## Identity, content and occurrences

Every observed instance receives a capture-local `instanceId`. A rename or move
changes metadata; two different instances remain separate even if their names,
paths, or script contents coincide. Paths may be duplicated. The global sequence
orders captured observations inside one session; IDs and sequences from different
sessions are not directly comparable.

Script index entries retain their separate instance identities. Reconstructed
sources can share a content file under `scripts/sources/content/` after their
bytes have been checked for equality. Checksums apply to returned reconstructed
bytes, not unavailable original server source. Missing, empty or failed
reconstruction remains visible in the index and status.
Script index version 2 counts physical files/bytes separately from logical
files/bytes and shared references. Newly written content files have
`headerByteLength = 0`. A verified legacy file retained by source-extraction
resume can keep its original header and nonzero offset in the same index;
read its source using that offset. Logical byte totals include each referenced
file's complete bytes, including such retained legacy headers.

## GUI states

`gui/states/index.json` has `schemaVersion = 2` and lists state descriptors,
observation counts, aggregate transition counts, button coverage and summary
metrics. State files use `gui/states/stateNNNNNN.json`:

```json
{"schemaVersion":2,"stateId":2,"baseStateId":1,
 "upserts":[{"instanceId":12,"parentInstanceId":4,"className":"TextLabel",
             "path":"PlayerGui/Menu/Status","properties":{"Text":"Open"}}],
 "removes":[15],"elementCount":100}
```

An absent `baseStateId` means a full baseline. Otherwise reconstruct the base
first, remove the listed instance IDs and replace/add full projected records in
`upserts`. Baselines are also written periodically after 64 unique states to
bound replay depth. Each projection contains `instanceId`, optional
`parentInstanceId`, `className`, `path`, and the scalar values observed for
`Visible`, `Enabled`, `Text`, `Active`, `Interactable`, `Selected`, `Selectable`,
`TextEditable`, `ScrollingEnabled`, and `Playing`. Missing fields are not
assumed false. A GUI parent can be outside the GUI projection.

`gui/states/lookup/<digest>/<slot>.json` is a durable lookup descriptor. A
digest narrows the search; the candidate state is reconstructed and compared
exactly before reuse, including when hashes collide. A RAM cache is not the
source of truth. A → B → A preserves successive transition occurrences while
reusing A's existing state content. Transition records represent successive
observations, not proof that an action caused a change. Rapid states between
observations may be absent. The index's transition aggregates do not replace
the chronological journal.

The Python reader supports the versioned state format:

```python
from reconstruct_export import reconstruct_gui, iter_events
rows = reconstruct_gui("path/to/export", 2)
for event in iter_events("path/to/export"):
    print(event["sequence"], event.get("event"))
```

The module is in `scripts/`; add that directory to Python's import path. The
independent validator is `python scripts/validate_export.py <export-directory>`.
Legacy GUI schema-1 snapshots remain readable by the validator.

## Journal and checkpoints

V0.9 uses `journal/index.json` and immutable segment documents under
`journal/<stream>/bNNNNNN.json`. Each segment has `version`, `stream`, and
ordered `rows`; the index records its path, count and first/last sequence.
Streams include GUI actions, GUI transitions, remote observations and temporal
relations. Every recorded remote occurrence remains a separate row: repeated
calls are not deduplicated merely because they look alike. Optional remote
observation is passive and its availability and losses must be read from the
report. Argument values are not recorded by this observer.
The existing adapter supplies a shallow type summary for at most 32 arguments
plus an ellipsis marker, and the original argument count. Compact signatures
preserve this available summary, including optional Request/Callback kind;
they do not recover omitted values or types beyond that adapter limit.
Online temporal correlation considers up to 128 recent GUI actions and 128
remote observations within the configured window. These derived associations
are not exhaustive causal links. The chronological action/remote occurrences
remain separate, so offline analysis can apply a wider correlation policy.
The offline journal reader merges ordered streams one segment per stream at a
time. Fully consume its iterator to validate all segment counts and ranges.

Cobalt admission only copies bounded primitive metadata and temporarily keeps
the exact remote/origin references in a FIFO. It reserves sequence and time
immediately, without reading Instance properties or resolving hierarchy in the
interceptor. The main capture loop performs that work. A resolved occurrence
has `identityStatus: "resolved"`; `pathEvidence` and `scopeBasis` distinguish a
deferred resolution from immutable metadata already known at admission.
Caller IDs can likewise use a proven cached identity with
`callerPathEvidence: "last_structural_observation"`.

If identity or selected-root membership cannot be established after deferral,
the occurrence is retained as `identityStatus: "unresolved"` with reason
`deferred_identity_unavailable`. It has no invented instance/caller ID, name,
path or class. Direction, shared type signature, original sequence and time
remain available. `observedCalls` includes these rows; `unresolvedCalls` is
separate and makes the observation layer partial. This can include observations
outside the selected scope; it does not assert where an unknown Instance was
located when Cobalt observed it. Upstream Cobalt filters and rate limits apply
before the adapter and cannot be recovered by this exporter.

`checkpoints/cNNNNNN.json` is a version-1 recovery descriptor containing a
provisional manifest, artifact list, immutable copies of mutable sidecars under
`checkpoints/files/`, `lastSequence`, and pending counters. Checkpoint content
is verified by length and checksum. Checkpoints and their copied files are not
part of the final artifact ledger. Events admitted during a journal flush are
kept in the queue for a later flush; data not included in the chosen durable
checkpoint may be absent after interruption. A queued event is not the same as a
durably written event. Queue overflow and write failures affect capture status;
inspect diagnostics and partial reasons.
`pendingRawObservations` distinguishes admitted raw references from journal
rows already processed. Both raw and journal queues are bounded at 16,384
events in the engine; producer overflow is counted exactly and stops normal
collection. Strong temporary references are released on consumption; raw
references are never serialized into a dataset.
`lastSequence` is the maximum included durable sequence, not a promise of a
gap-free prefix across streams. Pending counters distinguish observed,
queued and persisted data. A checkpoint is deferred and retried when structural
events or GUI activations arrive during sidecar preparation, or when required
flushes/sidecars fail. A previous verified checkpoint remains recoverable.

Stop & Save disconnects admissions and joins callbacks and journal writes already
in flight before producing final indexes and reports. If those callbacks remain
blocked for ten seconds, finalization fails explicitly and directs the operator
to checkpoint recovery; it does not publish a successful final report.

Inspect or recover without modifying the original capture:

```sh
python scripts/recover_export.py <capture-directory>
python scripts/recover_export.py <capture-directory> --output <new-empty-directory>
python scripts/validate_export.py <new-empty-directory>
```

The tool checks artifact paths, lengths and checksums and tests semantic
reconstruction and validation in an isolated temporary directory for each
candidate. It falls back to an older checkpoint if a newer candidate fails
those checks. This offline inspection needs temporary disk space and additional
I/O proportional to the candidate artifacts. The recovered export is marked
`partial` with reason `recovered_checkpoint`; it is a separate, read-only
historical dataset, not a resumed recording. It is independently validated
before the tool reports success. A checksum-valid checkpoint can still fail
semantic validation; it is rejected and an older candidate is tried. If no
candidate succeeds, recovery reports an error and does not claim a valid
dataset. Partial output may remain in the specified output directory on failure.

## Memory and observation limits

Event and source work queues are bounded; overflow is counted and stops normal
collection with a partial reason. Journal segments and reconstructed source
contents are written progressively, and historical GUI payloads are read from
disk when needed. Current live instance wrappers remain anchored to preserve
identity across executor garbage collection; removal releases those anchors.

Historical IDs, script index entries, GUI descriptors, segment descriptors,
artifact descriptors and distinct relation/catalog entries still remain in RAM.
Their size grows with genuinely new data. The implementation does not promise
constant memory for an arbitrarily active session. An unchanged environment
does not add historical entries merely because another scan occurred.

GUI and selected non-GUI roots are reconciled periodically, with structural
signals retaining observed short-lived additions/removals. Changes between
observations can remain unseen, especially rapid property changes and periods
when a replaced root has not yet been rebound. Moving or renaming one known
script does not trigger another decompile. The exporter does not infer arbitrary
source edits on the same instance: it only records source versions that can
actually be established. Client-wide Lua heap/FPS measurements also include the
game, executor, Cobalt and test fixtures; they are not exporter-only allocation
measurements.

## Measuring comparisons

`python scripts/compare_gui_exports.py <v08-export> <v09-export>` compares the
controlled fixture's projected GUI graphs without treating capture-local IDs as
cross-session identities. It retains parentage and duplicate sibling
multiplicity. A `~N` suffix is removed only when the same capture's GUI metadata
supports the underlying name; parent classes are checked against captured
metadata by instance ID and path. Missing or conflicting evidence leaves
comparison uncertain. It reports physical GUI state storage for each dataset,
and reports total disk savings only when complete GUI state sets are
comparable. The fixture projection byte figure is a normalized logical estimate,
not bytes saved on disk. Equal state sets do not prove equal timing or that all
short-lived states were observed.

One controlled active client comparison with 5,000 fixture labels produced 11
distinct fixture states and 11 complete normalized GUI states in each version.
The sets of reconstructed states matched. The complete `gui/states/` storage
measured 9,784,616 bytes for v0.8 and 899,308 bytes for v0.9, a reduction of
8,885,308 bytes (90.81%) in this comparison. These are whole-GUI storage bytes,
not physical bytes attributable to the fixture alone. Matching state sets does
not prove identical transition timing or observation of every brief state.
In that controlled pair, both journals contain 25 transition occurrences and
both indexes aggregate them into 12 transition kinds. The ordered sequence
of normalized full-GUI state pairs matches; timestamps, causes and unobserved
states were not compared. V0.8's GUI summary `transitions` counts aggregate
kinds, while v0.9's summary `transitions` counts occurrences. The comparator
checks the journal against the aggregate counts and can include the normalized
walk with `--normalized-transition-walk`.
