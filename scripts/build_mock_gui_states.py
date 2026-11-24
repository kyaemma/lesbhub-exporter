#!/usr/bin/env python3
"""Inline GUI state module to run its mock independently of the bundler."""
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
token = 'local Gui = require("../src/gui_states")'
if len(sys.argv) != 2:
    raise SystemExit("Usage: python scripts/build_mock_gui_states.py OUTPUT")
mock = (root / 'tests/mock_gui_states.luau').read_text(encoding='utf-8-sig')
source = (root / 'src/gui_states.lua').read_text(encoding='utf-8-sig')
if mock.count(token) != 1:
    raise SystemExit('GUI mock insertion point missing')
Path(sys.argv[1]).write_text(mock.replace(token, 'local Gui = (function()\n' + source + '\nend)()'), encoding='utf-8', newline='\n')
