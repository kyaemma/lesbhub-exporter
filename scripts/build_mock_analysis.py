#!/usr/bin/env python3
"""Inline the analyzer into its synthetic Luau CLI fixture."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if len(sys.argv) != 2:
    raise SystemExit("Usage: python scripts/build_mock_analysis.py OUTPUT")
source = (ROOT / "src/source_analysis.lua").read_text(encoding="utf-8")
mock = (ROOT / "tests/mock_source_analysis.luau").read_text(encoding="utf-8")
marker = 'require("../src/source_analysis")'
assert mock.count(marker) == 1
Path(sys.argv[1]).write_text(mock.replace(marker, "(function()\n" + source + "\nend)()"), encoding="utf-8")
