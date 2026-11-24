"""Inline the writer into its synthetic Luau tests; no executor required."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
if __name__ == "__main__":
    source = (ROOT / "src/deep_scripts.lua").read_text(encoding="utf-8")
    mock = (ROOT / "tests/mock_deep_scripts.luau").read_text(encoding="utf-8")
    result = mock.replace('local Deep = require("../src/deep_scripts")',
                          'local Deep = (function()\n' + source + '\nend)()')
    Path(sys.argv[1]).write_text(result, encoding="utf-8", newline="\n")
