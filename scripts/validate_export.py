#!/usr/bin/env python3
"""Validate both categorized v2 and original flat v1 Lesbhub export directories."""
from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path
import re
import sys
import hashlib
import zlib
from pathlib import PurePosixPath, PureWindowsPath

FLAT_RE = re.compile(r"^([A-Za-z][A-Za-z0-9]*)-p([1-9][0-9]*)-([0-9]{4,})\.(json|jsonl|csv)$")
NESTED_RE = re.compile(r"^p([1-9][0-9]*)-([0-9]{4,})\.(json|jsonl|csv)$")
CATEGORIES = {"scripts", "gui", "remotes", "values", "world",
              "assets", "structures", "other"}
REQUIRED_RECORD = {"path", "parentPath", "name", "className", "depth", "properties"}
STATUSES = {"complete", "partial", "cancelled", "stopped", "recording"}


def digest(data: bytes, algorithm: str) -> str:
    if algorithm == "sha256":
        return hashlib.sha256(data).hexdigest()
    if algorithm == "adler32":
        return f"{zlib.adler32(data) & 0xffffffff:08x}"
    raise ValueError("unsupported checksum algorithm")


def safe_file(folder: Path, relative: object) -> Path:
    if not isinstance(relative, str) or not relative or "\\" in relative:
        raise ValueError("unsafe relative path")
    parts = relative.split("/")
    if (any(part in {"", ".", ".."} for part in parts)
            or relative.startswith("/") or PureWindowsPath(relative).drive
            or any(c in relative for c in ':<>"|?*')
            or any(ord(c) < 32 for c in relative)):
        raise ValueError("unsafe relative path")
    path = folder / relative
    if not path.resolve().is_relative_to(folder.resolve()):
        raise ValueError("unsafe relative path")
    return path


def parse_chunk(path: Path, service: str, capture_pass: int,
                category: str | None, issues: list[str]):
    try:
        if path.suffix == ".json":
            body = json.loads(path.read_text(encoding="utf-8"))
            if not isinstance(body, dict):
                issues.append(f"{path}: chunk must be an object")
                return []
            if body.get("schemaVersion") != 1:
                issues.append(f"{path}: wrong schema version")
            if body.get("service") != service or body.get("pass") != capture_pass:
                issues.append(f"{path}: service/pass mismatch")
            if category is not None and body.get("category") != category:
                issues.append(f"{path}: category header mismatch")
            records = body.get("records")
            if not isinstance(records, list):
                issues.append(f"{path}: records must be an array")
                return []
            return records
        if path.suffix == ".jsonl":
            return [
                json.loads(line) for line in
                path.read_text(encoding="utf-8").splitlines()
                if line.strip()
            ]
        with path.open("r", encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream)
            header = ["path", "parentPath", "name", "className", "depth", "properties_json"]
            extended = header + ["instanceId", "parentInstanceId", "sequence", "scriptId", "operation", "observedAtUtc"]
            if reader.fieldnames not in (header, extended):
                issues.append(f"{path}: invalid CSV header")
                return []
            records = []
            for row in reader:
                try:
                    record = {
                        "path": row["path"], "parentPath": row["parentPath"],
                        "name": row["name"], "className": row["className"],
                        "depth": int(row["depth"]),
                        "properties": json.loads(row["properties_json"]),
                    }
                    for field in ("instanceId", "parentInstanceId", "sequence"):
                        if row.get(field): record[field] = int(row[field])
                    for field in ("scriptId", "operation", "observedAtUtc"):
                        if row.get(field): record[field] = row[field]
                    records.append(record)
                except (TypeError, ValueError, KeyError, json.JSONDecodeError) as exc:
                    issues.append(f"{path}: invalid CSV record ({exc})")
            return records
    except (OSError, ValueError, UnicodeDecodeError) as exc:
        issues.append(f"{path}: unreadable chunk ({exc})")
    return []


def parse_location(relative: Path, version: int):
    parts = relative.parts
    if version == 2:
        if len(parts) != 3 or parts[0] not in CATEGORIES:
            return None
        match = NESTED_RE.fullmatch(parts[2])
        if not match or not re.fullmatch(r"[A-Za-z][A-Za-z0-9]*", parts[1]):
            return None
        capture_pass, index, fmt = match.groups()
        return parts[1], int(capture_pass), int(index), fmt, parts[0]
    if len(parts) != 1:
        return None
    match = FLAT_RE.fullmatch(parts[0])
    if not match:
        return None
    service, capture_pass, index, fmt = match.groups()
    return service, int(capture_pass), int(index), fmt, None


