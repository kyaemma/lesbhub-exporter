#!/usr/bin/env python3
"""Read and independently reconstruct v0.9 Lesbhub export histories.

This module intentionally reads the on-disk contract rather than exporter RAM
caches. It is also usable by validators and small offline inspection tools.
"""
from __future__ import annotations

import json
import heapq
import re
from pathlib import Path
from typing import Any, Iterator


class ReconstructionError(ValueError):
    """Raised when an export history is incomplete, malformed, or inconsistent."""


def _json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ReconstructionError(f"{path}: cannot read JSON ({exc})") from exc


def _safe_relative(folder: Path, value: Any) -> Path:
    if (not isinstance(value, str) or not value or "\\" in value
            or value.startswith("/") or ":" in value):
        raise ReconstructionError(f"unsafe relative path: {value!r}")
    parts = value.split("/")
    if any(part in {"", ".", ".."} for part in parts):
        raise ReconstructionError(f"unsafe relative path: {value!r}")
    result = folder.joinpath(*parts)
    try:
        result.resolve().relative_to(folder.resolve())
    except ValueError as exc:
        raise ReconstructionError(f"unsafe relative path: {value!r}") from exc
    return result


def _state_index(folder: Path) -> dict[int, dict[str, Any]]:
    index_path = folder / "gui" / "states" / "index.json"
    index = _json(index_path)
    if not isinstance(index, dict) or index.get("schemaVersion") != 2:
        raise ReconstructionError("GUI state index must use schemaVersion 2")
    descriptors = index.get("states")
    if descriptors == {}:
        descriptors = []
    if not isinstance(descriptors, list):
        raise ReconstructionError("GUI state index states must be an array")
    result: dict[int, dict[str, Any]] = {}
    paths: set[str] = set()
    for descriptor in descriptors:
        if not isinstance(descriptor, dict):
            raise ReconstructionError("GUI state descriptor must be an object")
        state_id, path = descriptor.get("stateId"), descriptor.get("path")
        if (not isinstance(state_id, int) or isinstance(state_id, bool) or state_id < 1
                or state_id in result):
            raise ReconstructionError(f"invalid or duplicate GUI stateId: {state_id!r}")
        if not isinstance(path, str) or path in paths:
            raise ReconstructionError(f"invalid or duplicate GUI state path: {path!r}")
        expected = f"gui/states/state{state_id:06d}.json"
        if path != expected:
            raise ReconstructionError(f"state {state_id} has unexpected path {path!r}")
        result[state_id] = descriptor
        paths.add(path)
    for path in (folder / "gui" / "states").glob("state*.json"):
        relative = path.relative_to(folder).as_posix()
        if relative not in paths:
            raise ReconstructionError(f"unindexed GUI state file: {relative}")
    return result


def indexed_gui_lookup_paths(folder: str | Path) -> set[str]:
    """Validate content-addressed GUI lookup records and return their safe paths."""
    folder = Path(folder)
    states = _state_index(folder)
    indexed: set[str] = set()
    referenced_states: set[int] = set()
    slots_by_digest: dict[str, list[int]] = {}
    lookup_root = folder / "gui" / "states" / "lookup"
    for path in lookup_root.rglob("*.json") if lookup_root.exists() else ():
        relative = path.relative_to(folder).as_posix()
        match = re.fullmatch(r"gui/states/lookup/([A-Za-z0-9_-]+)/([1-9][0-9]*)\.json", relative)
        if not match:
            raise ReconstructionError(f"invalid GUI lookup path: {relative}")
        digest, slot_text = match.groups()
        slot = int(slot_text)
        row = _json(path)
        if (not isinstance(row, dict) or row.get("schemaVersion") != 2
                or row.get("digest") != digest):
            raise ReconstructionError(f"{relative}: invalid GUI lookup descriptor")
        state_id = row.get("stateId")
        if not isinstance(state_id, int) or isinstance(state_id, bool) or state_id not in states:
            raise ReconstructionError(f"{relative}: lookup references an unknown state")
        if row.get("path") != f"gui/states/state{state_id:06d}.json":
            raise ReconstructionError(f"{relative}: lookup state path mismatch")
        if state_id in referenced_states:
            raise ReconstructionError(f"{relative}: state is referenced by multiple lookup records")
        referenced_states.add(state_id)
        slots_by_digest.setdefault(digest, []).append(slot)
        indexed.add(relative)
    if referenced_states != set(states):
        missing = sorted(set(states) - referenced_states)
        raise ReconstructionError(f"GUI states missing lookup descriptors: {missing}")
    for digest, slots in slots_by_digest.items():
        if sorted(slots) != list(range(1, len(slots) + 1)):
            raise ReconstructionError(f"GUI lookup slots are not contiguous for digest {digest}")
    return indexed


