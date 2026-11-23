# V1 live test plan (manual; results pending)

Potassium live results (modded Criminality variant, 2026-11-23): GUI-only capture completed with 28,418 objects and 7,173 asset references in 3.17 seconds. The next full-client export was partial at 14,000 visited, 13,800 written, with `json_encode_failed:ReplicatedStorage`. V0.2.1 includes tested recovery; live retest pending. The following scenarios are the acceptance suite.

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

| E18 | More than 100,000 discovered objects | progress range expands automatically; no object budget or artificial completion |
| E19 | Faulty UTF-8 property while scanning | record is recovered, other objects still exported, manifest `partial` explains modification |
| E20 | Map geometry JSON | CFrame/Position/Size collected from reachable parts; no voxel/binary data claimed |
| E21 | Native place export supported or unsupported | disabled until explicit operator opt-in; unsupported executors return clear message |
| E22 | Targets selector all selected by default | multi-select works, no per-target toggle spam |
| E23 | Presets Max informations / Smart / Fast | all three enable privacy-sensitive values, all include GUI passes by default |
| E24 | Options → Advanced | collapsed by default, settings remain overrideable |
| E25 | Full export single action | includes selected PlayerGui/StarterGui and guided GUI passes without second button |
| E26 | Data privacy confirmation | no scan until user explicitly accepts warning, cancellation leaves no new capture |
| E27 | Progress and counters | activity bar never claims false completion, counts compact K/M, animation stops at end |
| E28 | Keybind | RightShift initially, new binding toggles once and ignores input while editing |
| E29 | Unload GUI | destroys UI, clears handle/listeners and requests capture cancellation |

For each run record: executor version, client FPS before/during/after, duration, number of visited/written objects, number of files, manifest status, and validation output. Avoid including player names in test logs.

