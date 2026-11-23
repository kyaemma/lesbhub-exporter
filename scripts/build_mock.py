#!/usr/bin/env python3
"""Inline engine source into the Luau CLI mock test.

The standard Luau CLI isolates globals between require() modules, unlike an
executor's script environment. This builds a smoke test with the source in a
local function, so the mock "game" globals are visible without changing V1.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOKEN = 'local Exporter = require("../src/engine")'


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python scripts/build_mock.py /tmp/test.luau")
    test = (ROOT / "tests" / "mock_capture.luau").read_text(encoding="utf-8")
    engine = (ROOT / "src" / "engine.lua").read_text(encoding="utf-8").rstrip()
    if test.count(TOKEN) != 1:
        raise SystemExit("Mock test entrypoint missing or duplicated")
    patched = test.replace(
        TOKEN, "local function loadEngine()\n" + engine + "\nend\nlocal Exporter = loadEngine()"
    )
    Path(sys.argv[1]).write_text(patched, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