def _apply_gui_state(folder: Path, state_id: int,
                     descriptors: dict[int, dict[str, Any]],
                     memo: dict[int, dict[Any, dict[str, Any]]],
                     visiting: set[int]) -> dict[Any, dict[str, Any]]:
    if state_id in memo:
        return memo[state_id]
    if state_id in visiting:
        raise ReconstructionError(f"cycle in GUI state bases at state {state_id}")
    descriptor = descriptors.get(state_id)
    if descriptor is None:
        raise ReconstructionError(f"GUI state {state_id} is not indexed")
    visiting.add(state_id)
    relative = _safe_relative(folder, descriptor["path"])
    state = _json(relative)
    if not isinstance(state, dict) or state.get("schemaVersion") != 2 or state.get("stateId") != state_id:
        raise ReconstructionError(f"{relative}: invalid state document/header")
    base_id = state.get("baseStateId")
    if base_id is None:
        elements: dict[Any, dict[str, Any]] = {}
    else:
        if not isinstance(base_id, int) or isinstance(base_id, bool) or base_id == state_id:
            raise ReconstructionError(f"{relative}: invalid baseStateId")
        elements = dict(_apply_gui_state(folder, base_id, descriptors, memo, visiting))
    upserts = state.get("upserts")
    removes = state.get("removes")
    if not isinstance(upserts, list) or not isinstance(removes, list):
        raise ReconstructionError(f"{relative}: upserts/removes must be arrays")
    removed_ids: set[int] = set()
    for instance_id in removes:
        if not isinstance(instance_id, int) or isinstance(instance_id, bool) or instance_id < 1:
            raise ReconstructionError(f"{relative}: invalid removed InstanceId {instance_id!r}")
        if instance_id in removed_ids:
            raise ReconstructionError(f"{relative}: duplicate removed InstanceId {instance_id}")
        removed_ids.add(instance_id)
        if instance_id not in elements:
            raise ReconstructionError(f"{relative}: removal of absent InstanceId {instance_id}")
        del elements[instance_id]
    seen: set[int] = set()
    for row in upserts:
        if not isinstance(row, dict):
            raise ReconstructionError(f"{relative}: upsert must be an object")
        instance_id = row.get("instanceId")
        if not isinstance(instance_id, int) or isinstance(instance_id, bool) or instance_id < 1:
            raise ReconstructionError(f"{relative}: upsert has invalid InstanceId")
        if instance_id in removed_ids:
            raise ReconstructionError(f"{relative}: InstanceId {instance_id} is both removed and upserted")
        if instance_id in seen:
            raise ReconstructionError(f"{relative}: duplicate upsert InstanceId {instance_id}")
        seen.add(instance_id)
        if not isinstance(row.get("parentInstanceId"), (int, type(None))):
            raise ReconstructionError(f"{relative}: invalid parentInstanceId for {instance_id}")
        if not isinstance(row.get("className"), str) or not isinstance(row.get("path"), str):
            raise ReconstructionError(f"{relative}: upsert lacks className/path for {instance_id}")
        if row.get("properties") == []:
            row = dict(row)
            row["properties"] = {}
        if not isinstance(row.get("properties"), dict):
            raise ReconstructionError(f"{relative}: invalid properties for {instance_id}")
        elements[instance_id] = row
    if len(elements) != state.get("elementCount") or len(elements) != descriptor.get("elementCount"):
        raise ReconstructionError(f"{relative}: reconstructed element count mismatch")
    for instance_id, row in elements.items():
        parent_id = row.get("parentInstanceId")
        if parent_id is not None:
            parent = elements.get(parent_id)
            if parent is not None:
                expected_parent_path = parent.get("path")
                row_parent_path = row.get("parentPath")
                if row_parent_path is not None and row_parent_path != expected_parent_path:
                    raise ReconstructionError(f"{relative}: {instance_id} parentPath differs from parent InstanceId")
    visiting.remove(state_id)
    memo[state_id] = elements
    return elements


