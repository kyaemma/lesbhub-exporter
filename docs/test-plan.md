# V1 live test plan (manual; results pending)

No Potassium or Roblox runtime test has been completed as part of this initial repository implementation. The following scenarios are the acceptance suite.

| ID | Scenario | Expected result |
|---|---|---|
| E01 | Empty baseplate, GUI-only preset | manifest + PlayerGui/StarterGui chunks where roots exist, no `Source` |
| E02 | ReplicatedStorage/Workspace on active Criminality variant | bounded capture, no unresponsive client, readable chunks |
| E03 | Open/close a menu between first and second GUI pass | distinct `-p1-` and `-p2-` files, manifest `passes` = 2 |
| E04 | Stop during a long Workspace traversal | `cancelled` status and partial manifest, previously written files preserved |
| E05 | Max objects or byte budget reached | `partial` status with explicit reason |
| E06 | Missing `writefile` / `makefolder` | clear error, no silent upload / fallback exfiltration |
| E07 | TextBox containing a typed personal message | no TextBox.Text in default export |
| E08 | Player names and characters | other characters omitted; known player aliases masked |
| E09 | JSON / JSONL / CSV output | each passes `validate_export.py` |
| E10 | StarterGui/PlayerGui not yet present | no crash; missing root reported |
| E11 | Repeat capture without `isfolder` API | folder behavior verified on target executor |
| E12 | Workspace StreamingEnabled | manifest marked partial even if traversal completed |
| E13 | WindUI fork not reachable | understandable UI load error; engine remains independently usable |
| E14 | Audit public release | no real-world names, chat transcripts or private game strings committed |

For each run record: executor version, client FPS before/during/after, total time, max objects, number of files, manifest status, and validation output. Avoid including player names in test logs.
