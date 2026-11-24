#!/usr/bin/env python3
"""Inline Relations module for the isolated Luau CLI contract mock."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
TOKEN = 'local Relations = require("../src/relations")'


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python scripts/build_mock_relations.py /tmp/mock-relations.luau")
    mock = (ROOT / "tests" / "mock_relations.luau").read_text(encoding="utf-8")
    module = (ROOT / "src" / "relations.lua").read_text(encoding="utf-8").rstrip()
    if mock.count(TOKEN) != 1:
        raise SystemExit("Mock Relations entrypoint missing or duplicated")
    result = mock.replace(TOKEN, "local function loadRelations()\n" + module
                          + "\nend\nlocal Relations = loadRelations()")
    Path(sys.argv[1]).write_text(result, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
