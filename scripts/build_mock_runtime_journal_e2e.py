#!/usr/bin/env python3
"""Build a separate Engine integration mock without editing mock_capture."""
from pathlib import Path
import sys

from build import engine_source

ROOT = Path(__file__).resolve().parents[1]
ENGINE_TOKEN = 'local Exporter = require("../src/engine")'


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python scripts/build_mock_runtime_journal_e2e.py OUTPUT")
    base = (ROOT / "tests" / "mock_capture.luau").read_text(encoding="utf-8")
    extra = (ROOT / "tests" / "mock_runtime_journal_e2e.luau").read_text(encoding="utf-8")
    if base.count(ENGINE_TOKEN) != 1:
        raise SystemExit("Engine insertion point missing or duplicated")
    generated = base.replace(
        ENGINE_TOKEN,
        "local function loadEngine()\n" + engine_source() + "\nend\nlocal Exporter = loadEngine()",
    )
    Path(sys.argv[1]).write_text(generated + "\n" + extra, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
