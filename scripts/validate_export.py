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

FLAT_RE = re.compile(r"^([A-Za-z][A-Za-z0-9]*)-p([1-9][0-9]*)-([0-9]{4,})\.(json|jsonl|csv)$")
NESTED_RE = re.compile(r"^p([1-9][0-9]*)-([0-9]{4,})\.(json|jsonl|csv)$")
CATEGORIES = {"scripts", "gui", "remotes", "values", "world",
              "assets", "structures", "other"}
REQUIRED_RECORD = {"path", "parentPath", "name", "className", "depth", "properties"}
STATUSES = {"complete", "partial", "cancelled", "stopped", "recording"}


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
            if reader.fieldnames != header:
                issues.append(f"{path}: invalid CSV header")
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
    for file in folder.rglob("*"):
        if not file.is_file() or file == manifest_path:
            continue
        if file.suffix not in {".json", ".jsonl", ".csv"}:
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
    print("OK: coherent Lesbhub Exporter dataset")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
