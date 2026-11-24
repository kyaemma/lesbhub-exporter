#!/usr/bin/env python3
"""Append deferred-admission tests to the inlined runtime observer fixture."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
token = 'local Runtime = require("../src/runtime_observer")'
if len(sys.argv) != 2:
    raise SystemExit("Usage: python scripts/build_mock_runtime_deferred.py OUTPUT")
mock = (root / "tests/mock_runtime_observer.luau").read_text(encoding="utf-8")
extra = (root / "tests/mock_runtime_deferred_extra.luau").read_text(encoding="utf-8")
source = (root / "src/runtime_observer.lua").read_text(encoding="utf-8")
if mock.count(token) != 1:
    raise SystemExit("Runtime insertion point missing")
Path(sys.argv[1]).write_text(mock.replace(token, "local Runtime = (function()\n" + source + "\nend)()") + "\n" + extra, encoding="utf-8", newline="\n")
