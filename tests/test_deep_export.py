"""Deep Export integrity checks using exclusively synthetic, public fixtures."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import test_contract
from validate_export import validate_folder


class DeepExportTests(unittest.TestCase):
    def fixture(self, folder, source=b"-- synthetic\nreturn 42\n", status="success"):
        test_contract.ExportFormatTests().write_dataset(folder, "json")
        output = "scripts/sources/PlayerGui/s1_Fixture.luau"
        path = folder / output
        path.parent.mkdir(parents=True)
        header = b"-- Synthetic reconstructed fixture\n\n"
        path.write_bytes(header + source)
        entry = dict(scriptId="s1", instanceId=1, name="Fixture", className="LocalScript",
                     robloxPath="PlayerGui/Fixture", outputPath=output, status=status,
                     error="" if status == "success" else "syntax failure", method="decompile",
                     attempted=True, byteLength=len(source), lineCount=source.count(b"\n") + 1,
                     checksum=hashlib.sha256(source).hexdigest(), checksumAlgorithm="sha256",
                     headerByteLength=len(header), fileByteLength=len(header + source),
                     fileChecksum=hashlib.sha256(header + source).hexdigest(),
                     fileChecksumAlgorithm="sha256", verifiedReadback=True,
                     compiles=status == "success", truncationDetected=False)
        counts = dict(discovered=1, attempted=1, succeeded=int(status == "success"),
                      failed=0, inaccessible=0, empty=0, partial=int(status == "partial"),
                      skipped=0, pending=0, files=1, bytes=len(header + source))
        index = dict(version=1, scripts=[entry], stats=counts)
        (folder / "scripts/index.json").write_text(json.dumps(index), encoding="utf-8")
        manifest_path = folder / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["exporterVersion"] = "0.7.0"
        manifest["scriptExport"] = dict(enabled=True, indexPath="scripts/index.json", stats=counts)
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        return path, index

    def test_default_script_reconstruction_contract(self):
        root = Path(__file__).resolve().parents[1]
        engine = (root / "src" / "engine.lua").read_text(encoding="utf-8")
        ui = (root / "src" / "ui.lua").read_text(encoding="utf-8")
        self.assertIn(
            "cfg.includeReconstructedCode = input.includeReconstructedCode ~= false", engine
        )
        self.assertEqual(
            ui.count("includeReconstructedCode = true, twoPassGui = true"), 3
        )
        self.assertIn(
            "if config.includeReconstructedCode == nil then config.includeReconstructedCode = true end",
            ui,
        )

    def test_verified_long_source(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.fixture(folder, b"-- synthetic long line\r\n" * 4000 + b"return 42\n")
            self.assertEqual(validate_folder(folder), [])

    def test_v09_script_contents_can_be_shared_between_logical_entries(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.fixture(folder)
            index_path = folder / "scripts/index.json"
            index = json.loads(index_path.read_text(encoding="utf-8"))
            first = index["scripts"][0]
            second = dict(first, scriptId="s2", instanceId=2, robloxPath="PlayerGui/OtherController")
            index["scripts"].append(second)
            index["version"] = 2
            source = (folder / first["outputPath"]).read_bytes()[first["headerByteLength"]:]
            (folder / first["outputPath"]).write_bytes(source)
            for entry in index["scripts"]:
                entry.update(headerByteLength=0, fileByteLength=len(source),
                             fileChecksum=hashlib.sha256(source).hexdigest())
            stats = index["stats"]
            stats.update(discovered=2, attempted=2, succeeded=2, files=1,
                         bytes=len(source), logicalFiles=2,
                         logicalBytes=2 * first["byteLength"], sharedReferences=1)
            index_path.write_text(json.dumps(index), encoding="utf-8")
            manifest_path = folder / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["scriptExport"].update(version=2, stats=stats)
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            self.assertEqual(validate_folder(folder), [])

    def test_v09_resumed_index_retains_verified_legacy_header(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            file, index = self.fixture(folder)
            first = index["scripts"][0]
            source = file.read_bytes()[first["headerByteLength"]:]
            output = f"scripts/sources/content/sha256-{first['checksum']}-{len(source)}.luau"
            target = folder / output; target.parent.mkdir(parents=True); target.write_bytes(source)
            second = dict(first, scriptId="s2", instanceId=2, outputPath=output,
                          headerByteLength=0, fileByteLength=len(source), fileChecksum=first["checksum"])
            index["scripts"].append(second); index["version"] = 2
            total = first["fileByteLength"] + len(source)
            index["stats"].update(discovered=2, attempted=2, succeeded=2, files=2, bytes=total,
                                  logicalFiles=2, logicalBytes=total, sharedReferences=0)
            (folder / "scripts/index.json").write_text(json.dumps(index), encoding="utf-8")
            path = folder / "manifest.json"; manifest=json.loads(path.read_text(encoding="utf-8"))
            manifest["scriptExport"].update(version=2, stats=index["stats"])
            path.write_text(json.dumps(manifest), encoding="utf-8")
            self.assertEqual(validate_folder(folder), [])
            second["instanceId"] = first["instanceId"]
            (folder / "scripts/index.json").write_text(json.dumps(index), encoding="utf-8")
            self.assertTrue(any("duplicate instanceId" in issue for issue in validate_folder(folder)))

    def test_partial_code_can_be_preserved(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.fixture(folder, b"synthetic broken code", "partial")
            self.assertEqual(validate_folder(folder), [])

    def test_deleted_or_corrupt_code_is_not_success(self):
        for mode in ("delete", "modify"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as directory:
                folder = Path(directory)
                file, _ = self.fixture(folder)
                if mode == "delete": file.unlink()
                else: file.write_bytes(file.read_bytes() + b"-- changed")
                self.assertTrue(validate_folder(folder))

    def test_unsafe_or_duplicate_output(self):
        for output in ("scripts/sources/../../outside.luau", "C:/outside.luau",
                       "scripts/sources/../outside.luau", "scripts/sources/bad:stream.luau"):
            with self.subTest(output=output), tempfile.TemporaryDirectory() as directory:
                folder = Path(directory)
                _, index = self.fixture(folder)
                index["scripts"][0]["outputPath"] = output
                (folder / "scripts/index.json").write_text(json.dumps(index), encoding="utf-8")
                self.assertTrue(any("unsafe outputPath" in issue for issue in validate_folder(folder)))

    def test_duplicate_script_id(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            _, index = self.fixture(folder)
            index["scripts"].append(index["scripts"][0])
            (folder / "scripts/index.json").write_text(json.dumps(index), encoding="utf-8")
            self.assertTrue(any("scriptId" in issue for issue in validate_folder(folder)))

    def test_truncation_must_not_be_success(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            _, index = self.fixture(folder)
            index["scripts"][0]["truncationDetected"] = True
            (folder / "scripts/index.json").write_text(json.dumps(index), encoding="utf-8")
            self.assertTrue(any("truncation" in issue for issue in validate_folder(folder)))

    def test_unindexed_code_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            file, _ = self.fixture(folder)
            file.with_name("unindexed.luau").write_text("return 0", encoding="utf-8")
            self.assertTrue(any("unindexed" in issue for issue in validate_folder(folder)))

    def test_malformed_sidecar_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            self.fixture(folder)
            (folder / "scripts/progress.jsonl").write_text("not JSON\n", encoding="utf-8")
            self.assertTrue(any("sidecar" in issue for issue in validate_folder(folder)))


if __name__ == "__main__":
    unittest.main()
