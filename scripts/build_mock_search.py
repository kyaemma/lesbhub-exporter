#!/usr/bin/env python3
"""Inline exporter engine into the isolated source search mock."""
from pathlib import Path
import sys
from build import engine_source

root = Path(__file__).resolve().parents[1]
token = 'local Exporter = require("../src/engine")'
if len(sys.argv) != 2:
    raise SystemExit("Usage: python scripts/build_mock_search.py OUTPUT")
mock = (root / "tests/mock_search.luau").read_text(encoding="utf-8-sig")
if mock.count(token) != 1:
    raise SystemExit("Search mock insertion point missing")
Path(sys.argv[1]).write_text(mock.replace(token, "local Exporter = (function()\n" + engine_source() + "\nend)()"), encoding="utf-8", newline="\n")
