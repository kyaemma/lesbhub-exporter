# Lesbhub Exporter

A public, read-only **Roblox client structure exporter** built for collecting datasets, comparing experiences and studying stable client-visible object structures. **V1 exports data only. There is no game detector.**

The UI is built with our [Lesbhub WindUI fork](https://github.com/kyaemma/lesbhub-ui). The capture engine is separate and can be tested independently.

## Status

**V0.3.0: streamlined WindUI and option presets.** The UI and engine are covered by Luau CLI mock tests and GitHub Actions; this UI update still needs a fresh Potassium session test. Earlier builds successfully exported large client snapshots. On a modded Criminality variant, a GUI-only capture completed with 28,418 records (7,173 asset references, 3.17s). The following full-client run reached 14,000 visited records but aborted on JSON encoding. V0.2.1 adds recursive chunk isolation and a record-level fallback to continue after malformed data; this recovery now passes a dedicated simulated Luau test but still needs a new live retest.

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
- **Live UI:** indeterminate activity animation while capturing (no fake percentage), exact visited/written stats formatted as K/M, service/pass, current path, files, assets, elapsed time and recent events. Animation stops on completion.
- **Map tab:** JSON geometry export (Workspace/Lighting/SoundService, BasePart position/CFrame/size, Model world pivot, materials and asset references). Optional separate native `saveinstance()` command like Infinite Yield, only after explicit opt-in and only if the executor supports it.
- **Fault tolerance:** JSON serialization errors are isolated to the offending records. Recovery keeps traversing and records a `partial` manifest status instead of aborting a whole service.
- **Performance:** iterative depth-first traversal, periodic `task.wait()`, small chunk files, cancellation and no global depth/object/total-byte/string-length cap.
- **Privacy:** skips other players' characters, chat GUI, `CoreGui` and script source. In v0.3.0 the three option presets **enable** TextBox.Text and StringValue.Value by default for local research; every capture requires acknowledging a private-data warning. Redaction of known player names and common token patterns remains best-effort.

## WindUI interface

The default preset is **Max informations**. All targets are selected. Open **Options → Advanced** only if you need to override a setting; it starts collapsed.

| Preset | Content | GUI snapshots | Traversal |
|---|---|---|---|
| **Max informations** | All allowlisted GUI and world properties, GUI text, asset IDs, TextBox.Text and StringValue.Value | 4 | Thorough, frequent yields |
| **Smart** | Same allowlisted property set, reduced GUI passes and balanced chunking | 3 | Balanced |
| **Fast** | Still all selected objects, GUI text, asset IDs, TextBox.Text and StringValue.Value, but fewer geometry/layout properties | 2 | Larger chunks, less property work |

All presets require **explicit confirmation before export**, explaining that the locally saved archive may contain private fields and must not be published without review. There is no network upload.

The **Capture** tab shows a moving, indeterminate activity bar and real live counts abbreviated as K/M. It intentionally does **not** claim to know the final percentage before traversal completes. Full export already captures GUI snapshots; **Capture GUI now** is an extra manual capture, not a required second step.

The **Settings** tab contains a configurable show/hide keybind (**RightShift** by default), a Hide button and an **Unload GUI** button. Unload destroys WindUI, disconnects the library's listeners and requests cancellation of any running capture (written chunks are retained). Clicking the window's built-in close-and-destroy action triggers the same cancellation cleanup.

If the exporter is already open, re-running the loader focuses the existing window rather than making duplicates. To load an updated UI version within the same session, use **Settings → Unload GUI** before re-injecting.

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
3. In **Options**, choose **Max informations**, **Smart** or **Fast**. Use **Advanced** only if you want to customize details. **Full export + GUI** includes guided GUI snapshots by default: open **STORE** and **SKINS** when prompted. **Capture GUI now** is optional.
4. Read and accept the **local-data privacy confirmation** before the capture starts. Then review the `manifest.json` (especially `status`, `partialReasons` and counts), and validate the directory:
   ```powershell
   python scripts/validate_export.py "C:\path\to\LesbhubExporter\criminality\criminality\variant-a\run-folder"
   ```
5. For map geometry, open the **Map** tab and choose **Export map geometry**. If `saveinstance()` exists, an optional **Save native Roblox place** button delegates to the executor; it may export more than the JSON allowlist, including scripts. Never publish an unreviewed native export.
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
- `StringValue.Value` and `TextBox.Text` are **off by default** and should remain off for general datasets; enabling either increases the risk of collecting sensitive information.
- The exporter may miss instances due to permissions, streaming, concurrent object destruction, cancellation or write errors. A `partial` status is informative, not proof of a game difference.
- Removing dataset caps does not remove physical resource limits: disk space, Roblox replication, intermittent changes and the executor can still constrain a capture. The animated progress bar is **activity**, not an estimated percentage; actual counts are shown alongside.
- **Map files:** The JSON geometry mode does not export Terrain voxel occupancy or binary asset contents. The native `saveinstance()` mode is controlled by the executor, has different privacy guarantees, and may not be implemented by Potassium. It never runs during normal JSON captures.
- **Encoding recovery:** If one object has a property that cannot be serialized, the exporter attempts to preserve its metadata and unaffected properties. In rare cases it may replace a property with a marker; check `partialReasons` and `errors` before using that capture as a dataset.

## References / credits

The `reference/` folder contains **Git submodules** (pinned upstream revisions), not vendored source, so licenses and provenance remain clear. See [reference/README.md](reference/README.md).

MIT License. See [LICENSE](LICENSE).
