# V1 live test plan (manual; results pending)

An initial Potassium live launch produced a WindUI screenshot and the first 200-record ReplicatedStorage JSON chunk. Full exhaustive mode and dynamic GUI passes remain to be validated in a new live run. The following scenarios are the acceptance suite.

| ID | Scenario | Expected result |
|---|---|---|
| E01 | Empty baseplate, GUI-only preset | manifest + PlayerGui/StarterGui chunks where roots exist, no `Source` |
| E02 | ReplicatedStorage/Workspace on active Criminality variant | exhaustive capture, incremental writes, readable chunks, stable FPS |
| E03 | Open STORE and SKINS between guided GUI passes | distinct `-p1-`, `-p2-` and `-p3-` files, GUI text included where visible to client |
| E04 | Stop during a long Workspace traversal | `cancelled` status and partial manifest, previously written files preserved |
| E05 | Client dataset larger than 15,000 nodes and/or deeper than 28 levels | no global limit truncation; all reachable nodes enumerated until manual cancellation or actual runtime failure |
| E06 | Missing `writefile` / `makefolder` | clear error, no silent upload / fallback exfiltration |
| E07 | TextBox containing a typed personal message | no TextBox.Text in default export |
| E08 | Player names and characters | other characters omitted; known player aliases masked |
| E09 | JSON / JSONL / CSV output | each passes `validate_export.py` |
| E10 | StarterGui/PlayerGui not yet present | no crash; missing root reported |
| E11 | Repeat capture without `isfolder` API | folder behavior verified on target executor |
| E12 | Workspace StreamingEnabled | manifest marked partial even if traversal completed |
| E13 | WindUI fork not reachable | understandable UI load error; engine remains independently usable |
| E14 | Audit public release | no real-world names, chat transcripts or private game strings committed |
| E15 | Roblox asset-bearing instances | `Image`, `MeshId`, `Texture`, `SoundId` stored as references; no binary downloads claimed |
| E16 | Live WindUI progress | changing class/path, counters, files written and elapsed time visible without significant FPS spikes |
| E17 | Manual GUI-only capture | separate snapshot of currently opened STORE or SKINS via Capture GUI now |

For each run record: executor version, client FPS before/during/after, duration, number of visited/written objects, number of files, manifest status, and validation output. Avoid including player names in test logs.
