#!/usr/bin/env python3
"""Inspect or recover the latest fully verified durable v0.9 checkpoint.

Recovery creates a separate partial dataset; it never resumes an old recording.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import re
import shutil
import sys
import tempfile
import zlib
from collections import defaultdict
from pathlib import Path
from typing import Any

from reconstruct_export import ReconstructionError, iter_events
from validate_export import (CATEGORIES, INSPECTION_LAYERS, parse_chunk,
                             parse_location, safe_file, validate_folder)

WRAPPERS = {"manifest.json", "report.json", "report.md", "artifacts/index.json"}
MUTABLE = {"scripts/index.json", "gui/index.json", "gui/states/index.json", "remotes/index.json",
           "remotes/signatures.json", "journal/index.json", "relations/index.json", "client.json",
           "assets/index.json", "errors/index.json"}
CHECKPOINT = re.compile(r"^c([0-9]+)\.json$")
RESERVED = re.compile(r"^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$", re.I)


class RecoveryError(ValueError):
    pass


def checked_path(root: Path, relative: Any) -> Path:
    try:
        path = safe_file(root, relative)
        if any(part.endswith((".", " ")) or RESERVED.fullmatch(part) for part in relative.split("/")):
            raise ValueError("unsafe Windows path")
        current = root
        for part in relative.split("/"):
            current = current / part
            if current.is_symlink() or (hasattr(current, "is_junction") and current.is_junction()):
                raise ValueError("symbolic links are not accepted")
        return path
    except (ValueError, OSError, TypeError) as exc:
        raise RecoveryError(f"unsafe path {relative!r}: {exc}") from exc


def checked_bytes(root: Path, relative: str, descriptor: dict) -> None:
    path = checked_path(root, relative)
    length = descriptor.get("bytes")
    if not isinstance(length, int) or isinstance(length, bool) or length < 0:
        raise RecoveryError(f"{relative}: invalid byte count")
    try:
        algorithm = descriptor.get("checksumAlgorithm")
        if algorithm not in {"sha256", "adler32"}: raise RecoveryError(f"{relative}: unsupported checksum")
        checksum = hashlib.sha256() if algorithm == "sha256" else None
        adler, count = 1, 0
        with path.open("rb") as stream:
            while block := stream.read(1024 * 1024):
                count += len(block)
                if checksum is not None: checksum.update(block)
                else: adler = zlib.adler32(block, adler)
        actual = checksum.hexdigest() if checksum is not None else f"{adler & 0xffffffff:08x}"
        if count != length or actual != descriptor.get("checksum"):
            raise RecoveryError(f"{relative}: checksum or length mismatch")
    except (OSError, ValueError) as exc:
        raise RecoveryError(f"{relative}: {exc}") from exc


def verify_checkpoint(root: Path, path: Path) -> tuple[dict, list[dict]]:
    try:
        relative = path.relative_to(root).as_posix()
        checkpoint = json.loads(checked_path(root, relative).read_text(encoding="utf-8"))
    except (OSError, ValueError, UnicodeDecodeError) as exc:
        raise RecoveryError(f"{path.name}: invalid checkpoint: {exc}") from exc
    if not isinstance(checkpoint, dict) or checkpoint.get("checkpointVersion") != 1:
        raise RecoveryError(f"{path.name}: unsupported checkpoint")
    if not isinstance(checkpoint.get("manifest"), dict) or checkpoint["manifest"].get("inspectionVersion") != 2:
        raise RecoveryError(f"{path.name}: missing v0.9 provisional manifest")
    last = checkpoint.get("lastSequence")
    if not isinstance(last, int) or isinstance(last, bool) or last < 0:
        raise RecoveryError(f"{path.name}: invalid lastSequence")
    artifacts = checkpoint.get("artifacts")
    snapshots = checkpoint.get("snapshots")
    if artifacts == {}: artifacts = []
    if snapshots == {}: snapshots = []
    if not isinstance(artifacts, list) or not isinstance(snapshots, list):
        raise RecoveryError(f"{path.name}: invalid artifact or snapshot list")
    snapshot_by_path: dict[str, dict] = {}
    for snapshot in snapshots:
        if not isinstance(snapshot, dict): raise RecoveryError("invalid snapshot descriptor")
        original, frozen = snapshot.get("path"), snapshot.get("snapshotPath")
        checked_path(root, original)
        checked_path(root, frozen)
        if not frozen.startswith("checkpoints/files/"):
            raise RecoveryError("snapshot must reside under checkpoints/files/")
        key = original.casefold()
        if key in snapshot_by_path: raise RecoveryError("duplicate snapshot path")
        snapshot_by_path[key] = snapshot
    found, rows = set(), []
    for artifact in artifacts:
        if not isinstance(artifact, dict): raise RecoveryError("invalid artifact descriptor")
        relative = artifact.get("path")
        checked_path(root, relative)
        if relative.casefold() in {p.casefold() for p in WRAPPERS} or relative.casefold().startswith("checkpoints/"):
            raise RecoveryError(f"reserved artifact path: {relative}")
        key = relative.casefold()
        if key in found: raise RecoveryError(f"duplicate artifact: {relative}")
        found.add(key)
        if not isinstance(artifact.get("kind"), str) or not artifact["kind"]:
            raise RecoveryError(f"{relative}: missing kind")
        snapshot = snapshot_by_path.get(key)
        if key in MUTABLE and snapshot is None:
            raise RecoveryError(f"{relative}: mutable artifact has no frozen snapshot")
        source = snapshot["snapshotPath"] if snapshot else relative
        if snapshot:
            if snapshot["path"] != relative:
                raise RecoveryError("snapshot path case differs from artifact")
            for field in ("bytes", "checksum", "checksumAlgorithm"):
                if snapshot.get(field) != artifact.get(field):
                    raise RecoveryError(f"{relative}: snapshot and artifact disagree")
        checked_bytes(root, source, artifact)
        rows.append({"artifact": artifact, "source": source})
    if set(snapshot_by_path) - found:
        raise RecoveryError("snapshot has no corresponding artifact")
    return checkpoint, rows


def select_checkpoint(root: Path) -> tuple[Path, dict, list[dict], list[str]]:
    root = root.resolve(strict=True)
    directory = checked_path(root, "checkpoints")
    try:
        paths = [p for p in directory.iterdir() if CHECKPOINT.fullmatch(p.name)]
    except OSError as exc:
        raise RecoveryError(f"cannot list checkpoints: {exc}") from exc
    paths.sort(key=lambda p: int(CHECKPOINT.fullmatch(p.name).group(1)), reverse=True)
    warnings = []
    for path in paths:
        try:
            checkpoint, rows = verify_checkpoint(root, path)
            # Valid hashes alone cannot establish that frozen indexes describe
            # one coherent dataset. Validate an isolated view before selecting
            # it, so a logically damaged newest checkpoint can fall back too.
            with tempfile.TemporaryDirectory(prefix="lesbhub-checkpoint-") as directory:
                materialize_checkpoint(root, Path(directory), path, checkpoint, rows, warnings)
            return path, checkpoint, rows, warnings
        except (RecoveryError, OSError, ValueError, TypeError, KeyError) as exc:
            warnings.append(f"{path.name}: {exc}")
    raise RecoveryError("no fully verified checkpoint" + (": " + "; ".join(warnings) if warnings else ""))


def recount(folder: Path, manifest: dict, rows: list[dict]) -> None:
    version = manifest.get("layout", {}).get("version", 1)
    services = manifest.get("services")
    stats = manifest.get("stats")
    if not isinstance(services, dict) or not isinstance(stats, dict):
        raise RecoveryError("checkpoint manifest lacks services/stats")
    by_service, files_service = defaultdict(int), defaultdict(int)
    by_category, files_category = defaultdict(int), defaultdict(int)
    by_pair, files_pair = defaultdict(int), defaultdict(int)
    total_records = total_bytes = total_files = 0
    for row in rows:
        relative = row["artifact"]["path"]
        position = parse_location(Path(relative), version)
        if position is None: continue
        service, capture_pass, _, _, category = position
        if service not in services: raise RecoveryError(f"metadata references unknown service {service}")
        path = checked_path(folder, relative)
        issues: list[str] = []
        records = parse_chunk(path, service, capture_pass, category, issues)
        if issues: raise RecoveryError("invalid checkpoint metadata: " + "; ".join(issues))
        limit = manifest["recovery"]["lastSequence"]
        if any(not isinstance(record, dict) or not isinstance(record.get("sequence"), int)
               or isinstance(record.get("sequence"), bool) or record["sequence"] > limit for record in records):
            raise RecoveryError(f"{relative}: record exceeds durable sequence")
        count = len(records)
        by_service[service] += count; files_service[service] += 1
        total_records += count; total_bytes += path.stat().st_size; total_files += 1
        if version == 2:
            by_category[category] += count; files_category[category] += 1
            by_pair[(category, service)] += count; files_pair[(category, service)] += 1
    for service, summary in services.items():
        if not isinstance(summary, dict): raise RecoveryError("invalid service summary")
        summary.update(records=by_service[service], files=files_service[service])
    if version == 2:
        categories = manifest.get("categories")
        if not isinstance(categories, dict): raise RecoveryError("missing categorized summaries")
        for category in set(categories) | set(by_category):
            if category not in CATEGORIES: raise RecoveryError("invalid category")
            summary = categories.setdefault(category, {})
            if not isinstance(summary, dict): raise RecoveryError("invalid category summary")
            summary.update(records=by_category[category], files=files_category[category])
            subs = summary.setdefault("services", {})
            for service in set(subs) | {s for c, s in by_pair if c == category}:
                subs.setdefault(service, {}).update(records=by_pair[(category, service)], files=files_pair[(category, service)])
    stats.update(written=total_records, files=total_files, bytes=total_bytes)
    scripts = folder / "scripts/index.json"
    if scripts.is_file():
        index = json.loads(scripts.read_text(encoding="utf-8"))
        if isinstance(index, dict) and isinstance(index.get("stats"), dict):
            manifest.setdefault("scriptExport", {})["stats"] = index["stats"]


def make_report(manifest: dict) -> tuple[dict, str]:
    script_stats = manifest.get("scriptExport", {}).get("stats", {})
    layers = {}
    counts = {"metadata": manifest.get("stats", {}), "reconstructedScripts": script_stats,
              "gui": manifest.get("guiAnalysis", {}), "remoteInventory": manifest.get("remoteInventory", {}),
              "runtime": manifest.get("runtime", {}), "relations": manifest.get("relations", {})}
    for name in sorted(INSPECTION_LAYERS):
        value = counts.get(name, {})
        layers[name] = {"status": "partial", "reason": "Recovered durable checkpoint; capture did not complete.",
                        "counts": value if isinstance(value, dict) else {}, "artifacts": [],
                        "evidence": {"source": "verified durable checkpoint"}}
    report = {"reportVersion": 2, "layers": layers, "limitations": ["Recovery includes only the last verified checkpoint; later data may be absent."],
              "sourceFidelity": {"kind": "reconstructed_client_output", "originalSourceChecksum": "unavailable"}}
    for field in ("exporterVersion", "status", "capturedAtUtc", "endedReason", "game", "client", "settings",
                  "stats", "scriptExport", "diagnostics", "partialReasons", "errors", "continuous"):
        if field in manifest: report[field] = copy.deepcopy(manifest[field])
    report["dedup"] = copy.deepcopy(manifest.get("dedup", manifest.get("continuous", {})))
    lines = ["# Recovered export report", "", "- Status: partial", "- Recovery: verified durable checkpoint", "",
             "## Layers", "", "| Layer | Status | Reason |", "|---|---|---|"]
    lines += [f"| {name} | partial | Recovered durable checkpoint; capture did not complete. |" for name in sorted(layers)]
    lines += ["", "## Limitations", "", "- Data after the selected checkpoint may be absent.",
              "- Recording was not resumed; a new capture uses a new identity.", ""]
    return report, "\n".join(lines)


def save_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def materialize_checkpoint(root: Path, output: Path, path: Path, checkpoint: dict,
                           rows: list[dict], warnings: list[str]) -> None:
    """Copy and independently validate one frozen view; never modify input."""
    for row in rows:
        artifact = row["artifact"]
        checked_bytes(root, row["source"], artifact)
        target = checked_path(output, artifact["path"])
        target.parent.mkdir(parents=True, exist_ok=True)
        with checked_path(root, row["source"]).open("rb") as source, target.open("xb") as destination:
            shutil.copyfileobj(source, destination, length=1024 * 1024)
        checked_bytes(output, artifact["path"], artifact)
    manifest = copy.deepcopy(checkpoint["manifest"])
    manifest["status"] = "partial"
    manifest["endedReason"] = "recovered_checkpoint"
    reasons = manifest.get("partialReasons")
    if not isinstance(reasons, list): reasons = []
    if "recovered_checkpoint" not in reasons: reasons.append("recovered_checkpoint")
    manifest["partialReasons"] = reasons
    manifest["artifactIndex"] = {"path": "artifacts/index.json", "version": 1}
    manifest["report"] = {"version": 2, "path": "report.json", "markdownPath": "report.md"}
    manifest["recovery"] = {"checkpoint": path.name, "lastSequence": checkpoint["lastSequence"],
                            "newCaptureRequired": True, "warnings": warnings}
    if isinstance(manifest.get("identity"), dict):
        manifest["identity"]["lastSequence"] = checkpoint["lastSequence"]
    recount(output, manifest, rows)
    report, markdown = make_report(manifest)
    save_json(output / "manifest.json", manifest)
    save_json(output / "report.json", report)
    (output / "report.md").write_text(markdown, encoding="utf-8")
    save_json(output / "artifacts/index.json", {"version": 1, "artifacts": [r["artifact"] for r in rows]})
    try:
        if any(event["sequence"] > checkpoint["lastSequence"] for event in iter_events(output)):
            raise RecoveryError("journal exceeds durable sequence")
    except ReconstructionError as exc:
        raise RecoveryError(f"invalid recovered journal: {exc}") from exc
    issues = validate_folder(output)
    if issues: raise RecoveryError("recovered dataset failed validation: " + "; ".join(issues))


def recover(root: Path, output: Path) -> dict:
    root = root.resolve(strict=True)
    output = output.resolve()
    if output == root or output.is_relative_to(root):
        raise RecoveryError("output must be outside the source capture")
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise RecoveryError("output directory must be empty")
    path, checkpoint, rows, warnings = select_checkpoint(root)
    output.mkdir(parents=True, exist_ok=True)
    materialize_checkpoint(root, output, path, checkpoint, rows, warnings)
    return {"checkpoint": path.name, "lastSequence": checkpoint["lastSequence"],
            "artifacts": len(rows), "warnings": warnings, "output": str(output)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--output", type=Path, help="new or empty directory for the recovered dataset")
    args = parser.parse_args()
    try:
        if args.output:
            result = recover(args.folder, args.output)
        else:
            path, checkpoint, rows, warnings = select_checkpoint(args.folder)
            result = {"checkpoint": path.name, "lastSequence": checkpoint["lastSequence"],
                      "artifacts": len(rows), "warnings": warnings, "pending": checkpoint.get("pending", {})}
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (RecoveryError, OSError, ValueError, TypeError) as exc:
        print(f"Recovery error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
