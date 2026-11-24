# Deep Export v0.8 inspection layers

Version 0.8 keeps the v0.7 metadata and reconstructed-script formats and adds
client metadata, passive GUI state history, runtime capability/observer status,
conservative source hints, identity-backed relations, artifact checksums and a
layered report. `inspectionVersion: 1` identifies the additive inspection
sidecars; the historical metadata schema remains v1.

## Capture pipeline

The modules are deliberately small and are composed by `scripts/build.py`:

- `client_metadata.lua` records public place identifiers/version, available
  executor APIs, streaming state and public product metadata when requested.
  It does not collect player names or session/private-server identifiers.
- `work_budget.lua` yields cooperatively after configured work slices and
  records slice/native-call timings. It cannot interrupt a blocking executor or
  Roblox-native call; an overrun is measurement, not preemption.
- `source_analysis.lua` tokenizes reconstructed Luau as text and emits
  candidate import, remote and GUI path hints with line/byte offsets. It never
  executes or requires captured code. A textual candidate does not prove the
  code ran or that the path is used at runtime.
- `gui_states.lua` projects a small allowlist of GUI state properties and writes
  distinct observed states plus transitions. It records operator activations
  passively and does not click controls. Only states observed during the capture
  are represented; unvisited or lazy menus remain unknown.
- `runtime_observer.lua` accepts an optional local Cobalt adapter. It stores
  observed call counts, direction and top-level argument types, plus bounded
  temporal associations. Raw argument values are not recorded. Temporal
  proximity is not causality. Cleanup failure is partial; dropped temporal or
  caller relations mark the relations layer partial and expose drop counters.
- `relations.lua` keeps a small catalog of scripts, GUI objects and remotes.
  It resolves a source hint only against one exact complete path and an
  appropriate class. Ambiguous, name-only, dynamic and unknown candidates stay
  unresolved. Direct serialized `InstanceRef` IDs may be checked against the
  broader metadata identity map without copying all records into the catalog.
  Parent links are structural; Cobalt links are observed associations; neither
  is a handler or causality claim.
- `report.lua` builds one reportVersion 2 object used for both `report.json` and
  `report.md`. Each layer has an explicit status, reason, counts, artifact paths
  and evidence. The script fidelity statement describes exact reconstructed
  output bytes and explicitly says original `Script.Source` is unavailable.

## Added files

```text
client.json
assets/index.json
relations/index.json
errors/index.json
artifacts/index.json
gui/states/index.json
gui/states/state000001.json
gui/transitions.jsonl
report.json
report.md
```

`artifacts/index.json` lists artifact-relative paths, byte lengths, checksum
algorithm and checksum. The ledger does not recursively hash itself or the final
manifest/report; those would create a self-reference. Source-file checksums
continue to cover exact bytes returned by `decompile`, with a separate checksum
for the saved file including its provenance header. Neither digest proves
equivalence to an original Roblox source file.

The report layer statuses use `complete`, `partial`, `unavailable`, `disabled`
and `not_observed`. For example, an unavailable observer adapter is different
from an attached adapter that saw no calls. A report with a global partial
capture may still have a complete script layer if its script counters are all
successful; layer status is based on that layer's evidence. Observer cleanup
failure and bounded relation-buffer drops remain explicit partial results.

## Validation and compatibility

### Character scope and privacy

The operator's own character may be included in client-visible records, with
known player-name strings redacted on a best-effort basis. Character filtering
uses current Player/Character identity and aliases; it is not a general
anonymization pass. A v0.8 four-pass UI run exposed respawn-created character
records escaping the earlier exclusion tracking. The final candidate tracks
`PlayerAdded`, `CharacterAdded`, known aliases and `GetPlayerFromCharacter` at
record observation, and checked the actual APIs. Join/respawn simulation remains
separate; this is not a general privacy audit or anonymization guarantee. Keep
captures private and review before reuse or sharing.

`validate_export.py` continues to accept v0.5-v0.7 fixtures. For v0.8 it
validates the artifact ledger, report/layer consistency, state and transition
sidecars, sequence uniqueness and the existing reconstructed-source checksums.
Old records without `inspectionVersion` do not acquire new requirements.

The standard checks run in CI:

```powershell
python scripts/build.py --check
python -m unittest discover -s tests -v
```

Luau CI compiles each source module and the generated bundle, then runs synthetic
mocks for the capture engine, writer, UI, Cobalt adapter, work budget, source
analysis, GUI states, runtime observer, relations, report, resume, search and
capture cancellation. Mock builders inline modules so tests do not need Roblox
or executor APIs. Fixtures contain only synthetic records and code; live
captures stay outside Git.
