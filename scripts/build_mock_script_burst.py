#!/usr/bin/env python3
"""Inline the script writer into the bounded-burst fixture."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
token = 'local Deep = require("../src/deep_scripts")'
if len(sys.argv) != 2:
    raise SystemExit("Usage: python scripts/build_mock_script_burst.py OUTPUT")
mock = (root / "tests/mock_script_burst.luau").read_text(encoding="utf-8")
source = (root / "src/deep_scripts.lua").read_text(encoding="utf-8")
if mock.count(token) != 1:
    raise SystemExit("Script writer insertion point missing")
Path(sys.argv[1]).write_text(mock.replace(token, "local Deep = (function()\n" + source + "\nend)()"), encoding="utf-8", newline="\n")
