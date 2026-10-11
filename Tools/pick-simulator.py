#!/usr/bin/env python3
"""Prints the UDID of the newest available iPad simulator (iPad Air 13" preferred), or with --iphone the largest
iPhone (6.9", Pro Max preferred). With --size mini|11|13 it picks that size of iPad instead (the atlas runs on all
three). Used by CI."""
import json
import subprocess
import sys

devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
WANT_PHONE = "--iphone" in sys.argv
SIZE = sys.argv[sys.argv.index("--size") + 1] if "--size" in sys.argv else None
# What each size's name contains, best first.
SIZES = {
    "mini": ["iPad mini"],
    "11": ['iPad Air 11', 'iPad Pro 11', 'iPad (A16)', "iPad (10th"],
    "13": ['iPad Air 13', 'iPad Pro 13'],
}


def size_rank(name):
    """How well an iPad's name matches the wanted size (higher is better); None when it isn't that size."""
    for rank, part in enumerate(SIZES[SIZE]):
        if part in name:
            return len(SIZES[SIZE]) - rank
    return None


best = None
for runtime, entries in devices.items():
    if "iOS" not in runtime:
        continue
    version = tuple(int(part) for part in runtime.split("iOS-")[-1].split("-"))
    for device in entries:
        name = device["name"]
        if WANT_PHONE:
            if "iPhone" not in name:
                continue
            score = (version, "Pro Max" in name, "Plus" in name or "Air" in name)
        elif "iPad" not in name:
            continue
        elif SIZE:
            rank = size_rank(name)
            if rank is None:
                continue
            score = (version, rank)
        else:
            score = (version, "iPad Air 13" in name, "iPad Air" in name)
        if best is None or score > best[0]:
            best = (score, device["udid"], name)
if best is None:
    sys.exit("No iPhone simulator available" if WANT_PHONE else f"No iPad simulator available{' of size ' + SIZE if SIZE else ''}")
print(best[2], file=sys.stderr)
print(best[1])
