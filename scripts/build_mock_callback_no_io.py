#!/usr/bin/env python3
"""Append the non-yielding callback burst to the inlined capture fixture."""
from pathlib import Path
import sys
from build import engine_source

root = Path(__file__).resolve().parents[1]
token = 'local Exporter = require("../src/engine")'
if len(sys.argv) != 2:
    raise SystemExit("Usage: python scripts/build_mock_callback_no_io.py OUTPUT")
mock = (root / "tests/mock_capture.luau").read_text(encoding="utf-8")
extra = (root / "tests/mock_callback_no_io_extra.luau").read_text(encoding="utf-8")
if mock.count(token) != 1:
    raise SystemExit("Capture mock insertion point missing")
engine = "local function loadEngine()\n" + engine_source() + "\nend\nlocal Exporter = loadEngine()"
Path(sys.argv[1]).write_text(mock.replace(token, engine) + "\n" + extra, encoding="utf-8", newline="\n")
