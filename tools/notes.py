#!/usr/bin/env python3
"""Prints the CHANGELOG.md section for a version (used by build.sh --package and tools/release.sh)."""
import re, sys
v = sys.argv[1]
try:
    text = open("CHANGELOG.md").read()
except OSError:
    text = ""
m = re.search(r"^## %s[^\n]*\n(.*?)(?=^## |\Z)" % re.escape(v), text, re.S | re.M)
print((m.group(1).strip() if m else "Tide %s" % v))
