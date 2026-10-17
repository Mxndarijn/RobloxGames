#!/usr/bin/env python3
"""Decide the runtime budget verdict. Usage:
    runtime_budget_check.py HEAD_COUNTS.json BASE_COUNTS.json|- PART_BUDGET MESH_BUDGET

Per metric (parts vs runtime_part_budget, meshes vs mesh_slot_budget):
  base known and base > budget : FAIL only if head > base (the PR makes it worse)
  otherwise                    : FAIL if head > budget
Prints one summary line, appends a markdown table to $GITHUB_STEP_SUMMARY, exit 1 on FAIL.
"""
import json
import os
import sys


def verdict(head, base, budget):
    """(ok, note) for one metric."""
    if base is not None and base > budget:
        if head > base:
            return False, f"+{head - base} over a base that is already over budget"
        return True, "base already over budget; PR does not increase it"
    if head > budget:
        return False, f"{head - budget} over budget"
    return True, "within budget"


def main(argv):
    head = json.load(open(argv[1]))
    base = None if argv[2] == "-" else json.load(open(argv[2]))
    budgets = {"parts": int(argv[3]), "meshes": int(argv[4])}
    keys = {"parts": "runtime_parts", "meshes": "mesh_slots"}
    ok_all, parts, notes, rows = True, [], [], []
    for name in ("parts", "meshes"):
        h = head[keys[name]]
        b = base[keys[name]] if base else None
        ok, note = verdict(h, b, budgets[name])
        ok_all = ok_all and ok
        base_txt = f"base {b}, {h - b:+d}" if b is not None else "base n/a"
        parts.append(f"{name} {h}/{budgets[name]} ({base_txt})")
        if not ok or (b is not None and b > budgets[name]):
            notes.append(f"{name}: {note}")
        rows.append(f"| {name} | {h} | {b if b is not None else 'n/a'} | {budgets[name]} | {'PASS' if ok else 'FAIL'} | {note} |")
    line = "runtime-budget: " + " ".join(parts) + " -> " + ("PASS" if ok_all else "FAIL")
    if notes:
        line += " (" + "; ".join(notes) + ")"
    print(line)
    print(
        f"  offline raw parts {head.get('runtime_parts_offline')} + Studio-only offset {head.get('offset')}; "
        f"meshes: build {head.get('mesh_slots_build')}, runtime {head.get('mesh_slots_runtime')} (+offset)"
    )
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("### runtime-budget\n\n| metric | head | base | budget | result | note |\n|---|---|---|---|---|---|\n")
            f.write("\n".join(rows) + "\n\n")
    return 0 if ok_all else 1


sys.exit(main(sys.argv))
