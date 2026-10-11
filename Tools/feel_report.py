"""Reads a feel recording (Diagnostics ▸ Record) and ranks the slowest moments against U1's gates.

    python Tools/feel_report.py feel-iPad14,8-0.10.1-20261011-101500.json
    python Tools/feel_report.py before.json after.json     # the gates side by side
    python Tools/feel_report.py recording.json --top 40    # a longer ranked list

Every touch in the file was followed to the refresh that shows its answer, with its time split into input (the touch
reaching the app), main (the app's own work on the main thread), encode and GPU (the stage's frame, for touches on
it). `missed` counts refreshes that went by before the answer was ready: 0 is the gate.
"""
from __future__ import annotations

import argparse
import json
import math
import pathlib
import statistics
import sys
from collections import defaultdict

# The gates (PHASES.md, U1): every touch answered within one frame, a panel open in under 0.1 s, a project's first
# frame in under 0.5 s, no dropped frames.
PANEL_MS = 100
OPEN_MS = 500
LAUNCH_MS = 1000


def percentile(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    rank = max(min(math.ceil(p / 100 * len(ordered)) - 1, len(ordered) - 1), 0)
    return ordered[rank]


def region(touch: dict, width: float, height: float) -> str:
    """Where on the screen, in the layout's words (CONTEXT §4.1), so a slow moment can be found again."""
    x, y = touch["x"] / width, touch["y"] / height
    vertical = "top" if y < 0.15 else "bottom" if y > 0.8 else "middle"
    horizontal = "left" if x < 0.2 else "right" if x > 0.8 else "centre"
    return f"{vertical}-{horizontal}"


def where_time_went(touch: dict) -> str:
    parts = {"input": touch["input"], "main": touch["main"], "encode": touch.get("encode") or 0, "gpu": touch.get("gpu") or 0}
    name, value = max(parts.items(), key=lambda item: item[1])
    return f"{name} {value:.1f}"


def gates(rec: dict) -> dict[str, tuple[str, bool]]:
    touches = rec["touches"]
    on_time = [t for t in touches if t["missed"] == 0]
    share = 100 * len(on_time) / len(touches) if touches else 100.0
    taps = [t for t in touches if t["phase"] == "ended" and t.get("gpu") is None]
    slow_taps = [t for t in taps if t["total"] > PANEL_MS]
    opens = [m for m in rec["marks"] if m["name"] == "Open project"]
    worst_open = max((m["duration"] for m in opens), default=None)
    launch = rec.get("launch")
    result = {
        "touches answered within one frame": (f"{share:.1f} % of {len(touches)}", share == 100.0),
        "taps answered under 0.1 s": (f"{len(taps) - len(slow_taps)} of {len(taps)}", not slow_taps),
        "dropped frames": (f"{len(rec['hitches'])} hitches, {len(rec['stalls'])} main-thread stalls", not rec["hitches"]),
    }
    if worst_open is not None:
        result["project's first frame under 0.5 s"] = (f"worst {worst_open:.0f} ms of {len(opens)}", worst_open < OPEN_MS)
    if launch is not None:
        result["cold launch under 1 s"] = (f"{launch:.0f} ms", launch < LAUNCH_MS)
    return result


def report(path: pathlib.Path, top: int) -> dict:
    rec = json.loads(path.read_text(encoding="utf-8"))
    touches = rec["touches"]
    width = rec.get("width") or max((t["x"] for t in touches), default=1) or 1
    height = rec.get("height") or max((t["y"] for t in touches), default=1) or 1
    print(f"# {rec['app']} {rec['appVersion']} · {rec['device']} · {rec['system']} · {rec['refreshRate']:.0f} Hz")
    print(f"{rec['seconds']:.0f} s, {len(touches)} touches, {len(rec['frames'])} stage frames\n")

    print("## Gates")
    for name, (value, passed) in gates(rec).items():
        print(f"- [{'x' if passed else ' '}] {name}: {value}")

    print(f"\n## The {top} slowest touches")
    print("| when | ms | missed | phase | screen | target | where | most time |")
    print("|---:|---:|---:|---|---|---|---|---|")
    for touch in sorted(touches, key=lambda t: t["total"], reverse=True)[:top]:
        print(f"| {touch['t']:.2f} s | {touch['total']:.0f} | {touch['missed']} | {touch['phase']} {touch['kind']} | {touch['screen']} | "
              f"{touch['target']} | {region(touch, width, height)} | {where_time_went(touch)} |")

    print("\n## Where the time goes, by what was touched (worst first)")
    groups: dict[tuple, list[dict]] = defaultdict(list)
    for touch in touches:
        groups[(touch["screen"], touch["target"], touch["phase"])].append(touch)
    rows = []
    for (screen, target, phase), items in groups.items():
        totals = [t["total"] for t in items]
        rows.append((percentile(totals, 95), screen, target, phase, items, totals))
    print("| p95 ms | worst | count | missed | screen | target | phase | main p95 | gpu p95 |")
    print("|---:|---:|---:|---:|---|---|---|---:|---:|")
    for p95, screen, target, phase, items, totals in sorted(rows, key=lambda row: row[0], reverse=True)[:top]:
        missed = sum(1 for t in items if t["missed"] > 0)
        gpus = [t["gpu"] for t in items if t.get("gpu") is not None]
        gpu = f"{percentile(gpus, 95):.1f}" if gpus else "-"
        print(f"| {p95:.0f} | {max(totals):.0f} | {len(items)} | {missed} | {screen} | {target} | {phase} | "
              f"{percentile([t['main'] for t in items], 95):.1f} | {gpu} |")

    if rec["stalls"]:
        print("\n## The main thread's longest stalls")
        for stall in sorted(rec["stalls"], key=lambda s: s["busy"], reverse=True)[:10]:
            print(f"- {stall['t']:.2f} s: {stall['busy']:.0f} ms on {stall['screen']}")
    if rec["hitches"]:
        print("\n## Missed refreshes")
        for hitch in sorted(rec["hitches"], key=lambda h: h["gap"], reverse=True)[:10]:
            print(f"- {hitch['t']:.2f} s: a {hitch['gap']:.0f} ms gap on {hitch['screen']}")
    if rec["marks"]:
        print("\n## Marks")
        for mark in rec["marks"]:
            print(f"- {mark['t']:.2f} s: {mark['name']} {mark['duration']:.0f} ms ({mark['screen']})")
    if rec["frames"]:
        gpu = [f["gpu"] for f in rec["frames"]]
        encode = [f["encode"] for f in rec["frames"]]
        print(f"\n## Stage frames\nGPU p50 {statistics.median(gpu):.1f} ms, p95 {percentile(gpu, 95):.1f}, worst {max(gpu):.1f} · "
              f"encode p50 {statistics.median(encode):.1f} ms, p95 {percentile(encode, 95):.1f}, worst {max(encode):.1f}")
    print()
    return rec


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("recordings", nargs="+", type=pathlib.Path)
    parser.add_argument("--top", type=int, default=25)
    args = parser.parse_args(argv)
    sys.stdout.reconfigure(encoding="utf-8")
    recordings = [report(path, args.top) for path in args.recordings]
    if len(recordings) > 1:
        print("## Gates side by side")
        tables = [gates(rec) for rec in recordings]
        names = list(dict.fromkeys(name for table in tables for name in table))
        print("| gate | " + " | ".join(path.name for path in args.recordings) + " |")
        print("|---|" + "---|" * len(recordings))
        for name in names:
            cells = [f"{'pass' if t[name][1] else 'FAIL'}: {t[name][0]}" if name in t else "-" for t in tables]
            print(f"| {name} | " + " | ".join(cells) + " |")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
