# Continuous Capture v0.9 validation

**Status: live and local automated validation completed.** CI and publication
are tracked in the PR. This report summarizes private local measurements and
automated checks available on 2026-11-24.
Captures and their contents remain in
the local executor workspace and are not included in this repository. This
document intentionally records aggregate counts only; it omits captured object,
player, and source names.

## Confirmed datasets

| Evidence | Result | Scope and limit |
|---|---:|---|
| Full v0.8 comparison reference | Independent validator passed; 689/689 reconstructed files compiled | Completed full capture used as the comparison reference. This validates that dataset, not the v0.9 release candidate. |
| Controlled v0.8/v0.9 idle and active comparisons | Two minutes per mode and version | Controlled metrics are available for both modes. They do not establish performance for every live client or workload. |
| Normalized GUI-state comparison | 11 distinct states; 25 transition occurrences; 12 transition kinds | The normalized ordered state-pair walk and state sets matched between versions. Timestamps, causes, and unobserved states were not compared. |
| GUI-state storage | 9,784,616 bytes in v0.8; 899,308 bytes in v0.9; 90.809% lower | Measures the comparable GUI-state artifacts. Whole-dataset storage fell by about 26%; checkpoint and index overhead remain in the dataset total. |
| One-hour idle endurance, R2 generation | 3,601.829 seconds; independent validation and recovered output passed | Recovery selected the last verified checkpoint at sequence 5,069 with no warnings. This was not the R10 code now being exercised by R11. |
| R7 all-target active capture | Finalization timed out; no final report was published | A durable checkpoint at sequence 177,150 covering 6,712 artifacts was recovered and independently validated. The client reported “Client Not Responding >300 seconds”; the cause is unknown. This was not a completed ten-minute pass. |
| R9 all-target active capture | Finalization timed out; no connection error was reported | A durable checkpoint at sequence 163,577 covering 3,687 artifacts was recovered and independently validated. At timeout, the journal writer was idle, 685 remote callbacks remained in flight, and no GUI callbacks were in flight. |
| R10 active capture | 459.727 seconds; final output validator passed | A fresh audit found the client had already disconnected before capture started. The run was stopped by its own test control, so it is excluded from in-game live acceptance. Its checkpoint recovery also passed. |
| R11 connected active capture | 601.785335 seconds of monitoring; final validator passed | 3,560 journal events replayed; all 324 physical Luau source files compiled. The manifest remains partial for explicitly recorded capture limits. |
| R11 Continuous UI workflow | Capture and Stop & Save completed; final output remained partial | Independent validator and event replay passed; UI listener and observer cleanup counts returned to baseline. |
| Full UI workflow | Passed on the same 315,258-byte bundle | Independent validation, event replay, source compilation, and unload/reload lifecycle checks passed. The manifest correctly retained partial status. |

The state comparison shows that delta storage retained the compared state
contents and transition walk while reducing GUI-state bytes. It does not prove
that every brief state was observed or that transitions occurred at identical
times. The GUI byte reduction should not be presented as the whole-dataset
reduction.

## Automated checks

The current R10 candidate has 54 Python tests discovered: 53 executed and one
Windows symlink test skipped because the environment does not support creating
the required link. A rerun passed with the same result. The 25 Luau mock suites
pass. Fourteen targeted source and bundle compilation checks passed, and
targeted analysis reported zero `LocalUnused`, `SyntaxError`, `DuplicateLocal`,
or `UnreachableCode` findings. The R10 automated checks include a normal capture
baseline of roughly 9,000 script entries, 10,000 repeated remote observations
through the Engine runtime observer, compact signature interning, and ordered
journal writes, GUI replay, and an idle-GC negative control. The runtime/journal test
uses a synthetic adapter callback; it is not evidence of live Cobalt traffic.

Checkpoint and recovery checks cover failed or partial writes, readback and
checksum errors, invalid checkpoint artifacts, event admission during a flush,
and callbacks that remain in flight during finalization. These race checks use
real Luau coroutines against deterministic mock filesystem/client APIs; they
are not Roblox process-kill or forced-disconnect tests. Verified checkpoint
recovery and independent validation passed for completed anchored idle and
active captures, and for the completed one-hour capture.

The current tests detect damage to declared artifacts and reject a semantically
invalid GUI-state index. They also cover journal ordering, duplicate or missing
sequence data, recovery fallback, and finalization waiting for in-flight work.
They do not establish recovery after every possible executor or filesystem
failure.

