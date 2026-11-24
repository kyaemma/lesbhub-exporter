"""Synthetic v0.9 reconstruction contracts; no Roblox client is used."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import reconstruct_export
from reconstruct_export import ReconstructionError, iter_events, reconstruct_gui, replay_structure


def write_json(folder: Path, relative: str, value):
    path = folder / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")
    return path


def gui_row(instance_id, text, parent=None, path=None):
    return {
        "instanceId": instance_id,
        "parentInstanceId": parent,
        "className": "TextLabel",
        "path": path or f"PlayerGui/Panel/Label{instance_id}",
        "parentPath": "PlayerGui/Panel" if parent else "PlayerGui",
        "properties": {"Text": text, "Visible": True},
    }


class ReconstructExportTests(unittest.TestCase):
    def write_gui_ababa(self, folder):
        a = [gui_row(10, "Panel", path="PlayerGui/Panel"), gui_row(11, "A", 10)]
        b = [gui_row(11, "B", 10)]
        write_json(folder, "gui/states/state000001.json", {
            "schemaVersion": 2, "stateId": 1, "upserts": a, "removes": [], "elementCount": 2,
        })
        write_json(folder, "gui/states/state000002.json", {
            "schemaVersion": 2, "stateId": 2, "baseStateId": 1,
            "upserts": b, "removes": [], "elementCount": 2,
        })
        write_json(folder, "gui/states/index.json", {
            "schemaVersion": 2,
            "states": [
                {"stateId": 1, "path": "gui/states/state000001.json", "elementCount": 2, "visits": 3},
                {"stateId": 2, "path": "gui/states/state000002.json", "elementCount": 2, "visits": 2},
            ],
            "transitions": [
                {"fromStateId": 1, "toStateId": 2, "count": 2},
                {"fromStateId": 2, "toStateId": 1, "count": 2},
            ],
        })
        rows = [{"sequence": seq, "event": "gui_state_transition",
                 "fromStateId": 1 if seq % 2 else 2,
                 "toStateId": 2 if seq % 2 else 1}
                for seq in range(1, 5)]
        write_json(folder, "journal/gui-transitions/b000001.json", {
            "version": 1, "stream": "gui-transitions", "rows": rows,
        })
        streams = {"gui-transitions": {"segments": [
            {"path": "journal/gui-transitions/b000001.json", "count": 4,
             "firstSequence": 1, "lastSequence": 4}], "events": 4}}
        write_json(folder, "journal/index.json", {"version": 1, "streams": streams})
        write_json(folder, "manifest.json", {
            "inspectionVersion": 2, "journal": {"version": 1, "path": "journal/index.json", "streams": streams},
        })

    def test_gui_ababa_uses_two_projections_four_ordered_transitions(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.write_gui_ababa(folder)
            a = reconstruct_gui(folder, 1)
            b = reconstruct_gui(folder, 2)
            self.assertEqual(len(a), 2)
            self.assertEqual(len(b), 2)
            self.assertEqual(a[1]["properties"]["Text"], "A")
            self.assertEqual(b[1]["properties"]["Text"], "B")
            transitions = list(iter_events(folder))
            self.assertEqual([row["sequence"] for row in transitions], [1, 2, 3, 4])
            self.assertEqual([(row["fromStateId"], row["toStateId"]) for row in transitions],
                             [(1, 2), (2, 1), (1, 2), (2, 1)])

    def test_empty_json_objects_and_external_gui_parent_are_valid(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            write_json(folder, "gui/states/state000001.json", {
                "schemaVersion": 2, "stateId": 1,
                "upserts": [{"instanceId": 8, "parentInstanceId": 999,
                             "className": "Frame", "path": "PlayerGui/Panel",
                             "properties": []}],
                "removes": [], "elementCount": 1,
            })
            write_json(folder, "gui/states/index.json", {"schemaVersion": 2, "states": [
                {"stateId": 1, "path": "gui/states/state000001.json", "elementCount": 1}],
            })
            self.assertEqual(reconstruct_gui(folder, 1)[0]["properties"], {})

    def test_cycle_and_damaged_remove_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            write_json(folder, "gui/states/state000001.json", {
                "schemaVersion": 2, "stateId": 1, "baseStateId": 2,
                "upserts": [], "removes": [], "elementCount": 0,
            })
            write_json(folder, "gui/states/state000002.json", {
                "schemaVersion": 2, "stateId": 2, "baseStateId": 1,
                "upserts": [], "removes": [], "elementCount": 0,
            })
            write_json(folder, "gui/states/index.json", {"schemaVersion": 2, "states": [
                {"stateId": 1, "path": "gui/states/state000001.json", "elementCount": 0},
                {"stateId": 2, "path": "gui/states/state000002.json", "elementCount": 0},
            ]})
            with self.assertRaisesRegex(ReconstructionError, "cycle"):
                reconstruct_gui(folder, 1)

    def test_journal_retains_all_ten_thousand_repeated_remote_occurrences(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            rows = [{"sequence": seq, "instanceId": 7, "direction": "FireServer",
                     "signatureId": 1} for seq in range(1, 10_001)]
            write_json(folder, "journal/remote-observations/b000001.json", {
                "version": 1, "stream": "remote-observations", "rows": rows,
            })
            streams = {"remote-observations": {"segments": [
                {"path": "journal/remote-observations/b000001.json", "count": len(rows),
                 "firstSequence": 1, "lastSequence": 10_000}], "events": len(rows)}}
            write_json(folder, "journal/index.json", {"version": 1, "streams": streams})
            write_json(folder, "manifest.json", {
                "inspectionVersion": 2, "journal": {"version": 1, "path": "journal/index.json", "streams": streams},
            })
            events = list(iter_events(folder))
            self.assertEqual(len(events), 10_000)
            self.assertEqual(events[0]["sequence"], 1)
            self.assertEqual(events[-1]["sequence"], 10_000)
            self.assertEqual(sum(event["instanceId"] == 7 for event in events), 10_000)

    def test_idle_hour_reuses_one_gui_projection_without_journal_growth(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.write_gui_ababa(folder)
            # The idle fixture has one durable state and no event segments.
            state = json.loads((folder / "gui/states/state000001.json").read_text(encoding="utf-8"))
            state["upserts"] = [gui_row(10, "Panel", path="PlayerGui/Panel")]
            state["elementCount"] = 1
            write_json(folder, "gui/states/state000001.json", state)
            (folder / "gui/states/state000002.json").unlink()
            write_json(folder, "gui/states/index.json", {"schemaVersion": 2, "states": [
                {"stateId": 1, "path": "gui/states/state000001.json", "elementCount": 1, "visits": 3601}],
                "transitions": [],
            })
            empty_stream = {"gui-transitions": {"segments": [], "events": 0}}
            write_json(folder, "journal/index.json", {"version": 1, "streams": empty_stream})
            write_json(folder, "manifest.json", {
                "inspectionVersion": 2, "journal": {"version": 1, "path": "journal/index.json", "streams": empty_stream},
            })
            before = sorted(path.relative_to(folder).as_posix()
                            for path in (folder / "gui/states").glob("state*.json"))
            for _ in range(3600):
                self.assertEqual(reconstruct_gui(folder, 1)[0]["properties"]["Text"], "Panel")
            after = sorted(path.relative_to(folder).as_posix()
                           for path in (folder / "gui/states").glob("state*.json"))
            self.assertEqual(before, after)
            self.assertEqual(list(iter_events(folder)), [])

    def test_journal_merges_incrementally_and_detects_cross_stream_duplicates(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            streams = {}
            for name, sequences in (("gui-actions", (1, 3)), ("remote-observations", (2, 4))):
                segments = []
                for part, sequence in enumerate(sequences, 1):
                    path = f"journal/{name}/b{part:06d}.json"
                    write_json(folder, path, {"version": 1, "stream": name,
                                             "rows": [{"sequence": sequence}]})
                    segments.append({"path": path, "count": 1,
                                     "firstSequence": sequence, "lastSequence": sequence})
                streams[name] = {"segments": segments, "events": 2}
            write_json(folder, "journal/index.json", {"version": 1, "streams": streams})
            write_json(folder, "manifest.json", {"journal": {"version": 1, "path": "journal/index.json",
                                                              "streams": streams}})
            original, opened = reconstruct_export._json, []
            def read(path):
                opened.append(path.relative_to(folder).as_posix())
                return original(path)
            with patch.object(reconstruct_export, "_json", read):
                events = iter_events(folder)
                self.assertEqual(next(events)["sequence"], 1)
                self.assertFalse(any("b000002" in path for path in opened), "reader loaded future history")
                self.assertEqual([row["sequence"] for row in events], [2, 3, 4])
            duplicate = streams["gui-actions"]["segments"][1]
            duplicate.update(firstSequence=2, lastSequence=2)
            write_json(folder, duplicate["path"], {"version": 1, "stream": "gui-actions",
                                                  "rows": [{"sequence": 2}]})
            write_json(folder, "journal/index.json", {"version": 1, "streams": streams})
            write_json(folder, "manifest.json", {"journal": {"version": 1, "path": "journal/index.json",
                                                              "streams": streams}})
            with self.assertRaisesRegex(ReconstructionError, "duplicate global sequence"):
                list(iter_events(folder))

    def test_structure_replay_uses_instance_identity_and_order(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            write_json(folder, "manifest.json", {"inspectionVersion": 2, "layout": {"version": 1}})
            row = {"name": "Same", "className": "Folder", "path": "PlayerGui/Same",
                   "parentPath": "PlayerGui", "depth": 1, "properties": {},
                   "instanceId": 1, "sequence": 1, "operation": "add"}
            write_json(folder, "PlayerGui-p1-0001.json", {
                "schemaVersion": 1, "service": "PlayerGui", "pass": 1, "records": [row],
            })
            second = dict(row, instanceId=2, sequence=2)
            write_json(folder, "PlayerGui-p1-0002.json", {
                "schemaVersion": 1, "service": "PlayerGui", "pass": 1, "records": [second],
            })
            update = dict(row, sequence=3, operation="update", properties={"Visible": False})
            write_json(folder, "PlayerGui-p2-0001.json", {
                "schemaVersion": 1, "service": "PlayerGui", "pass": 2, "records": [update],
            })
            current = replay_structure(folder)
            self.assertEqual(set(current), {1, 2})
            self.assertEqual(current[1]["properties"], {"Visible": False})


if __name__ == "__main__":
    unittest.main()
