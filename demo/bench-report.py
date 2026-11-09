#!/usr/bin/env python3
"""Table of demo/bench.sh results: bench-report.py LINES.jsonl [SAVE.json] [COMPARE.json].

Steps of the same name (runs × rounds) are reduced to their median.
CPU of an idle window comes from the process samples around it (clock ticks, 100/s).
"""
import json
import statistics
import sys
from collections import defaultdict

TICKS_PER_S = 100
IDLE_S = 10
FIELDS = ("sync", "frame", "blocked", "blockedMax", "spawns", "popupFps", "panelFps")


def medians(path):
    steps = defaultdict(lambda: defaultdict(list))
    samples = defaultdict(list)
    for line in open(path):
        r = json.loads(line)
        if "cpuTicks" in r:
            samples[r["name"]].append(r)
            continue
        for f in FIELDS:
            if f in r:
                steps[r["name"]][f].append(r[f])
    out = {name: {f: statistics.median(v) for f, v in fs.items()} for name, fs in steps.items()}
    # Runs are in order, so the n-th begin pairs with the n-th end.
    for idle in ("idle-open", "idle-collapsed"):
        begins, ends = samples[idle + "-begin"], samples[idle + "-end"]
        cpu = [100 * (e["cpuTicks"] - b["cpuTicks"]) / TICKS_PER_S / IDLE_S for b, e in zip(begins, ends)]
        if cpu and idle in out:
            out[idle]["cpuPercent"] = statistics.median(cpu)
    for name in ("startup", "idle-collapsed-end"):
        if samples[name]:
            out.setdefault("process", {})["rssMb-" + name] = statistics.median(s["rssKb"] for s in samples[name]) / 1024
            out["process"]["spawns-" + name] = statistics.median(s["spawnsTotal"] for s in samples[name])
    return out


def main():
    cur = medians(sys.argv[1])
    save = sys.argv[2] if len(sys.argv) > 2 else ""
    base = json.load(open(sys.argv[3])) if len(sys.argv) > 3 and sys.argv[3] else None
    if save:
        json.dump(cur, open(save, "w"), indent=1, sort_keys=True)
    print(f"{'step':24} {'metric':14} {'value':>10}" + (f" {'before':>10} {'change':>8}" if base else ""))
    for name in sorted(cur):
        for metric, v in sorted(cur[name].items()):
            row = f"{name:24} {metric:14} {v:10.1f}"
            if base and name in base and metric in base[name]:
                b = base[name][metric]
                change = f"{100 * (v - b) / b:+7.0f}%" if b else "      -"
                row += f" {b:10.1f} {change}"
            print(row)


main()