## Completed endurance details

The one-hour idle capture ran for 3,601.829 seconds. It inspected 6,735,585
items and recorded 5,069 unique instances and metadata records, with zero
structural deltas. It attempted one script reconstruction, producing one
logical and physical source file of 26,375 bytes. It recorded one GUI state and
zero transitions. The journal had zero lost or queued events. The run wrote 59
checkpoints; its 165 physical files, including checkpoint files, occupied
10,855,941 bytes, compared with 7,629,948 bytes in the ordinary artifact
ledger.

The independent validator passed, and recovery produced a separately validated
output from the last verified checkpoint (sequence 5,069) with no warnings. The
capture reported no partial reasons. Monitoring-weighted FPS was 79.4949, with
a worst observed frame of 263.866 ms. Monitoring heap snapshots were 930,946
KiB initially, 759,071 KiB finally, 638,109 KiB minimum, and 1,062,073 KiB
maximum. All nine fixture listener counts were restored. These are client-wide
measurements, not exporter-only resource measurements.

This endurance run used the earlier R2 generation. It predates later checkpoint
cut, callback join, full-root anchoring, and source-backpressure changes, so it
is not a one-hour pass of the R10 code now being exercised by R11.

## R7/R9 active runs and recovery

The R7 all-target active capture did not finalize. The client displayed
“Client Not Responding >300 seconds”; the cause is unknown. The engine reported
a callback-join timeout and did not publish a final report. The last durable
checkpoint (global sequence 177,150, 6,712 declared artifacts) was recovered
to a separate output and passed independent validation. The interrupted
capture retains its checkpoint for later inspection. This verifies recovery of
that checkpoint, not completion or lossless recovery of the full active run.

A standard teleport and reconnect into a fresh client environment at the same
place and version succeeded. This used the normal reconnect flow, not an
anti-cheat bypass or a game-directed remote. The local observer plugin was
reloaded; the hub itself was not reloaded, so this does not establish capture
continuity across a reconnect.

An attempted R7 native-decompile call count used an invalid instrumentation
target and is excluded. A corrected counter targets the Engine environment in
the R10/R11 code; no validated live decompile total is reported yet.

The R9 all-target active capture also failed finalization, without a client
connection error. The finalizer timed out while the journal writer was idle,
685 remote callbacks were in flight, and no GUI callbacks were in flight. No
final report was published. Recovery selected checkpoint sequence 163,577
covering 3,687 artifacts; the recovered output passed independent validation.
This identifies the state at the timeout but does not establish why those
remote callbacks remained active.

## R8/R9 journal and producer checks

The R8 synthetic flush test admitted 100 observations and wrote them in five
segments instead of 34, preserving all 100 sequence positions and their order.
R9 removes filesystem writes and waits from the Cobalt and GUI event producers.
The bounded admission queue holds up to 16,384 events with automatic producer
flush disabled; the main pump flushes at one-second intervals, in batches of at
most 256, and forces flushes at checkpoints and stop.

In a synthetic R9 stress check, all 10,000 callbacks were admitted without a
`writefile` or `task.wait` during production, then persisted in order across 40
segments. These are deterministic mock measurements, not live Cobalt workload
or client-responsiveness results.

R10 changes the raw callback path: admission reserves event sequence, time,
argument-type summary, and strong references without reading Instance
properties. The main pump resolves metadata and caller references. An immutable
cache preserves identity after destruction; unresolved rows carry no instance
ID, path, name, or caller. The raw-event and journal queues are each bounded at
16,384 entries, with pending and lost counts declared. During the R10 capture,
checkpoint sequence 138,417 covering 1,285 artifacts was written, recovered,
and independently validated while the capture was still running. This was a
real capture prefix and recovery operation, distinct from the synthetic
checkpoint tests. The client had already disconnected before R10 began, so
this evidence does not count as a connected in-game live capture.

## Completed R11 connected active run

R11 used the same R10 code and 315,258-byte bundle. The engine candidate
SHA-256 is
`0a4b068b2f029c0692b0eac962e70c8218a9ebb1203ac272864885ca2d057b93`; the
bundle SHA-256 is
`07222e5cafa097dbe7d0fc537211eb249bd2bc891be137e1dd06d80f6dc242fa`. A fresh
client was reconnected normally to the same place and version, with observation
instrumentation attached before capture. The all-target active run monitored
for 601.785335 seconds and took 662.270634 seconds overall.

