#!/usr/bin/env python3
"""Validate the shape and accounting of a Lesbhub Exporter V1 directory."""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import re
import sys

CHUNK_RE = re.compile(r"^([A-Za-z][A-Za-z0-9]*)-p([1-9][0-9]*)-([0-9]{4,})\.(json|jsonl|csv)$")
REQUIRED_RECORD = {"path", "parentPath", "name", "className", "depth", "properties"}
STATUSES = {"complete", "partial", "cancelled", "stopped", "recording"}


def parse_chunk(path: Path, service: str, capture_pass: int, issues: list[str]):
    try:
        if path.suffix == ".json":
            body = json.loads(path.read_text(encoding="utf-8"))
            if body.get("schemaVersion") != 1:
                issues.append(f"{path.name}: wrong schema version")
            if body.get("service") != service or body.get("pass") != capture_pass:
                issues.append(f"{path.name}: service or pass header mismatch")
            records = body.get("records", [])
            if not isinstance(records, list):
                issues.append(f"{path.name}: records must be an array")
                return []
            return records
        if path.suffix == ".jsonl":
            lines = path.read_text(encoding="utf-8").splitlines()
            return [json.loads(line) for line in lines if line.strip()]
        with path.open("r", encoding="utf-8", newline="") as stream:
            reader = csv.DictReader(stream)
            expected = ["path", "parentPath", "name", "className", "depth", "properties_json"]
            if reader.fieldnames != expected:
                issues.append(f"{path.name}: incorrect CSV header")
                return []
            records = []
            for row in reader:
                try:
                    records.append({
                        "path": row["path"], "parentPath": row["parentPath"],
                        "name": row["name"], "className": row["className"],
                        "depth": int(row["depth"]),
                        "properties": json.loads(row["properties_json"]),
                    })
                except (TypeError, ValueError, KeyError, json.JSONDecodeError) as exc:
                    issues.append(f"{path.name}: invalid CSV record ({exc})")
            return records
    except (OSError, ValueError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        issues.append(f"{path.name}: unreadable chunk ({exc})")
        return []


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
    if manifest.get("schemaVersion") != 1:
        issues.append("unsupported manifest schemaVersion")
    if manifest.get("status") not in STATUSES:
        issues.append("invalid capture status")
    if manifest.get("clientOnly") is not True:
        issues.append("clientOnly must be true")
    if not isinstance(manifest.get("game"), dict):
        issues.append("game metadata is missing")
    stats = manifest.get("stats")
    services = manifest.get("services")
    if not isinstance(stats, dict):
        return issues + ["missing stats object"]
    if not isinstance(services, dict):
        return issues + ["missing services object"]
    expected_format = manifest.get("settings", {}).get("format")
    if expected_format not in {"json", "jsonl", "csv"}:
        issues.append("invalid format in settings")
    chunks = sorted(p for p in folder.iterdir() if p.is_file() and CHUNK_RE.match(p.name))
    unknown = [
        p.name for p in folder.iterdir()
        if p.is_file() and p.name != "manifest.json"
        and p.suffix in {".json", ".jsonl", ".csv"}
        and not CHUNK_RE.match(p.name)
    ]
    if unknown:
        issues.append("unknown data file names: " + ", ".join(unknown[:5]))
    service_records = {name: 0 for name in services}
    service_files = {name: 0 for name in services}
    total_records, total_bytes = 0, 0
    chunks_by_pass: dict[tuple[str, int], list[int]] = {}

    for chunk in chunks:
        match = CHUNK_RE.match(chunk.name)
        assert match is not None
        service, pass_raw, index_raw, fmt = match.groups()
        capture_pass, index = int(pass_raw), int(index_raw)
        chunks_by_pass.setdefault((service, capture_pass), []).append(index)
        if service not in services:
            issues.append(f"{chunk.name}: service not listed in manifest")
        if fmt != expected_format:
            issues.append(f"{chunk.name}: format differs from manifest")
        total_bytes += chunk.stat().st_size
        records = parse_chunk(chunk, service, capture_pass, issues)
        service_records[service] = service_records.get(service, 0) + len(records)
        service_files[service] = service_files.get(service, 0) + 1
        total_records += len(records)
        for n, record in enumerate(records):
            where = f"{chunk.name}: record {n + 1}"
            if not isinstance(record, dict) or not REQUIRED_RECORD.issubset(record):
                issues.append(f"{where}: missing required keys")
                continue
            if not isinstance(record["depth"], int) or record["depth"] < 0:
                issues.append(f"{where}: invalid depth")
            if not isinstance(record["properties"], dict):
                issues.append(f"{where}: properties must be an object")
            elif "Source" in record["properties"]:
                issues.append(f"{where}: script Source must not be exported")
            if not isinstance(record["path"], str) or not record["path"].startswith(service):
                issues.append(f"{where}: invalid root path")
            if not isinstance(record["parentPath"], str):
                issues.append(f"{where}: parentPath must be a string")

    for (service, capture_pass), indices in chunks_by_pass.items():
        if indices != list(range(1, len(indices) + 1)):
            issues.append(f"{service} pass {capture_pass}: nonconsecutive chunk indexes")
    for service, summary in services.items():
        if not isinstance(summary, dict):
            issues.append(f"{service}: summary is not an object")
            continue
        if summary.get("records") != service_records.get(service, 0):
            issues.append(f"{service}: record count differs from manifest")
        if summary.get("files") != service_files.get(service, 0):
            issues.append(f"{service}: file count differs from manifest")

    if stats.get("written") != total_records:
        issues.append("stats.written differs from chunk records")
    if stats.get("files") != len(chunks):
        issues.append("stats.files differs from chunk count")
    if stats.get("bytes") != total_bytes:
        issues.append("stats.bytes differs from data file bytes")
    if not isinstance(manifest.get("partialReasons"), list):
        issues.append("partialReasons must be an array")
    return issues


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
    print("OK: coherent Lesbhub Exporter V1 directory")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
