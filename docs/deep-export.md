# Deep Export v0.7 contract and migration

The runtime exporter is autonomous. Potassium MCP was used to develop and test it,
not to perform the product's discovery, reconstruction or file writes.

Reconstructed client Luau extraction is **enabled by default** in both the engine
and all three UI presets. Disable **Options → Advanced → Include reconstructed client script code**
for a metadata-only capture. Standard selected-service traversal
discovers LocalScript, ModuleScript and replicated Script objects. The writer
calls the documented `decompile(instance)` under `pcall`; it never requires a
captured module, executes reconstructed code, reads original `Script.Source`,
invokes a server remote or uploads the capture.

## Files and integrity

```text
<capture>/
  manifest.json
  report.md
  report.json
  scripts/index.json
  scripts/progress.jsonl
  scripts/sources/PlayerScripts/s42_MenuController.luau
  remotes/index.json
  gui/index.json
  gui/actions.jsonl                 # when activations are observed
  remotes/observations.jsonl        # when the optional bridge receives calls
  <category>/<service>/p1-0001.json # original metadata layout
```

Source filenames combine a capture-local script ID with a sanitized, bounded
human-readable name. Names containing Windows-invalid characters, reserved device
names, empty names or duplicate siblings cannot overwrite another script: the ID
prefix is unique. Deep Roblox hierarchies are represented in the index rather
than duplicated as arbitrarily long Windows directories. Source filenames are
bounded; **code text has no line or byte cap**.

Each index entry contains `scriptId`, `instanceId`, `className`, `name`, `service`,
`robloxPath`, `latestObservedPath`, `debugId`, `outputPath`, `status`, `error`,
`method`, `byteLength`, `lineCount`, `checksum`, `checksumAlgorithm`, syntax-check
results and truncation assessment. `robloxPath` is the first normalized observed
path; later renames update `latestObservedPath`. GUI nesting is structural
context, not evidence that the script handles any particular interaction.

Statuses are `success`, `failed`, `inaccessible`, `empty` or `partial`. Pending
entries can exist in an interrupted checkpoint but not a finalized capture.
Disabled or absent reconstruction APIs produce explicit inaccessible/skipped
entries. Empty/comment-only decompiler results do not create fake source files.
An inaccessible replicated Script object is not evidence of accessible server code.

The `.luau` file adds a provenance comment header and preserves the exact returned
code bytes after that header. It does not redact, reformat, normalize newlines or
send code through JSON/model chunks. `byteLength` and `checksum` cover the returned
code; `fileByteLength` and `fileChecksum` include the header. `headerByteLength`
locates the original returned bytes. `lineCount` is newline count plus one, including
a trailing empty line. SHA-256 is used if supported; the explicitly identified
portable fallback is Adler-32, an integrity check rather than a cryptographic hash.

`appendfile`, when available, writes code in 64 KiB steps. Otherwise `writefile`
writes the complete file. Both paths require `isfile` and exact `readfile` equality
before success. `loadstring` **compiles only**; its returned function is discarded.
Syntax failure, invalid UTF-8 or explicit truncation markers preserve the output
as partial. A lack of a truncation marker cannot prove original-source completeness
or semantic equivalence. Native decompiler calls may block; cancellation is checked
before/after extraction and between writes, but cannot forcibly preempt such a call.

The index is checkpointed before extraction; subsequent per-script results are
appended to `scripts/progress.jsonl`, then consolidated in the final index. An
executor without append support checkpoints the full index. Final `scriptExport`
counters distinguish discovered, attempted, succeeded, failed, empty, inaccessible,
partial and skipped. Code file totals are separate from historical metadata totals.

## Resume and navigation

```luau
local result, err = LesbhubExporterEngine.resumeScripts(captureFolder, nil, control)
```

Resume is limited to the **same Roblox/executor session**. It merges durable
progress into the index, skips verified successful files and retries other entries
only against the original DebugId and class in the selected service trees. A local
runtime token and place/game checks prevent guessing equivalent instances after
reconnection. It does not recapture metadata or assume a matching name is identity.
All paths remain under `LesbhubExporter/`; unsafe roots and script IDs are rejected.

The Capture tab searches the script, remote and GUI indexes by literal name/path
and displays up to 50 matches in the activity journal. It also copies the local
report. The report and index list output paths and every failed/partial extraction.

## Continuous identity and optional diagnostics

Every new record carries capture-local `instanceId`, `parentInstanceId`, `sequence`
and a UTC timestamp. Identity is based on Instance references; cloned script/remote
wrappers are reconciled with DebugId plus `compareinstances` when available. Names
and paths are context, never identity. A rename preserves the ID; a replacement at
the same path receives a new ID.

Listeners attach **before** the baseline traversal. Event handlers capture the
record and properties immediately, instead of retaining a reference to inspect
after destruction. Event and rescan signatures share one identity ledger. A single
global sequence orders records and optional diagnostic events across service/pass
files. Read in sequence order, not directory or pass order. Repeated guided GUI
snapshots remain separate observations, not deduplicated objects.

**Observe GUI activations** registers only passive `Activated` callbacks on
discovered buttons; the product never clicks buttons or initiates purchases.
Operator activation logs and latest GUI states are separate from structural chunks.

**Accept optional Cobalt observations** enables a local bridge for the separately
started observer plugin. It records direction, global sequence, timestamp, argument
count and top-level types. Raw values, nested payloads and secrets are not recorded.
`info.Origin` must be an actual known Instance before an observed caller link is
added; strings, matching names and source-text guesses do not create causal links.
Without Cobalt, inventory remains useful and no activity is invented. See
[Cobalt setup](cobalt-integration.md).

All listeners and the bridge are cleaned on stop, cancel and capture exceptions.
Very short objects before subscription, client suspension, missing replication and
executor failures remain physical limits. Raw payload export is deliberately not
provided; more detailed test diagnostics currently mean caller identities and
ordered type signatures.

## Compatibility with v0.5/v0.6

- Metadata `schemaVersion: 1` and categorized layout v2 / flat layout v1 remain.
- New fields are additive. Never interpret v0.5/v0.6 paths as stable IDs.
- `stats.written/files/bytes`, service totals and category totals still describe
  metadata chunks only. Sidecars and `.luau` counts are under `scriptExport`.
- CSV v0.7 appends `instanceId,parentInstanceId,sequence,scriptId,operation,observedAtUtc`
  after the historical six columns. Strict external CSV readers must accept the
  extended header. The bundled validator accepts both old and extended headers.
- Use the updated validator for v0.7 sidecars; old validators may flag them as
  unknown files. Existing v0.5/v0.6 fixtures remain accepted.
- `privacy.excludesScriptSource` refers to original Source. The separate
  `privacy.includesReconstructedCode` flag discloses the opt-in pseudocode.
- Keep captures private and outside Git. Source reconstruction does not make
  third-party game code suitable for publication in this repository.
