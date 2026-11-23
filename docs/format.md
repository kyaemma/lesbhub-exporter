# Dataset format v1

The exporter writes one `manifest.json` and one or more chunk files per service and capture pass.

```text
<Service>-p<pass>-<chunk:04d>.<format>
```

`Service` is selected from the exporter's fixed target list; `pass` starts at `1` and may increase (guided GUI snapshots, up to the configured count). `chunk` starts at 1 per service/pass, padded to at least four digits (e.g. `0001`, `10000`).

## Record

```json
{
  "name": "PlayButton",
  "className": "TextButton",
  "path": "PlayerGui/MainMenu/PlayButton",
  "parentPath": "PlayerGui/MainMenu",
  "depth": 2,
  "properties": {
    "Text": "PLAY",
    "Visible": true,
    "Size": {"xScale": 0.3, "xOffset": 0, "yScale": 0.1, "yOffset": 0}
  }
}
```

- `path`: normalized path from the selected service root, using `/` rather than Roblox's `GetFullName()`. Duplicate sibling names may receive `~2` etc. **These indexes are not necessarily stable**.
- `parentPath`: empty string for root records.
- `name`: best-effort redacted; names can contain unstable identifiers. Analyze only after normalizing.
- `properties`: allowlisted property reads. Missing keys mean disabled, unsupported, unavailable, or nonserializable—not automatically false.

### JSON

Each `.json` chunk contains:

```json
{
  "schemaVersion": 1,
  "service": "PlayerGui",
  "pass": 1,
  "records": []
}
```

### JSONL

Each line is exactly one JSON object with the record schema. There is no top-level chunk metadata; service and pass come from the filename.

### CSV

Header: `path,parentPath,name,className,depth,properties_json`. The `properties_json` column contains a **JSON-encoded object** safely CSV-quoted. Each chunk has its own header.

## Manifest

```json
{
  "schemaVersion": 1,
  "exporterVersion": "0.3.0",
  "clientOnly": true,
  "game": {
    "label": "Criminality",
    "category": "Criminality",
    "variant": "Variant A",
    "placeId": 123,
    "gameId": 456
  },
  "capturedAtUtc": "2026-11-23T14:07:00Z",
  "status": "partial",
  "partialReasons": ["workspace_streaming_enabled"],
  "stats": {
    "visited": 1000, "written": 1000, "files": 5, "bytes": 430000,
    "redactions": 12, "errors": 0, "assetReferences": 120, "classCounts": {}
  },
  "services": {
    "ReplicatedStorage": {"visited": 1000, "records": 1000, "files": 5, "passes": 1}
  },
  "errors": [],
  "settings": {"format": "json", "captureMode": "exhaustive", "chunkSize": 200, "guiPasses": 3},
  "privacy": {},
  "notes": []
}
```

`status` is `complete`, `partial`, or `cancelled`. Even a `complete` export represents only a client-visible snapshot; never interpret it as every object in the experience.

## Guidelines for later signature research (not implemented here)

Do not include `placeId`, `gameId`, capture timestamp, volatile object indexes, player names, raw chat, local text input, or session IDs in signatures. Distinguish absent structures caused by streaming from true absence, and compare both positive and negative controls to avoid false positives.

## Compatibility

A Rust/Python analyzer can read chunks independently, aggregate per service/pass and validate counts against the manifest. Do not merge passes 1, 2, 3, etc. as if they were a single tree: they are separate snapshots. The progress counter is not a fixed total. `stats.files` counts data chunks, not the manifest.

**No completeness cap:** `settings.captureMode = "exhaustive"` means no fixed maximum number of objects, depth, total export bytes or GUI text length; the number of files may be large. Roblox streaming and read restrictions still apply. `stats.assetReferences` counts asset-valued properties included in exported records; it does not indicate downloaded binary asset files.

## Map geometry in JSON

The **Export map geometry** button uses the same versioned chunk schema and exports `Workspace`, `Lighting` and `SoundService`. `BasePart` records include `Position` (Vector3), `CFrame` (12 numeric components: translation + rotation matrix), `Orientation`, `Size`, material and asset references when readable. `Model.WorldPivot` is included where accessible. No voxel data or external binaries are reconstructed.

## Encoding recovery

If a chunk cannot be JSON-encoded, it is recursively subdivided until the problematic record can be isolated. The engine first attempts property-level recovery, then uses placeholder values if necessary. Capture status becomes `partial` and `partialReasons` can contain `record_serialization_recovered` or `property_serialization_error`. A recovery means records were preserved, **not** that every property was preserved without change.

A native place file from `saveinstance()` is a separate executor-controlled format and **does not** follow this JSON schema or the JSON privacy filtering.
