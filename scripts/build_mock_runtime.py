#!/usr/bin/env python3
"""Inline the runtime observer for testing against a mock executor environment."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
token = 'local Runtime = require("../src/runtime_observer")'
if len(sys.argv) != 2:
    raise SystemExit("Usage: python scripts/build_mock_runtime.py OUTPUT")
mock = (root / 'tests/mock_runtime_observer.luau').read_text(encoding='utf-8-sig')
source = (root / 'src/runtime_observer.lua').read_text(encoding='utf-8-sig')
if mock.count(token) != 1:
    raise SystemExit('Runtime mock insertion point missing')
Path(sys.argv[1]).write_text(mock.replace(token, 'local Runtime = (function()\n' + source + '\nend)()'), encoding='utf-8', newline='\n')
