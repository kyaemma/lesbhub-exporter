"""v0.8 inspection validation with synthetic fixtures only."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
import zlib

import test_deep_export
from validate_export import INSPECTION_LAYERS, validate_folder


def save(folder, name, value):
    file = folder / name
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(json.dumps(value), encoding="utf-8")


def ledger(folder):
    excluded = {"manifest.json", "report.json", "report.md", "artifacts/index.json"}
    rows = []
    for file in sorted(folder.rglob("*")):
        if file.is_file() and (relative := file.relative_to(folder).as_posix()) not in excluded:
            body = file.read_bytes()
            rows.append(dict(path=relative, bytes=len(body), checksumAlgorithm="sha256",
                             checksum=hashlib.sha256(body).hexdigest(), kind="fixture"))
    save(folder, "artifacts/index.json", dict(version=1, artifacts=rows))


class InspectionExportTests(unittest.TestCase):
    def fixture(self, folder):
        test_deep_export.DeepExportTests().fixture(folder)
        path = folder / "PlayerGui-p1-0001.json"
        chunk = json.loads(path.read_text(encoding="utf-8"))
        chunk["records"][0].update(sequence=1, instanceId=1)
        save(folder, path.name, chunk)
        manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
        manifest.update(exporterVersion="0.8.0", inspectionVersion=1,
                        artifactIndex={"path": "artifacts/index.json", "version": 1},
                        report={"version": 2, "path": "report.json", "markdownPath": "report.md"},
                        identity={"version": 1, "lastSequence": 4})
        manifest["stats"]["bytes"] = path.stat().st_size
        save(folder, "manifest.json", manifest)
        for name in ("client.json", "assets/index.json", "relations/index.json", "errors/index.json"):
            save(folder, name, {"version": 1})
        save(folder, "gui/states/state000001.json", {"stateId": 1, "elements": []})
        save(folder, "gui/states/index.json", {"states": [{"stateId": 1,
             "path": "gui/states/state000001.json", "elementCount": 0}]})
        for name, seq in (("gui/actions.jsonl", 2), ("remotes/observations.jsonl", 3),
                          ("gui/transitions.jsonl", 4)):
            file = folder / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(json.dumps({"sequence": seq}) + "\n", encoding="utf-8")
        layers = {name: dict(status="complete", reason="", counts={}, artifacts=[], evidence="synthetic")
                  for name in INSPECTION_LAYERS}
        layers["reconstructedScripts"]["counts"] = manifest["scriptExport"]["stats"]
        save(folder, "report.json", dict(reportVersion=2, status=manifest["status"], game=manifest["game"],
             stats=manifest["stats"], partialReasons=manifest["partialReasons"],
             scriptExport=manifest["scriptExport"], layers=layers))
        (folder / "report.md").write_text("Synthetic fixture\n", encoding="utf-8")
        ledger(folder)
        return manifest

    def v09_fixture(self, folder):
        manifest = self.fixture(folder)
        (folder / "gui/transitions.jsonl").unlink()
        (folder / "gui/actions.jsonl").unlink()
        (folder / "remotes/observations.jsonl").unlink()
        (folder / "gui/states/state000001.json").write_text(json.dumps({
            "schemaVersion": 2, "stateId": 1, "upserts": [], "removes": [], "elementCount": 0,
        }), encoding="utf-8")
        save(folder, "gui/states/index.json", {"schemaVersion": 2, "states": [
            {"stateId": 1, "path": "gui/states/state000001.json", "elementCount": 0, "visits": 1}],
            "transitions": [],
        })
        save(folder, "journal/remote-observations/b000001.json", {
            "version": 1, "stream": "remote-observations", "rows": [
                {"sequence": 2, "instanceId": 99, "direction": "Outgoing", "signatureId": 1},
            ],
        })
        save(folder, "gui/states/lookup/testdigest/1.json", {
            "schemaVersion": 2, "digest": "testdigest", "stateId": 1,
            "path": "gui/states/state000001.json",
        })
        streams = {"remote-observations": {"segments": [
            {"path": "journal/remote-observations/b000001.json", "count": 1,
             "firstSequence": 2, "lastSequence": 2}], "events": 1}}
        save(folder, "journal/index.json", {"version": 1, "streams": streams})
        save(folder, "remotes/signatures.json", {"version": 1, "signatures": [
            {"signatureId": 1, "argumentCount": 0, "argumentTypes": []},
        ]})
        manifest.update(exporterVersion="0.9.0", inspectionVersion=2,
                        journal={"version": 1, "path": "journal/index.json", "streams": streams},
                        dedup={"eventsWritten": 1, "occurrences": 1})
        save(folder, "manifest.json", manifest)
        report = json.loads((folder / "report.json").read_text(encoding="utf-8"))
        report["dedup"] = manifest["dedup"]
        save(folder, "report.json", report)
        ledger(folder)
        return manifest

    def test_valid_legacy_and_inspection(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.fixture(folder)
            self.assertEqual(validate_folder(folder), [])

    def test_v09_inspection_two_validates_segments_and_ignores_checkpoint_folder(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.v09_fixture(folder)
            checkpoint = folder / "checkpoints/c000001.json"
            checkpoint.parent.mkdir(parents=True)
            checkpoint.write_text("{}", encoding="utf-8")
            self.assertEqual(validate_folder(folder), [])

    def test_v09_malformed_journal_index_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.v09_fixture(folder)
            (folder / "journal/index.json").write_text("{", encoding="utf-8")
            ledger(folder)
            issues = validate_folder(folder)
            self.assertTrue(any("journal" in issue for issue in issues), issues)

    def test_v09_unresolved_occurrence_retained_without_fabricated_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            manifest = self.v09_fixture(folder)
            path = folder / "journal/remote-observations/b000001.json"
            data = json.loads(path.read_text(encoding="utf-8"))
            row = data["rows"][0]; row.pop("instanceId")
            row.update(identityStatus="unresolved", reason="deferred_identity_unavailable")
            save(folder, path.relative_to(folder).as_posix(), data); ledger(folder)
            self.assertEqual(validate_folder(folder), [])
            row["instanceId"] = 99
            save(folder, path.relative_to(folder).as_posix(), data); ledger(folder)
            self.assertTrue(any("must not invent identity" in issue for issue in validate_folder(folder)))

    def test_v09_unindexed_journal_file_is_not_authorized_by_ledger(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.v09_fixture(folder)
            save(folder, "journal/remote-observations/b000002.json", {
                "version": 1, "stream": "remote-observations", "rows": [],
            })
            ledger(folder)
            issues = validate_folder(folder)
            self.assertTrue(any("unrecognized data file" in issue for issue in issues), issues)

    def test_v09_unindexed_gui_lookup_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.v09_fixture(folder)
            save(folder, "gui/states/lookup/not-an-index-entry.json", {
                "schemaVersion": 2, "digest": "not-an-index-entry", "stateId": 1,
                "path": "gui/states/state000001.json",
            })
            ledger(folder)
            issues = validate_folder(folder)
            self.assertTrue(any("invalid GUI lookup path" in issue for issue in issues), issues)

    def test_invalid_artifacts(self):
        for mode in ("missing", "corrupt", "unindexed", "unsafe", "duplicate", "algorithm"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                folder = Path(directory)
                self.fixture(folder)
                path = folder / "artifacts/index.json"
                index = json.loads(path.read_text(encoding="utf-8"))
                if mode == "missing": (folder / "client.json").unlink()
                if mode == "corrupt": (folder / "client.json").write_text("{}", encoding="utf-8")
                if mode == "unindexed": (folder / "unlisted.txt").write_text("fixture", encoding="utf-8")
                if mode == "unsafe": index["artifacts"][0]["path"] = "../outside"
                if mode == "duplicate": index["artifacts"].append(index["artifacts"][0])
                if mode == "algorithm": index["artifacts"][0]["checksumAlgorithm"] = "unknown"
                if mode in {"unsafe", "duplicate", "algorithm"}: save(folder, "artifacts/index.json", index)
                issues = validate_folder(folder)
                self.assertTrue(issues)

    def test_report_and_sequence_coherence(self):
        for mode in ("report_status", "report_counts", "layer_status", "sequence", "bad_json", "missing_state"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                folder = Path(directory)
                self.fixture(folder)
                report = json.loads((folder / "report.json").read_text(encoding="utf-8"))
                if mode == "report_status": report["status"] = "partial"
                if mode == "report_counts": report["layers"]["reconstructedScripts"]["counts"]["files"] = 0
                if mode == "layer_status": report["layers"]["gui"]["status"] = "unknown"
                save(folder, "report.json", report)
                if mode == "sequence": (folder / "gui/transitions.jsonl").write_text('{"sequence": 2}\n', encoding="utf-8")
                if mode == "bad_json": (folder / "gui/states/state000001.json").write_text('{', encoding="utf-8")
                if mode == "missing_state": (folder / "gui/states/state000001.json").unlink()
                if mode in {"sequence", "bad_json", "missing_state"}: ledger(folder)
                issues = validate_folder(folder)
                self.assertTrue(issues)
                if mode == "sequence":
                    self.assertTrue(any("duplicate global sequence" in issue for issue in issues), issues)
                if mode == "missing_state":
                    self.assertTrue(any("gui/states/index.json" in issue for issue in issues), issues)

    def test_diagnostics_do_not_count_as_source_files(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.fixture(folder)
            index = json.loads((folder / "scripts/index.json").read_text(encoding="utf-8"))
            diagnostic = b"-- synthetic diagnostic\n"
            file = folder / "errors/script-diagnostics/s2.txt"
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(diagnostic)
            index["scripts"].append(dict(scriptId="s2", className="Script", robloxPath="PlayerGui/Fixture2",
                outputPath="", status="empty", error="comments only", method="decompile", attempted=True,
                byteLength=0, lineCount=0, checksum="", diagnosticPath="errors/script-diagnostics/s2.txt",
                diagnosticByteLength=len(diagnostic), diagnosticChecksumAlgorithm="adler32",
                diagnosticChecksum=f"{zlib.adler32(diagnostic):08x}"))
            counts = index["stats"]
            counts.update(discovered=2, attempted=2, empty=1)
            save(folder, "scripts/index.json", index)
            manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
            manifest.update(status="partial", partialReasons=["script_extraction_incomplete"])
            manifest["scriptExport"]["stats"] = counts
            save(folder, "manifest.json", manifest)
            report = json.loads((folder / "report.json").read_text(encoding="utf-8"))
            report.update(status=manifest["status"], partialReasons=manifest["partialReasons"])
            report["scriptExport"]["stats"] = counts
            report["layers"]["reconstructedScripts"]["counts"] = counts
            save(folder, "report.json", report)
            ledger(folder)
            self.assertEqual(validate_folder(folder), [])
            file.write_bytes(b"modified")
            ledger(folder)
            self.assertTrue(any("diagnostic" in item for item in validate_folder(folder)))


if __name__ == "__main__":
    unittest.main()
