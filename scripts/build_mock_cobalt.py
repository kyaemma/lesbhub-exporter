#!/usr/bin/env python3
"""Inline the optional Cobalt plugin into a mock Luau environment."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
TOKEN = 'local plugin = require("../integrations/cobalt/LesbhubRemoteObserver")'


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python scripts/build_mock_cobalt.py /tmp/mock-cobalt.luau")
    mock = (ROOT / "tests" / "mock_cobalt.luau").read_text(encoding="utf-8")
    source = (ROOT / "integrations" / "cobalt" / "LesbhubRemoteObserver.luau").read_text(
        encoding="utf-8"
    ).rstrip()
    if mock.count(TOKEN) != 1:
        raise SystemExit("Cobalt mock insertion point missing")
    result = mock.replace(TOKEN, source)
    Path(sys.argv[1]).write_text(result, encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
