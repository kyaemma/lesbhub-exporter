# Lesbhub Exporter

A public, read-only **Roblox client structure exporter** built for collecting datasets, comparing experiences and studying stable client-visible object structures. **V1 exports data only. There is no game detector.**

The UI is built with our [Lesbhub WindUI fork](https://github.com/kyaemma/lesbhub-ui). The capture engine is separate and can be tested independently.

## Status

**v0.4.0: bilingual Home and floating activity journal.** Earlier Potassium captures have demonstrated large exports; the most recent screenshots show 223.7K objects, 44.7K asset references and a 60.3-second run (partial status, reason not yet confirmed from its manifest). This UI update is validated with Luau and Python automated tests, including a simulated floating journal. A visual Potassium retest is still needed.

## Run from a supported Roblox client environment

```luau
loadstring(game:HttpGet("https://raw.githubusercontent.com/kyaemma/lesbhub-exporter/main/dist/lesbhub-exporter.lua"))()
```

This loads the public exporter, which then downloads the UI code from **kyaemma/lesbhub-ui** (not upstream WindUI). The core requires `writefile` and `makefolder` for local exports. A GUI-compatible executor supporting `loadstring` and `game:HttpGet` is required for this entrypoint. **No data is uploaded to our API or a Discord webhook.**

For offline/manual distribution, use `dist/lesbhub-exporter.lua` (but the UI still requires our WindUI fork). The engine source is in `src/engine.lua`; it does not require the UI.

## Features

- **Targets:** ReplicatedStorage, ReplicatedFirst, StarterGui, PlayerGui, StarterPlayer, PlayerScripts, StarterPack, Workspace, Lighting, SoundService, Teams.
- **Targets:** multi-select searchable dropdown, with **all services selected by default**, plus one-click presets for all, GUI-only and game structures.
- **Properties:** names, classes, parent/child paths, depth, GUI labels/text/buttons, TextBox placeholders, visual styles, asset IDs, selected world properties and basic values.
- **Formats:** chunked JSON, JSONL or CSV; one **manifest.json** per capture, with settings, counts, status, errors, and partial reasons.
- **Full export + GUI:** one action for structures and guided GUI snapshots (4 passes by default in Max informations); optional extra **Capture GUI now** for an ad-hoc menu. Open menus yourself; the exporter does not simulate clicks, purchases or remote calls.
- **Floating activity log:** detached draggable journal, auto-opened for every export, with exact K/M counters, current path, recent events and copy control. No false percentage.
- **Map tab:** JSON geometry export (Workspace/Lighting/SoundService, BasePart position/CFrame/size, Model world pivot, materials and asset references). Optional separate native `saveinstance()` command like Infinite Yield, only after explicit opt-in and only if the executor supports it.
- **Fault tolerance:** JSON serialization errors are isolated to the offending records. Recovery keeps traversing and records a `partial` manifest status instead of aborting a whole service.
- **Performance:** iterative depth-first traversal, periodic `task.wait()`, small chunk files, cancellation and no global depth/object/total-byte/string-length cap.
- **Privacy:** skips other players' characters, chat GUI, `CoreGui` and script source. All UI presets **enable** TextBox.Text and StringValue.Value for local research; every capture requires acknowledging a private-data warning. Redaction of known player names and common token patterns remains best-effort.

## WindUI interface (v0.4)

The interface defaults to **English**. The new **Home** tab provides shortcuts to Full export + GUI, GUI-only capture, map export, the floating log, Targets and Options.

### Language and persistence

In **Settings → Language / Langue**, choose **Français** to switch the entire Lesbhub UI to French. The selected language is saved as `en` or `fr` to the executor-local file `LesbhubExporter/language.txt` using `writefile`. If `readfile` is supported, the next launch restores it. Switching languages reloads WindUI after the previous instance is destroyed and preserves current options/targets. Language changes are blocked while exporting.

### Capture modes and presets

All target services are selected initially. **Full export + GUI** always includes a local PlayerGui and StarterGui snapshot, plus additional guided passes if enabled. The other button **Capture GUI now** is strictly optional.

| Preset | Content | GUI snapshots | Work per step |
|---|---|---|---|
| Max information | All allowlisted properties including user input fields | 4 | Detailed |
| Smart | All allowlisted properties, balanced pace | 3 | Balanced |
| Fast | All object names/classes, GUI text, asset references and opted-in values, fewer visual/world properties | 2 | Faster |

The advanced settings remain collapsed by default. Every export confirms that local data may be sensitive, and no data is uploaded by the exporter.

### Floating journal

The **activity window** is an independently draggable, non-modal panel attached to the WindUI ScreenGui (not to the Capture tab). It automatically opens when an export starts **from Home, Capture or Map**, with a moving activity indicator, actual K/M counters, current service/path and recent events. Close and reopen it without interrupting the capture via **Open activity window** in Home, Capture, Map or Settings. The **Copy log** button uses an available clipboard API.

Settings also has a configurable show/hide keybind (initially **RightShift**), Hide and **Unload GUI**. Unload destroys both the main UI and floating window, disconnects UI listeners and requests cancellation of a running capture. The written files remain on disk.

**Native place backup:** Only the separate optional `saveinstance()` action invokes executor-native place saving. The executor may display `Decompiling scripts...`; the normal JSON exporter never decompiles scripts.

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

The timestamp and clock suffix are **run identifiers**, not signature material. Each object is a flat record with `name`, `className`, `path`, `parentPath`, `depth`, and `properties`. See [schema](docs/format.md).

**Note:** The default 200 records per file is **only chunking, not a limit**. The output may have thousands of files if the client can see many objects. JSON chunks are not monolithic. A later analyzer must process all chunks and treat GUI passes as separate snapshots.

**Assets:** Asset IDs/references are exported as properties (`Image`, `MeshId`, `Texture`, `SoundId`, templates, surface maps, etc.). **Images, sounds, meshes and other binary files are not downloaded.** An empty `workspace/lesbhub-exporter/assets` folder is not evidence of missing object exports; actual data is stored under `workspace/LesbhubExporter/.../`.

## Capture procedure

1. Start a Roblox session and launch the exporter. Enter a game label, category and variant.
2. Select target services and output format. Use GUI-only for targeted interface studies or full client for broad structural comparisons.
3. In **Options**, choose **Max information**, **Smart** or **Fast**. Use **Advanced** only if you want to customize details. **Full export + GUI** includes guided GUI snapshots by default: open **STORE** and **SKINS** when prompted. **Capture GUI now** is optional.
4. Read and accept the **local-data privacy confirmation** before the capture starts. Then review the `manifest.json` (especially `status`, `partialReasons` and counts), and validate the directory:
   ```powershell
   python scripts/validate_export.py "C:\path\to\LesbhubExporter\criminality\criminality\variant-a\run-folder"
   ```
5. For map geometry, open the **Map** tab and choose **Export map as JSON**. If `saveinstance()` exists, an optional **Save native Roblox place** button delegates to the executor; it may export more than the JSON allowlist, including scripts. Never publish an unreviewed native export.
6. Review text manually **before sharing**. The automatic redaction layer cannot guarantee removal of all personal or sensitive information.

## Development

```powershell
git clone --recurse-submodules https://github.com/kyaemma/lesbhub-exporter.git
cd lesbhub-exporter
python scripts/build.py
python scripts/build.py --check
python -m unittest discover -s tests
```

Edit `src/engine.lua` and `src/ui.lua`, then regenerate `dist/lesbhub-exporter.lua` with `python scripts/build.py`. CI checks bundle sync and validator tests.

To connect an **already existing empty Windows folder** `C:\dev\Lesbhub\lesbhub-exporter`, follow [local setup](docs/local-setup.md) rather than cloning over it.

## Limitations / security

- Roblox replication and StreamingEnabled determine visibility. ServerScriptService, ServerStorage, server-only scripts and private server state cannot be exported from the client.
- Script metadata can be listed; **no Source, bytecode, decompilation or privileged executor APIs are collected**.
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
