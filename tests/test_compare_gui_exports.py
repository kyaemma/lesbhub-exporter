"""Graph equivalence must preserve multiplicity, parentage, and native names."""
import copy
import json
import sys
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from compare_gui_exports import graph_projection, node_name, read_parent_evidence, read_transition_walk


def row(ident, parent, path, text=""):
    return {"instanceId": ident, "parentInstanceId": parent, "path": path,
            "className": "Frame", "properties": {"Text": text}}


class GuiComparisonTests(unittest.TestCase):
    def test_duplicate_siblings_and_duplicate_parent_paths(self):
        a = [row(1, 99, "StarterGui/THUMNAIL"), row(2, 1, "StarterGui/THUMNAIL/Frame", "a"),
             row(3, 1, "StarterGui/THUMNAIL/Frame~2", "b"),
             row(4, 2, "StarterGui/THUMNAIL/Frame/Frame", "x"),
             row(5, 3, "StarterGui/THUMNAIL/Frame~2/Frame", "y")]
        metadata = {3: {"name": "Frame", "robloxPath": "StarterGui/THUMNAIL/Frame~2"}}
        b = [row(10, 77, "StarterGui/THUMNAIL"), row(30, 10, "StarterGui/THUMNAIL/Frame", "b"),
             row(20, 10, "StarterGui/THUMNAIL/Frame", "a"),
             row(50, 30, "StarterGui/THUMNAIL/Frame/Frame", "y"),
             row(40, 20, "StarterGui/THUMNAIL/Frame/Frame", "x")]
        self.assertEqual(graph_projection(a, metadata, False)[0], graph_projection(b, {}, False)[0])
        wrong = copy.deepcopy(b); wrong[-1]["parentInstanceId"] = 30
        self.assertNotEqual(graph_projection(a, metadata, False)[0], graph_projection(wrong, {}, False)[0])
        self.assertNotEqual(graph_projection(b, {}, False)[0], graph_projection(b[:-1], {}, False)[0])

    def test_suffix_removed_only_with_matching_native_name_and_path(self):
        item = row(1, 0, "StarterGui/Menu~10")
        self.assertEqual(node_name(item, {}), "Menu~10")
        self.assertEqual(node_name(item, {1: {"name":"Menu~10", "robloxPath":item["path"]}}), "Menu~10")
        self.assertEqual(node_name(item, {1: {"name":"Menu", "robloxPath":item["path"]}}), "Menu")
        self.assertEqual(node_name(item, {1: {"name":"Menu", "robloxPath":"stale"}}), "Menu~10")

    def test_external_parent_class_requires_identity_path_and_unambiguous_class(self):
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory)
            (folder/"structures/StarterGui").mkdir(parents=True)
            (folder/"manifest.json").write_text(json.dumps({"layout":{"version":2}}), encoding="utf-8")
            path=folder/"structures/StarterGui/p1-0001.json"
            record={"instanceId":9,"path":"StarterGui/BanUI","className":"Folder"}
            def save(records):
                path.write_text(json.dumps({"schemaVersion":1,"service":"StarterGui","pass":1,
                                            "category":"structures","records":records}),encoding="utf-8")
            rows=[row(10,9,"StarterGui/BanUI/Screen")]
            save([record]); evidence=read_parent_evidence(folder)
            self.assertTrue(graph_projection(rows,{},False,evidence)[2])
            self.assertFalse(graph_projection(rows,{},False,{})[2])
            wrong=copy.deepcopy(record); wrong["instanceId"]=19
            save([wrong]); self.assertFalse(graph_projection(rows,{},False,read_parent_evidence(folder))[2])
            wrong=copy.deepcopy(record); wrong["path"]="StarterGui/Another"
            save([wrong]); self.assertFalse(graph_projection(rows,{},False,read_parent_evidence(folder))[2])
            wrong=copy.deepcopy(record); wrong["className"]="Model"
            save([record,wrong]); self.assertFalse(graph_projection(rows,{},False,read_parent_evidence(folder))[2])

    def test_transition_occurrences_and_normalized_walk(self):
        with tempfile.TemporaryDirectory() as directory:
            folder=Path(directory); (folder/"gui").mkdir()
            rows=[{"event":"gui_state_transition","sequence":5,"fromStateId":1,"toStateId":2,"reason":"change"},
                  {"event":"gui_state_transition","sequence":8,"fromStateId":2,"toStateId":1,"reason":"change"},
                  {"event":"gui_state_transition","sequence":9,"fromStateId":1,"toStateId":2,"reason":"change"}]
            index={"transitions":[{"fromStateId":1,"toStateId":2,"reason":"change","count":2},
                                  {"fromStateId":2,"toStateId":1,"reason":"change","count":1}]}
            (folder/"gui/transitions.jsonl").write_text("\n".join(map(json.dumps,rows))+"\n",encoding="utf-8")
            stats, walk=read_transition_walk(folder,1,index,{1:"A",2:"B"})
            self.assertEqual((stats["aggregateKinds"],stats["aggregateOccurrences"],stats["journalOccurrences"]),(2,3,3))
            self.assertTrue(stats["aggregateMatchesJournal"] and stats["transitionWalkContinuous"])
            self.assertEqual(walk,[["A","B"],["B","A"],["A","B"]])
            v09=[dict(item,stream="gui-transitions") for item in rows]
            with patch("compare_gui_exports.iter_events", return_value=iter(v09)):
                newer, newer_walk=read_transition_walk(folder,2,index,{1:"A",2:"B"})
            self.assertEqual(newer_walk,walk); self.assertTrue(newer["aggregateMatchesJournal"])
            broken=copy.deepcopy(index); broken["transitions"][0]["count"]=1; broken["transitions"][1]["count"]=2
            bad, _=read_transition_walk(folder,1,broken,{1:"A",2:"B"})
            self.assertFalse(bad["aggregateMatchesJournal"])
            rows[1]["fromStateId"]=1
            (folder/"gui/transitions.jsonl").write_text("\n".join(map(json.dumps,rows)),encoding="utf-8")
            bad, _=read_transition_walk(folder,1,index,{1:"A",2:"B"})
            self.assertFalse(bad["transitionWalkContinuous"])


if __name__ == "__main__": unittest.main()
