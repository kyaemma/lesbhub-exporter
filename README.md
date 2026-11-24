# Lesbhub Exporter

A public, read-only **Roblox client structure and reconstructed-code exporter** built for collecting datasets, comparing experiences and studying stable client-visible object structures. **Deep Export v0.8 adds layered inspection reports, passive GUI state history, runtime availability and evidence-based relations. There is no game detector.**

The UI is built with our [Lesbhub WindUI fork](https://github.com/kyaemma/lesbhub-ui). The capture engine is separate and can be tested independently.

## Status

**v0.8.0: Deep Export inspection layers.** **Full export + GUI** remains the single guided action and saves reconstructed `.luau` by default. The latest validated candidate found 1,015 script objects, saved 714 reconstructed files (625 ModuleScripts and 89 LocalScripts), reported 301 empty results, and had zero failed, partial or inaccessible results. All 714 files compiled and the export passed integrity validation. It recorded 149,347 metadata records, 13 GUI states / 12 transitions and 2,172 Cobalt-observed incoming calls (zero outgoing). The capture took 74.09 seconds; FPS averaged 124.17 before and 74.89 during capture. This is a dynamic client sample, not a controlled comparison to the `main@0b61c6f` baseline (667 files / 941 script objects in 38.08 seconds). Reconstructed output is not original source or proof of semantic equivalence. See [v0.8 architecture](docs/deep-export-v08.md) and [live evidence and limitations](docs/deep-export-validation.md).

## Run from a supported Roblox client environment

```luau
loadstring(game:HttpGet("https://raw.githubusercontent.com/kyaemma/lesbhub-exporter/main/dist/lesbhub-exporter.lua"))()
```

This loads the public exporter, which then downloads the UI code from **kyaemma/lesbhub-ui** (not upstream WindUI). The core requires `writefile` and `makefolder` for local exports. A GUI-compatible executor supporting `loadstring` and `game:HttpGet` is required for this entrypoint. **No data is uploaded to our API or a Discord webhook.**

For offline/manual distribution, use `dist/lesbhub-exporter.lua` (but the UI still requires our WindUI fork). The engine source is in `src/engine.lua`; it does not require the UI.

## Features

- **Targets:** ReplicatedStorage, ReplicatedFirst, StarterGui, PlayerGui, StarterPlayer, PlayerScripts, StarterPack, Workspace, Lighting, SoundService, Teams.
- **Targets:** multi-select searchable dropdown, with **all services selected by default**, plus one-click presets for all, GUI-only and game structures.
- **Properties:** names, classes, hierarchy, GUI labels/layout, geometry, assets, constrained/typed values, Instance references when safely addressable, and additional joint/camera/light metadata.
- **Reconstructed code:** enabled by default (disable in Advanced for metadata-only exports), protected `decompile(instance)`, one intelligibly named `.luau` per accessible script, progressive local writes, exact readback, syntax checks, SHA-256 (or identified Adler-32 fallback), durable progress and per-script errors. Recovered code is never executed or required.
- **Scripts and remotes:** script `Archivable`/`Enabled`/`RunContext` when readable; remotes include `Archivable` and a static `RemoteInfo` class-capability descriptor, plus attributes/tags where available. These static metadata fields are separate from default reconstructed code and optional Cobalt traffic.
- **Optional Cobalt adapter:** the separately installed [passive observer plugin](docs/cobalt-integration.md) publishes a local adapter. When present, the exporter subscribes automatically during capture if observation is enabled (default in UI presets); it does not install or start Cobalt. It records observed direction and top-level argument **types**, not raw values.
- **Inspection report:** `report.json` and `report.md` summarize metadata, reconstructed scripts, GUI states, remote inventory/observations, runtime capabilities, evidence-backed relations and validation. Missing adapters and layers are marked unavailable; no observed activity is invented.
- **GUI state history:** distinct client-visible state projections and transitions are written under `gui/states/` and `gui/transitions.jsonl`. GUI activations are passive; the exporter never opens menus or clicks controls. Menus not visited remain unknown.
- **Source hints and relations:** a conservative lexical scan emits import/remote/GUI path candidates. Only unique complete paths with an appropriate class resolve; name-only, dynamic and ambiguous references remain unresolved. Static hints and temporal proximity do not establish runtime causality.
- **Runtime budget:** a cooperative 6 ms default work slice records yields and native-call overruns. It cannot preempt a blocking executor/native call. A default 6-second passive runtime window records additional observed GUI and remote activity when available.
- **Formats:** chunked JSON, JSONL or CSV; one **manifest.json** per capture, with settings, counts, status, errors, partial reasons, and category totals.
- **Organized datasets:** by default, records are grouped by type (`gui`, `scripts`, `remotes`, `world`, `values`, `assets`, `structures`, `other`) and by Roblox service. UI scripts live under `scripts/PlayerGui/`, while UI widgets go under `gui/PlayerGui/`. Full original paths and parent relationships are preserved. The legacy flat layout remains selectable in Dataset.
- **One-time full export + GUI:** one action for structures and guided GUI snapshots (4 passes by default in Max information). Open and close any UI elements during the guided passes; no game-specific menu names or automation.
- **Continuous capture:** starts with an exhaustive snapshot, then watches new/removed client instances and periodically compares GUI snapshots, saving only added, updated or removed records. Continues until **Stop & Save** or Cancel. A final GUI sweep is performed when stopped. No duration or global size cap.
- **Capture controls:** visually distinct tinted primary action buttons (blue for full export, teal for continuous, amber for Stop & Save, dark secondary actions, red for Cancel).
- **Floating activity log:** detached draggable journal, auto-opened for every export, with exact K/M counters, current path, recent events and copy control. No false percentage.
- **Map tab:** JSON geometry export (Workspace/Lighting/SoundService, BasePart position/CFrame/size, Model world pivot, materials and asset references). Optional separate native `saveinstance()` command like Infinite Yield, only after explicit opt-in and only if the executor supports it.
- **Fault tolerance:** JSON serialization errors are isolated to the offending records. Recovery keeps traversing and records a `partial` manifest status instead of aborting a whole service.
- **Performance:** iterative depth-first traversal, periodic `task.wait()`, small chunk files, cancellation and no global depth/object/total-byte/string-length cap.
- **Privacy:** character exclusions, chat GUI filtering, `CoreGui` filtering and name redaction are not an anonymization guarantee. A historical v0.8 four-pass UI run exposed a respawn-related exclusion gap; the latest candidate tracks actual player/character APIs, but join/respawn simulation is separate and does not prove that every live character record is excluded. Keep captures private and review them before any reuse or sharing. Reconstructed code is enabled by default, preserved without content redaction, and must stay private. All UI presets **enable** TextBox.Text and StringValue.Value for local research; every capture requires acknowledging a private-data warning.

## WindUI interface (v0.5.2)

The interface defaults to **English**. The new **Home** tab provides shortcuts to Full export + GUI, GUI-only capture, map export, the floating log, Targets and Options.

### File organization (v0.5.2)

**Dataset → File organization → Categorized folders** is selected by default. If an older analyzer expects `<Service>-p<pass>-<chunk>.json` files directly in the run folder, choose **Flat (legacy)** instead.

Categorized output:

```text
LesbhubExporter/<category>/<game>/<variant>/<capture-id>/
  manifest.json
  gui/PlayerGui/p1-0001.json
  gui/StarterGui/p1-0001.json
  scripts/PlayerGui/p1-0001.json
  scripts/ReplicatedStorage/p1-0001.json
  remotes/ReplicatedStorage/p1-0001.json
  values/ReplicatedStorage/p1-0001.json
  world/Workspace/p1-0001.json
  assets/ReplicatedStorage/p1-0001.json
  structures/ReplicatedStorage/p1-0001.json
```

Each object is stored in **one** type category; `path` and `parentPath` still reference the original Roblox hierarchy, not the filesystem. Not every category exists in every game. Script metadata chunks remain under `scripts/<service>/`; reconstructed code is written by default under `scripts/sources/<service>/`, with `scripts/index.json` and `report.md`. Original `Script.Source` is never read. The `assets` folder contains asset-bearing instances, not downloaded image/sound binaries. The `manifest.json` contains the per-category and per-service record/file counts. On v0.6+, most script and remote records also contain safe metadata instead of an empty `properties` object.

This layout works with full scans, guided GUI passes and continuous `add/update/remove` deltas. To validate old or new exports: `python scripts/validate_export.py <run-directory>`.

### Language and persistence

In **Settings → Language / Langue**, choose **Français** to switch the entire Lesbhub UI to French. The selected language is saved as `en` or `fr` to the executor-local file `LesbhubExporter/language.txt` using `writefile`. If `readfile` is supported, the next launch restores it. Switching languages reloads WindUI after the previous instance is destroyed and preserves current options/targets. Language changes are blocked while exporting.

### Capture modes and presets

All target services are selected initially. **Full export + GUI** always includes a local PlayerGui and StarterGui snapshot, plus additional guided passes if enabled. Attributes and tags are enabled in all presets, with dedicated Advanced toggles. The other button **Capture GUI now** is strictly optional.

| Preset | Content | GUI snapshots | Work per step |
|---|---|---|---|
| Max information | All allowlisted properties including user input fields | 4 | Detailed |
| Smart | All allowlisted properties, balanced pace | 3 | Balanced |
| Fast | All object names/classes, GUI text, asset references and opted-in values, fewer visual/world properties | 2 | Faster |

The advanced settings remain collapsed by default. Every export confirms that local data may be sensitive, and no data is uploaded by the exporter.

### Continuous mode (universal)

Click **Start continuous capture** in Home or Capture. The exporter first saves all selected client-visible objects (including PlayerGui and StarterGui). After that:
- `DescendantAdded`/`DescendantRemoving` events capture short-lived structural changes in the selected services, including Workspace.
- PlayerGui and StarterGui are periodically re-scanned (interval configurable in **Options → Advanced**) to detect new interfaces, changing labels and visibility.
- Other selected non-Workspace services are rechecked less frequently; Workspace uses events instead of constantly traversing the full map.
- Only **deltas** are written after the baseline: `operation=add`, `update` or `remove`. An unchanged object is not saved again.
- **Stop & Save** stops monitoring, does one final GUI comparison, flushes records and finalizes `manifest.json` with `status=stopped`. **Cancel capture** is different: it records an explicit cancellation.

The local manifest is periodically checkpointed with `status=recording`, for inspection if Roblox closes unexpectedly. The capture may grow while monitoring continues; keep sufficient free disk space. No game-specific GUI text, names, remotes or menus are hardcoded. The engine does not open game menus or invoke remotes. If a menu is not loaded into the client, open it yourself while monitoring.

A clean stop is needed for a definitive `stopped` manifest; forced process termination can leave only the last `recording` checkpoint. The feature is not guaranteed to observe objects that appear and disappear entirely while Roblox is suspended or before monitoring begins.

### Floating journal

The **activity window** is an independently draggable, non-modal panel attached to the WindUI ScreenGui (not to the Capture tab). It automatically opens when an export starts **from Home, Capture or Map**, with a moving activity indicator, actual K/M counters, current service/path and recent events. Close and reopen it without interrupting the capture via **Open activity window** in Home, Capture, Map or Settings. The **Copy log** button uses an available clipboard API.

Settings also has a configurable show/hide keybind (initially **RightShift**), Hide and **Unload GUI**. Unload destroys both the main UI and floating window, disconnects UI listeners and requests cancellation of a running capture. The written files remain on disk.

**Native place backup:** Only the separate optional `saveinstance()` action invokes executor-native place saving. The executor may display `Decompiling scripts...`; the standard capture also reconstructs accessible client code when its separate opt-in is enabled.

### Output directory

```text
LesbhubExporter/
  criminality/
    criminality/
      variant-a/
        20261123T140700Z-123456/
          manifest.json
          ReplicatedStorage-p1-0001.json
          ReplicatedStorage-p1-0002.json
          PlayerGui-p1-0001.json
          PlayerGui-p2-0001.json
```

The timestamp and clock suffix are **run identifiers**, not signature material. The sample below shows the legacy **Flat** layout; the categorized layout above is the new default. Each object is a flat record with `name`, `className`, `path`, `parentPath`, `depth`, and `properties`. See [schema](docs/format.md).

**Note:** The default 200 records per file is **only chunking, not a limit**. The output may have thousands of files if the client can see many objects. JSON chunks are not monolithic. A later analyzer must process all chunks and treat GUI passes as separate snapshots.

**Assets:** Asset IDs/references are exported as properties (`Image`, `MeshId`, `Texture`, `SoundId`, templates, surface maps, etc.). **Images, sounds, meshes and other binary files are not downloaded.** An empty `workspace/lesbhub-exporter/assets` folder is not evidence of missing object exports; actual data is stored under `workspace/LesbhubExporter/.../`.

## Capture procedure

1. Start a Roblox session and launch the exporter. Enter a game label, category and variant.
2. Select target services, output format, and **Categorized folders** (recommended) or **Flat (legacy)** in Dataset. Use GUI-only for targeted interface studies or full client for broad structural comparisons.
3. In **Options**, choose **Max information**, **Smart** or **Fast**. Use **Advanced** only if you want to customize details. **Full export + GUI** includes guided GUI snapshots, passive GUI activation observation and optional Cobalt observation when its adapter is present. You can manually open any in-game menu during capture; no special interface is assumed. For longer exploration, choose **Start continuous capture**, then press **Stop & Save** when finished.
4. Luau code extraction is enabled already; disable **Include reconstructed client script code** in Options → Advanced only for metadata-only exports. Inspect `report.md`/`report.json`, `scripts/index.json`, `scripts/sources/`, `gui/states/` and `relations/index.json`; Capture search can search indexes or reconstructed source, with explicit 50-result pages.
5. Read and accept the **local-data privacy confirmation** before the capture starts. Then review the `manifest.json` (especially `status`, `partialReasons` and counts), and validate the directory:
   ```powershell
   python scripts/validate_export.py "C:\path\to\LesbhubExporter\criminality\criminality\variant-a\run-folder"
   ```
6. For map geometry, open the **Map** tab and choose **Export map as JSON**. If `saveinstance()` exists, an optional **Save native Roblox place** button delegates to the executor; it may export more than the JSON allowlist, including scripts. Never publish an unreviewed native export.
7. Review text manually **before sharing**. The automatic redaction layer cannot guarantee removal of all personal or sensitive information.

## Development

```powershell
git clone --recurse-submodules https://github.com/kyaemma/lesbhub-exporter.git
cd lesbhub-exporter
python scripts/build.py
python scripts/build.py --check
python -m unittest discover -s tests
```

Edit the relevant `src/*.lua` module, then regenerate `dist/lesbhub-exporter.lua` with `python scripts/build.py`. CI checks bundle sync, Python validation, Luau compilation and synthetic module mocks.

To connect an **already existing empty Windows folder** `C:\dev\Lesbhub\lesbhub-exporter`, follow [local setup](docs/local-setup.md) rather than cloning over it.

## Limitations / security

- Roblox replication and StreamingEnabled determine visibility. ServerScriptService, ServerStorage, server-only scripts and private server state cannot be exported from the client.
- Original `Script.Source` and bytecode are never collected. The default-on pipeline uses the documented executor `decompile` function to obtain reconstructed pseudocode. Missing APIs, empty results, syntax failures, detected truncation and file failures are reported explicitly.
- Checksums cover bytes returned by the decompiler and saved reconstructed files, not original Roblox source. Earlier comparison tooling reported 104 source files, some truncated; this exporter has no artificial source-text cap, but that does not establish semantic correctness or equivalence.
- A scan is a **snapshot**. Not all dynamically created GUI will exist at capture time. Additional GUI passes can capture menus opened by the operator. Hidden but already-instantiated objects are exported even when `Visible = false`.
- Paths may contain unstable per-session indexes; direct PlaceId/GameId and player-dependent details should **not** become detection signatures.
- All **UI presets** enable `StringValue.Value` and `TextBox.Text` by default at the user's request; the headless engine still defaults them off. Review private exports before reuse.
- The exporter may miss instances due to permissions, streaming, concurrent object destruction, cancellation or write errors. A `partial` status is informative, not proof of a game difference.
- Removing dataset caps does not remove physical resource limits: disk space, Roblox replication, intermittent changes and the executor can still constrain a capture. The animated progress bar is **activity**, not an estimated percentage; actual counts are shown alongside.
- **Map files:** The JSON geometry mode does not export Terrain voxel occupancy or binary asset contents. The native `saveinstance()` mode is controlled by the executor, has different privacy guarantees, and may not be implemented by Potassium. It never runs during normal JSON captures.
- **Encoding recovery:** If one object has a property that cannot be serialized, the exporter attempts to preserve its metadata and unaffected properties. In rare cases it may replace a property with a marker; check `partialReasons` and `errors` before using that capture as a dataset.

## References / credits

The `reference/` folder contains **Git submodules** (pinned upstream revisions), not vendored source, so licenses and provenance remain clear. See [reference/README.md](reference/README.md).

MIT License. See [LICENSE](LICENSE).


## Deep Export v0.8

- [v0.8 architecture and report contract](docs/deep-export-v08.md): inspection layers, evidence rules, artifact ledger, validation and compatibility.
- [Output contract and migration](docs/deep-export.md): v0.5-v0.8 compatibility, code/index integrity, resume, identity and ordering.
- [Live validation](docs/deep-export-validation.md): v0.7 history, v0.8 full-client trial, controlled local fixtures, performance caveats and unverified cases.
- `scripts/probe_decompile.luau` is a development probe for three existing client scripts. It is not required by the shipped exporter.
- `scripts/probe_continuous.luau` creates and removes only its own client-local fixture. It does not activate existing game buttons or invoke a server remote.

The shipped bundle performs discovery, reconstruction and file writes autonomously. MCP is used only during development. Keep generated captures outside this public repository.

## Continuous capture v0.9 format contract

[English data and recovery guide](docs/continuous-v09.md) · [Guide en français](docs/continuous-v09.fr.md).

The v0.9 format keeps the full metadata baseline and records later structural changes as ordered `add`, `update` and `remove` rows keyed by capture-local `instanceId`. Paths and names remain descriptive fields; duplicate paths do not merge distinct instances. GUI state files use a baseline projection followed by `baseStateId`, `upserts` and `removes`, so each distinct projection is stored once while observed transitions retain their chronology.

Append-only event streams are stored in immutable batches under `journal/`; `journal/index.json` declares each stream's segments, event count and sequence range. Sequence numbers are global across metadata and event rows. Remote signatures are stored separately from occurrences, so repeated calls stay individually countable. Script source files may be shared by multiple logical script entries only when their verified bytes match. The validator keeps the v0.5-v0.8 formats intact and applies the new reconstruction checks only to `inspectionVersion: 2` exports.

Automated fixtures verify independent replay, repeated GUI transitions and remote occurrences, legacy validation, queue pressure and damaged-history detection. [Live validation and release evidence](docs/continuous-v09-validation.md) distinguishes completed Roblox measurements, interrupted candidates, synthetic tests and the final release gate.