def validate_deep(folder: Path, manifest: dict, issues: list[str]) -> None:
    """Validate optional v0.7 sidecars without changing historical chunk totals."""
    summary = manifest.get("scriptExport")
    if not isinstance(summary, dict):
        return
    index_path = folder / "scripts" / "index.json"
    try:
        index = json.loads(index_path.read_text(encoding="utf-8"))
        entries = index["scripts"]
        if entries == {}:  # Roblox's empty table encoding is executor-dependent.
            entries = []
        if not isinstance(entries, list):
            raise ValueError("scripts must be an array")
    except (OSError, ValueError, KeyError, TypeError) as exc:
        issues.append(f"scripts/index.json: {exc}")
        return
    index_version = index.get("version", 1)
    if index_version not in {1, 2}:
        issues.append("scripts/index.json: unsupported version")
        return
    if index_version == 2 and summary.get("version") != 2:
        issues.append("scriptExport summary version differs from scripts index")
    counts = dict(discovered=len(entries), attempted=0, succeeded=0, failed=0,
                  inaccessible=0, empty=0, partial=0, skipped=0, pending=0,
                  files=0, bytes=0)
    if index_version == 2:
        counts.update(logicalFiles=0, logicalBytes=0, sharedReferences=0)
    ids, instance_ids, outputs, physical_sources = set(), set(), {}, {}
    for n, entry in enumerate(entries, 1):
        label = f"scripts/index.json entry {n}"
        if not isinstance(entry, dict):
            issues.append(f"{label}: must be an object"); continue
        required = {"scriptId", "className", "robloxPath", "outputPath", "status", "error",
                    "byteLength", "lineCount", "checksum", "method"}
        if not required.issubset(entry):
            issues.append(f"{label}: missing required script fields"); continue
        script_id = entry["scriptId"]
        if not isinstance(script_id, str) or script_id in ids:
            issues.append(f"{label}: invalid/duplicate scriptId")
        else:
            ids.add(script_id)
        if index_version == 2:
            instance_id = entry.get("instanceId")
            if (not isinstance(instance_id, int) or isinstance(instance_id, bool)
                    or instance_id < 1 or instance_id in instance_ids):
                issues.append(f"{label}: invalid/duplicate instanceId")
            else:
                instance_ids.add(instance_id)
        status = entry["status"]
        if not isinstance(status, str) or status not in {"success", "failed", "inaccessible", "empty", "partial"}:
            issues.append(f"{label}: invalid final status"); continue
        counts["succeeded" if status == "success" else status] += 1
        counts["attempted"] += bool(entry.get("attempted"))
        counts["skipped"] += bool(entry.get("skipped"))
        diagnostic_path = entry.get("diagnosticPath")
        if diagnostic_path is not None:
            try:
                file = safe_file(folder, diagnostic_path)
                if diagnostic_path != f"errors/script-diagnostics/{script_id}.txt":
                    raise ValueError("invalid diagnosticPath")
                data = file.read_bytes()
                if len(data) != entry.get("diagnosticByteLength"):
                    raise ValueError("diagnostic byte length mismatch")
                if digest(data, entry.get("diagnosticChecksumAlgorithm")) != entry.get("diagnosticChecksum"):
                    raise ValueError("diagnostic checksum mismatch")
            except (OSError, ValueError, TypeError) as exc:
                issues.append(f"{label}: {exc}")
        output = entry["outputPath"]
        if not output:
            if status in {"success", "partial"}:
                issues.append(f"{label}: saved code requires outputPath")
            continue
        if not isinstance(output, str) or not output.startswith("scripts/sources/") or "\\" in output:
            issues.append(f"{label}: unsafe outputPath"); continue
        parts = PurePosixPath(output).parts
        if (PureWindowsPath(output).drive or ".." in parts or ":" in output
                or any(c in output for c in '<>"|?*') or any(ord(c) < 32 for c in output)
                or not output.endswith(".luau")
                or not (folder / output).resolve().is_relative_to(folder.resolve())):
            issues.append(f"{label}: unsafe outputPath"); continue
        if output.casefold() in outputs:
            if index_version == 1 or outputs[output.casefold()] != output:
                issues.append(f"{label}: duplicate or case-colliding outputPath")
        else:
            outputs[output.casefold()] = output
        file = folder / output
        if status in {"success", "partial"} and not file.is_file():
            issues.append(f"{label}: missing .luau file"); continue
        if not entry.get("verifiedReadback"):
            if status in {"success", "partial"}:
                issues.append(f"{label}: saved code has no verified readback")
            continue
        try:
            content = file.read_bytes()
            offset = entry["headerByteLength"]
            if not isinstance(offset, int) or not 0 <= offset <= len(content):
                raise ValueError("invalid headerByteLength")
            if index_version == 2 and output.startswith("scripts/sources/content/") and offset != 0:
                raise ValueError("v2 shared source files require headerByteLength 0")
            source = content[offset:]
            if len(source) != entry["byteLength"] or len(content) != entry["fileByteLength"]:
                raise ValueError("byte length mismatch")
            if source.count(b"\n") + 1 != entry["lineCount"]:
                raise ValueError("line count mismatch")
            if digest(source, entry["checksumAlgorithm"]) != entry["checksum"]:
                raise ValueError("source checksum mismatch")
            if digest(content, entry["fileChecksumAlgorithm"]) != entry["fileChecksum"]:
                raise ValueError("file checksum mismatch")
            if status == "success":
                source.decode("utf-8")
                if entry.get("truncationDetected") or entry.get("compiles") is not True:
                    raise ValueError("success requires syntax validation and no detected truncation")
            if index_version == 1:
                counts["files"] += 1
                counts["bytes"] += len(content)
            else:
                previous = physical_sources.get(output)
                if previous is not None and previous != content:
                    raise ValueError("shared outputPath content differs between logical entries")
                physical_sources[output] = content
                counts["logicalFiles"] += 1
                counts["logicalBytes"] += len(content)
        except (OSError, ValueError, KeyError, TypeError) as exc:
            issues.append(f"{label}: {exc}")
    if index_version == 2:
        counts["files"] = len(physical_sources)
        counts["bytes"] = sum(len(content) for content in physical_sources.values())
        counts["sharedReferences"] = counts["logicalFiles"] - counts["files"]
    for stats_name, stats in (("index", index.get("stats")), ("manifest", summary.get("stats"))):
        if not isinstance(stats, dict) or any(stats.get(k) != v for k, v in counts.items()):
            issues.append(f"scriptExport {stats_name} counters differ from script index/files")
    for file in folder.rglob("*.luau"):
        if file.relative_to(folder).as_posix().casefold() not in outputs:
            issues.append(f"{file.relative_to(folder)}: unindexed .luau file")


