#!/usr/bin/env python3
"""Reads p2_explain_BEFORE.txt and p2_explain_AFTER.txt (real EXPLAIN ANALYZE output) and prints a
BEFORE/AFTER table: the scan used on the biggest (fact) table and the real Execution Time.
Nothing is typed in by hand."""
import re
import sys

d = sys.argv[1]
FACT = ("pickup", "collection_record", "payment", "shift")
SCAN = re.compile(r"(Seq Scan|Index Only Scan|Index Scan|Bitmap Heap Scan)(?: using (\S+))? on (\w+)")


def parse(path):
    out, cur = {}, None
    for line in open(path):
        m = re.match(r"==== (Q\d+) EXPLAIN", line)
        if m:
            cur = m.group(1)
            out[cur] = {"scans": [], "ms": None}
            continue
        if cur is None:
            continue
        s = SCAN.search(line)
        if s:
            out[cur]["scans"].append((s.group(1), s.group(2), s.group(3)))
        t = re.search(r"Execution Time: ([\d.]+) ms", line)
        if t:
            out[cur]["ms"] = float(t.group(1))
    return out


def pick(scans):
    for s in scans:
        if s[2] in FACT:
            return s
    return scans[0] if scans else None


def fmt(q):
    s = pick(q["scans"])
    label = "?" if s is None else (f"{s[0]} on {s[2]}" + (f" ({s[1]})" if s[1] else ""))
    return label, q["ms"]


b, a = parse(f"{d}/p2_explain_BEFORE.txt"), parse(f"{d}/p2_explain_AFTER.txt")
print(f"{'Q':<3} | {'BEFORE: scan on fact table':<44} {'ms':>8} | {'AFTER: scan on fact table':<64} {'ms':>8} | change")
print("-" * 150)
for k in sorted(b, key=lambda x: int(x[1:])):
    lb, tb = fmt(b[k])
    la, ta = fmt(a[k])
    ch = f"{(ta - tb) / tb * 100:+.0f}%" if tb and ta else "n/a"
    print(f"{k:<3} | {lb:<44} {tb:>8.3f} | {la:<64} {ta:>8.3f} | {ch}")
print("\nNegative change = faster after the index. Small tables or whole-table aggregates keep a Seq Scan "
      "(that is the correct plan: an index cannot help when most rows are needed).")
