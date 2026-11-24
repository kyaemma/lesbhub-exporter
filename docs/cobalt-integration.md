# Optional Cobalt remote observation

[upio / Cobalt](https://gitlab.com/upio/cobalt) is a separate Roblox runtime network-inspection tool with documented incoming/outgoing monitoring. Its [plugin API](https://docs.mspaint.cc/cobalt/plugins/api) offers `Cobalt.Spy:InterceptExecutedCalls`, `Cobalt.UI:CreatePluginSettings` and `Cobalt:BindToUnload`.

Lesbhub Exporter deliberately keeps **two distinct data sources**:

1. **Standard Lesbhub export:** `remotes/<service>/` contains Roblox remote/bindable **inventory**: name, class, hierarchy, readable attributes/tags and a `RemoteInfo` object describing documented class capabilities. It does *not* observe actual invocations or recover server handlers.
2. **Optional Cobalt integration:** a separate plugin can record aggregate **observed activity**, including incoming/outgoing call counts and *types* of top-level arguments, without saving payload values.

This integration does not bundle, install or automatically start Cobalt. Install the adapter plugin separately. When it is present and **Accept optional Cobalt observations** is enabled in Lesbhub (enabled by default in the UI presets), the exporter subscribes automatically for the duration of a capture. This only enables the passive adapter subscription; the plugin's separate standalone-summary recorder remains off until you press **Start observing**. Neither path calls `FireServer`/`InvokeServer`, blocks or replays traffic, modifies arguments, or uploads data.

## Setup

Install Cobalt using its own official instructions. Copy our file:

`integrations/cobalt/LesbhubRemoteObserver.luau`

to the **Cobalt plugin directory** for your Roblox executor:

`Cobalt/Plugins/LesbhubRemoteObserver.luau`

Cobalt creates `Cobalt/Plugins` in the executor workspace on first load. Restart/rescan its plugins if necessary.

Inside Cobalt's **Plugins → Lesbhub Remote Observer** settings:

- **Start observing:** explicitly registers the plugin's standalone-summary callback. Use this only when you also want a separate Cobalt summary file. Lesbhub captures subscribe automatically when an exporter run starts, whether or not this button was pressed.
- **Stop and save summary:** unregisters the callback and writes a local JSON summary.
- Unloading the plugin also unregisters the callback and attempts to save an active summary.

Output directory: `LesbhubExporter/cobalt-observations/cobalt-<timestamp>-<suffix>.json`.

The standalone summary stays outside capture chunks. In v0.8, the exporter adapter subscription writes observations into `remotes/observations.jsonl` and aggregates counts/types in the remote index while a capture is active. It reads caller identity as `callerInstanceId` only when documented `info.Origin` resolves to an actual known Instance. It does not retain or serialize the caller Instance itself. A later identity lookup may enrich a caller association; matching names, source text or time windows do not establish causality. Temporal relations are explicitly marked `causal=false`. No raw arguments are saved.

In v0.9 (`inspectionVersion: 2`), occurrences use immutable segments declared in
`journal/index.json`; `remotes/signatures.json` holds shared type definitions.
The exporter callback only admits metadata to a bounded queue. It does not
read Instance properties, resolve hierarchy, write files or wait for a journal
flush inside the Cobalt interceptor. Sequence and time are reserved on admission;
unresolved identities remain explicit typed occurrences. The capture loop performs ordinary flushes on a one-second
cadence and forces them at checkpoints and finalization. Availability, skipped
observations, overflow and cleanup remain explicit in the report. See the
[continuous format](continuous-v09.md) and [validation evidence](continuous-v09-validation.md).

## What is collected

The plugin records only:

- Remote class and conservatively normalized path, when it can be mapped to a selected client-visible Roblox service.
- Counts of *observed* incoming and outgoing calls.
- A capture-local caller Instance ID when a documented origin Instance is known; no caller object, source text or payload.
- First and last observation timestamps and internal sequence counters.
- The **count and types** of top-level parameters, e.g. `number,string,table`, with frequency counts.

It intentionally does **not** record string contents, numbers, tables, nested argument values, player identifiers, origin source paths, function bodies, captured remote handlers or replayable calls. An argument type signature does not prove the full expected parameter schema or server behavior.

The plugin skips paths containing unusual characters or possible user information. It records how many were skipped. It may miss calls because of executor compatibility, Actor boundaries, plugin start time or Cobalt's own coverage; a count of zero does **not** prove the remote was unused.

## Output example

```json
{
  "schemaVersion": 1,
  "source": "cobalt_plugin",
  "captureMode": "passive_summary",
  "game": {"placeId": 123, "gameId": 456},
  "stats": {"observedCalls": 2, "remoteInstances": 1, "pathsSkipped": 0},
  "remotes": [
    {
      "id": 1,
      "path": "ReplicatedStorage/Events/Example",
      "className": "RemoteEvent",
      "incoming": 1,
      "outgoing": 1,
      "firstSequence": 1,
      "lastSequence": 2,
      "signatures": [
        {"count": 1, "direction": "Outgoing",
         "argumentCount": 2, "argumentTypes": ["string", "number"]}
      ]
    }
  ]
}
```

## Risks and limitations

Cobalt itself uses executor interception capabilities. Run it only in environments where you have permission to observe traffic, and use its upstream compatibility guidance. The optional plugin does not grant access to server-only objects or hidden remote implementations.

A complete Cobalt log may contain sensitive values; **do not confuse it with this sanitized summary**. If you inspect Cobalt's full logs directly, review them before saving or sharing.

### Adapter lifecycle

The exporter never launches Cobalt or installs its plugin. The optional plugin publishes a small adapter in the executor environment; the exporter subscribes to it only when the user-enabled observation option is true and a capture is running. If Cobalt or the adapter is missing, the report says the observation layer is unavailable. An attached observer with zero calls is reported as `not_observed`, not as proof that a remote is unused. A normal capture stop closes the subscription; plugin unload or subscription errors are reported as an interrupted/partial observation when calls had already been received.

**Reference:** [GitLab project](https://gitlab.com/upio/cobalt), [Cobalt README](https://gitlab.com/upio/cobalt/-/raw/main/README.md) and [plugin API](https://docs.mspaint.cc/cobalt/plugins/api). The Lesbhub plugin is original code written against the documented API, not a vendored copy of Cobalt.


## Live validation

An eight-second live probe received 201 incoming and 36 outgoing calls. Separate
full capture trials also recorded real Cobalt observations: the first v0.8 run
received 3,726 calls; a later optimized run received 1,850 incoming and zero
outgoing; the final candidate received 2,172 incoming and zero outgoing. These
are counts received by the adapter, not unique network requests or proof of
complete coverage. The Cobalt API, plugin start time, executor compatibility and
game activity affect which calls are visible. No payload values are included in
the reports. See [the aggregate evidence and limitations](deep-export-validation.md).

The local synthetic fixture separately validates an inert RemoteEvent and
synthetic known caller without activating real game UI or sending a request. Its
fixture handlers are synchronous; it does not model server latency, replication,
or live game behavior.

## Local benchmark helper

[`scripts/benchmark_client.luau`](../scripts/benchmark_client.luau) is a development-only
helper. Load the desired bundled engine first; it runs a short FPS baseline,
performs one capture, and reports elapsed time, frame percentiles, maximum frame
interval and Lua heap readings. It writes aggregate performance metrics beside
the capture, outside `artifacts/index.json`. Run comparable variants in the same
client session when possible, and record any other UI/tools that are active.
Game state, garbage collection, Cobalt and other client activity remain
confounders. A before/after `gcinfo()` reading does not prove a retained-memory
limit or leak.
