"""Offline contract tests. Live Roblox/Potassium testing is separate."""
import csv
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from validate_export import validate_folder  # noqa: E402


class ExportFormatTests(unittest.TestCase):
    RECORD = {
        "name": "PlayButton",
        "className": "TextButton",
        "path": "PlayerGui/MainMenu/PlayButton",
        "parentPath": "PlayerGui/MainMenu",
        "depth": 2,
        "properties": {"Text": "PLAY", "Visible": True},
    }

    def write_dataset(self, folder: Path, format_name: str, records=None, corrupt_count=False):
        records = list(records if records is not None else [self.RECORD])
        path = folder / ("PlayerGui-p1-0001." + format_name)
        if format_name == "json":
            path.write_text(json.dumps({
                "schemaVersion": 1, "service": "PlayerGui", "pass": 1,
                "records": records,
            }), encoding="utf-8")
        elif format_name == "jsonl":
            path.write_text("".join(json.dumps(record) + "\n" for record in records), encoding="utf-8")
        else:
            with path.open("w", encoding="utf-8", newline="") as stream:
                writer = csv.writer(stream)
                writer.writerow(["path", "parentPath", "name", "className", "depth", "properties_json"])
                for record in records:
                    writer.writerow([
                        record["path"], record["parentPath"], record["name"],
                        record["className"], record["depth"], json.dumps(record["properties"]),
                    ])
        manifest = {
            "schemaVersion": 1, "exporterVersion": "0.1.0", "clientOnly": True,
            "game": {"label": "Fixture", "category": "Tests", "variant": "Default", "placeId": 1, "gameId": 2},
            "capturedAtUtc": "2026-11-23T14:00:00Z",
            "status": "complete", "partialReasons": [],
            "stats": {"visited": len(records), "written": len(records) + int(corrupt_count),
                      "files": 1, "bytes": path.stat().st_size,
                      "redactions": 0, "errors": 0, "classCounts": {}},
            "services": {"PlayerGui": {"visited": len(records), "records": len(records), "files": 1, "passes": 1}},
            "settings": {"format": format_name}, "errors": [], "privacy": {}, "notes": [],
        }
        (folder / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
        return path

    def test_valid_json(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.write_dataset(folder, "json")
            self.assertEqual(validate_folder(folder), [])

    def test_valid_jsonl(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.write_dataset(folder, "jsonl")
            self.assertEqual(validate_folder(folder), [])

    def test_valid_csv(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.write_dataset(folder, "csv")
            self.assertEqual(validate_folder(folder), [])

    def test_reject_wrong_counts(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.write_dataset(folder, "json", corrupt_count=True)
            errors = validate_folder(folder)
            self.assertTrue(any("stats.written" in error for error in errors), errors)

    def test_reject_script_source(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            record = dict(self.RECORD)
            record["properties"] = {"Source": "print('should never leak')"}
            self.write_dataset(folder, "json", records=[record])
            errors = validate_folder(folder)
            self.assertTrue(any("Source" in error for error in errors), errors)

    def test_more_than_two_gui_passes(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            path = self.write_dataset(folder, "json")
            new_path = folder / "PlayerGui-p3-0001.json"
            path.rename(new_path)
            payload = json.loads(new_path.read_text(encoding="utf-8"))
            payload["pass"] = 3
            new_path.write_text(json.dumps(payload), encoding="utf-8")
            manifest_path = folder / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["stats"]["bytes"] = new_path.stat().st_size
            manifest["services"]["PlayerGui"]["passes"] = 3
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            self.assertEqual(validate_folder(folder), [])

    def test_continuous_stopped_manifest_with_delta(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.write_dataset(folder, "json")
            initial = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))
            initial["status"] = "stopped"
            initial["settings"]["captureMode"] = "continuous"
            initial["settings"]["continuous"] = True
            initial["endedReason"] = "user_stopped"
            record = dict(self.RECORD)
            record["path"] = "PlayerGui/Menu/Start"
            record["parentPath"] = "PlayerGui/Menu"
            record["name"] = "Start"
            record["operation"] = "add"
            record["observedAtUtc"] = "2026-11-23T15:00:00Z"
            delta = folder / "PlayerGui-p2-0001.json"
            delta.write_text(json.dumps({
                "schemaVersion": 1, "service": "PlayerGui",
                "pass": 2, "records": [record],
            }), encoding="utf-8")
            initial["stats"]["written"] += 1
            initial["stats"]["files"] += 1
            initial["stats"]["bytes"] += delta.stat().st_size
            initial["stats"]["deltaRecords"] = 1
            initial["services"]["PlayerGui"]["records"] += 1
            initial["services"]["PlayerGui"]["files"] += 1
            initial["services"]["PlayerGui"]["passes"] = 2
            (folder / "manifest.json").write_text(json.dumps(initial), encoding="utf-8")
            self.assertEqual(validate_folder(folder), [])

    def test_no_game_specific_gui_prompts(self):
        ui = (ROOT / "src" / "ui.lua").read_text(encoding="utf-8")
        for specific_menu in ("STORE", "SKINS", "ToggleStoreUI", "ToggleSkinsUI",
                              "Criminality", "CrimModded"):
            self.assertNotIn(specific_menu, ui)
        self.assertIn("continuous", ui)
        self.assertIn("stopRequested", ui)

    def write_categorized(self, folder: Path, format_name: str, malformed=False):
        category, service = "scripts", "PlayerGui"
        directory = folder / category / service
        directory.mkdir(parents=True)
        record = dict(self.RECORD)
        record["name"] = "HUDController"
        record["className"] = "LocalScript"
        record["path"] = "PlayerGui/MainMenu/HUDController"
        record["category"] = category
        record["properties"] = {}
        file = directory / ("p1-0001." + format_name)
        if format_name == "json":
            file.write_text(json.dumps({
                "schemaVersion": 1, "service": service, "pass": 1,
                "category": category if not malformed else "gui",
                "records": [record],
            }), encoding="utf-8")
        elif format_name == "jsonl":
            file.write_text(json.dumps(record) + "\\n", encoding="utf-8")
        else:
            with file.open("w", encoding="utf-8", newline="") as stream:
                writer = csv.writer(stream)
                writer.writerow(["path", "parentPath", "name", "className", "depth", "properties_json"])
                writer.writerow([record["path"], record["parentPath"], record["name"],
                                 record["className"], record["depth"], "{}"])
        manifest = {
            "schemaVersion": 1, "exporterVersion": "0.5.2",
            "clientOnly": True, "game": {"label": "Fixture"},
            "capturedAtUtc": "2026-11-24T12:00:00Z", "status": "complete",
            "partialReasons": [], "layout": {"version": 2, "id": "categorized"},
            "settings": {"format": format_name, "organizedOutput": True},
            "stats": {"written": 1, "files": 1, "bytes": file.stat().st_size},
            "services": {service: {"records": 1, "files": 1, "passes": 1}},
            "categories": {category: {"records": 1, "files": 1,
                                     "services": {service: {"records": 1, "files": 1}}}},
        }
        (folder / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")

    def test_categorized_json(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.write_categorized(folder, "json")
            self.assertEqual(validate_folder(folder), [])

    def test_categorized_jsonl(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.write_categorized(folder, "jsonl")
            self.assertEqual(validate_folder(folder), [])

    def test_categorized_csv(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.write_categorized(folder, "csv")
            self.assertEqual(validate_folder(folder), [])

    def test_reject_wrong_categorized_header(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.write_categorized(folder, "json", malformed=True)
            issues = validate_folder(folder)
            self.assertTrue(any("category header mismatch" in issue for issue in issues), issues)

    def test_reject_duplicate_or_missing_nested_chunks(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.write_categorized(folder, "json")
            first = folder / "scripts" / "PlayerGui" / "p1-0001.json"
            first.rename(folder / "scripts" / "PlayerGui" / "p1-0002.json")
            issues = validate_folder(folder)
            self.assertTrue(any("missing/duplicate chunk indexes" in issue
                                for issue in issues), issues)

    def test_missing_manifest(self):
        with tempfile.TemporaryDirectory() as directory:
            errors = validate_folder(Path(directory))
            self.assertIn("missing manifest.json", errors)

    def test_generated_bundle_in_sync(self):
        proc = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "build.py"), "--check"],
            capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 0, proc.stderr + proc.stdout)

    def test_no_script_source_or_remote_invocation(self):
        source = (ROOT / "src" / "engine.lua").read_text(encoding="utf-8")
        self.assertNotIn("getscriptbytecode", source.lower())
        self.assertNotIn("getscriptclosure", source.lower())
        self.assertNotIn(":fireserver(", source.lower())
        self.assertNotIn(":invokeserver(", source.lower())


if __name__ == "__main__":
    unittest.main()
