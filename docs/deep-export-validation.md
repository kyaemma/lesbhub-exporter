# Deep Export v0.7 validation — 2026-11-24

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

The candidate WindUI dashboard also loaded in Potassium and reported engine v0.7.0.
Automated UI tests exercise language, persistence, controls, privacy consent,
Stop & Save and unload/reload. Live visual polish across all display sizes and real
Cobalt traffic observation still require separate validation.

## Automated checks

Python fixtures cover historical JSON/JSONL/CSV layouts, sidecars, long synthetic
code, checksums, deleted/corrupt/unindexed files, invalid paths, duplicate IDs and
truncation status. Luau mocks cover protected extraction, empty/error results,
long output, progressive writes, naming collisions, unavailable APIs, resume/skip,
disk/readback failures, cancellation and unsafe paths. The engine mock also covers
short events during the baseline, homonyms, replacements, rename identity and cleanup.

Only synthetic code is committed in fixtures. Native executor blocking behavior,
decompiler semantic correctness, every game variant and real incoming/outgoing
Cobalt traffic have not been universally validated.
