# Optional Cobalt remote observation

[upio / Cobalt](https://gitlab.com/upio/cobalt) is a separate Roblox runtime network-inspection tool with documented incoming/outgoing monitoring. Its [plugin API](https://docs.mspaint.cc/cobalt/plugins/api) offers `Cobalt.Spy:InterceptExecutedCalls`, `Cobalt.UI:CreatePluginSettings` and `Cobalt:BindToUnload`.

Lesbhub Exporter deliberately keeps **two distinct data sources**:

1. **Standard Lesbhub export:** `remotes/<service>/` contains Roblox remote/bindable **inventory**: name, class, hierarchy, readable attributes/tags and a `RemoteInfo` object describing documented class capabilities. It does *not* observe actual invocations or recover server handlers.
2. **Optional Cobalt integration:** a separate plugin can record aggregate **observed activity**, including incoming/outgoing call counts and *types* of top-level arguments, without saving payload values.

This integration does not bundle Cobalt or install it for you. **It is opt-in and OFF by default.** It does not call `FireServer`, `InvokeServer`, block events, replay traffic, modify remote arguments, or upload data. Cobalt itself may support those features; this Lesbhub plugin intentionally does not use them.

## Setup

Install Cobalt using its own official instructions. Copy our file:

`integrations/cobalt/LesbhubRemoteObserver.luau`

to the **Cobalt plugin directory** for your Roblox executor:

`Cobalt/Plugins/LesbhubRemoteObserver.luau`

Cobalt creates `Cobalt/Plugins` in the executor workspace on first load. Restart/rescan its plugins if necessary.

Inside Cobalt's **Plugins → Lesbhub Remote Observer** settings:

- **Start observing:** explicitly registers a passive callback. You may now explore and operate the game normally.
- **Stop and save summary:** unregisters the callback and writes a local JSON summary.
- Unloading the plugin also unregisters the callback and attempts to save an active summary.

Output directory: `LesbhubExporter/cobalt-observations/cobalt-<timestamp>-<suffix>.json`.

The standalone summary stays outside capture chunks. In v0.7, enabling **Accept optional Cobalt observations** on the exporter also accepts observations from the separately started plugin into `remotes/observations.jsonl` in the active capture. The bridge uses the capture's global sequence and exact Instance identity, and links a known caller only when documented `info.Origin` is an actual known Instance. Similar names, paths or time windows alone do not establish a causal link. No raw arguments are saved.

## What is collected

The plugin records only:

- Remote class and conservatively normalized path, when it can be mapped to a selected client-visible Roblox service.
- Counts of *observed* incoming and outgoing calls.
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

### Why not automatically run Cobalt in Lesbhub?

Keeping these tools separate makes the standard client hierarchy exporter lightweight, read-only and portable across executors. There is no dependence on Cobalt's hook methods, no automatic network monitoring, and no accidental mixture of observed calls with static object properties.

**Reference:** [GitLab project](https://gitlab.com/upio/cobalt), [Cobalt README](https://gitlab.com/upio/cobalt/-/raw/main/README.md) and [plugin API](https://docs.mspaint.cc/cobalt/plugins/api). The Lesbhub plugin is original code written against the documented API, not a vendored copy of Cobalt.


## v0.7 validation boundary

The plugin and bridge protocol have mock coverage. A live client-local synthetic
fixture validates ordered bridge records, caller identity and exclusion of payload
values. Actual Cobalt incoming/outgoing traffic was not part of that synthetic
fixture and remains separately unverified. See [the evidence report](deep-export-validation.md).