The independent dataset validator returned no issues. Offline replay consumed
all 3,560 journal events, including 1,335 temporal relations. The official Luau
0.745 compiler accepted all 324/324 physical reconstructed source files.

| Measure | R11 result |
|---|---:|
| Discovered / attempted script instances | 936 / 936 (926 in initial pass, 10 new during monitoring) |
| Logical successful reconstructions / shared references / empty results | 655 / 331 / 281 |
| Failed / partial / inaccessible reconstructions | 0 / 0 / 0 |
| Unique instances / metadata records | 140,246 / 156,917 |
| Inspection visits / unchanged records | 2,117,293 / 1,960,384 |
| Structural deltas | 23,355: 7,453 adds, 9,160 updates, 6,742 removals |
| GUI states / transitions / controlled fixture activations | 119 / 124 / 119 |
| Cobalt observations / unresolved identities | 1,982 / 132 |
| Lost / pending / skipped remote observations | 0 / 0 / 0 |
| Checkpoints | 10 |
| Physical files / bytes including checkpoints | 3,895 / 256,894,586 |
| Ordinary artifact ledger bytes | 126,433,057 |

The manifest reports one metadata recovery and these partial reasons:
`index_serialization_recovered:remotes/index.json`, `read_or_write_errors`,
`record_serialization_recovered`, `remote_identity_unresolved`, and
`script_extraction_incomplete`. These remain visible despite the clean
independent validator result. The 281 empty reconstruction results and
unresolved remote identities are capture limits; the dataset is not described
as complete.

At stop, all 24 watched signal counts matched their pre-capture counts, all
nine fixture listener counts were restored, and the observer had one
subscription, one cleanup, and zero active subscriptions. Recovery of the
running prefix passed: checkpoint sequence 146,391 covered 2,502 artifacts and
produced no recovery warnings. The final checkpoint also passed recovery and
validation: checkpoint sequence 159,914 covered 3,698 artifacts with no
warnings.

Monitoring-weighted FPS was 325.44847; whole-run weighted FPS was 326.58084.
Frame p95, p99, and maximum were 5.99728 ms, 9.01238 ms, and 710.55877 ms.
Monitoring heap snapshots were 384,237 KiB initially, 424,987 KiB finally,
356,648 KiB minimum, and 596,537 KiB maximum. The fresh VM baseline was
12,290 KiB and includes environment initialization; it is not an isolated
exporter-allocation measurement. These are client-wide figures.

The controlled fixture completed 119 steps. Attempts to open ordinary game
menus did not open them, so this run does not validate gameplay menus or a live
respawn.

### Continuous capture through the UI

Continuous capture launched through the actual UI at 13:08:20 UTC and ran for
110.343109 seconds overall, including 33.022148 seconds of monitoring. Stop &
Save was clicked and observed; the UI ended with the expected stopped-and-saved
partial result.

The independent validator returned no issues, the event reader replayed all 552
events, and the official compiler accepted all 331/331 physical source files.

| Measure | UI Continuous result |
|---|---:|
| Unique instances / metadata records | 134,696 / 139,563 |
| Inspection visits / unchanged records | 171,602 / 32,039 |
| Structural deltas | 10,189: 5,547 adds, 35 updates, 4,607 removals |
| Discovered / attempted / native decompile calls | 939 (933 initially, 6 during monitoring) |
| Logical successes / physical source files / shared references / empty results | 665 / 331 / 334 / 274 |
| Failed / partial / inaccessible reconstructions | 0 / 0 / 0 |
| GUI states / transitions | 20 / 19 |
| Cobalt observations / unresolved identities | 533 / 22 |
| Retained / lost / queued observations | 533 / 0 / 0 |
| Checkpoints | 1 |
| Physical files / bytes including checkpoint | 1,784 / 119,508,270 |
| Ordinary artifact ledger bytes | 106,475,030 |

The UI run reported one metadata recovery and the same explicit partial reasons
as the R11 active run. Watched root listener counts matched before and after;
the observer had one subscription, one cleanup, zero active subscriptions,
and zero errors. Whole-run weighted FPS was 307.135633. Frame p95, p99, and
maximum were 6.692482 ms, 14.018144 ms, and 207.917288 ms. Heap snapshots were
27,016 KiB before and 503,193 KiB after; these include the client and are not
isolated exporter-allocation measurements.

