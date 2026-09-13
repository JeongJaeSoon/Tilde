#!/usr/bin/env python3
"""Check docs/APP_STORE_LISTING.md field lengths against App Store Connect limits."""
import re, sys, pathlib
LIMITS = {"Name": 30, "Subtitle": 30, "Promotional Text": 170, "Keywords": 100,
          "Description": 4000, "What's New in This Version": 4000}
text = pathlib.Path(__file__).resolve().parent.parent.joinpath("docs/APP_STORE_LISTING.md").read_text()
locale = "?"
bad = 0
for m in re.finditer(r"^## ([^\n]+)$|^\*\*(.+?)\*\*\n```\n(.*?)\n```", text, re.M | re.S):
    if m.group(1):
        locale = m.group(1).split(" — ")[0]; continue
    field, body = m.group(2), m.group(3)
    if field not in LIMITS: continue
    n, lim = len(body), LIMITS[field]
    ok = n <= lim; bad += not ok
    print(f"{'OK  ' if ok else 'OVER'} {n:>5}/{lim:<5} {locale:12} {field}")
sys.exit(1 if bad else 0)