INSPECTION_SIDECARS = {
    "client.json", "assets/index.json", "relations/index.json", "gui/states/index.json",
    "gui/transitions.jsonl", "errors/index.json", "artifacts/index.json",
}
V09_LEGACY_LOGS = {"gui/actions.jsonl", "gui/transitions.jsonl",
                   "remotes/observations.jsonl", "relations/temporal.jsonl"}
INSPECTION_LAYERS = {"metadata", "reconstructedScripts", "gui", "remoteInventory",
                     "remoteObservations", "runtime", "relations", "validation"}
LAYER_STATUSES = {"complete", "partial", "unavailable", "disabled", "not_observed"}
LEDGER_EXCLUDED = {"manifest.json", "report.json", "report.md", "artifacts/index.json"}


def validate_inspection(folder: Path, manifest: dict, issues: list[str]) -> None:
    inspection_version = manifest.get("inspectionVersion")
    if inspection_version not in {1, 2}:
        issues.append("inspectionVersion must be 1 or 2")
    if not isinstance(manifest.get("scriptExport"), dict):
        issues.append("inspection manifest requires scriptExport")
    required_sidecars = INSPECTION_SIDECARS if inspection_version == 1 else (
        INSPECTION_SIDECARS - {"gui/transitions.jsonl"}) | {
            "journal/index.json", "remotes/signatures.json"}
    for name in required_sidecars | {"report.json", "report.md"}:
        if not (folder / name).is_file():
            issues.append(f"{name}: missing required inspection artifact")

    if inspection_version == 2:
        present_legacy_logs = sorted(name for name in V09_LEGACY_LOGS if (folder / name).exists())
        if present_legacy_logs:
            issues.append("v0.9 must use immutable journal segments, not legacy monolithic logs: "
                          + ", ".join(present_legacy_logs))

    try:
        states_index = json.loads((folder / "gui/states/index.json").read_text(encoding="utf-8"))
        if inspection_version == 2:
            if not isinstance(states_index, dict) or states_index.get("schemaVersion") != 2:
                raise ValueError("v0.9 GUI states index must use schemaVersion 2")
            from reconstruct_export import ReconstructionError, reconstruct_gui
            descriptors = states_index.get("states")
            if descriptors == {}:
                descriptors = []
            if not isinstance(descriptors, list):
                raise ValueError("states must be an array")
            state_ids = set()
            for descriptor in descriptors:
                if not isinstance(descriptor, dict):
                    issues.append("gui/states/index.json: state descriptor must be an object")
                    continue
                state_id = descriptor.get("stateId")
                if not isinstance(state_id, int) or isinstance(state_id, bool) or state_id < 1 or state_id in state_ids:
                    issues.append("gui/states/index.json: invalid or duplicate stateId")
                    continue
                state_ids.add(state_id)
                try:
                    reconstruct_gui(folder, state_id)
                except (OSError, ValueError, TypeError, ReconstructionError) as exc:
                    issues.append(f"gui/states/index.json: state {state_id}: {exc}")
            try:
                from reconstruct_export import indexed_gui_lookup_paths
                indexed_gui_lookup_paths(folder)
            except (OSError, ValueError, TypeError) as exc:
                issues.append(f"gui/states/lookup: invalid lookup index: {exc}")
            transitions = states_index.get("transitions", [])
            if transitions == {}:
                transitions = []
            if not isinstance(transitions, list):
                issues.append("gui/states/index.json: transitions must be an array")
            else:
                for transition in transitions:
                    if not isinstance(transition, dict):
                        issues.append("gui/states/index.json: transition must be an object")
                        continue
                    if (transition.get("fromStateId") not in state_ids
                            or transition.get("toStateId") not in state_ids
                            or not isinstance(transition.get("count"), int)
                            or isinstance(transition.get("count"), bool)
                            or transition.get("count", 0) < 1):
                        issues.append("gui/states/index.json: invalid transition endpoints/count")
            try:
                from reconstruct_export import iter_events, replay_structure
                events = iter_events(folder)
                global_sequences = set()
                transition_counts = defaultdict(int)
                remote_event_count = 0
                unresolved_remote_count = 0
                event_count = 0
                for row in events:
                    event_count += 1
                    sequence = row.get("sequence")
                    if sequence in global_sequences:
                        issues.append(f"journal: duplicate global sequence {sequence}")
                    global_sequences.add(sequence)
                    if row.get("stream") == "gui-transitions":
                        source, target = row.get("fromStateId"), row.get("toStateId")
                        if source not in state_ids or target not in state_ids:
                            issues.append("journal GUI transition references an unknown state")
                        else:
                            transition_counts[(source, target)] += 1
                    elif row.get("stream") == "remote-observations":
                        remote_event_count += 1
                        unresolved = row.get("identityStatus") == "unresolved"
                        if unresolved:
                            unresolved_remote_count += 1
                            if (row.get("reason") != "deferred_identity_unavailable"
                                    or any(key in row for key in ("instanceId", "robloxPath", "path", "name",
                                                                  "className", "callerInstanceId", "scriptId"))):
                                issues.append("unresolved remote occurrence must not invent identity or caller metadata")
                        elif (row.get("identityStatus", "resolved") != "resolved"
                              or not isinstance(row.get("instanceId"), int)
                              or isinstance(row.get("instanceId"), bool) or row.get("instanceId", 0) < 1):
                            issues.append("journal remote observation lacks a positive resolved identity")
                        if (row.get("direction") not in {"Incoming", "Outgoing"}
                                or not isinstance(row.get("signatureId"), int)
                                or isinstance(row.get("signatureId"), bool) or row.get("signatureId", 0) < 1):
                            issues.append("journal remote observation lacks identity/direction/signature")
                        if any(key in row for key in ("args", "arguments", "payload", "argumentValues")):
                            issues.append("journal remote observation must not store argument values")
                if isinstance(transitions, list):
                    indexed_counts = defaultdict(int)
                    for transition in transitions:
                        if isinstance(transition, dict):
                            indexed_counts[(transition.get("fromStateId"), transition.get("toStateId"))] += transition.get("count", 0)
                    if dict(indexed_counts) != dict(transition_counts):
                        issues.append("GUI transition summary differs from journal occurrences")
                signatures = json.loads((folder / "remotes/signatures.json").read_text(encoding="utf-8"))
                if not isinstance(signatures, dict) or signatures.get("version") != 1:
                    raise ValueError("remotes/signatures.json must use version 1")
                signature_rows = signatures.get("signatures")
                if signature_rows == {}:
                    signature_rows = []
                if not isinstance(signature_rows, list):
                    raise ValueError("remote signatures must be an array")
                signature_ids = set()
                for signature in signature_rows:
                    if not isinstance(signature, dict):
                        issues.append("remotes/signatures.json: signature must be an object")
                        continue
                    signature_id = signature.get("signatureId")
                    if not isinstance(signature_id, int) or isinstance(signature_id, bool) or signature_id < 1 or signature_id in signature_ids:
                        issues.append("remotes/signatures.json: invalid or duplicate signatureId")
                    else:
                        signature_ids.add(signature_id)
                    if (not isinstance(signature.get("argumentCount"), int)
                            or isinstance(signature.get("argumentCount"), bool)
                            or signature.get("argumentCount", -1) < 0
                            or not isinstance(signature.get("argumentTypes"), list)
                            or any(not isinstance(kind, str) for kind in signature.get("argumentTypes", []))
                            or signature.get("invokeKind") not in {None, "Request", "Callback"}):
                        issues.append("remotes/signatures.json: invalid signature fields")
                for row in iter_events(folder):
                    if (row.get("stream") == "remote-observations"
                            and row.get("signatureId") not in signature_ids):
                        issues.append("journal remote observation references unknown signatureId")
                if isinstance(manifest.get("dedup"), dict):
                    if manifest["dedup"].get("eventsWritten") != event_count:
                        issues.append("manifest dedup.eventsWritten differs from journal rows")
                    if manifest["dedup"].get("occurrences") is not None and manifest["dedup"]["occurrences"] != remote_event_count:
                        issues.append("manifest dedup.occurrences differs from remote observation rows")
                runtime = manifest.get("runtime")
                observer = runtime.get("observer", {}) if isinstance(runtime, dict) else {}
                if isinstance(observer, dict):
                    if "observedCalls" in observer and observer["observedCalls"] != remote_event_count:
                        issues.append("observer observedCalls differs from remote observation rows")
                    if "unresolvedCalls" in observer and observer["unresolvedCalls"] != unresolved_remote_count:
                        issues.append("observer unresolvedCalls differs from remote observation rows")
                layout = manifest.get("layout", {})
                layout_version = layout.get("version", 1) if isinstance(layout, dict) else -1
                for file in folder.rglob("*"):
                    if not file.is_file() or file.suffix not in {".json", ".jsonl", ".csv"}:
                        continue
                    relative = file.relative_to(folder).as_posix()
                    if relative == "manifest.json" or relative.startswith(("journal/", "gui/states/")):
                        continue
                    location = parse_location(Path(relative), layout_version)
                    if location is None:
                        continue
                    service, capture_pass, _, _, category = location
                    rows = parse_chunk(file, service, capture_pass, category, issues)
                    for row in rows:
                        if not isinstance(row, dict):
                            continue
                        sequence = row.get("sequence")
                        if sequence in global_sequences:
                            issues.append(f"duplicate global sequence {sequence}")
                        global_sequences.add(sequence)
                replay_structure(folder)
            except (OSError, ValueError, TypeError) as exc:
                issues.append(f"journal: invalid event stream: {exc}")
            # Continue into the shared report and ledger checks below.
            states = None
        else:
            states = states_index.get("states") if isinstance(states_index, dict) else None
        if inspection_version == 1:
            if states == {}:
                states = []
            if not isinstance(states, list):
                raise ValueError("states must be an array")
            state_paths, state_ids = set(), set()
            for state in states:
                try:
                    if not isinstance(state, dict):
                        raise ValueError("state entry must be an object")
                    state_id, path = state.get("stateId"), state.get("path")
                    if not isinstance(state_id, int) or isinstance(state_id, bool) or state_id < 1:
                        raise ValueError("invalid stateId")
                    if path != f"gui/states/state{state_id:06d}.json" or state_id in state_ids:
                        raise ValueError("invalid or duplicate state path/ID")
                    state_ids.add(state_id); state_paths.add(path)
                    projection = json.loads(safe_file(folder, path).read_text(encoding="utf-8"))
                    elements = projection.get("elements") if isinstance(projection, dict) else None
                    if elements == {}:
                        elements = []
                    if (not isinstance(projection, dict) or projection.get("stateId") != state_id
                            or not isinstance(elements, list) or state.get("elementCount") != len(elements)):
                        raise ValueError("state projection differs from index")
                except (OSError, ValueError, TypeError) as exc:
                    issues.append(f"gui/states/index.json: {exc}")
            for file in (folder / "gui/states").glob("state*.json"):
                if file.relative_to(folder).as_posix() not in state_paths:
                    issues.append(f"{file.relative_to(folder)}: unindexed GUI state")
    except (OSError, ValueError, TypeError) as exc:
        issues.append(f"gui/states/index.json: invalid state index: {exc}")

    declaration = manifest.get("artifactIndex")
    if not isinstance(declaration, dict) or declaration.get("path") != "artifacts/index.json" or declaration.get("version") != 1:
        issues.append("manifest artifactIndex declaration is invalid")
    try:
        ledger = json.loads((folder / "artifacts/index.json").read_text(encoding="utf-8"))
        if not isinstance(ledger, dict) or ledger.get("version") != 1:
            raise ValueError("invalid ledger version")
        artifacts = ledger.get("artifacts")
        if artifacts == {}:
            artifacts = []
        if not isinstance(artifacts, list):
            raise ValueError("artifacts must be an array")
        recorded: set[str] = set()
        for number, artifact in enumerate(artifacts, 1):
            label = f"artifacts/index.json entry {number}"
            try:
                if not isinstance(artifact, dict):
                    raise ValueError("artifact must be an object")
                relative = artifact.get("path")
                file = safe_file(folder, relative)
                if relative in LEDGER_EXCLUDED:
                    raise ValueError("self-referential or report artifact in ledger")
                if inspection_version == 2 and relative.startswith("checkpoints/"):
                    raise ValueError("checkpoint snapshots are excluded from the artifact ledger")
                folded = relative.casefold()
                if folded in recorded:
                    raise ValueError("duplicate artifact path")
                recorded.add(folded)
                if not isinstance(artifact.get("kind"), str) or not artifact["kind"]:
                    raise ValueError("artifact kind missing")
                length = artifact.get("bytes")
                if not isinstance(length, int) or isinstance(length, bool) or length < 0:
                    raise ValueError("invalid artifact byte length")
                data = file.read_bytes()
                if len(data) != length:
                    raise ValueError("artifact byte length mismatch")
                if digest(data, artifact.get("checksumAlgorithm")) != artifact.get("checksum"):
                    raise ValueError("artifact checksum mismatch")
            except (OSError, ValueError, TypeError) as exc:
                issues.append(f"{label}: {exc}")
        for file in folder.rglob("*"):
            if file.is_file():
                relative = file.relative_to(folder).as_posix()
                if inspection_version == 2 and relative.startswith("checkpoints/"):
                    continue
                if relative not in LEDGER_EXCLUDED and relative.casefold() not in recorded:
                    issues.append(f"{relative}: missing from artifact ledger")
    except (OSError, ValueError, TypeError) as exc:
        issues.append(f"artifacts/index.json: invalid ledger: {exc}")

    report_ref = manifest.get("report")
    if not isinstance(report_ref, dict) or report_ref.get("version") != 2 or report_ref.get("path") != "report.json" or report_ref.get("markdownPath") != "report.md":
        issues.append("manifest report declaration is invalid")
    try:
        report = json.loads((folder / "report.json").read_text(encoding="utf-8"))
        if not isinstance(report, dict) or report.get("reportVersion") != 2:
            raise ValueError("invalid report version")
        for field in ("status", "game", "stats", "partialReasons"):
            if report.get(field) != manifest.get(field):
                issues.append(f"report {field} differs from manifest")
        if inspection_version == 2:
            expected_dedup = manifest.get("dedup", manifest.get("continuous", {}))
            if report.get("dedup") != expected_dedup:
                issues.append("report dedup counters differ from manifest")
            if "continuous" in manifest and report.get("continuous") != manifest.get("continuous"):
                issues.append("report continuous counters differ from manifest")
        script_stats = manifest.get("scriptExport", {}).get("stats") if isinstance(manifest.get("scriptExport"), dict) else None
        report_scripts = report.get("scriptExport")
        if not isinstance(report_scripts, dict) or report_scripts.get("stats") != script_stats:
            issues.append("report scriptExport stats differ from manifest")
        layers = report.get("layers")
        if not isinstance(layers, dict) or set(layers) != INSPECTION_LAYERS:
            issues.append("report layers must contain the eight inspection layers")
        else:
            for name, layer in layers.items():
                if not isinstance(layer, dict) or layer.get("status") not in LAYER_STATUSES:
                    issues.append(f"report layer {name} has invalid status")
                    continue
                if not isinstance(layer.get("reason"), str) or not isinstance(layer.get("counts"), dict) or not isinstance(layer.get("artifacts"), (list, dict)) or "evidence" not in layer:
                    issues.append(f"report layer {name} has invalid fields")
            scripts_layer = layers.get("reconstructedScripts")
            if not isinstance(scripts_layer, dict) or scripts_layer.get("counts") != script_stats:
                issues.append("report reconstructedScripts counts differ from manifest")
    except (OSError, ValueError, TypeError) as exc:
        issues.append(f"report.json: invalid report: {exc}")


