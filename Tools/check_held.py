#!/usr/bin/env python3
"""The App Store build's held list (CONTEXT §D.25) in one place: project.yml's AppStore MAQUETTE_HELD.

Checks that every name in it is a case of MaquetteHeld (Workspace/Support/Held.swift) and every case is in it, that
Debug and Release hold nothing, then prints the list (CI compares it with the built Info.plist).
"""
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
yml = (root / "project.yml").read_text(encoding="utf-8")
swift = (root / "Packages/LoweyFeatures/Sources/LoweyFeatures/Workspace/Support/Held.swift").read_text(encoding="utf-8")

base = re.findall(r'^    MAQUETTE_HELD: "(.*)"$', yml, re.M)
store = re.findall(r'^      MAQUETTE_HELD: "(.*)"$', yml, re.M)
cases = re.findall(r"^    case (\w+)$", swift, re.M)
errors = []
if base != [""]:
    errors.append(f"Debug and Release must hold nothing, found {base}")
if len(store) != 1:
    errors.append(f"one AppStore MAQUETTE_HELD expected, found {len(store)}")
names = store[0].split() if store else []
if sorted(names) != sorted(cases):
    errors.append(f"project.yml holds {sorted(names)}, Held.swift lists {sorted(cases)}")
if errors:
    for error in errors:
        print(f"::error::{error}")
    sys.exit(1)
print(" ".join(names))
