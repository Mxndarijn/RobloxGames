#!/usr/bin/env python3
"""Top-down map of the Steal a Slime kit prop placement (headless).

    lune run tools/placement/export      # writes sheets/placement/placement.json
    python3 tools/placement/render.py    # writes sheets/placement/placement_map.png

Run both from games/steal-a-slime. World X is drawn to the right, world Z up;
every footprint is the slot's turned rectangle (native size x uniform scale).
Panel 1 is the whole world, panel 2 zooms on the plaza and the plot fronts.
"""
import json
import math
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.lines import Line2D  # noqa: E402
from matplotlib.patches import Circle, Patch, Polygon, Wedge  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "sheets/placement/placement.json"
OUT = ROOT / "sheets/placement/placement_map.png"

# Categorical slots 1-3 of the validated reference palette (blue, orange, aqua),
# fixed order by cluster; the zones and world furniture stay neutral.
CLUSTER = {"plaza": "#2a78d6", "entrance": "#eb6834", "farm": "#1baf7a"}
INK, MUTED, SURFACE = "#2b2b29", "#8a897f", "#fbfaf7"
GRASS, SAND, GOO, PLOT = "#e6eedb", "#eadfc8", "#cfeedd", "#f1efe9"
GLASS, MOAT, KEEP = "#8fc9cf", "#6ee2aa", "#d8d6cf"
BORDER, BORDER_ACCENT = "#a9b99a", "#6f7f60"


def corners(r):
    a = math.radians(r["yaw"])
    ux, uz, vx, vz = math.cos(a), -math.sin(a), math.sin(a), math.cos(a)
    out = []
    for sx, sz in ((1, 1), (1, -1), (-1, -1), (-1, 1)):
        out.append((r["cx"] + ux * r["hx"] * sx + vx * r["hz"] * sz, r["cz"] + uz * r["hx"] * sx + vz * r["hz"] * sz))
    return out


def annulus(ax, inner, outer, color, z=1, **kw):
    ax.add_patch(Wedge((0, 0), outer, 0, 360, width=outer - inner, facecolor=color, edgecolor="none", zorder=z, **kw))


def draw(ax, d, zoom):
    ax.set_facecolor(SURFACE)
    ax.add_patch(Polygon([(-320, -320), (320, -320), (320, 320), (-320, 320)], closed=True, facecolor=GRASS,
                         edgecolor="none", zorder=0))
    ax.add_patch(Circle((0, 0), d["wallRadius"], facecolor="none", edgecolor=INK, lw=1.0, zorder=6))
    ax.add_patch(Circle((0, 0), d["edge"], facecolor="none", edgecolor=MUTED, lw=0.6, ls="--", zorder=6))
    for b in d["border"]:
        ax.add_patch(Polygon(corners(b["rect"]), closed=True, facecolor=BORDER_ACCENT if b["uploaded"] else BORDER,
                             edgecolor=SURFACE, lw=0.3, zorder=5))
    annulus(ax, 0, 66, SAND, 1)
    annulus(ax, d["landing"]["inner"], d["landing"]["outer"], "#f3e2b8", 2)
    annulus(ax, d["lane"]["inner"], d["lane"]["outer"], GOO, 2)
    rp = d["ringPath"]
    annulus(ax, rp["radius"] - rp["width"] / 2, rp["radius"] + rp["width"] / 2, SAND, 2)
    ax.add_patch(Circle((0, 0), d["fountain"]["plinth"], facecolor="#c99a68", edgecolor=INK, lw=0.6, zorder=4))
    xs, zs = zip(*d["slide"])
    ax.plot(xs, zs, color="#5fbf8f", lw=1.6 if zoom else 0.8, zorder=5)
    # parade lane despawn gate at +Z
    ax.plot([0, 0], [d["lane"]["inner"], d["lane"]["outer"]], color=INK, lw=2.2, zorder=5)

    for z in d["zones"]:
        if z["kind"] == "rect" and z["name"].endswith("entrance"):
            ax.add_patch(Polygon(corners(z["rect"]), closed=True, facecolor="none", edgecolor=MUTED,
                                 hatch="////", lw=0.5, zorder=3))
        elif z["kind"] == "circle":
            ax.add_patch(Circle((z["x"], z["z"]), z["radius"], facecolor=KEEP, edgecolor=MUTED, lw=0.5, zorder=3))
            if zoom and not z["name"].startswith("plot"):
                ax.annotate(z["name"], (z["x"], z["z"]), fontsize=5.5, color=MUTED, ha="center", va="center", zorder=9)

    for p in d["plots"]:
        ax.add_patch(Polygon(corners(p["rect"]), closed=True, facecolor=PLOT, edgecolor="none", zorder=3))
        j = p["jar"]
        ax.add_patch(Circle((j["x"], j["z"]), p["moat"], facecolor=MOAT, edgecolor="none", zorder=5, alpha=0.6))
        ax.add_patch(Circle((j["x"], j["z"]), j["radius"], facecolor=PLOT, edgecolor=GLASS, lw=1.2, zorder=6))
        g = p["door"]
        ax.plot(g["x"], g["z"], marker="v", ms=4 if zoom else 2.5, color=INK, zorder=8)
        cx, cz = p["rect"]["cx"], p["rect"]["cz"]
        ax.annotate(f"Plot {p['index']}", (cx, cz), fontsize=7 if zoom else 6, color=INK, ha="center", va="center",
                    zorder=9)

    for prop in d["props"]:
        ax.add_patch(Polygon(corners(prop["rect"]), closed=True, facecolor=CLUSTER[prop["cluster"]],
                             edgecolor=SURFACE, lw=0.6, zorder=8))
        if zoom:
            r = prop["rect"]
            if math.hypot(r["cx"], r["cz"]) < 135:
                ax.annotate(prop["name"], (r["cx"], r["cz"] + max(r["hx"], r["hz"]) + 1.5), fontsize=4.5,
                            color=INK, ha="center", va="bottom", zorder=9)

    lim = 140 if zoom else 322
    ax.set_xlim(-lim, lim)
    ax.set_ylim(-lim, lim)
    ax.set_aspect("equal")
    ax.tick_params(labelsize=6, colors=MUTED)
    for s in ax.spines.values():
        s.set_color(KEEP)
    ax.set_xlabel("world X (studs)", fontsize=7, color=MUTED)
    ax.set_ylabel("world Z (studs)", fontsize=7, color=MUTED)


