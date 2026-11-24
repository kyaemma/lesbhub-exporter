#!/usr/bin/env python3
"""Inline Report module for the isolated Luau CLI contract mock."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
TOKEN = 'local Report = require("../src/report")'


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python scripts/build_mock_report.py /tmp/mock-report.luau")
    mock = (ROOT / "tests" / "mock_report.luau").read_text(encoding="utf-8")
    report = (ROOT / "src" / "report.lua").read_text(encoding="utf-8").rstrip()
    if mock.count(TOKEN) != 1:
        raise SystemExit("Mock Report entrypoint missing or duplicated")
    result = mock.replace(TOKEN, "local function loadReport()\n" + report + "\nend\nlocal Report = loadReport()")
    Path(sys.argv[1]).write_text(result, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