def validate_folder(folder: Path) -> list[str]:
    issues: list[str] = []
    manifest_path = folder / "manifest.json"
    if not manifest_path.is_file():
        return ["missing manifest.json"]
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeDecodeError) as exc:
        return [f"invalid manifest.json: {exc}"]
    if not isinstance(manifest, dict):
        return ["manifest must be a JSON object"]
    version_match = re.match(r"^(\d+)\.(\d+)(?:\.|$)", str(manifest.get("exporterVersion", "")))
    inspection = ("inspectionVersion" in manifest or
                  bool(version_match and tuple(map(int, version_match.groups())) >= (0, 8)))
    if manifest.get("schemaVersion") != 1:
        issues.append("unsupported manifest schemaVersion")
    if manifest.get("status") not in STATUSES:
        issues.append("invalid capture status")
    if manifest.get("clientOnly") is not True:
        issues.append("clientOnly must be true")
    if not isinstance(manifest.get("game"), dict):
        issues.append("game metadata is missing")

    services = manifest.get("services")
    stats = manifest.get("stats")
    settings = manifest.get("settings")
    if not isinstance(services, dict) or not isinstance(stats, dict):
        return issues + ["manifest requires stats and services objects"]
    if not isinstance(settings, dict):
        return issues + ["manifest settings must be an object"]
    fmt = settings.get("format")
    if fmt not in {"json", "jsonl", "csv"}:
        issues.append("invalid export format in settings")

    layout = manifest.get("layout", {})
    version = layout.get("version", 1) if isinstance(layout, dict) else -1
    if version not in {1, 2}:
        return issues + ["unsupported layout version"]
    if isinstance(layout, dict) and "id" in layout:
        expected_id = "categorized" if version == 2 else "flat"
        if layout.get("id") != expected_id:
            issues.append("layout id/version mismatch")
    if "organizedOutput" in settings and settings["organizedOutput"] != (version == 2):
        issues.append("settings.organizedOutput disagrees with layout")

    chunk_files: list[tuple[Path, tuple]] = []
    seen_sequences = set()
    identity_enabled = isinstance(manifest.get("identity"), dict) and manifest["identity"].get("version") == 1
    def check_sequence(row, location):
        seq = row.get("sequence")
        if not isinstance(seq, int) or isinstance(seq, bool) or seq < 1:
            issues.append(f"{location}: invalid sequence")
        elif seq in seen_sequences:
            issues.append(f"{location}: duplicate global sequence")
        else:
            seen_sequences.add(seq)
    sidecars = {"scripts/index.json", "remotes/index.json", "remotes/signatures.json", "gui/index.json",
                "gui/actions.jsonl", "remotes/observations.jsonl", "report.json",
                "scripts/progress.jsonl", "performance-local.json", "journal/index.json"}
    if inspection:
        sidecars |= INSPECTION_SIDECARS
    declared_v09_paths = (declared_v09_auxiliary_paths(folder, issues)
                          if manifest.get("inspectionVersion") == 2 else set())
    for file in folder.rglob("*"):
        if not file.is_file() or file == manifest_path:
            continue
        if file.suffix not in {".json", ".jsonl", ".csv"}:
            continue
        relative = file.relative_to(folder).as_posix()
        if inspection and manifest.get("inspectionVersion") == 2 and relative.startswith("checkpoints/"):
            continue
        is_gui_state = inspection and re.fullmatch(r"gui/states/state[0-9]{6,}\.json", relative)
        if (("scriptExport" in manifest or inspection)
                and (relative in sidecars or is_gui_state or relative in declared_v09_paths)):
            try:
                if file.suffix == ".json":
                    json.loads(file.read_text(encoding="utf-8"))
                else:
                    for line in file.read_text(encoding="utf-8").splitlines():
                        if line.strip():
                            row = json.loads(line)
                            if (identity_enabled or inspection) and relative in {
                                "gui/actions.jsonl", "remotes/observations.jsonl", "gui/transitions.jsonl"
                            }:
                                if isinstance(row, dict): check_sequence(row, str(file.relative_to(folder)))
                                else: issues.append(f"{file}: invalid diagnostic event")
            except (OSError, ValueError) as exc:
                issues.append(f"{file.relative_to(folder)}: invalid sidecar: {exc}")
            continue
        position = parse_location(file.relative_to(folder), version)
        if position is None:
            issues.append(f"{file.relative_to(folder)}: unrecognized data file")
        else:
            chunk_files.append((file, position))
    service_records = defaultdict(int)
    service_files = defaultdict(int)
    category_records = defaultdict(int)
    category_files = defaultdict(int)
    category_service_records = defaultdict(int)
    category_service_files = defaultdict(int)
    sequence = defaultdict(list)
    total_records, total_bytes = 0, 0

    for path, (service, capture_pass, part, extension, category) in chunk_files:
        where = str(path.relative_to(folder))
        sequence[(category if version == 2 else "", service, capture_pass)].append(part)
        if service not in services:
            issues.append(f"{where}: unknown service in manifest")
        if extension != fmt:
            issues.append(f"{where}: format differs from manifest")
        total_bytes += path.stat().st_size
        records = parse_chunk(path, service, capture_pass, category, issues)
        count = len(records)
        service_records[service] += count
        service_files[service] += 1
        total_records += count
        if version == 2:
            category_records[category] += count
            category_files[category] += 1
            category_service_records[(category, service)] += count
            category_service_files[(category, service)] += 1
        for n, record in enumerate(records, 1):
            prefix = f"{where}: record {n}"
            if not isinstance(record, dict) or not REQUIRED_RECORD.issubset(record):
                issues.append(f"{prefix}: missing required fields")
                continue
            if identity_enabled or inspection:
                check_sequence(record, prefix)
                if not isinstance(record.get("instanceId"), int) or record["instanceId"] < 1:
                    issues.append(f"{prefix}: invalid instanceId")
            if not isinstance(record["depth"], int) or record["depth"] < 0:
                issues.append(f"{prefix}: invalid depth")
            if not isinstance(record["properties"], dict):
                issues.append(f"{prefix}: properties must be an object")
            elif "Source" in record["properties"]:
                issues.append(f"{prefix}: script Source must not be exported")
            path_name = record["path"]
            if not isinstance(path_name, str) or not (
                path_name == service or path_name.startswith(service + "/")
            ):
                issues.append(f"{prefix}: path not under declared service")
            if not isinstance(record["parentPath"], str):
                issues.append(f"{prefix}: parentPath must be a string")
            if version == 2 and extension != "csv" and record.get("category") != category:
                issues.append(f"{prefix}: category differs from folder")

    for (category, service, capture_pass), parts in sequence.items():
        if sorted(parts) != list(range(1, len(parts) + 1)):
            issues.append(f"{category}/{service} pass {capture_pass}: missing/duplicate chunk indexes")

    for service, summary in services.items():
        if not isinstance(summary, dict):
            issues.append(f"{service}: service summary must be an object")
            continue
        if summary.get("records") != service_records[service]:
            issues.append(f"{service}: record count differs from manifest")
        if summary.get("files") != service_files[service]:
            issues.append(f"{service}: file count differs from manifest")

    if version == 2:
        categories = manifest.get("categories")
        if not isinstance(categories, dict):
            issues.append("categorized layout requires a categories index in manifest")
        else:
            for category in set(categories) | set(category_records):
                summary = categories.get(category)
                if category not in CATEGORIES or not isinstance(summary, dict):
                    issues.append(f"{category}: invalid category summary")
                    continue
                if summary.get("records") != category_records[category]:
                    issues.append(f"{category}: category record count mismatch")
                if summary.get("files") != category_files[category]:
                    issues.append(f"{category}: category file count mismatch")
                sub = summary.get("services")
                if not isinstance(sub, dict):
                    issues.append(f"{category}: missing category/service summary")
                    continue
                for service in set(sub) | {
                    svc for cat, svc in category_service_records if cat == category
                }:
                    service_summary = sub.get(service, {})
                    if service_summary.get("records") != category_service_records[(category, service)]:
                        issues.append(f"{category}/{service}: record count mismatch")
                    if service_summary.get("files") != category_service_files[(category, service)]:
                        issues.append(f"{category}/{service}: file count mismatch")

    if stats.get("written") != total_records:
        issues.append("stats.written differs from data records")
    if stats.get("files") != len(chunk_files):
        issues.append("stats.files differs from chunk count")
    if stats.get("bytes") != total_bytes:
        issues.append("stats.bytes differs from data file bytes")
    if not isinstance(manifest.get("partialReasons"), list):
        issues.append("partialReasons must be an array")
    validate_deep(folder, manifest, issues)
    if inspection:
        validate_inspection(folder, manifest, issues)
    return issues


