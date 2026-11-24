# Exporter acceptance plan and historical live results

For completed v0.7 code extraction and controlled continuous tests, see [Deep Export validation](deep-export-validation.md). The notes below include historical results; they are not a claim that every scenario has been retested live.

Potassium live results (modded Criminality variant, 2026-11-23): GUI-only capture completed with 28,418 objects and 7,173 asset references in 3.17 seconds. The next full-client export was partial at 14,000 visited, 13,800 written, with `json_encode_failed:ReplicatedStorage`. V0.2.1 added encoding recovery. Later screenshots show 223.7K records, 44.7K asset references and a 60.3-second run (partial status; cause needs manifest review). The original v0.5 continuous mode had not been live-validated at that time; v0.7 now has a controlled local live fixture. The following scenarios are the acceptance suite.

| ID | Scenario | Expected result |
|---|---|---|
| E01 | Empty baseplate, GUI-only preset | manifest + PlayerGui/StarterGui chunks where roots exist, no `Source` |
| E02 | ReplicatedStorage/Workspace on active Criminality variant | exhaustive capture, incremental writes, readable chunks, stable FPS |
| E03 | Open any game-specific GUI during guided passes | distinct pass files, with new interface paths and text where visible to the client |
| E04 | Stop during a long Workspace traversal | `cancelled` status and partial manifest, previously written files preserved |
| E05 | Client dataset larger than 15,000 nodes and/or deeper than 28 levels | no global limit truncation; all reachable nodes enumerated until manual cancellation or actual runtime failure |
| E06 | Missing `writefile` / `makefolder` | clear error, no silent upload / fallback exfiltration |
| E07 | TextBox containing a typed personal message | Headless engine default omits it; UI presets include it only after privacy acknowledgment |
| E08 | Player names and characters | other characters omitted; known player aliases masked |
| E09 | JSON / JSONL / CSV output | each passes `validate_export.py` |
| E10 | StarterGui/PlayerGui not yet present | no crash; missing root reported |
| E11 | Repeat capture without `isfolder` API | folder behavior verified on target executor |
| E12 | Workspace StreamingEnabled | manifest marked partial even if traversal completed |
| E13 | WindUI fork not reachable | understandable UI load error; engine remains independently usable |
| E14 | Audit public release | no real-world names, chat transcripts or private game strings committed |
| E15 | Roblox asset-bearing instances | `Image`, `MeshId`, `Texture`, `SoundId` stored as references; no binary downloads claimed |
| E16 | Detached log activity | changing path and real counters visible from Home/Capture/Map with no FPS spikes |
| E17 | Manual GUI-only capture | separate snapshot of any currently open interface via Capture GUI now |
| E18 | More than 100,000 discovered objects | indeterminate progress and exact compact K/M counters without a fake completion percentage |
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
| E29 | Unload GUI | destroys main UI and floating log, clears handle/listeners and requests capture cancellation |
| E30 | First launch without language file | navigation and UI start in English |
| E31 | Switch language in Settings | French is saved in LesbhubExporter/language.txt and restored on relaunch |
| E32 | Change language while capturing | blocked, without stopping capture |
| E33 | Home shortcuts | Full/GUI/Map, log and settings navigation available |
| E34 | Map capture | floating log opens automatically and remains accessible |
| E35 | WindUI modal button layout | long button labels stack within dialog, never overflow |
| E36 | Native saveinstance() | native saving remains separate; standard captures reconstruct code by default and allow explicit opt-out |
| E37 | Continuous capture on unrelated game | no hardcoded names or menu assumptions; starts with initial snapshot |
| E38 | Open new client menu during monitoring | new GUI nodes appear in delta files with `operation=add` |
| E39 | Modify existing GUI Text/Visible | subsequent delta has `operation=update`; unchanged records omitted |
| E40 | Remove GUI node during monitoring | delta tombstone has `operation=remove` |
| E41 | Stop & Save between GUI intervals | final GUI sweep captures last changes; status becomes `stopped` and manifest is complete |
| E42 | Cancel during monitoring | status is `cancelled`, not `stopped`; buffered chunks remain |
| E43 | Long recording / forced disconnect | periodically updated manifest uses `status=recording`; no indefinite in-memory accumulation of entire event history |
| E44 | Capture UI colors | start/full/stop/cancel visually distinct from informational sections |
| E45 | No game-specific prompts | no references to specific experience interfaces in source or UI |
| E46 | Categorized output default | scripts/PlayerGui, gui/PlayerGui, remotes/ReplicatedStorage and world/Workspace are distinct when populated |
| E47 | UI script metadata | LocalScript under GUI saved to scripts/PlayerGui with unchanged path, no Source |
| E48 | Categorized manifests | category and service file/record counts match all chunks |
| E49 | Flat legacy output | original filenames preserved, no collision when multiple categories share service/pass |
| E50 | Categorized JSON/JSONL/CSV validator | recursive verification accepts each format and rejects a wrong category or missing chunk |
| E51 | Continuous categorized capture | add/update/remove records retain their type folder; final Stop & Save manifest reconciles |

For each run record: executor version, client FPS before/during/after, duration, number of visited/written objects, number of files, manifest status, and validation output. Avoid including player names in test logs.


| E52 | Remote object from ReplicatedStorage | `RemoteInfo` class metadata, no fabricated invocation count or raw arguments |
| E53 | Script metadata | `Archivable` and supported `Enabled`/RunContext flags, no Source |
| E54 | Constrained/typed values | `IntConstrainedValue` includes numeric Value/MinValue/MaxValue where readable |
| E55 | Attributes and tags | client-visible GetAttributes/GetTags values collected, sensitive keys filtered |
| E56 | Optional Cobalt plugin | OFF by default, explicit start/stop, only coarse type signatures and counts |
| E57 | Cobalt integration unload | interceptor cleanup occurs; no replay, blocking, raw arguments or uploads |


| E58 | Reconstructed client code default | all presets and engine export `.luau` by default; protected decompile, exact readback and syntax check, never execute returned code |
| E59 | >2000 lines / large source | no artificial text cap; source checksum matches returned bytes |
| E60 | Empty/failed/unavailable decompile | truthful per-script status, no placeholder code files |
| E61 | File integrity / cancellation | no false success; partial writes and cancellation are reported |
| E62 | Resume in same executor session | verified files skipped; class/DebugId checked before retry |
| E63 | Instance identity / short events | distinct homonyms/replacements, stable rename ID, events retained before baseline visit |
| E64 | Global sequence / diagnostics | unique order across chunks, operator activations and optional Cobalt records |
| E65 | Public repository hygiene | no private game source, capture files, payloads or user identities committed |

| E62 | Metadata-only choice | Advanced toggle disables Luau extraction explicitly without disabling GUI/structural export |
