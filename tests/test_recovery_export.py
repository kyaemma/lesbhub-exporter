"""Recovery tests use synthetic exports and never touch a running capture."""
import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import test_inspection_export
from test_inspection_export import save
from recover_export import RecoveryError, recover, select_checkpoint
from validate_export import validate_folder


class RecoveryExportTests(unittest.TestCase):
    def fixture(self, folder):
        manifest = test_inspection_export.InspectionExportTests().fixture(folder)
        for name in ("gui/actions.jsonl", "gui/transitions.jsonl", "remotes/observations.jsonl"):
            (folder / name).unlink()
        save(folder, "gui/states/state000001.json", {"schemaVersion": 2, "stateId": 1,
             "upserts": [], "removes": [], "elementCount": 0})
        save(folder, "gui/states/index.json", {"schemaVersion": 2, "states": [{"stateId": 1,
             "path": "gui/states/state000001.json", "elementCount": 0}], "transitions": []})
        save(folder, "gui/states/lookup/recoveryfixture/1.json", {"schemaVersion": 2,
             "digest": "recoveryfixture", "stateId": 1,
             "path": "gui/states/state000001.json"})
        save(folder, "journal/index.json", {"version": 1, "streams": {}})
        save(folder, "remotes/signatures.json", {"version": 1, "signatures": []})
        manifest.update(inspectionVersion=2, exporterVersion="0.9.0", continuous={},
                        journal={"version": 1, "path": "journal/index.json", "streams": {}})
        artifacts, snapshots = [], []
        excluded = {"manifest.json", "report.json", "report.md", "artifacts/index.json"}
        mutable = {"scripts/index.json", "gui/index.json", "gui/states/index.json", "remotes/index.json",
                   "journal/index.json", "remotes/signatures.json", "relations/index.json", "client.json",
                   "assets/index.json", "errors/index.json"}
        for file in sorted(folder.rglob("*")):
            if not file.is_file(): continue
            relative = file.relative_to(folder).as_posix()
            if relative in excluded: continue
            body = file.read_bytes()
            item = dict(path=relative, bytes=len(body), checksumAlgorithm="sha256",
                        checksum=hashlib.sha256(body).hexdigest(), kind="fixture")
            artifacts.append(item)
            if relative in mutable:
                frozen = "checkpoints/files/" + str(len(snapshots)) + ".bin"
                destination = folder / frozen
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(body)
                snapshots.append({key: item[key] for key in ("path", "bytes", "checksumAlgorithm", "checksum")}
                                 | {"snapshotPath": frozen})
        checkpoint = {"checkpointVersion": 1, "manifest": manifest, "artifacts": artifacts,
                      "snapshots": snapshots, "lastSequence": 1, "pending": {}}
        save(folder, "checkpoints/c000001.json", checkpoint)
        return checkpoint

    def test_recovered_verified_prefix_validates_and_ignores_later_mutations(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "input"; root.mkdir()
            checkpoint = self.fixture(root)
            frozen = next(s for s in checkpoint["snapshots"] if s["path"] == "gui/states/index.json")
            original = (root / frozen["snapshotPath"]).read_bytes()
            (root / frozen["path"]).write_text("invalid newer mutation", encoding="utf-8")
            (root / "uncommitted.txt").write_text("must not copy")
            newer = copy.deepcopy(checkpoint)
            newer["artifacts"][0]["checksum"] = "0" * 64
            save(root, "checkpoints/c000002.json", newer)
            output = Path(directory) / "output"
            result = recover(root, output)
            self.assertEqual(result["checkpoint"], "c000001.json")
            self.assertEqual(len(result["warnings"]), 1)
            self.assertEqual((output / frozen["path"]).read_bytes(), original)
            self.assertFalse((output / "uncommitted.txt").exists())
            self.assertEqual(validate_folder(output), [])
            manifest = json.loads((output / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(manifest["status"], "partial")
            self.assertIn("recovered_checkpoint", manifest["partialReasons"])
            self.assertEqual(manifest["recovery"]["lastSequence"], 1)
            self.assertEqual((root / frozen["path"]).read_text(encoding="utf-8"), "invalid newer mutation")

    def test_invalid_paths_incomplete_files_and_corruption_fail_closed(self):
        for mode in ("traversal", "drive", "duplicate", "snapshot_escape", "snapshot_absent", "truncated", "corrupt", "missing"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                root=Path(directory); checkpoint=self.fixture(root)
                item=checkpoint["artifacts"][0]
                if mode=="traversal": item["path"]="../outside"
                if mode=="drive": item["path"]="C:/outside"
                if mode=="duplicate": checkpoint["artifacts"].append(copy.deepcopy(item))
                if mode=="snapshot_escape": checkpoint["snapshots"][0]["snapshotPath"]="../outside"
                if mode=="snapshot_absent": checkpoint["snapshots"].pop(0)
                if mode in {"truncated", "corrupt", "missing"}:
                    snapshot = checkpoint["snapshots"][0]
                    path = root / snapshot["snapshotPath"]
                    if mode=="truncated": path.write_bytes(b"")
                    if mode=="corrupt": path.write_bytes(b"x" * path.stat().st_size)
                    if mode=="missing": path.unlink()
                save(root,"checkpoints/c000001.json",checkpoint)
                with self.assertRaises(RecoveryError): select_checkpoint(root)

    def test_valid_checksums_but_incoherent_newest_checkpoint_falls_back(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "input"; root.mkdir()
            newer = copy.deepcopy(self.fixture(root))
            snapshot = next(s for s in newer["snapshots"] if s["path"] == "gui/states/index.json")
            body = json.dumps({"schemaVersion": 2, "states": [], "transitions": []}).encode()
            frozen = "checkpoints/files/logically-invalid-index.bin"
            (root / frozen).write_bytes(body)
            snapshot.update(snapshotPath=frozen, bytes=len(body), checksum=hashlib.sha256(body).hexdigest())
            artifact = next(a for a in newer["artifacts"] if a["path"] == snapshot["path"])
            artifact.update(bytes=snapshot["bytes"], checksum=snapshot["checksum"])
            save(root, "checkpoints/c000002.json", newer)
            result = recover(root, Path(directory) / "output")
            self.assertEqual(result["checkpoint"], "c000001.json")
            self.assertEqual(len(result["warnings"]), 1)
            self.assertIn("failed validation", result["warnings"][0])

    def test_nonempty_or_inside_output_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)/"in"; root.mkdir(); self.fixture(root)
            with self.assertRaises(RecoveryError): recover(root, root/"output")
            output=Path(directory)/"out"; output.mkdir(); (output/"keep").write_text("keep")
            with self.assertRaises(RecoveryError): recover(root, output)
            self.assertEqual((output/"keep").read_text(), "keep")

    def test_symlink_rejected_when_available(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)/"in"; root.mkdir(); checkpoint=self.fixture(root)
            target=Path(directory)/"external"; target.write_bytes(b"outside")
            link=root/"outside-link"
            try: link.symlink_to(target)
            except (OSError, NotImplementedError): self.skipTest("symlink creation unavailable")
            checkpoint["artifacts"].append({"path":"outside-link", "bytes":7, "checksumAlgorithm":"sha256",
                "checksum":hashlib.sha256(b"outside").hexdigest(), "kind":"fixture"})
            save(root,"checkpoints/c000001.json",checkpoint)
            with self.assertRaises(RecoveryError): select_checkpoint(root)

    def test_symlink_detection_even_when_windows_cannot_create_one(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); checkpoint=self.fixture(root)
            target = checkpoint["snapshots"][0]["snapshotPath"]
            original = Path.is_symlink
            with patch.object(Path, "is_symlink", lambda path: path.name == Path(target).name or original(path)):
                with self.assertRaises(RecoveryError): select_checkpoint(root)

    def test_sequence_after_checkpoint_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)/"in"; root.mkdir(); checkpoint=self.fixture(root)
            checkpoint["lastSequence"] = 0
            save(root,"checkpoints/c000001.json",checkpoint)
            with self.assertRaisesRegex(RecoveryError, "sequence"):
                recover(root,Path(directory)/"output")


if __name__ == "__main__": unittest.main()
