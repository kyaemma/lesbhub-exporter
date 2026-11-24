# Deep Export validation — 2026-11-24

This report contains metrics and original test code descriptions only. No third-party
game source, player identity, private server identifier or captured payload is published.
Full datasets remain in the local Potassium workspace outside this repository.

## Preparation and API audit

The Windows checkout was clean at `25ef5e7` and 93 commits behind origin/main.
It was fetched and fast-forwarded to `62f5bbf` without reset, clean or forced writes.
Work proceeded on `feat/deep-export-v07`. Issue #1 and its complete comment list
(empty at inspection) were read before implementation.

Potassium documented and exposed decompile, readfile, writefile, appendfile, isfile,
makefolder, loadstring, cloneref and compareinstances in the connected live client.
The audit also found getscripts/getloadedmodules/bytecode APIs; the product does
not require those or use arbitrary require/bytecode extraction. API signatures were
checked against the local Potassium documentation, including decompile, file APIs,
crypt.hash and signals. The Cobalt callback contract was checked against the
[official plugin API](https://docs.mspaint.cc/cobalt/plugins/api) and local reference
CallInfo (`Origin`), rather than guessed.

## Three-script proof before generalization

The passive probe selected exact client Instances under PlayerScripts, wrote files
locally, verified byte-for-byte readback and compiled the returned code without
executing it:

| Script | Class | Returned bytes | Lines | Result |
|---|---|---:|---:|---|
| SoundClient | LocalScript | 22,569 | 653 | verified, compiles |
| PlayerModule | ModuleScript | 585 | 27 | verified, compiles |
| ControlModule | ModuleScript | 17,990 | 519 | verified, compiles |

The completed proof ran in about 0.062 seconds in that session. An initial probe
harness returned assert's extra argument as a fourth table element; this harness
bug was fixed and all three were rerun through the completed probe before broad
extraction. It did not affect the three verified file contents.

## Standard capture in the live client

First the integrated engine exported all 44 PlayerScripts scripts: 44 verified,
compilable `.luau` files in 1.39 seconds. The private output passed the Python
dataset validator. The largest returned script was XIIX: **336,430 bytes and
7,534 lines**, read back exactly and compiled. The older crimconexport XIIX header
reported only lines 1–2000 of 7525; that is a quality comparison, not proof that
these different captures have identical original code.

A subsequent full-client run found 941 script objects, saved 669 files and reported
272 empty results in 32.39 seconds. It exposed an invalid UTF-8 remote name in the
readable index, and unnecessary full-index rewrites. The index now preserves such
bytes as explicit `~XX` escapes; durable per-script JSONL checkpoints avoid rewriting
the complete index on every successful file.

The corrected full-client run captured **132,043 metadata records** and:

| Script outcome | Count |
|---|---:|
| Discovered / attempted | 940 |
| Verified successful `.luau` files | 669 |
| Successful ModuleScript | 584 |
| Successful LocalScript | 85 |
| Empty Script results | 270 |
| Empty ModuleScript result | 1 |
| Failed / partial code results | 0 / 0 |
| Source files including headers | 3,968,567 bytes |

Every one of the 669 files also passed an independent Windows **official Luau
0.745 compiler** invocation. The complete directory passed `validate_export.py`,
including source and file checksums. No reconstructed game code was executed.

A same-session resume then skipped all 669 verified files without replacing their
contents. Five previously empty instances had disappeared and were reported as
inaccessible; 266 remained empty. The resume took 6.44 seconds in that session.

The dataset status is deliberately **partial**: empty extraction results and metadata
encoding recoveries remain explicit. Observed reasons were
`script_extraction_incomplete`, `record_serialization_recovered`,
`read_or_write_errors`, and `index_serialization_recovered:remotes/index.json`.
The remote index was present and valid after recovery. These results establish
working extraction for accessible client scripts, not access to server-only code.

### Performance observation

The corrected run took **24.72 seconds**. A two-second RenderStepped baseline was
approximately 437 FPS; during capture the measured average was 220 FPS and the
largest sampled frame interval was 47.5 ms. Lua heap readings were approximately
29,030 KiB before and 56,843 KiB immediately after. Those are Lua heap readings,
not total Roblox process memory or evidence of a persistent leak. GC timing,
game activity, existing tools and changing objects affect the measurements. The
two runs were not a controlled performance benchmark, and the FPS reduction is
material even though reconstruction and writes completed.

## Controlled local continuous fixture

The test creates only its own ScreenGui and inert client-local Instances under
StarterGui, then removes the fixture. It does not activate existing game UI, purchase
anything or invoke a server remote.

- A NumberValue created and destroyed before baseline visitation survived as add
  then remove, preserving Value=17 and its original Instance ID.
- Two same-name instances kept separate IDs; replacing one at the same path created
  a third ID. Renaming the other kept its original ID and produced an update.
- All 76 metadata observations and two diagnostic events had unique global sequence
  values, covering 1–78 in that fixture.
- One synthetic button signal was recorded. One **synthetic bridge protocol call**
  using an inert local RemoteEvent recorded a known caller and an argument type;
  the injected secret value was absent from the output. This was not real network
  activity and is not claimed as a live Cobalt integration test.
- The clean stop used `status=stopped`; before/after DescendantAdded connection
  counts were both two (pre-existing listeners), and the bridge was removed.
- The resulting dataset passed the Python validator.

The candidate v0.7 WindUI dashboard also loaded in Potassium and reported engine
v0.7.0. Automated UI tests exercise language, persistence, controls, privacy
consent, Stop & Save and unload/reload. At that validation point, real Cobalt
traffic was still unverified; the v0.8 trials below provide live incoming/outgoing
observations. Live visual polish across all display sizes remains unverified.

## Automated checks

Python fixtures cover historical JSON/JSONL/CSV layouts, sidecars, long synthetic
code, checksums, deleted/corrupt/unindexed files, invalid paths, duplicate IDs and
truncation status. Luau mocks cover protected extraction, empty/error results,
long output, progressive writes, naming collisions, unavailable APIs, resume/skip,
disk/readback failures, cancellation and unsafe paths. The engine mock also covers
short events during the baseline, homonyms, replacements, rename identity and cleanup.

Only synthetic code is committed in fixtures. Native executor blocking behavior,
decompiler semantic correctness, every game variant and complete Cobalt coverage
have not been universally validated. Real Cobalt traffic was sampled in the v0.8
trials below, but those counts do not prove complete coverage.

## First v0.8 full-client trial

The v0.8 trial recorded aggregate counts only; no game source, place name, player
identity, server identifier, source payload or Cobalt argument value is included in
this repository. The capture itself remains in the local executor workspace.

| Metric | Observed |
|---|---:|
| Script objects discovered | 1,138 |
| Reconstructed `.luau` files saved | 811 |
| Empty decompiler results | 327 |
| Failed results | 0 |
| Distinct observed GUI states | 46 |
| GUI transitions | 45 |
| Cobalt-observed calls | 3,726 |
| Capture duration | 105.76 seconds |
| FPS before / during capture | 152 / 61.5 |

The capture passed integrity validation, and all 811 saved files compiled with
the official Luau compiler. Against the available baseline files, all 667 were
present; 662 reconstructed bodies were strictly byte-identical. Five bodies
differed while retaining the same byte count, consistent with decompiler output
variation. Therefore, not all file/source hashes matched across runs.

The call count represents observations received by the adapter, not unique
network requests. The observer records direction and top-level argument types;
raw values are excluded. GUI states only cover the states reached and observed
during this capture. Other menus and lazy interfaces remain unknown.

The reference comparison for `main@0b61c6f` was 667 saved files from 941 script
objects in 38.08 seconds. These two measurements are **not a controlled or direct
performance comparison**: the v0.8 trial ran in a different environment with
Cobalt and other UI activity enabled, and recorded FPS fell from 152 to 61.5.
The older v0.7 runs already described above also had different counts and timings;
do not merge their denominators or durations. The FPS drop is material and needs
controlled follow-up before drawing conclusions about the 6 ms cooperative work
budget.

A separate v0.7 trial with Cobalt present saved 668 files from 1,014 script
objects in 44.37 seconds. This is a closer environment comparison for observer
overhead, but still has different discovered objects and does not establish a
controlled performance delta. See the final candidate section below for the
latest validated v0.8 result.

An earlier comparison tool exposed 104 source files, with some files appearing
truncated. The current decompiler writer applies no artificial source-text cap and
checks that saved bytes match the bytes it returned. That comparison does not
prove the reconstructed output is complete, semantically equivalent, or the
original Roblox source.

## Earlier optimized v0.8 capture

This completed capture preceded the final candidate below and is retained as
historical evidence. It is not the latest validated result.

A later run, after the engine's folder cache and event batching changes, completed
integrity validation and compiled every saved script with the official Luau
compiler:

| Metric | Observed |
|---|---:|
| Script objects discovered | 1,010 |
| Reconstructed `.luau` files saved / compiled | 719 / 719 |
| Empty / failed results | 291 / 0 |
| Metadata records | 150,079 |
| Metadata bytes | 97,156,262 |
| Metadata chunks | 852 |
| Delta records | 16,921 |
| Distinct observed GUI states / transitions | 20 / 20 |
| Discovered GUI buttons / activations | 748 / 0 |
| Cobalt observations | 1,850 incoming / 0 outgoing |
| Capture duration | 68.87 seconds |
| FPS before / during capture | 186.7 / 81.1 |
| Frame p95 / p99 / maximum | 0.023023 / 0.041523 / 0.22264 seconds |
| Lua heap before / after | 443,510 / 532,784 KiB |

No existing live button was activated by the exporter. The local synthetic GUI
fixture exercised five unique observed states, including creation and removal;
its test handlers are synchronous and do not model replication or server latency.
The number of observed states depends on which UI was open during the capture;
the remaining menus are unknown. The 1,850/0 counts are calls received by the
Cobalt adapter, not unique network requests or proof that no outgoing call
occurred. Callers are represented by `callerInstanceId` when a known Origin
Instance is available, never by serializing a caller object.

All 668 files from the Cobalt-present v0.7 comparison capture were present in this
v0.8 output. Its v0.7 run recorded 134,709 metadata records, about 84 MB, 512
chunks, 44.37 seconds and FPS 183.45 before / 107.40 during capture. The newer
v0.8 run recorded more visible records, bytes and chunks. Although Cobalt was
present in both, changed client contents and other runtime activity prevent
treating this as a controlled performance comparison.

Artifact profiling counted 4,314 write calls and 29.037 seconds in the earlier
trial, compared with 880 calls and 5.749 seconds in the optimized run. Capture
enrichment and the dynamic client contents changed between those runs; this is
not a controlled percentage improvement. The local helper
[`benchmark_client.luau`](../scripts/benchmark_client.luau) records aggregate FPS,
frame intervals, elapsed time and pre/post Lua heap readings for future same-client
comparisons. Heap snapshots do not prove a retained-memory limit or leak.

The optimized run took 68.87 seconds, with FPS averaging 186.7 before and 81.1
during the capture. The frame maximum was 0.22264 seconds, which is material.
The work budget is cooperative and cannot preempt native calls; the heap increased
by the reported snapshot. These observations warrant further controlled profiling,
not a claim of a performance ceiling or bounded retained memory.

## Final candidate live validation

The final candidate was captured after the character-tracking, caller-resolution
and temporal-relation changes. The local export passed `validate_export.py`, and
all 714 saved source files compiled with the official Luau CLI.

| Metric | Observed |
|---|---:|
| Script objects discovered | 1,015 |
| Reconstructed sources saved | 714 (625 ModuleScripts, 89 LocalScripts) |
| Empty / failed / partial / inaccessible / pending | 301 / 0 / 0 / 0 / 0 |
| Source bytes / files including headers | 3,997,840 / 4,140,774 |
| Largest reconstructed script | 7,534 lines |
| Metadata records / unique instances | 149,347 / 142,407 |
| Metadata bytes / chunks / deltas | 96,767,208 / 862 / 15,337 |
| Artifact ledger files / bytes | 1,902 / 147,398,476 |
| GUI states / transitions | 13 / 12 |
| Discovered remote/bindable inventory entries | 1,187 (includes removed flags) |
| Cobalt-observed calls | 2,172 incoming / 0 outgoing |
| Observation rows with scriptId / callerInstanceId | 1,780 / 2,159 |
| Caller/relation overflow drops | 0 / 0 |
| Relations resolved / unresolved / ambiguous | 24,766 / 1,572 / 2 |
| Temporal associations | 132, all `causal=false` |
| Capture duration | 74.08694 seconds |
| FPS before / during capture | 124.1743 / 74.8882 |
| Frame p95 / p99 / maximum | 0.02408575 / 0.04265136 / 0.20780085 seconds |
| Lua heap before / after | 459,974 / 581,937 KiB |

All 668 files from the Cobalt-present v0.7 comparison capture were present in
the new output by path and class. Of those, 663 reconstructed bodies were strictly
byte-identical and five varied. This is a cross-capture file comparison, not
evidence that the same Instance was present; debug ID and class agreement alone
do not establish identity across changing clients.

The 747 discovered GUI buttons included one `Activated` record from the synthetic
local fixture only. The fixture produced five distinct states across its own
creation/removal scenario. A UI automation attempt also clicked the fixture, but
the observed count discrepancy means this is not evidence that a human activated
a live game button. Do not claim operator interaction based on that event.

Listeners remained balanced across capture: global `PlayerAdded` was 16 before
and after, `PlayerGui.DescendantAdded` was 5/5 and local-character `CharacterAdded`
was 33/33. The capture reported character tracking enabled and checked the actual
player/character APIs. Join and respawn simulation is separate; these checks do
not prove that every live player character or respawn is excluded, and do not
constitute an anonymization guarantee. Keep exports private and review before reuse.

This candidate was read back byte-for-byte from the local output file. A prior
MCP stdout rendering lost some Unicode glyphs in displayed text; local file bytes
were verified and the display artifact was not a bundle modification.

### Same-session resume and source search

The final candidate was resumed in the same executor session. All 714 verified
source files were skipped without decompilation or modification. Of the initial
301 empty entries, 270 remained empty and 31 became inaccessible because their
original client instances had disappeared; failed, partial and pending counters
remained zero. Observation logs remained frozen during resume and a two-second
post-stop check. The report marked relations partial with an explicit stale-source
reason rather than leaving prior links as current. The resumed dataset passed
`validate_export.py`.

An exact `require` source search returned 455 matches; its paginated page returned
three entries with valid source-line locations. Search was literal and limited to
reconstructed local files.

### Historical long UI workflow run — not a quality or privacy benchmark

An earlier full **Max** export was started through the real UI, accepted its
confirmation and continued through four guided passes to the result screen. This
proves the unified UI-to-report workflow reached completion; its dataset is not
privacy validated and is not a safe-to-share example. The run exposed respawned
character source trees outside the then-current exclusion tracking. No captured
source or player data from it is in this repository.

Its historical counters were 1,448 script objects, 1,009 successful sources,
439 empty results, 0 failures, 123 GUI states, 124 transitions and 754 discovered
buttons. The one `Activated` count came only from the synthetic local fixture;
it is not proof of a human action on a live game UI. It recorded 9,245 Cobalt
observations, but direction was not verified. Capture time was 240.168 seconds;
FPS averaged 93.274 before / 73.132 during capture. The run used a busier client,
four Max passes and `yieldEvery=45`; its totals and performance are historical,
not completeness, privacy, quality or controlled performance claims.

## v0.8 automated contract checks

The v0.8 synthetic checks cover client metadata, cooperative work slices,
candidate-only source analysis, observed GUI states and transitions, runtime
adapter availability, exact-path/InstanceRef relationships, report v2 layers,
artifact checksums, cancellation, resume/search and backward validation fixtures.
CI compiles the modules and generated bundle, then runs capture, writer, UI,
Cobalt, budget, analysis, GUI, runtime, relation, report, resume, search and
cancellation mocks with the official Luau CLI. These tests do not
establish behavior for every game, executor, Cobalt configuration or unvisited UI.
