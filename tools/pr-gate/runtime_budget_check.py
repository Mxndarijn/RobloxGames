#!/usr/bin/env python3
"""Decide the runtime budget verdict. Usage:
    runtime_budget_check.py COUNTS.json BUDGETS.json

BUDGETS.json is tools/pipeline/pc-watcher/budgets.json (single source, shared with the Studio perf step):
  runtime_parts    FAIL > runtime_parts.fail, WARN > runtime_parts.warn
  unique_meshes    FAIL > unique_meshes.fail
  mesh_parts       WARN > mesh_parts.warn (soft: never fails)
World triangles are checked by budget.sh (FBX triangle counts), not here.
Prints one summary line plus a WARN line per warning, appends a markdown table to $GITHUB_STEP_SUMMARY and
emits ::warning:: annotations under GitHub Actions. Exit 1 on FAIL only; warn-only exits 0.
"""
import json
import os
import sys


def main(argv):
    counts = json.load(open(argv[1]))
    b = json.load(open(argv[2]))
    parts, uniq, meshes = counts["runtime_parts"], counts["unique_meshes"], counts["mesh_slots"]
    p_fail, p_warn = b["runtime_parts"]["fail"], b["runtime_parts"]["warn"]
    u_fail, m_warn = b["unique_meshes"]["fail"], b["mesh_parts"]["warn"]
    fails, warns = [], []
    if parts > p_fail:
        fails.append(f"runtime parts {parts} > {p_fail} (over by {parts - p_fail})")
    elif parts > p_warn:
        warns.append(f"runtime parts {parts} > warn {p_warn} (fail above {p_fail})")
    if uniq > u_fail:
        fails.append(f"unique meshes {uniq} > {u_fail} (over by {uniq - u_fail})")
    if meshes > m_warn:
        warns.append(f"MeshParts {meshes} > soft budget {m_warn} (never fails; limits are triangles and unique meshes)")
    verdict = "FAIL" if fails else "PASS"
    print(
        f"runtime-budget: parts {parts}/{p_fail} (warn {p_warn}) unique meshes {uniq}/{u_fail} "
        f"mesh parts {meshes} (soft {m_warn}) -> {verdict}"
    )
    print(
        f"  offline raw parts {counts.get('runtime_parts_offline')} + Studio-only offset {counts.get('offset')}; "
        f"unique meshes offline {counts.get('unique_meshes_offline')} + offset; "
        f"MeshParts: build {counts.get('mesh_slots_build')}, runtime {counts.get('mesh_slots_runtime')} (+offset)"
    )
    for f in fails:
        print(f"  FAIL: {f}")
        if os.environ.get("GITHUB_ACTIONS"):
            print(f"::error::runtime-budget: {f}")
    for w in warns:
        print(f"  WARN: {w}")
        if os.environ.get("GITHUB_ACTIONS"):
            print(f"::warning::runtime-budget: {w}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        rows = [
            ("runtime parts", parts, f"fail > {p_fail}, warn > {p_warn}", "FAIL" if parts > p_fail else "WARN" if parts > p_warn else "PASS"),
            ("unique meshes", uniq, f"fail > {u_fail}", "FAIL" if uniq > u_fail else "PASS"),
            ("MeshParts", meshes, f"soft, warn > {m_warn}", "WARN" if meshes > m_warn else "PASS"),
        ]
        with open(summary, "a") as fh:
            fh.write("### runtime-budget\n\n| metric | count | limit | result |\n|---|---|---|---|\n")
            fh.write("\n".join(f"| {n} | {c} | {lim} | {r} |" for n, c, lim, r in rows) + "\n\n")
            for w in warns:
                fh.write(f"- :warning: {w}\n")
            for f in fails:
                fh.write(f"- :x: {f}\n")
            fh.write("\n")
    return 1 if fails else 0


sys.exit(main(sys.argv))
