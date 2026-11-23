#!/usr/bin/env python3
"""Inline UI source for the isolated Luau CLI mock (no Roblox runtime)."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
TOKEN = 'local UI = require("../src/ui")'


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python scripts/build_mock_ui.py /tmp/mock-ui.luau")
    mock = (ROOT / "tests" / "mock_ui.luau").read_text(encoding="utf-8")
    ui = (ROOT / "src" / "ui.lua").read_text(encoding="utf-8").rstrip()
    if mock.count(TOKEN) != 1:
        raise SystemExit("Mock UI entrypoint missing or duplicated")
    result = mock.replace(TOKEN, "local function loadUI()\n" + ui + "\nend\nlocal UI = loadUI()")
    Path(sys.argv[1]).write_text(result, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