def reconstruct_gui(folder: str | Path, stateId: int) -> list[dict[str, Any]]:
    """Reconstruct one indexed v0.9 GUI state as sorted full projection rows."""
    folder = Path(folder)
    descriptors = _state_index(folder)
    rows = _apply_gui_state(folder, stateId, descriptors, {}, set())
    return [rows[key] for key in sorted(rows)]


def _journal_streams(folder: Path) -> dict[str, dict[str, Any]]:
    manifest = _json(folder / "manifest.json")
    journal = manifest.get("journal") if isinstance(manifest, dict) else None
    if not isinstance(journal, dict):
        raise ReconstructionError("manifest journal declaration is missing")
    if journal.get("version", 1) != 1 or journal.get("path") != "journal/index.json":
        raise ReconstructionError("manifest journal declaration must reference journal/index.json version 1")
    index_path = _json(folder / "journal" / "index.json")
    if not isinstance(index_path, dict) or index_path.get("version") != 1:
        raise ReconstructionError("journal/index.json must use version 1")
    index_streams = index_path.get("streams")
    if not isinstance(index_streams, dict):
        raise ReconstructionError("journal index streams must be an object")
    streams = journal.get("streams")
    # The manifest may embed the declarations for convenience/checkpointing.
    # When present, require exact parity with the completed durable index.
    if streams is not None and streams != index_streams:
        raise ReconstructionError("manifest journal declaration differs from journal/index.json")
    return index_streams


def _stream_events(folder: Path, stream_name: str, stream: dict) -> Iterator[dict[str, Any]]:
    """Read at most one segment from this already ordered stream at a time."""
    if not isinstance(stream, dict) or not isinstance(stream.get("segments"), list):
        raise ReconstructionError(f"invalid journal stream declaration: {stream_name}")
    count = 0
    prior_stream_sequence = 0
    for segment in stream["segments"]:
        if not isinstance(segment, dict):
            raise ReconstructionError(f"invalid journal segment in {stream_name}")
        path = _safe_relative(folder, segment.get("path"))
        relative = path.relative_to(folder).as_posix()
        if not re.fullmatch(rf"journal/{re.escape(stream_name)}/b[0-9]{{6}}\.json", relative):
            raise ReconstructionError(f"invalid journal segment path: {relative}")
        payload = _json(path)
        if (not isinstance(payload, dict) or payload.get("version") != 1
                or payload.get("stream") != stream_name or not isinstance(payload.get("rows"), list)):
            raise ReconstructionError(f"{path}: invalid journal segment header")
        segment_rows = payload["rows"]
        if len(segment_rows) != segment.get("count"):
            raise ReconstructionError(f"{path}: segment count mismatch")
        first = last = None
        for row in segment_rows:
            if not isinstance(row, dict):
                raise ReconstructionError(f"{path}: event row must be an object")
            sequence = row.get("sequence")
            if not isinstance(sequence, int) or isinstance(sequence, bool) or sequence < 1:
                raise ReconstructionError(f"{path}: invalid event sequence")
            if sequence <= prior_stream_sequence:
                raise ReconstructionError(f"{path}: stream sequence is not strictly increasing")
            first = sequence if first is None else first
            last = sequence
            prior_stream_sequence = sequence
            result = dict(row)
            result["stream"] = stream_name
            yield result
        if first != segment.get("firstSequence") or last != segment.get("lastSequence"):
            raise ReconstructionError(f"{path}: sequence range differs from declaration")
        count += len(segment_rows)
    if count != stream.get("events"):
        raise ReconstructionError(f"journal stream {stream_name}: event count mismatch")


