#!/usr/bin/env python3
"""Inline the journal module into its standalone Luau test."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
token = 'local Journal = require("../src/journal")'
if len(sys.argv) != 2:
    raise SystemExit("Usage: python scripts/build_mock_journal.py OUTPUT")
mock = (root / "tests/mock_journal.luau").read_text(encoding="utf-8")
source = (root / "src/journal.lua").read_text(encoding="utf-8")
if mock.count(token) != 1:
    raise SystemExit("Journal mock insertion point missing")
Path(sys.argv[1]).write_text(mock.replace(token, "local Journal = (function()\n" + source + "\nend)()"), encoding="utf-8", newline="\n")