def declared_v09_auxiliary_paths(folder: Path, issues: list[str]) -> set[str]:
    """Return only journal/GUI lookup files authorized by their v0.9 indexes."""
    declared: set[str] = set()
    try:
        index = json.loads((folder / "journal/index.json").read_text(encoding="utf-8"))
        if not isinstance(index, dict) or index.get("version") != 1:
            raise ValueError("journal index must use version 1")
        streams = index.get("streams")
        if not isinstance(streams, dict):
            raise ValueError("journal index streams must be an object")
        for stream_name, stream in streams.items():
            if not isinstance(stream_name, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", stream_name):
                raise ValueError("invalid journal stream name")
            if not isinstance(stream, dict) or not isinstance(stream.get("segments"), list):
                raise ValueError(f"invalid journal stream {stream_name}")
            for segment in stream["segments"]:
                if not isinstance(segment, dict) or not isinstance(segment.get("path"), str):
                    raise ValueError(f"invalid journal segment in {stream_name}")
                path = segment["path"]
                if not re.fullmatch(rf"journal/{re.escape(stream_name)}/b[0-9]{{6}}\.json", path):
                    raise ValueError(f"invalid journal segment path: {path}")
                safe_file(folder, path)
                declared.add(path)
    except (OSError, ValueError, TypeError) as exc:
        issues.append(f"journal/index.json: {exc}")
    try:
        from reconstruct_export import indexed_gui_lookup_paths
        declared.update(indexed_gui_lookup_paths(folder))
    except (OSError, ValueError, TypeError) as exc:
        issues.append(f"gui/states/lookup: {exc}")
    return declared


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path, help="directory containing manifest.json")
    args = parser.parse_args()
    if not args.folder.is_dir():
        print(f"Not a directory: {args.folder}", file=sys.stderr)
        return 2
    issues = validate_folder(args.folder)
    if issues:
        for issue in issues:
            print("ERROR:", issue, file=sys.stderr)
        return 1
    print("OK: coherent Lesbhub Exporter dataset")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
