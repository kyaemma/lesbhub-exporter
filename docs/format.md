# Dataset format v1 (categorized layout v2)

The exporter writes one `manifest.json` and chunk files. The **record schema remains v1**, but there are two filesystem layouts:

- **Categorized v2 (default)**: `<category>/<service>/p<pass>-<chunk:04d>.<format>`
- **Flat v1 (compatibility)**: `<service>-p<pass>-<chunk:04d>.<format>`

For example, `scripts/PlayerGui/p1-0001.json` contains metadata for scripts nested inside PlayerGui, and `gui/PlayerGui/p1-0001.json` contains GUI instances. The dataset remains one logical tree: record `path` and `parentPath` are **never rewritten** to match the folders.

Categories are `scripts`, `gui`, `remotes`, `values`, `world`, `assets`, `structures` and `other`. An instance belongs to exactly one category. Folders are only created if the category contains records.

`chunk` starts at 1 per category/service/pass in v2 or service/pass in flat v1; files may exceed four digits. `pass` starts at 1 and increases for guided snapshots or continuous deltas.

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
  "category": "gui",
  "records": []
}
```

### JSONL

Each line is exactly one JSON object with the record schema. There is no top-level chunk metadata; service and pass come from the filename.

### CSV

Historical header: `path,parentPath,name,className,depth,properties_json`. V0.7 appends `instanceId,parentInstanceId,sequence,scriptId,operation,observedAtUtc`; the validator accepts both headers. The `properties_json` column contains a **JSON-encoded object** safely CSV-quoted. Each chunk has its own header. In categorized CSV/JSONL, the category is inferred from the folder name; JSON includes `category` in the chunk header, and JSON/JSONL records also carry it.

## Manifest

```json
{
  "schemaVersion": 1,
  "exporterVersion": "0.5.2",
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
  "layout": {"version": 2, "id": "categorized"},
  "categories": {
    "remotes": {"records": 120, "files": 1,
                "services": {"ReplicatedStorage": {"records": 120, "files": 1}}}
  },
  "errors": [],
  "settings": {"format": "json", "organizedOutput": true,
               "captureMode": "exhaustive", "chunkSize": 200, "guiPasses": 3},
  "privacy": {},
  "notes": []
}
```

`status` is `complete`, `partial`, `cancelled`, `stopped` (continuous mode stopped normally) or `recording` (provisional checkpoint). Even a `complete` export represents only a client-visible snapshot; never interpret it as every object in the experience.

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

## Continuous capture / event deltas (v0.5.0)

The initial scan writes ordinary **pass 1** files. During continuous monitoring, newly detected client objects, property changes and removals are emitted in later files using the same schema, with extra keys on each changed record:

```json
{
  "operation": "update",
  "observedAtUtc": "2026-11-23T15:10:00Z",
  "name": "MenuTitle", "className": "TextLabel",
  "path": "PlayerGui/Menu/MenuTitle",
  "parentPath": "PlayerGui/Menu", "depth": 2,
  "properties": {"Text": "New title"}
}
```

Operations are `add`, `update`, or `remove`. For removals `properties` is an empty JSON object. Always process chunks in pass order and chunk index order, and distinguish snapshots from deltas. Event-based structural records are written as pass 2; periodic rescans use later passes. A path is best-effort and is not guaranteed stable across duplicate sibling names or simultaneous moves.

During an active capture `manifest.json` is periodically overwritten with `status=recording`. Pressing **Stop & Save** writes the final manifest with `status=stopped`, `endedReason=user_stopped`, `settings.captureMode=continuous`, and counters `monitorCycles`, `deltaRecords`, `added`, `updated`, `removed`. Cancel instead yields `status=cancelled`.

Continuous mode does not infer a final object count, does not bypass Roblox streaming, and does not invoke game remotes or trigger UI actions. No specific game or menu names are assumed.


## Expanded client metadata (v0.6.0)

The allowlist includes typed/constrained values, basic camera/humanoid/joint/attachment/light properties, `Archivable` on Instances, and client-readable script flags when supported. Values are serialized by type, with `Instance` values represented as inert references such as:

```json
{"Value": {"kind": "InstanceRef", "className": "Part", "path": "Workspace/Map/Piece"}}
```

Links are only emitted when their targets have a safely identifiable path inside selected client-visible services. They do not dereference arbitrary references or bypass replication. Unavailable or unreadable fields remain absent, never fabricated.

Attributes and tags are included when available as `properties.Attributes` and `properties.Tags`, with potentially sensitive names/values filtered.

### Passive remote inventory

A `RemoteEvent` record may contain:

```json
{
  "properties": {
    "Archivable": true,
    "RemoteInfo": {
      "family": "remote",
      "boundary": "client_server",
      "style": "event",
      "asynchronous": true,
      "requiresResponse": false,
      "delivery": "reliable_ordered",
      "metadataSource": "roblox_class",
      "observedCalls": false,
      "parameterSchema": "unavailable"
    }
  }
}
```

`RemoteInfo` describes the Roblox **class**, not the game's actual usage, server-side handlers, call direction, or arguments. The main exporter **never invokes or spies on remotes**.

For optional call **observations** rather than class capabilities, see [Cobalt integration](cobalt-integration.md). Its local JSON summary is a separate dataset and intentionally stores *only* call counts, observed direction and argument types; it cannot reconstruct payload values.


## Deep Export v0.7 extension

See [the complete contract and migration plan](deep-export.md). Original metadata
chunk counts remain unchanged in meaning. Optional reconstructed `.luau` files and
readable script/remote/GUI indexes are separate sidecars, with `scriptExport` totals
in the manifest. Original `Script.Source` is never serialized into metadata.
Capture-local identity and global sequence are additive fields; paths/pass numbers
are insufficient for replay. Sidecars and files are validated by the updated
`scripts/validate_export.py`.

## Continuous Capture v0.9

`inspectionVersion = 2` identifies the v0.9 inspection extensions; the metadata
record schema remains version 1. Earlier inspection exports use
`inspectionVersion = 1` and GUI snapshots with `elements`. Readers must select
the appropriate GUI and journal format by version. Details, reconstruction and
recovery commands are in [Continuous Capture v0.9](continuous-v09.md).

Instance IDs are local to one capture. They distinguish simultaneously observed
instances, including siblings with the same name; neither paths nor names are
identities. V0.9 paths can be non-unique. Older capture paths can contain
unstable `~N` sibling suffixes, so path comparisons across captures need more
than a string match.