def main():
    d = json.loads(SRC.read_text())
    fig, axes = plt.subplots(1, 2, figsize=(18, 9.4), dpi=150, facecolor=SURFACE)
    draw(axes[0], d, False)
    draw(axes[1], d, True)
    counts = {c: sum(1 for p in d["props"] if p["cluster"] == c) for c in CLUSTER}
    axes[0].set_title(f"Whole world: {len(d['props'])} kit props, {len(d['border'])} border pieces\n"
                      f"{len(d['plots'])} plots, each a ground jar in a goo moat",
                      fontsize=10, color=INK, loc="left")
    axes[1].set_title("Plaza edge and plot entrances (r < 140)", fontsize=10, color=INK, loc="left")
    handles = [Patch(facecolor=CLUSTER[c], label=f"{c} props ({counts[c]})") for c in CLUSTER]
    handles += [
        Patch(facecolor=PLOT, edgecolor=GLASS, label="ground jar (glass wall)"),
        Patch(facecolor=MOAT, alpha=0.6, label="goo moat"),
        Line2D([], [], marker="v", ls="none", color=INK, label="jar door"),
        Patch(facecolor="none", edgecolor=MUTED, hatch="////", label="entrance corridor (keep clear)"),
        Patch(facecolor=KEEP, edgecolor=MUTED, label="prop spot / showpiece / buy stand"),
        Patch(facecolor=GOO, label="parade lane r64.75-71.25 (gate +Z)"),
        Patch(facecolor="#f3e2b8", label="wild landing band r34-62"),
        Patch(facecolor=SAND, label="plaza sand, ring path r74-82"),
        Line2D([], [], color="#5fbf8f", label="fountain slide"),
        Line2D([], [], color=INK, label="border wall ring r292"),
        Line2D([], [], color=MUTED, ls="--", label="prop edge r280"),
        Patch(facecolor=BORDER, label="border piece (BorderMesh)"),
        Patch(facecolor=BORDER_ACCENT, label="border accent (uploaded)"),
    ]
    fig.legend(handles=handles, loc="lower center", ncol=8, fontsize=7.5, frameon=False, labelcolor=INK)
    fig.suptitle("Steal a Slime: Slime Ranch prop placement (top-down, from WorldLayout.RANCH_PROPS)",
                 fontsize=12, color=INK, x=0.06, ha="left")
    fig.subplots_adjust(left=0.05, right=0.98, top=0.92, bottom=0.12, wspace=0.12)
    fig.savefig(OUT, facecolor=SURFACE)
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    sys.exit(main())