The Full UI workflow started at 13:11:25 UTC using the same bundle and passed.
The final screen displayed the expected partial result. Its manifest recorded
the run's capture limits rather than claiming a complete export.

| Measure | Full UI result |
|---|---:|
| Total duration | 79.2228281 seconds |
| Discovered / attempted / native decompile calls | 931 |
| Logical successes / physical source files / shared references / empty results | 655 / 323 / 332 / 276 |
| Failed / partial / inaccessible reconstructions | 0 / 0 / 0 |
| Unique instances / metadata records | 131,673 / 133,876 |
| Inspection visits / unchanged records | 146,773 / 12,897 |
| Structural deltas | 4,126: 2,152 adds, 42 updates, 1,932 removals |
| GUI states / transitions | 10 / 9 |
| Cobalt observations / unresolved identities | 347 / 16 |
| Retained / lost / queued observations | 347 / 0 / 0 |
| Checkpoints | 1 |
| Physical files / bytes including checkpoint | 1,604 / 116,389,481 |
| Ordinary artifact ledger bytes | 103,571,657 |

The independent validator rechecked the export indexes, checksums, and reports
and returned no issues. The event reader replayed all 356 journal events, and
the official Luau 0.745 compiler accepted all 323/323 physical reconstructed
source files. All 24 watched root signal counts matched before and after. The
observer had one subscription, one cleanup, zero active subscriptions, and
zero errors; the connection watcher ended at zero.
Whole-run weighted FPS was 287.3560176. Frame p95, p99, and maximum were
8.98281 ms, 14.981685 ms, and 167.050153 ms. Heap snapshots were 30,034 KiB
before and 440,457 KiB after; these include the client and are not isolated
exporter-allocation measurements.

After stop, the R11 active and Continuous UI output inventories retained the
same file sizes and modification times during a two-to-three-minute observation
and after the next capture. No post-stop writes were observed in those checks.

### Bundle unload and reload

The exact public bundle was loaded without instrumentation. Unloading the old
handle destroyed it, cleared the handle, and removed its UI. Instrumentation
was restored and the test watcher disconnected. Loading a fresh 0.9.0 bundle,
then loading it again, returned the same handle without duplicating the UI; the
final view contained one window.

## Portability and observation limits

The serialization portability fallback functions audited in the current
candidate are unchanged from v0.8. One remote object's name/path required byte
escaping while its metadata record and index remained consistent. No
`serialization_unavailable` or `property_serialization_error` was reported;
this does not prove recovery of the original bytes or that escaping is
reversible. The partial result remains the accurate status.

The 132 unresolved remote identities in the R11 active run were all outgoing.
Their cause is unknown; no cause is inferred here. The 119 controlled fixture
activations occurred only in the headless R11 active run. Continuous UI and
Full UI recorded zero fixture activations. Ordinary game menus did not open in
the controlled attempts, and no live respawn was tested.

The live R11, Continuous UI, Full UI, and unload/reload lifecycle gates passed
on the same bundle. CI and publication outcomes will be recorded in the PR;
this report does not claim those release steps have passed.

R10 ran for 459.727 seconds and its stopped output passed independent
validation, but the client had already been disconnected before the run began.
The client had remained idle for about 20 minutes after a prior reconnect and
showed disconnected-client error 278. R10 was stopped by its own test
control; it did not establish a connected live capture pass. Do not count its
elapsed time or passing file validation as the ten-minute live acceptance.

## Failure evidence and remaining limits

The completed failure evidence is primarily synthetic: journal write and
readback failures, partial segment writes, queue overflow, reentrant arrivals
during flush, checkpoint snapshot verification, semantically damaged index
fallback, and finalization while callbacks are in flight. The completed local
reference dataset passed independent integrity validation and compilation.

No deliberate forced client disconnect or process termination has been
completed as a live v0.9 test. R7 encountered an actual client-not-responding
stop and callback-join timeout; R9 timed out with remote callbacks still in
flight. Their latest verified checkpoints recovered and passed validation, but
the underlying causes remain unknown. R10's stopped output validated, but it
was run on a client that had already disconnected and is excluded from live
acceptance. R11's active capture and Continuous UI output passed independent
validation, replay, and source compilation, with the partial reasons listed
above. The final checkpoint also recovered and validated. The Full UI gate
passed. The R2 endurance run passed validation and recovery but used an earlier
generation.
