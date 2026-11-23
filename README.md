# Lesbhub Exporter

A public, read-only **Roblox client structure exporter** built for collecting datasets, comparing experiences and studying stable client-visible object structures. **V1 exports data only. There is no game detector.**

The UI is built with our [Lesbhub WindUI fork](https://github.com/kyaemma/lesbhub-ui). The capture engine is separate and can be tested independently.

## Status

**V0.2.1: full GUI export verified in Potassium; large full-client export still under validation.** On a modded Criminality variant, a GUI-only capture completed with 28,418 records (7,173 asset references, 3.17s). The following full-client run reached 14,000 visited records but aborted on JSON encoding. V0.2.1 adds recursive chunk isolation and a record-level fallback to continue after malformed data; this recovery now passes a dedicated simulated Luau test but still needs a new live retest.

## Run from a supported Roblox client environment

```luau
loadstring(game:HttpGet("https://raw.githubusercontent.com/kyaemma/lesbhub-exporter/main/dist/lesbhub-exporter.lua"))()
```

This loads the public exporter, which then downloads the UI code from **kyaemma/lesbhub-ui** (not upstream WindUI). The core requires `writefile` and `makefolder` for local exports. A GUI-compatible executor supporting `loadstring` and `game:HttpGet` is required for this entrypoint. **No data is uploaded to our API or a Discord webhook.**

For offline/manual distribution, use `dist/lesbhub-exporter.lua` (but the UI still requires our WindUI fork). The engine source is in `src/engine.lua`; it does not require the UI.

## Features

- **Targets:** ReplicatedStorage, ReplicatedFirst, StarterGui, PlayerGui, StarterPlayer, PlayerScripts, StarterPack, Workspace, Lighting, SoundService, Teams.
- **Presets:** full client **selected by default**, GUI only, structures only; individual target toggles in WindUI.
- **Properties:** names, classes, parent/child paths, depth, GUI labels/text/buttons, TextBox placeholders, visual styles, asset IDs, selected world properties and basic values.
- **Formats:** chunked JSON, JSONL or CSV; one **manifest.json** per capture, with settings, counts, status, errors, and partial reasons.
- **Dynamic GUI:** guided multi-pass capture (3 passes by default); optional immediate **Capture GUI now** button. Open menus yourself so the exporter never simulates clicks, purchases or remote calls.
- **Live UI:** current service/pass, class, path, visited/discovered/written objects, pending nodes, file writes, elapsed time, asset-reference counter and last events. The progress scale expands automatically, beyond 100k if necessary; no artificial upper bound.
- **Map tab:** JSON geometry export (Workspace/Lighting/SoundService, BasePart position/CFrame/size, Model world pivot, materials and asset references). Optional separate native `saveinstance()` command like Infinite Yield, only after explicit opt-in and only if the executor supports it.
- **Fault tolerance:** JSON serialization errors are isolated to the offending records. Recovery keeps traversing and records a `partial` manifest status instead of aborting a whole service.
- **Performance:** iterative depth-first traversal, periodic `task.wait()`, small chunk files, cancellation and no global depth/object/total-byte/string-length cap.
- **Privacy:** skips other players' characters, chat GUI, `CoreGui`, script source, and potentially sensitive textbox/strings by default. Redacts known player names and common contact/token patterns on a best-effort basis.

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
3. For dynamic menus, keep **Guided dynamic-menu snapshots** enabled. After the initial scan, open **STORE** during the next interval and **SKINS** during the one after that. Or open a menu first, then press **Capture GUI now** to take a separate snapshot immediately.
4. Review the `manifest.json` (especially `status`, `partialReasons` and counts), and validate the directory:
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
- Removing dataset caps does not remove physical resource limits: disk space, Roblox replication, intermittent changes and the executor can still constrain a capture. The adaptive progress scale is **not a known final object count** and expands as more descendants are discovered.
- **Map files:** The JSON geometry mode does not export Terrain voxel occupancy or binary asset contents. The native `saveinstance()` mode is controlled by the executor, has different privacy guarantees, and may not be implemented by Potassium. It never runs during normal JSON captures.
- **Encoding recovery:** If one object has a property that cannot be serialized, the exporter attempts to preserve its metadata and unaffected properties. In rare cases it may replace a property with a marker; check `partialReasons` and `errors` before using that capture as a dataset.

## References / credits

The `reference/` folder contains **Git submodules** (pinned upstream revisions), not vendored source, so licenses and provenance remain clear. See [reference/README.md](reference/README.md).

MIT License. See [LICENSE](LICENSE).
