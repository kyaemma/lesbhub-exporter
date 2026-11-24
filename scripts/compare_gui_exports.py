#!/usr/bin/env python3
"""Compare GUI state graphs across controlled v0.8 and v0.9 captures.

IDs are capture-local. Siblings with equal names remain separate nodes, and
children are matched as an unordered multiset. Whole-store savings are only
reported when the complete normalized state sets match.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from collections import Counter, defaultdict

from reconstruct_export import ReconstructionError, iter_events, reconstruct_gui
from validate_export import parse_chunk, parse_location

PREFIX = "StarterGui/LesbhubV09Controlled"


def array(value):
    return [] if value == {} else value


def encode(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def node_name(row, native_names):
    path = row.get("path")
    if not isinstance(path, str) or not path: raise ValueError("GUI row has no path")
    segment = path.rsplit("/", 1)[-1]
    metadata = native_names.get(row.get("instanceId"))
    if isinstance(metadata, dict) and metadata.get("robloxPath") == path and isinstance(metadata.get("name"), str):
        native = re.sub(r"[./\\]", "_", metadata["name"])
        if segment == native or re.fullmatch(re.escape(native) + r"~(?:[2-9]|[1-9][0-9]+)", segment):
            return native
    # Never infer that an actual name ending in ~N is a generated ordinal.
    return segment


def graph_projection(elements, native_names, fixture_only, parent_evidence=None):
    if not isinstance(elements, list): raise ValueError("state elements must be a list")
    nodes = {}; certain = True
    for row in elements:
        if not isinstance(row, dict) or row.get("instanceId") is None: raise ValueError("invalid GUI element")
        ident = row["instanceId"]
        if ident in nodes: raise ValueError("duplicate GUI instanceId")
        path = row.get("path")
        if not isinstance(path, str): raise ValueError("GUI element path missing")
        inside = path == PREFIX or path.startswith(PREFIX + "/")
        if fixture_only and not inside: continue
        props = row.get("properties")
        if props == []: props = {}
        if not isinstance(props, dict): raise ValueError("invalid GUI properties")
        segment = path.rsplit("/", 1)[-1]
        metadata = native_names.get(ident)
        if re.search(r"~(?:[2-9]|[1-9][0-9]+)$", segment):
            if not isinstance(metadata, dict) or metadata.get("robloxPath") != path or not isinstance(metadata.get("name"), str):
                certain = False
            else:
                native = re.sub(r"[./\\]", "_", metadata["name"])
                if segment != native and not re.fullmatch(re.escape(native) + r"~(?:[2-9]|[1-9][0-9]+)", segment):
                    certain = False
        nodes[ident] = {"path": path, "parent": row.get("parentInstanceId"),
                        "name": node_name(row, native_names), "className": row.get("className"),
                        "properties": props}
    if fixture_only and not any(row["path"] == PREFIX for row in nodes.values()):
        raise ValueError("controlled fixture root missing from state")
    children, parents, remaining, roots = defaultdict(list), {}, {}, []
    for ident, row in nodes.items():
        parent = row["parent"]
        if parent is not None and parent in nodes:
            parents[ident] = parent
            children[parent].append(ident)
        else:
            # Preserve root boundary location where observed; IDs outside this graph
            # cannot be matched safely across captures.
            root_parent = "<outside-fixture>" if fixture_only else (row["path"].rpartition("/")[0] if parent is not None else "<nil>")
            parent_class = "<outside-fixture>" if fixture_only else "<nil>"
            if not fixture_only and parent is not None:
                evidence = (parent_evidence or {}).get(parent)
                metadata = native_names.get(parent)
                if evidence is not None:
                    classes, paths = evidence
                    if len(classes) == 1 and root_parent in paths:
                        parent_class = next(iter(classes))
                    else:
                        parent_class = "<unknown>"; certain = False
                elif isinstance(metadata, dict) and metadata.get("robloxPath") == root_parent and isinstance(metadata.get("className"), str):
                    parent_class = metadata["className"]
                else:
                    parent_class = "<unknown>"; certain = False
            roots.append((ident, root_parent, parent_class))
    remaining = {ident: len(children[ident]) for ident in nodes}
    queue = [ident for ident, count in remaining.items() if count == 0]
    digests = {}
    while queue:
        ident = queue.pop()
        row = nodes[ident]
        value = {"name": row["name"], "className": row["className"], "properties": row["properties"],
                 "children": sorted(digests[child] for child in children[ident])}
        digests[ident] = hashlib.sha256(encode(value)).hexdigest()
        parent = parents.get(ident)
        if parent is not None:
            remaining[parent] -= 1
            if remaining[parent] == 0: queue.append(parent)
    if len(digests) != len(nodes): raise ValueError("cycle in GUI parent graph")
    root_graph = sorted((parent_path, parent_class, digests[ident]) for ident, parent_path, parent_class in roots)
    graph_hash = hashlib.sha256(encode(root_graph)).hexdigest()
    projection = []
    if fixture_only:
        # Normalized reconstructed projection bytes are a secondary logical-size
        # measure; they are not actual bytes written or an on-disk savings claim.
        for row in nodes.values():
            path = row["path"][len(PREFIX):] or "/"
            parent = nodes.get(row["parent"])
            parent_path = ((parent["path"][len(PREFIX):] or "/") if parent else "<outside-fixture>")
            projection.append({"path": path, "parent": parent_path, "className": row["className"],
                               "properties": row["properties"]})
        projection.sort(key=lambda row: encode(row))
    return graph_hash, len(encode(projection)) if fixture_only else None, certain


def read_parent_evidence(folder: Path):
    """Gather parent classes from metadata records, never from names alone."""
    manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
    layout = manifest.get("layout", {}).get("version", 1)
    if layout not in (1, 2): raise ValueError("unsupported metadata layout")
    evidence = {}
    for path in folder.rglob("*"):
        if not path.is_file() or path.suffix not in {".json", ".jsonl", ".csv"}: continue
        location = parse_location(path.relative_to(folder), layout)
        if location is None: continue
        service, capture_pass, _, _, category = location
        issues = []
        records = parse_chunk(path, service, capture_pass, category, issues)
        if issues: raise ValueError("invalid metadata while proving parent classes: " + "; ".join(issues))
        for row in records:
            if not isinstance(row, dict): continue
            ident, class_name, record_path = row.get("instanceId"), row.get("className"), row.get("path")
            if not isinstance(ident, int) or isinstance(ident, bool) or ident < 1: continue
            if not isinstance(class_name, str) or not isinstance(record_path, str): continue
            classes, paths = evidence.setdefault(ident, (set(), set()))
            classes.add(class_name); paths.add(record_path)
    return evidence


def read_transition_walk(folder: Path, schema: int, index: dict, state_hashes: dict):
    aggregates = array(index.get("transitions", []))
    if not isinstance(aggregates, list): raise ValueError("invalid transition aggregates")
    total = 0
    aggregate_counts = {}
    for item in aggregates:
        if not isinstance(item, dict) or not isinstance(item.get("count"), int) or isinstance(item.get("count"), bool) or item["count"] < 1:
            raise ValueError("invalid transition aggregate count")
        total += item["count"]
        key = (item.get("fromStateId"), item.get("toStateId"), item.get("reason"))
        if key in aggregate_counts: raise ValueError("duplicate transition aggregate")
        aggregate_counts[key] = item["count"]
    result = {"aggregateKinds": len(aggregates), "aggregateOccurrences": total}
    if schema == 1:
        path = folder / "gui/transitions.jsonl"
        if not path.is_file():
            result.update(journalAvailable=False, journalOccurrences=None, aggregateMatchesJournal=None)
            return result, None
        rows = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]
    else:
        rows = [row for row in iter_events(folder) if row.get("stream") == "gui-transitions"]
    previous_sequence, previous_state, continuous = 0, None, True
    journal_counts = Counter()
    walk = []
    for row in rows:
        if not isinstance(row, dict) or row.get("event") != "gui_state_transition": raise ValueError("invalid GUI transition row")
        sequence, source, target = row.get("sequence"), row.get("fromStateId"), row.get("toStateId")
        if not isinstance(sequence, int) or isinstance(sequence, bool) or sequence <= previous_sequence:
            raise ValueError("GUI transition sequences must be strictly increasing")
        if source not in state_hashes or target not in state_hashes: raise ValueError("transition references missing state")
        if previous_state is not None and source != previous_state: continuous = False
        journal_counts[(source, target, row.get("reason"))] += 1
        walk.append([state_hashes[source], state_hashes[target]])
        previous_sequence, previous_state = sequence, target
    result.update(journalAvailable=True, journalOccurrences=len(rows), aggregateMatchesJournal=(aggregate_counts == journal_counts),
                  transitionWalkContinuous=continuous)
    return result, walk


def inspect(folder: Path):
    index = json.loads((folder / "gui/states/index.json").read_text(encoding="utf-8"))
    descriptors = array(index.get("states"))
    if not isinstance(descriptors, list): raise ValueError("GUI index has no states list")
    schema = index.get("schemaVersion", 1)
    if schema not in (1, 2): raise ValueError(f"unsupported GUI schema {schema}")
    parent_evidence = read_parent_evidence(folder)
    try:
        raw_names = array(json.loads((folder / "gui/index.json").read_text(encoding="utf-8")).get("elements"))
        native_names = {row["instanceId"]: row for row in raw_names if isinstance(row, dict) and "instanceId" in row}
    except (OSError, ValueError, TypeError):
        native_names = {}
    hashes, full_hashes, counts, logical_sizes, state_hashes = set(), set(), {}, {}, {}
    full_certain = fixture_certain = True
    for state in descriptors:
        state_id = state.get("stateId")
        if schema == 2:
            elements = reconstruct_gui(folder, state_id)
        else:
            expected = f"gui/states/state{state_id:06d}.json"
            if state.get("path") != expected: raise ValueError("unexpected state path")
            payload = json.loads((folder / expected).read_text(encoding="utf-8"))
            elements = array(payload.get("elements"))
        fingerprint, logical_bytes, fixture_state_certain = graph_projection(elements, native_names, True, parent_evidence)
        fixture_certain = fixture_certain and fixture_state_certain
        full_hash, _, certain = graph_projection(elements, native_names, False, parent_evidence)
        if state_id in state_hashes: raise ValueError("duplicate state ID")
        state_hashes[state_id] = full_hash
        full_certain = full_certain and certain
        hashes.add(fingerprint); full_hashes.add(full_hash)
        logical_sizes[fingerprint] = logical_bytes
        counts[fingerprint] = counts.get(fingerprint, 0) + int(state.get("observations", state.get("visits", 0)))
    files = [p for p in (folder / "gui/states").rglob("*") if p.is_file()]
    transition_stats, walk = read_transition_walk(folder, schema, index, state_hashes)
    return {"schemaVersion": schema, "indexedStates": len(descriptors), "uniqueFixtureStates": len(hashes),
            "stateStorageBytes": sum(p.stat().st_size for p in files), "stateStorageFiles": len(files),
            "normalizedStateHashes": sorted(hashes), "observationsByState": counts,
            "fixtureProjectionFullEquivalentBytes": sum(logical_sizes.values()),
            "fixtureGraphComparisonCertain": fixture_certain,
            "completeGraphComparisonCertain": full_certain, "transitions": transition_stats}, hashes, full_hashes, walk


def compare(old: Path, new: Path, include_walk=False):
    before, old_hashes, old_full, old_walk = inspect(old); after, new_hashes, new_full, new_walk = inspect(new)
    fixture_certain = before["fixtureGraphComparisonCertain"] and after["fixtureGraphComparisonCertain"]
    full_certain = before["completeGraphComparisonCertain"] and after["completeGraphComparisonCertain"]
    same = (bool(old_hashes) and old_hashes == new_hashes) if fixture_certain else None
    full_same = (bool(old_full) and old_full == new_full) if full_certain else None
    result = {"old": before, "new": after, "equalObservedFixtureStateSets": same,
              "overlapCount": len(old_hashes & new_hashes), "onlyOldCount": len(old_hashes-new_hashes),
              "onlyNewCount": len(new_hashes-old_hashes), "equalCompleteGuiStateSets": full_same,
              "limitation": "Null equality means available paths or parent classes cannot prove equivalence. State-set equality does not establish equal transition timing or complete coverage of rapid changes. Fixture projection bytes are normalized logical estimates, not disk savings."}
    old_stats, new_stats = before["transitions"], after["transitions"]
    walk_certain = (full_certain and old_walk is not None and new_walk is not None
                    and old_stats.get("transitionWalkContinuous") and new_stats.get("transitionWalkContinuous")
                    and old_stats.get("aggregateMatchesJournal") and new_stats.get("aggregateMatchesJournal"))
    result["equalNormalizedTransitionWalk"] = old_walk == new_walk if walk_certain else None
    result["transitionWalkNote"] = "Compares ordered normalized state pairs; elapsed times, causes and unobserved changes are not compared."
    if include_walk:
        before["normalizedTransitionWalk"] = old_walk
        after["normalizedTransitionWalk"] = new_walk
    if same and full_same and before["stateStorageBytes"]:
        result["savedBytes"] = before["stateStorageBytes"] - after["stateStorageBytes"]
        result["savedPercent"] = 100 * result["savedBytes"] / before["stateStorageBytes"]
    else:
        result["sizeComparison"] = "Not comparable: fixture or complete GUI state sets differ or are empty."
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("v08", type=Path); parser.add_argument("v09", type=Path)
    parser.add_argument("--normalized-transition-walk", action="store_true", help="include ordered normalized from/to hashes")
    args = parser.parse_args()
    try:
        print(json.dumps(compare(args.v08, args.v09, args.normalized_transition_walk), indent=2)); return 0
    except (OSError, ValueError, TypeError, KeyError, ReconstructionError) as exc:
        print(f"Comparison error: {exc}", file=sys.stderr); return 1


if __name__ == "__main__": raise SystemExit(main())