def iter_events(folder: str | Path) -> Iterator[dict[str, Any]]:
    """Merge durable ordered streams without retaining the entire history.

    Fully consume the iterator to verify all segment counts and ranges.
    """
    folder = Path(folder)
    streams = _journal_streams(folder)
    iterators = [_stream_events(folder, name, stream) for name, stream in streams.items()]
    previous = 0
    for row in heapq.merge(*iterators, key=lambda row: row["sequence"]):
        sequence = row["sequence"]
        if sequence <= previous:
            raise ReconstructionError(f"duplicate global sequence {sequence}")
        previous = sequence
        yield row


def replay_structure(folder: str | Path, through_sequence: int | None = None) -> dict[int, dict[str, Any]]:
    """Replay metadata baseline and add/update/remove records by InstanceId.

    v0.9 exports keep their normal categorized/flat chunk paths. Each row is
    ordered by its global sequence, so duplicate paths remain distinct.
    """
    from validate_export import parse_chunk, parse_location

    folder = Path(folder)
    manifest = _json(folder / "manifest.json")
    inspection_version = manifest.get("inspectionVersion") if isinstance(manifest, dict) else None
    if inspection_version != 2:
        raise ReconstructionError("structural replay requires inspectionVersion 2")
    layout = manifest.get("layout", {})
    layout_version = layout.get("version", 1) if isinstance(layout, dict) else -1
    if layout_version not in {1, 2}:
        raise ReconstructionError("unsupported chunk layout")
    operations: list[tuple[int, dict[str, Any]]] = []
    issues: list[str] = []
    for path in folder.rglob("*"):
        if not path.is_file() or path.suffix not in {".json", ".jsonl", ".csv"}:
            continue
        relative = path.relative_to(folder).as_posix()
        if relative == "manifest.json" or relative.startswith(("journal/", "gui/states/")):
            continue
        location = parse_location(Path(relative), layout_version)
        if location is None:
            continue
        service, capture_pass, _, _, category = location
        records = parse_chunk(path, service, capture_pass, category, issues)
        for row in records:
            if not isinstance(row, dict):
                raise ReconstructionError(f"{relative}: record must be an object")
            sequence = row.get("sequence")
            instance_id = row.get("instanceId")
            if (not isinstance(sequence, int) or isinstance(sequence, bool) or sequence < 1
                    or not isinstance(instance_id, int) or isinstance(instance_id, bool) or instance_id < 1):
                raise ReconstructionError(f"{relative}: record needs positive sequence and instanceId")
            if through_sequence is None or sequence <= through_sequence:
                operations.append((sequence, row))
    if issues:
        raise ReconstructionError("invalid metadata chunks: " + "; ".join(issues))
    operations.sort(key=lambda item: item[0])
    current: dict[int, dict[str, Any]] = {}
    seen_sequences: set[int] = set()
    for sequence, row in operations:
        if sequence in seen_sequences:
            raise ReconstructionError(f"duplicate global sequence {sequence}")
        seen_sequences.add(sequence)
        instance_id = row["instanceId"]
        operation = row.get("operation", "add")
        if operation == "remove":
            if instance_id not in current:
                raise ReconstructionError(f"remove of absent InstanceId {instance_id} at sequence {sequence}")
            del current[instance_id]
        elif operation in {"add", "update"}:
            if operation == "add" and instance_id in current:
                raise ReconstructionError(f"duplicate add for InstanceId {instance_id} at sequence {sequence}")
            if operation == "update" and instance_id not in current:
                raise ReconstructionError(f"update of absent InstanceId {instance_id} at sequence {sequence}")
            current[instance_id] = row
        else:
            raise ReconstructionError(f"unknown operation {operation!r} at sequence {sequence}")
    for instance_id, row in current.items():
        parent_id = row.get("parentInstanceId")
        if parent_id is not None and parent_id in current:
            parent_path = current[parent_id].get("path")
            if row.get("parentPath") is not None and row["parentPath"] != parent_path:
                raise ReconstructionError(f"InstanceId {instance_id} parentPath differs from parent InstanceId")
    return current
