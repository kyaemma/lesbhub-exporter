#!/usr/bin/env python3
"""Inline the cooperative budget module into its synthetic Luau test."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
TOKEN = 'local Budget = require("../src/work_budget")'


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python scripts/build_mock_budget.py /tmp/mock-budget.luau")
    mock = (ROOT / "tests" / "mock_work_budget.luau").read_text(encoding="utf-8")
    source = (ROOT / "src" / "work_budget.lua").read_text(encoding="utf-8").rstrip()
    if mock.count(TOKEN) != 1:
        raise SystemExit("Work budget mock insertion point missing or duplicated")
    result = mock.replace(TOKEN, "local function loadBudget()\n" + source + "\nend\nlocal Budget = loadBudget()")
    Path(sys.argv[1]).write_text(result, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
