#!/usr/bin/env python3
"""Inline checkpoints into a standalone Luau test."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
token = 'local Checkpoints = require("../src/checkpoints")'
if len(sys.argv) != 2:
    raise SystemExit("Usage: python scripts/build_mock_checkpoints.py OUTPUT")
mock = (root / "tests/mock_checkpoints.luau").read_text(encoding="utf-8")
source = (root / "src/checkpoints.lua").read_text(encoding="utf-8")
if mock.count(token) != 1:
    raise SystemExit("Checkpoint mock insertion point missing")
Path(sys.argv[1]).write_text(mock.replace(token, "local Checkpoints = (function()\n" + source + "\nend)()"), encoding="utf-8", newline="\n")
