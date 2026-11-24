#!/usr/bin/env python3
"""Inline engine modules into the synthetic resume fixture."""
from pathlib import Path
import sys
from build import engine_source

ROOT = Path(__file__).resolve().parents[1]
if len(sys.argv) != 2:
    raise SystemExit("Usage: python scripts/build_mock_resume.py OUTPUT")
mock = (ROOT / "tests/mock_resume.luau").read_text(encoding="utf-8")
token = 'require("../src/engine")'
assert mock.count(token) == 1
Path(sys.argv[1]).write_text(mock.replace(token, "(function()\n" + engine_source() + "\nend)()"),
                             encoding="utf-8", newline="\n")
