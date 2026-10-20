#!/usr/bin/env python3
"""Steal a Slime PC watcher: Studio checks for every new origin/main sha, on Merijn's PC.

  watcher.py loop                       poll `git ls-remote` every 60 s, run new shas
  watcher.py once [--sha SHA] [--kind full|partial] [--reason TXT]
                                        one run for a sha (default: full run of origin/main), ignores last-sha
  watcher.py perf [--sha SHA] [--extra 0,500,1000] [--seconds 30] [--no-sync] [--phone] [--quality 10,1] [--meshparts N] [--unique-meshes N] [--terrain-off]   perf measurement, never publishable
  watcher.py step build|launch|perf|play|devices|twoplayer|close|sync [--sha SHA]
  watcher.py tools                      dump StudioMCP tool schemas (needs a running Studio for most calls)
  watcher.py mcp TOOL [JSON_ARGS]       one raw tools/call ("$studio" in args = the watcher's studio id)
  watcher.py capture [--out f.jpg]      StudioMCP screen_capture of the watcher's Studio (the game viewport)
  watcher.py selftest                   pure checks, any OS
Global flags: --home DIR (default C:\\gate\\pc-watcher or $PCW_HOME), --dry-run, -v.

Studio is driven only through StudioMCP.exe (stdio JSON-RPC) plus Win32 for window size. It runs in
the background on its own Win32 desktop ("pcw-studio"), so it cannot take focus on the user's desktop;
frames come from StudioMCP screen_capture and nothing sends real mouse/keyboard input (README "Runs in
the background"). See README.md for the flow, report format and limits.
"""

import argparse
import copy
import datetime
import fnmatch
import glob
import json
import logging
import logging.handlers
import math
import os
import platform
import re
import shutil
import subprocess
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import imaging  # noqa: E402
import mcp_client  # noqa: E402
import win32  # noqa: E402

VERSION = "1.0.0"
log = logging.getLogger("pcw")

DEFAULTS = {
    "remote": "origin",
    "branch": "main",
    "game_dir": "games/steal-a-slime",
    "project": "default.project.json",
    "keep_builds": 5,
    "poll_s": 60,
    "busy_retry_s": 300,
    "run_budget_s": 900,
    # Perf budgets: budgets.json (next to this file) is the single source and overlays these; they are the fallback
    # when it is missing or broken (selftest.py keeps them equal to it).
    "mesh_slot_budget": 500,  # SOFT: MeshParts only warn above it
    "runtime_part_budget": 3000,  # FAIL above this. World BaseParts at runtime (excl. slimes/characters/transients)
    "runtime_part_warn": 2900,  # WARN (non-blocking) above this
    "unique_mesh_budget": 120,  # FAIL above this (distinct MeshIds)
    "world_triangle_budget": 500000,  # FAIL above this, CI only (pr-gate budget.sh from FBX); Studio cannot count triangles
    "launch_timeout_s": 120,
    "client_timeout_s": 90,
    "stats_seconds": 5,
    "play_bt_max_s": 120,  # play step: max wait for the BorderTerrain attribute before the settled fps sample
    "play_settle_s": 30,  # play step: extra seconds after BorderTerrain is true, then the settled sample
    "devices": [["desktop", 1920, 1080], ["phone-portrait", 390, 844], ["phone-landscape", 844, 390]],
    "device_iterations": 5,
    "menu_panels": ["plot", "merge", "shop", "rebirth", "goals", "dex", "leaders", "codes", "guide"],  # src/ui/init.client allPanels
    "phone_min_fps": 30,  # phone_perf fails below this average FPS (Studio on a PC, not phone hardware)
    "phone_min_slimes": 16,  # SlimeLife.MAX_ACTIVE: animating slimes wanted near the camera
    # kind (mouse_down, mouse_up, key_down, key_up) -> action template, "$x" / "$y" / "$key" filled in.
    # Empty = built from the tool's inputSchema (see mcp_client.build_action).
    "reports_branch": "studio-reports",
    "push_retries": 3,
    "jpeg_quality": 80,
    "sync": True,
    "partial_runs": True,  # False = every new tip gets a full run (the old behaviour)
    "candidate_wait_s": 150,  # a new tip waits this long for a publish candidate request before a partial run
    "full_schedule": ["11:15", "18:15"],  # local HH:MM (PC clock, Europe/Amsterdam): full run of the main tip
    "full_schedule_grace_s": 10800,  # a slot missed by more than this (PC off, loop restarted late) is skipped
    "full_request_depth": 8,  # a candidate request counts when its sha is among the newest N main commits
    "partial_max_files": 60,  # more changed files than this = full run
}

# A step outside these that ends "fail" still fails the run; these also fail it when skipped.
HARD_STEPS = ("build", "launch", "perf", "geometry", "play", "onboarding", "shop", "esc", "devices", "menus", "phone_perf")
STEP_ORDER = ("build", "launch", "perf", "geometry", "play", "onboarding", "shop", "esc", "devices", "menus", "phone_perf", "two_player", "shots")
SOFT_STEPS = ("shots",)  # never fail the run; missing = fine
# Per-shot Config.FEATURES override ("flags": {"MergeVat3": true}). The Studio session reads ReplicatedStorage
# attribute PcwFlag_<Name> = true as the flag on (src/shared/FeatureOverride, Studio only). FLAG_NAMES mirrors
# FeatureOverride.FLAGS (selftest keeps them in sync). BOOT_FLAGS are read once when the server/client boots
# (Audio mount, Profiler.new, WeeklyEventService), so they are set in the Edit datamodel before the playtest
# and stay on for the whole run; the others are set live on the shot and cleared after it.
FLAG_NAMES = ("FountainTiers", "MergeVat3", "RainMagnet", "StealAlerts", "WeeklyEvents", "EventsBoard", "PlotSkins",
              "ServerProfiler", "Audio", "PvP")
BOOT_FLAGS = ("Audio", "ServerProfiler", "WeeklyEvents")
GIT_ENV = {"GIT_TERMINAL_PROMPT": "0", "GCM_INTERACTIVE": "never"}


class StepFail(Exception):
    """A hard failure of the current step (message goes to the report)."""


class StudioBusy(Exception):
    pass


def utc_now():
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


# ---------------------------------------------------------------------------
# Pure helpers (selftest.py)
# ---------------------------------------------------------------------------

def parse_ls_remote(text, branch):
    ref = "refs/heads/" + branch
    for line in (text or "").splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[1] == ref and re.fullmatch(r"[0-9a-f]{40}", parts[0]):
            return parts[0]
    return None


def builds_to_prune(entries, keep):
    """entries: [(path, mtime)] -> paths beyond the newest `keep`."""
    ordered = sorted(entries, key=lambda e: e[1], reverse=True)
    return [p for p, _ in ordered[keep:]]


def test_project(project, attributes=None):
    """default.project.json + Workspace $attributes DataStoreMode=Memory (test build only, never shipped)."""
    p = json.loads(json.dumps(project))
    ws = p.setdefault("tree", {}).setdefault("Workspace", {"$className": "Workspace"})
    attrs = ws.setdefault("$attributes", {})
    attrs.update(attributes or {"DataStoreMode": "Memory"})
    return p


def next_client_guess(target, samples):
    """Next client size to try so the viewport hits `target`.

    samples: [((client_w, client_h), (vp_w, vp_h))], newest last. Uses the secant slope per axis
    when two samples differ on that axis, else assumes viewport changes 1:1 with the client.
    """
    (cw, ch), (vw, vh) = samples[-1]
    guess = []
    for axis, (c, v, t) in enumerate(((cw, vw, target[0]), (ch, vh, target[1]))):
        slope = 1.0
        for (pc, pv) in reversed([(s[0][axis], s[1][axis]) for s in samples[:-1]]):
            if pc != c and pv != v:
                slope = min(3.0, max(0.33, (c - pc) / float(v - pv)))
                break
        guess.append(int(round(c + (t - v) * slope)))
    return tuple(guess)


def menu_record(m, frame=None, error=None):
    """report.menus[device][panel] from a luau/menu_measure result (None = panel not found / not opened).

    frac_* = AbsoluteSize / ViewportSize. #76 menus are content-sized cards, so a fraction below 1 is
    normal and never fails; a panel passes when it is on screen and its Close button is visible and on screen.
    """
    rec = {"frac_w": None, "frac_h": None, "on_screen": False, "close_button": False, "frame": frame}
    if error:
        rec["error"] = error
    if not m or not m.get("found"):
        rec.setdefault("error", "panel not found")
        return rec
    vw, vh = m["viewport"]
    rec["frac_w"] = round(m["size"][0] / vw, 3) if vw else None
    rec["frac_h"] = round(m["size"][1] / vh, 3) if vh else None
    rec["on_screen"] = bool(m.get("shown") and m.get("on_screen"))
    c = m.get("close") or {}
    rec["close_button"] = bool(c.get("found") and c.get("shown") and c.get("on_screen"))
    return rec


def menus_failed(menus):
    """['device/panel', ...] of every panel that is not on screen with a visible close button."""
    return ["%s/%s" % (d, p) for d, panels in menus.items() for p, r in panels.items()
            if not (r.get("on_screen") and r.get("close_button"))]


def geometry_verdict(raw, checks):
    """luau/geometry raw items -> {check: {pass, items, errors}}. Missing / unknown instances fail with a message."""
    out = {}
    for name in ("bench_faces_campfire", "shops_face_centre", "silo_centred", "plot_signs"):
        cfg, got = checks.get(name) or {}, (raw or {}).get(name) or {}
        items, errors = [dict(i) for i in got.get("items") or []], list(got.get("errors") or [])
        if not got:
            errors.append("check missing from the geometry result")
        if len(items) < cfg.get("min_items", 1):
            errors.append("only %d item(s) found, wanted >= %s" % (len(items), cfg.get("min_items", 1)))
        for it in items:
            if name == "silo_centred":
                it["pass"] = it.get("dist") is not None and it["dist"] <= cfg["max_dist"]
            elif name == "plot_signs":
                gd = it.get("dot_gate_front")
                it["pass"] = (it.get("dot_out", -1) >= cfg["min_dot"] and not it.get("mirrored", True)
                              and gd is not None and gd >= cfg["min_dot"] and bool(it.get("enabled", True)))
                if gd is None:
                    errors.append("%s: no gate front to compare" % it.get("name"))
            else:
                it["pass"] = it.get("dot", -1) >= cfg["min_dot"]
        out[name] = {"pass": bool(items) and not errors and all(i["pass"] for i in items),
                     "items": items, "errors": errors}
    return out


def phone_perf_verdict(stats, min_fps, min_slimes):
    """(ok, problems): ok = average FPS >= min_fps. Too few animating slimes is a problem but not a failure."""
    problems = []
    fps = stats.get("fps")
    ok = fps is not None and fps >= min_fps
    if not ok:
        problems.append("avg FPS %s < %s" % (None if fps is None else round(fps, 1), min_fps))
    if (stats.get("animating") or 0) < min_slimes:
        problems.append("only %s animating slimes (wanted %s)" % (stats.get("animating"), min_slimes))
    return ok, problems


SHOT_TOOL_ERROR_MAX = 4  # more shots than this whose Luau / MCP call itself failed (StepFail) = the shots step FAILS


def shot_tool_errors(results):
    """Shots whose capture could not run at all (a StepFail from a luau / MCP call, e.g. shot_camera rejected by Studio),
    as opposed to a shot that ran and found a problem. 0 in a healthy run; many = the frames are missing, not reviewed."""
    return [r.get("id") for r in results if "StepFail(" in str(r.get("error") or "")]


def luau_literal(v):
    """Placeholder value -> Luau source: number, "x, y, z" for a sequence, quoted string otherwise."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return repr(round(v, 3))
    if isinstance(v, (list, tuple)):
        return ", ".join(luau_literal(float(x)) for x in v)
    return json.dumps(str(v))  # a JSON string literal is a valid Luau string literal


def shot_camera(target, pitch_deg=35.0):
    """Server bounding box -> (eye, at): on the target's front (LookVector) side, looking down
    `pitch_deg` at the box centre from max(extent) * 1.8 + 15 studs away."""
    px, py, pz = target["pos"]
    lx, _, lz = target["look"]
    flat = math.hypot(lx, lz)
    hx, hz = (lx / flat, lz / flat) if flat > 1e-3 else (0.0, 1.0)  # looking straight up/down: any side
    dist = max(target["size"]) * 1.8 + 15
    pitch = math.radians(pitch_deg)
    across, up = math.cos(pitch) * dist, math.sin(pitch) * dist
    return (px + hx * across, py + up, pz + hz * across), (px, py, pz)


def shot_camera_from(target, mode, aim=None, dist=None, height=None, centre=(0.0, 0.0), pitch_deg=35.0):
    """Eye/at for a shots/*.json "from" entry: the eye stands `dist` studs from the target (flat) on the side
    given by `mode`, `height` up, looking at `aim` (second target's pos) or at the target.
      front   along the target's #75 front vector       look    along its raw LookVector (SurfaceGui Front)
      back    opposite its front                        centre  towards the plaza centre
      behind  opposite `aim` (over the target towards aim)
    """
    px, py, pz = target["pos"]
    if mode == "centre":
        d = (centre[0] - px, centre[1] - pz)
    elif mode == "behind" and aim:
        d = (px - aim[0], pz - aim[2])
    else:
        vx, _, vz = target["look"] if mode == "look" else target.get("front") or target["look"]
        d = (-vx, -vz) if mode == "back" else (vx, vz)
    flat = math.hypot(*d)
    hx, hz = (d[0] / flat, d[1] / flat) if flat > 1e-3 else (0.0, 1.0)
    if dist is None:
        dist = max(target["size"]) * 1.8 + 15
    if height is None:
        height = dist * math.tan(math.radians(pitch_deg))
    at = tuple(aim) if aim else (px, py, pz)
    return (px + hx * dist, py + height, pz + hz * dist), at


def shot_todo(shot):
    """TODO item number(s) of a shots/*.json entry: its "todo", else "TODO 6/13:" at the start of its note."""
    if shot.get("todo"):
        return str(shot["todo"])
    m = re.match(r"\s*TODO\s+([\d/]+)", str(shot.get("note") or ""))
    return m.group(1) if m else None


def shot_flags_error(shot):
    """None when the shot's "flags" field is absent or valid ({FlagName: true}); else why it is rejected."""
    flags = shot.get("flags")
    if flags is None:
        return None
    if not isinstance(flags, dict) or not flags:
        return "flags must be a non-empty object like {\"MergeVat3\": true}"
    bad = sorted(str(k) for k in flags if k not in FLAG_NAMES)
    if bad:
        return "unknown flag(s) %s (known: %s)" % (", ".join(bad), ", ".join(FLAG_NAMES))
    off = sorted(k for k, v in flags.items() if v is not True)
    if off:
        return "flag(s) %s must be true (a shot can only force a flag on)" % ", ".join(off)
    return None


def shot_flags(shot):
    """Sorted flag names a valid shot forces on."""
    return sorted(shot.get("flags") or {})


def boot_flags(shots):
    """Boot-time flags any shot asks for: set once in the Edit datamodel before the playtest."""
    return sorted({f for s in shots if not shot_flags_error(s) for f in shot_flags(s) if f in BOOT_FLAGS})


def viewport_error(vp, target):
    return abs(vp[0] - target[0]) + abs(vp[1] - target[1])


def overall_status(steps):
    # B6: the slide_walk shot is a HARD assertion even though the rest of "shots" is soft
    if (steps.get("shots", {}).get("detail") or {}).get("slide_walk_failed") or (steps.get("shots", {}).get("detail") or {}).get("fountain_walk_failed"):
        return "fail"
    if (steps.get("shots", {}).get("detail") or {}).get("mesh_slots_failed"):
        return "fail"
    if (steps.get("shots", {}).get("detail") or {}).get("runtime_parts_failed"):
        return "fail"
    for name, s in steps.items():
        st = s.get("status")
        if name in SOFT_STEPS:
            continue
        if st == "skip" and (s.get("detail") or {}).get("partial"):
            continue  # deliberately not selected by a partial run
        if st == "fail":
            return "fail"
        if name in HARD_STEPS and st not in ("pass", "warn"):
            return "fail"
    for name in HARD_STEPS:
        if name not in steps:
            return "fail"
    return "pass"


# ---------------------------------------------------------------------------
# Full vs partial runs (pure helpers; README "Full vs partial runs")
# ---------------------------------------------------------------------------

# Steps every partial run keeps (cheap); "devices" (menus + phone_perf, ~140 s) only when a rule asks for it.
PARTIAL_BASE_STEPS = ("build", "launch", "play", "perf", "geometry", "onboarding", "shop", "esc", "two_player", "shots")
DEVICE_STEPS = ("devices", "menus", "phone_perf")
_GLOB_CACHE = {}


def path_glob_match(path, pattern):
    """Repo-relative, forward-slash glob: `**` = any depth (also zero dirs when written `**/`), `*` = no slash, `?` = one non-slash char."""
    rx = _GLOB_CACHE.get(pattern)
    if rx is None:
        out, i = [], 0
        while i < len(pattern):
            c = pattern[i]
            if pattern.startswith("**/", i):
                out.append("(?:.*/)?")
                i += 3
                continue
            if pattern.startswith("**", i):
                out.append(".*")
                i += 2
                continue
            out.append("[^/]*" if c == "*" else "[^/]" if c == "?" else re.escape(c))
            i += 1
        rx = _GLOB_CACHE[pattern] = re.compile("".join(out) + r"\Z", re.S)
    return rx.match(path) is not None


def _expand(patterns, shot_map):
    vars_ = shot_map.get("vars") or {}
    out = []
    for p in patterns or []:
        for k, v in vars_.items():
            p = p.replace("{%s}" % k, v)
        out.append(p)
    return out


def _any_glob(path, patterns, shot_map):
    return any(path_glob_match(path, p) for p in _expand(patterns, shot_map))


def shot_selected_by(shot, rule):
    """True when a shot-map rule's id globs / kinds / keys select this shot (ids match case-insensitively)."""
    sid = str(shot.get("id", "")).lower()
    return (any(fnmatch.fnmatchcase(sid, g.lower()) for g in rule.get("shots") or [])
            or shot.get("kind") in (rule.get("kinds") or [])
            or any(k in shot for k in rule.get("keys") or []))


def plan_run(changed_paths, shots, shot_map, max_files):
    """Decides FULL vs PARTIAL for a set of changed paths. Pure. Returns
    {run_kind, reason, shots (ids in shot order), steps, changed, full_paths, unknown_paths}."""
    paths = sorted({re.sub(r"^\./", "", str(p).replace("\\", "/")) for p in changed_paths if str(p).strip()})
    plan = {"run_kind": "partial", "reason": "", "shots": [], "steps": [], "changed": len(paths),
            "full_paths": [], "unknown_paths": []}
    picked, device_wanted, hit_rules = set(), False, []
    rules = shot_map.get("rules") or []
    for path in paths:
        if _any_glob(path, shot_map.get("full"), shot_map):
            plan["full_paths"].append(path)
        elif _any_glob(path, shot_map.get("ignore"), shot_map):
            continue
        else:
            rule = next((r for r in rules if _any_glob(path, r.get("paths"), shot_map)), None)
            if rule is None:
                plan["unknown_paths"].append(path)
                continue
            if rule["name"] not in hit_rules:
                hit_rules.append(rule["name"])
            device_wanted = device_wanted or "devices" in (rule.get("steps") or [])
            picked.update(s["id"] for s in shots if shot_selected_by(s, rule))
    if len(paths) > max_files:
        plan["run_kind"], plan["reason"] = "full", "%d changed files > %d" % (len(paths), max_files)
    elif plan["full_paths"]:
        plan["run_kind"], plan["reason"] = "full", "full-run path: " + ", ".join(plan["full_paths"][:3])
    elif plan["unknown_paths"]:
        plan["run_kind"], plan["reason"] = "full", "unknown path: " + ", ".join(plan["unknown_paths"][:3])
    if plan["run_kind"] == "full":
        return plan
    always = set(shot_map.get("smoke") or [])
    keys = shot_map.get("always_keys") or []
    always.update(s["id"] for s in shots if any(k in s for k in keys))
    chosen = always | picked
    plan["shots"] = [s["id"] for s in shots if s["id"] in chosen]
    plan["steps"] = list(PARTIAL_BASE_STEPS) + (["devices"] if device_wanted else [])
    plan["reason"] = ("rules: " + ", ".join(hit_rules)) if hit_rules else "no run-relevant files changed"
    return plan


def due_schedule_slot(now_ts, schedule, done_slot, grace_s=10800):
    """Key ("YYYY-MM-DD HH:MM", local time) of the most recent schedule slot <= now (today or yesterday),
    or None when there is no schedule, that slot is already done, or it was missed by more than grace_s."""
    best = None
    for hhmm in schedule or []:
        try:
            h, m = (int(x) for x in str(hhmm).split(":"))
        except ValueError:
            continue
        for back in (0, 1):
            d = datetime.datetime.fromtimestamp(now_ts) - datetime.timedelta(days=back)
            slot = d.replace(hour=h, minute=m, second=0, microsecond=0)
            if slot.timestamp() <= now_ts and (best is None or slot > best):
                best = slot
    if best is None or now_ts - best.timestamp() > grace_s:
        return None
    key = best.strftime("%Y-%m-%d %H:%M")
    return None if key == done_slot else key


def choose_work(tip, last_sha, last_at, requests, full_done, order, now, cfg, tip_seen_at, sched_slot=None):
    """What the loop does next: (kind|None, sha|None, reason). kind is "full" or "partial".
    requests = shas publish.sh asked a full run for; order = main first-parent shas, newest first.
    sched_slot = the due schedule slot key (see due_schedule_slot) or None."""
    for sha in list(order)[:cfg["full_request_depth"]]:
        if sha in requests and sha not in full_done:
            return "full", sha, "candidate request"
    if sched_slot and tip not in full_done:
        return "full", tip, "scheduled full " + sched_slot
    if tip != last_sha:
        if not cfg["partial_runs"]:
            return "full", tip, "new tip (partial runs off)"
        if now - tip_seen_at < cfg["candidate_wait_s"]:
            return None, None, "waiting for candidate signal"
        return "partial", tip, "new tip"
    return None, None, "nothing to do"


def frame_title_ok(title, needles):
    low = (title or "").lower()
    return "roblox studio" in low or any(n and n.lower() in low for n in needles)


# ---------------------------------------------------------------------------
# Config, paths, logging
# ---------------------------------------------------------------------------

class Paths:
    def __init__(self, home):
        self.home = home
        self.repo = os.path.join(home, "repo")
        self.bin = os.path.join(home, "bin")
        self.builds = os.path.join(home, "builds")
        self.out = os.path.join(home, "out")
        self.logs = os.path.join(home, "logs")
        self.state = os.path.join(home, "state")
        self.reports = os.path.join(home, "reports")
        self.perf_reports = os.path.join(home, "perf-reports")  # separate clone for `perf` (the loop uses reports\)
        for d in (self.builds, self.out, self.logs, self.state):
            os.makedirs(d, exist_ok=True)

    def st(self, name):
        return os.path.join(self.state, name)


def load_config(paths):
    cfg = dict(DEFAULTS)
    f = os.path.join(paths.home, "config.json")
    if os.path.isfile(f):
        with open(f, encoding="utf-8") as fh:
            cfg.update(json.load(fh))
    return cfg


def setup_logging(paths, verbose):
    root = logging.getLogger()
    root.setLevel(logging.DEBUG)
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s")
    fh = logging.handlers.RotatingFileHandler(
        os.path.join(paths.logs, "watcher.log"), maxBytes=5_000_000, backupCount=5, encoding="utf-8")
    fh.setFormatter(fmt)
    fh.setLevel(logging.DEBUG)
    root.addHandler(fh)
    if sys.stderr is not None:  # pythonw has no console
        sh = logging.StreamHandler(sys.stderr)
        sh.setFormatter(fmt)
        sh.setLevel(logging.DEBUG if verbose else logging.INFO)
        root.addHandler(sh)


def read_json(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def data_path(repo, rel):
    """(path, src) of a watcher data file: the tested repo checkout's tools/pipeline/pc-watcher/<rel> when it
    exists (the installed app\\ copy goes stale), else the app copy next to this file. src is "repo" or "app"."""
    if repo:
        p = os.path.join(repo, "tools", "pipeline", "pc-watcher", *rel.split("/"))
        if os.path.exists(p):
            return p, "repo"
    return os.path.join(HERE, *rel.split("/")), "app"


BUDGET_KEYS = (("runtime_parts", "fail", "runtime_part_budget"), ("runtime_parts", "warn", "runtime_part_warn"),
               ("unique_meshes", "fail", "unique_mesh_budget"), ("world_triangles", "fail", "world_triangle_budget"),
               ("mesh_parts", "warn", "mesh_slot_budget"))


def apply_budgets(cfg, repo):
    """Overlay budgets.json (data_path: repo checkout first, app copy fallback) on cfg's budget keys, unless
    config.json set the key. Missing or broken file: DEFAULTS stay. Returns the source for the log/report."""
    path, src = data_path(repo, "budgets.json")
    data = read_json(path, None)
    if not isinstance(data, dict):
        log.warning("budgets.json missing or unreadable (%s): using DEFAULTS", path)
        return "defaults"
    for group, level, key in BUDGET_KEYS:
        v = (data.get(group) or {}).get(level) if isinstance(data.get(group), dict) else None
        if isinstance(v, int) and not isinstance(v, bool) and cfg.get(key) == DEFAULTS[key]:
            cfg[key] = v
    return src


def load_shots(folder=None, repo=None):
    """(shots, notes) from shots/*.json sorted by filename. A file holds one entry object or a list of
    them; unreadable files are skipped with a note. shots is None if the folder is missing or empty."""
    folder = folder or data_path(repo, "shots")[0]
    shots, notes = [], []
    for path in sorted(glob.glob(os.path.join(folder, "*.json")), key=lambda p: (int(re.match(r"\d+", os.path.basename(p)).group()) if re.match(r"\d+", os.path.basename(p)) else 10**9, os.path.basename(p))):
        name = os.path.basename(path)
        data = read_json(path, None)
        if isinstance(data, dict):
            data = [data]
        if not isinstance(data, list) or not all(isinstance(s, dict) for s in data):
            notes.append("skipped unreadable shot file " + name)
            continue
        shots.extend(data)
    return (shots or None), notes


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=False)
        f.write("\n")
    os.replace(tmp, path)


class Lock:
    """Exclusive lock file holding our pid; a lock whose pid is gone (or older than max_age) is stale.
    max_age only guards against pid reuse after a crash: it must stay well above the longest real run (a full run with
    bug probes took ~26 min on Oct 17; the old 1800 s let a waiting perf run steal a live loop lock)."""

    LOCK_MAX_AGE_S = 7200

    def __init__(self, path, max_age=LOCK_MAX_AGE_S):
        self.path, self.max_age, self.held = path, max_age, False

    def acquire(self):
        for _ in range(2):
            try:
                fd = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            except FileExistsError:
                info = read_json(self.path, {}) or {}
                pid, at = info.get("pid"), info.get("at", 0)
                alive = pid and (win32.pid_alive(pid) if os.name == "nt" else _posix_alive(pid))
                if alive and time.time() - at < self.max_age:
                    return False
                log.warning("removing stale lock %s (%s)", self.path, info)
                try:
                    os.remove(self.path)
                except OSError:
                    pass
                continue
            with os.fdopen(fd, "w") as f:
                json.dump({"pid": os.getpid(), "at": time.time()}, f)
            self.held = True
            return True
        return False

    def release(self):
        if self.held:
            try:
                os.remove(self.path)
            except OSError:
                pass
            self.held = False


def _posix_alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except Exception:
        return False


# ---------------------------------------------------------------------------
# Run context
# ---------------------------------------------------------------------------

class Run:
    run_kind = "full"
    run_plan = None
    shot_filter = None

    def __init__(self, paths, cfg, sha, dry=False, kind="full"):
        self.paths, self.cfg, self.sha, self.dry = paths, cfg, sha, dry
        self.t0 = time.time()
        self.notes = []
        self.steps = {}
        self.perf = {"mesh_slots": None, "unique_meshes": None, "budget": cfg["mesh_slot_budget"],
                     "runtime_parts": None, "runtime_part_budget": cfg["runtime_part_budget"],
                     "frame_time_ms": None, "memory_mb": None}
        self.frames = []
        self.extra = {}
        self.studio_dir = None
        self.studio_version = None
        self.mcp = None
        self.studio_id = None
        self.hwnd = None
        self.rbxl = os.path.join(paths.builds, "%s.rbxl" % sha) if sha else None
        # perf runs (run_kind "perf") write to out/perf/<sha>/, never into out/<sha>/ of the loop's runs
        self.outdir = os.path.join(paths.out, "dry-run" if dry else "", "perf" if kind == "perf" else "", sha) if sha else None
        self.playing = False
        self.hdesk = None  # CreateDesktopW handle of the Studio desktop (closed in close())
        self.worker = None  # win32.DesktopWorker: window calls run on its desktop thread
        self.frame_seq = 0
        self.our_pids = set()  # every Studio pid this run started (focus guard)
        self.fg_start = None  # (hwnd, pid) of the foreground window when the run began
        self.focus_stolen = []  # "FOCUS STOLEN at step X"
        self.run_kind = kind
        self.run_plan = None  # report run_plan (see full_run)
        self.shot_filter = None  # partial run: set of shot ids to capture (None = all)
        if self.outdir:
            os.makedirs(self.outdir, exist_ok=True)

    # --- budget ---
    def remaining(self):
        return self.cfg["run_budget_s"] - (time.time() - self.t0)

    def note(self, msg):
        log.info("note: %s", msg)
        self.notes.append(msg)

    # --- background guards ---
    def record_foreground(self):
        if self.dry or os.name != "nt":
            return
        try:
            self.fg_start = win32.foreground_pid()
        except Exception as e:
            log.warning("foreground: %r", e)

    def check_focus(self, where):
        """Notes 'FOCUS STOLEN at step X' when a Studio we started is the foreground window.
        Only looks: nothing ever hands the focus back (that would be one more focus change)."""
        if self.dry or os.name != "nt":
            return False
        try:
            hwnd, pid = win32.foreground_pid()
        except Exception as e:
            log.warning("foreground: %r", e)
            return False
        if not win32.focus_stolen(pid, self.our_pids | tracked_pids(self.paths)):
            return False
        msg = "FOCUS STOLEN at step %s" % where
        if msg not in self.focus_stolen:
            self.focus_stolen.append(msg)
            self.note("%s (foreground hwnd %s, Studio pid %s)" % (msg, hwnd, pid))
        return True

    def add_frame(self, fid, file=None, status="captured", **extra):
        """One report.frames entry: {id, file, status: captured|missing|blank, todo, ...}."""
        rec = dict({"id": fid, "file": file, "status": status, "todo": None}, **extra)
        self.frames.append(rec)
        return rec

    # --- shell ---
    def cmd(self, args, cwd=None, timeout=120, check=True, env=None):
        log.info("$ %s", " ".join(str(a) for a in args))
        if self.dry:
            return subprocess.CompletedProcess(args, 0, "", "")
        e = dict(os.environ)
        e.update(GIT_ENV)
        e.update(env or {})
        r = subprocess.run(args, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=e,
                           creationflags=win32.NO_WINDOW if os.name == "nt" else 0)
        if r.returncode != 0:
            log.warning("rc=%s stdout=%s stderr=%s", r.returncode, r.stdout[-800:], r.stderr[-1500:])
            if check:
                raise StepFail("%s failed (rc %s): %s" % (os.path.basename(str(args[0])), r.returncode,
                                                          (r.stderr or r.stdout).strip()[-300:]))
        return r

    def git(self, *args, cwd=None, timeout=180, check=True):
        return self.cmd(["git", "-C", cwd or self.paths.repo] + list(args), timeout=timeout, check=check)

    # --- Studio / MCP ---
    def studio_exe(self):
        if not self.studio_dir:
            self.studio_dir = mcp_client.find_studio_dir()
        if not self.studio_dir:
            raise StepFail("no Roblox Studio under %LOCALAPPDATA%\\Roblox\\Versions")
        return os.path.join(self.studio_dir, "RobloxStudioBeta.exe")

    def session(self):
        if self.mcp and self.mcp.alive():
            return self.mcp
        if self.mcp is not None:
            self.note("StudioMCP process died; started a new session")
        exe = os.path.join(os.path.dirname(self.studio_exe()), "StudioMCP.exe")
        if not os.path.isfile(exe):
            raise StepFail("StudioMCP.exe missing in %s" % self.studio_dir)
        self.mcp = mcp_client.McpSession(exe, client_name="pc-watcher-" + VERSION).start()
        schema_file = os.path.join(self.paths.state, "mcp-tools.json")
        write_json(schema_file, {"server": self.mcp.server_info, "tools": self.mcp.schemas})
        return self.mcp

    def luau(self, name, datamodel="Edit", timeout=60, /, **subs):
        with open(os.path.join(HERE, "luau", name + ".luau"), encoding="utf-8") as f:
            body = f.read()
        for k, v in subs.items():
            body = body.replace("%%" + k.upper() + "%%", luau_literal(v))
        ok, data, _ = self.session().luau(self.studio_id, body, datamodel, timeout=timeout)
        log.debug("luau %s/%s ok=%s %s", name, datamodel, ok, json.dumps(data)[:600])
        return ok, data

    def need_luau(self, name, datamodel="Edit", timeout=60, /, **subs):
        ok, data = self.luau(name, datamodel, timeout, **subs)
        if not ok:
            raise StepFail("%s (%s): %s" % (name, datamodel, str(data)[:300]))
        return data

    def tool(self, name, timeout=60, **args):
        args.setdefault("studio_id", self.studio_id)
        return self.session().call(name, args, timeout=timeout)

    # --- persisted context for `step` subcommands ---
    def save_current(self):
        write_json(self.paths.st("current.json"), {
            "sha": self.sha, "rbxl": self.rbxl, "studio_id": self.studio_id, "hwnd": self.hwnd,
            "studio_dir": self.studio_dir, "studio_version": self.studio_version, "playing": self.playing,
        })

    def load_current(self):
        cur = read_json(self.paths.st("current.json"), {}) or {}
        if not self.sha and cur.get("sha"):
            self.sha = cur["sha"]
            self.rbxl = os.path.join(self.paths.builds, "%s.rbxl" % self.sha)
            self.outdir = os.path.join(self.paths.out, "dry-run" if self.dry else "", self.sha)
            os.makedirs(self.outdir, exist_ok=True)
        if cur.get("sha") == self.sha:
            self.rbxl = cur.get("rbxl") or self.rbxl
            self.studio_id = cur.get("studio_id")
            self.hwnd = cur.get("hwnd")
            self.studio_dir = cur.get("studio_dir")
            self.studio_version = cur.get("studio_version")
            self.playing = bool(cur.get("playing"))
        return cur

    def desktop(self):
        """The Studio desktop's worker thread (creates the desktop on first use)."""
        if self.worker is None:
            self.hdesk = win32.create_desktop()
            self.worker = win32.DesktopWorker()
        return self.worker

    def on_desktop(self, fn, *args):
        """Runs a window call (win32.client_size, set_client_size, ...) on the desktop thread."""
        return self.desktop().call(fn, *args)

    def close(self):
        if self.mcp:
            self.mcp.close()
            self.mcp = None
        if self.worker:
            self.worker.close()
            self.worker = None
        if self.hdesk:
            win32.close_desktop(self.hdesk)
            self.hdesk = None


def tracked_pids(paths):
    return set(read_json(paths.st("pids.json"), []) or [])


def save_pids(paths, pids):
    write_json(paths.st("pids.json"), sorted(int(p) for p in pids))


# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

def step_build(run):
    p, cfg = run.paths, run.cfg
    if not os.path.isdir(os.path.join(p.repo, ".git")) and not run.dry:
        raise StepFail("repo clone missing: %s (run install.ps1)" % p.repo)
    run.git("fetch", "--prune", cfg["remote"], timeout=300)
    run.git("checkout", "--detach", "--force", run.sha)
    run.git("clean", "-ffdx", timeout=120)
    if not run.dry:
        head = run.git("rev-parse", "HEAD").stdout.strip()
        if head != run.sha:
            raise StepFail("checkout gave %s, wanted %s" % (head, run.sha))
    game = os.path.join(p.repo, cfg["game_dir"].replace("/", os.sep))
    # world/*.rbxmx are tracked; scripts/gen-world and the untracked src/visuals/static output are
    # not in the Rojo tree, so a plain rojo build is the whole place.
    tmp = os.path.join(game, ".pcwatcher.project.json")
    if not run.dry:
        project = read_json(os.path.join(game, cfg["project"]))
        if not project:
            raise StepFail("cannot read %s/%s" % (cfg["game_dir"], cfg["project"]))
        write_json(tmp, test_project(project))
    rojo = os.path.join(p.bin, "rojo.exe")
    if not os.path.isfile(rojo):
        rojo = shutil.which("rojo") or rojo
    t0 = time.time()
    try:
        run.cmd([rojo, "build", tmp, "-o", run.rbxl], cwd=game, timeout=300)
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    size = os.path.getsize(run.rbxl) if os.path.exists(run.rbxl) else 0
    if not run.dry and size < 10_000:
        raise StepFail("build output missing or tiny (%d bytes)" % size)
    entries = [(os.path.join(p.builds, f), os.path.getmtime(os.path.join(p.builds, f)))
               for f in os.listdir(p.builds) if f.endswith(".rbxl")]
    for old in builds_to_prune(entries, cfg["keep_builds"]):
        log.info("prune build %s", old)
        os.remove(old)
    return "pass", {"rbxl": run.rbxl, "size_mb": round(size / 1e6, 2), "rojo_s": round(time.time() - t0, 1),
                    "datastore_mode": "Memory (Workspace $attributes, test build only)"}


def studio_version_of(exe_dir):
    exe = os.path.join(exe_dir, "RobloxStudioBeta.exe")
    try:
        r = subprocess.run(
            ["powershell", "-NoProfile", "-NonInteractive", "-Command", "(Get-Item '%s').VersionInfo.ProductVersion" % exe],
            capture_output=True, text=True, timeout=20, creationflags=win32.NO_WINDOW)
        v = r.stdout.strip()
        if v:
            return "%s (%s)" % (v, os.path.basename(exe_dir))
    except Exception:
        pass
    return os.path.basename(exe_dir)


def kill_strays(run):
    """Kills Studio processes an earlier watcher run started; refuses to touch anyone else's."""
    mine = tracked_pids(run.paths)
    killed = []
    for pid in sorted(mine):
        if win32.pid_alive(pid):
            win32.kill_pid(pid)
            killed.append(pid)
    save_pids(run.paths, set())
    if killed:
        run.note("killed stray watcher Studio pids %s" % killed)
        time.sleep(2)
    foreign = [pid for pid in win32.list_pids() if pid not in mine]
    busy = []
    for pid in foreign:
        for w in win32.top_windows([pid]):
            if w["visible"] and win32.title_has_place(w["title"]):
                busy.append("%s (pid %s)" % (w["title"], pid))
    if busy:
        raise StudioBusy("studio busy: user Studio with a place open: " + "; ".join(busy))
    if foreign:
        run.note("user Studio without a place open (pids %s) left alone" % foreign)


def find_our_studio(run, mcp):
    studios, raw = mcp.list_studios()
    stem = os.path.splitext(os.path.basename(run.rbxl))[0]
    return mcp_client.pick_studio(studios, [os.path.basename(run.rbxl), stem, run.sha[:12]]), studios, raw


def step_launch(run):
    if run.dry:
        return "skip", {"dry_run": True}
    exe = run.studio_exe()
    run.studio_version = studio_version_of(run.studio_dir)
    if not os.path.isfile(run.rbxl):
        raise StepFail("build missing: %s" % run.rbxl)
    kill_strays(run)
    run.desktop()
    proc = win32.launch_on_desktop([exe, run.rbxl], cwd=run.studio_dir)  # CreateProcessW, lpDesktop pcw-studio
    ours = {proc.pid}
    run.our_pids |= ours

    def grow(pids):
        # Only processes descending from the one we started (never a Studio the user opens meanwhile).
        return win32.descendants(win32.process_table(), pids) & (set(win32.list_pids()) | pids)

    save_pids(run.paths, ours)
    log.info("launched Studio pid %s on desktop %s: %s", proc.pid, win32.DESKTOP_NAME, run.rbxl)
    mcp = run.session()
    deadline = time.time() + run.cfg["launch_timeout_s"]
    found, last = None, None
    while time.time() < deadline:
        ours = grow(ours)
        run.our_pids |= ours
        save_pids(run.paths, ours)
        find_window(run, ours)
        found, studios, raw = find_our_studio(run, mcp)
        last = raw.brief(400)
        if found:
            state = run.tool("get_studio_state", studio_id=found["id"], timeout=30)
            if state.ok:
                break
            found = None
        time.sleep(3)
    if not found:
        raise StepFail("Studio not listed by MCP within %ss (last list: %s)" % (run.cfg["launch_timeout_s"], last))
    run.studio_id = found["id"]
    win = None
    for _ in range(20):
        ours = grow(ours)
        run.our_pids |= ours
        win = find_window(run, ours)
        if win:
            break
        time.sleep(1)
    save_pids(run.paths, ours)
    run.hwnd = win["hwnd"] if win else None
    if not win:
        run.note("Studio main window not found (device sizes / frames will be skipped)")
    run.check_focus("launch")
    run.save_current()
    prepare_edit(run)
    detail = {"studio_id": run.studio_id, "pids": sorted(ours), "window": win and win["title"],
              "seconds_to_ready": round(run.cfg["launch_timeout_s"] - (deadline - time.time()), 1)}
    # Edit-time frame from MCP screen_capture (soft).
    try:
        shot = run.tool("screen_capture", timeout=60, capture_id="pcw-edit")
        img = shot.image_bytes()
        if img:
            name = save_mcp_image(run, img, "edit")
            if name:
                detail["edit_frame"] = name
        else:
            run.note("screen_capture returned no image (%s)" % shot.brief(120))
    except Exception as e:
        run.note("screen_capture failed: %r" % (e,))
    return "pass", detail


def find_window(run, pids):
    """The largest top-level window of `pids` on the Studio desktop (EnumDesktopWindows on the worker
    thread), or None. No move, no activation."""
    try:
        win = run.desktop().main_window(pids)
        if not win:
            return None
        for p in pids:
            win32.disable_power_throttling(p)
        return win
    except Exception as e:
        log.warning("find window: %r", e)
        return None


def save_mcp_image(run, img, device):
    mime, data = img
    ext = "jpg" if "jpeg" in mime or "jpg" in mime else "png"
    name = "%s-%s.%s" % (run.sha, device, ext)
    path = os.path.join(run.outdir, name)
    with open(path, "wb") as f:
        f.write(data)
    if ext == "png":
        try:
            w, h, mode, px = imaging.decode_png(data)
            if imaging.is_blank(imaging.frame_stats(w, h, px, mode)):
                run.note("%s frame is blank, not kept" % device)
                os.replace(path, path.replace(".png", "-rejected.png"))
                run.add_frame(device, status="blank", kind="edit")
                return None
        except ValueError as e:
            log.info("cannot check %s: %s", name, e)
    run.add_frame(device, name, kind="edit")
    return name


def prepare_edit(run):
    """Edit datamodel: counts (info) and DataStoreMode=Memory before anything plays."""
    deadline = time.time() + 40  # the place may still be loading right after MCP lists the studio
    while True:
        ok, d = run.luau("perf_edit", "Edit", timeout=30)
        if ok or time.time() > deadline:
            break
        time.sleep(3)
    if not ok:
        raise StepFail("Edit execute_luau failed: %s" % str(d)[:300])
    run.extra["edit_counts"] = d
    try:
        shots, _ = load_shots(repo=run.paths.repo)
        boot = boot_flags(shots or [])
        if boot:
            run.extra["boot_flags"] = run.need_luau("flag_set", "Edit", timeout=30, names=",".join(boot), on=True)
    except StepFail:
        raise
    except Exception as e:
        run.note("boot flags not set: %r" % (e,))
    if d.get("datastore_mode") != "Memory":
        raise StepFail("could not put the session on DataStoreMode=Memory")
    if d.get("datastore_mode_before") != "Memory":
        run.note("build lacked DataStoreMode=Memory; set it in the Edit session (not saved)")
    return d


def step_perf(run):
    """Mesh slots in the Server datamodel once MeshSwap has settled (Edit has none: see perf_server.luau)."""
    if run.dry:
        return "skip", {"dry_run": True}
    budgets_src = apply_budgets(run.cfg, run.paths.repo)
    budget = run.cfg["mesh_slot_budget"]
    deadline, counts, d = time.time() + 45, [], None
    while time.time() < deadline:
        d = run.need_luau("perf_server", "Server", timeout=30)
        counts.append(d.get("mesh_slots") or 0)
        if len(counts) >= 3 and counts[-1] == counts[-2] == counts[-3] and counts[-1] > 0:
            break
        time.sleep(3)
    settled = len(counts) >= 3 and counts[-1] == counts[-2] == counts[-3]
    run.perf.update({"mesh_slots": d.get("mesh_slots"), "unique_meshes": d.get("unique_meshes"),
                     "parts": d.get("parts"), "runtime_parts": d.get("runtime_parts"),
                     "runtime_parts_transient": d.get("runtime_parts_transient"), "triangles": None})
    part_budget, part_warn, mesh_budget = run.cfg["runtime_part_budget"], run.cfg["runtime_part_warn"], run.cfg["unique_mesh_budget"]
    run.perf.update({"budget": budget, "runtime_part_budget": part_budget, "runtime_part_warn": part_warn,
                     "unique_mesh_budget": mesh_budget, "world_triangle_budget": run.cfg["world_triangle_budget"]})
    detail = dict(d, budget=budget, samples=counts, settled=settled, edit=run.extra.get("edit_counts"), budgets_src=budgets_src,
                  triangles="not available from Luau (pr-gate budget.sh counts FBX triangles)")
    if not settled:
        run.note("mesh count still changing after 45 s: %s" % counts[-4:])
    # an absent/None key is unknown (old probes have no unique_meshes), never a failure
    parts, uniq, warnings = d.get("runtime_parts"), d.get("unique_meshes"), []
    if parts is not None and parts > part_budget:
        return "fail", dict(detail, runtime_part_budget=part_budget,
                            error="runtime parts %s > budget %s" % (parts, part_budget))
    if uniq is not None and uniq > mesh_budget:
        return "fail", dict(detail, unique_mesh_budget=mesh_budget, error="unique meshes %s > budget %s" % (uniq, mesh_budget))
    if not d.get("mesh_slots"):
        return "fail", dict(detail, error="no MeshParts in the play world (MeshSwap did not run?)")
    if parts is not None and parts > part_warn:
        warnings.append("runtime parts %s > warn %s (fail above %s)" % (parts, part_warn, part_budget))
    if (d.get("mesh_slots") or 0) > budget:
        warnings.append("MeshParts %s > soft budget %s" % (d.get("mesh_slots"), budget))
    for w in warnings:
        run.note("perf warning: " + w)
    if warnings:
        detail["warnings"] = warnings
    return "pass", detail


def step_geometry(run):
    """Facing / centring numbers (checks.json, luau/geometry) for #75; report.geometry = {check: {pass, items}}."""
    if run.dry:
        return "skip", {"dry_run": True}
    path, checks_src = data_path(run.paths.repo, "checks.json")
    checks = read_json(path, None)
    if not isinstance(checks, dict):
        raise StepFail("checks.json missing or unreadable")
    verdict = {}
    for attempt in range(3):  # PlotSigns / MeshSwap may still be finishing right after play starts
        raw = run.need_luau("geometry", "Server", timeout=30, checks=json.dumps(checks, separators=(",", ":")))
        verdict = geometry_verdict(raw, checks)
        if all(v["pass"] for v in verdict.values()):
            break
        time.sleep(4)
    run.extra["geometry"] = verdict
    bad = {k: (v["errors"] or [i.get("name") for i in v["items"] if not i["pass"]]) for k, v in verdict.items() if not v["pass"]}
    if bad:
        return "fail", {"error": "geometry failed: %s" % json.dumps(bad)[:400], "failed": sorted(bad), "checks_src": checks_src}
    return "pass", {"checks": {k: len(v["items"]) for k, v in verdict.items()}, "checks_src": checks_src}


def wait_client(run, timeout):
    """Client up: LocalPlayer + character + SlimeUI + a TutorialStepId (the server sent State).
    After 30 s, GUI + character alone are accepted (a profile without a tutorial step)."""
    t0 = time.time()
    deadline, last = t0 + timeout, None
    while time.time() < deadline:
        ok, d = run.luau("client_ready", "Client", timeout=20)
        if ok and (d.get("ready") or (time.time() - t0 > 30 and d.get("has_gui") and d.get("has_character"))):
            return d
        last = d
        time.sleep(2)
    raise StepFail("Client not ready within %ss: %s" % (timeout, str(last)[:200]))


def start_play(run):
    r = run.tool("start_stop_play", is_start=True, timeout=60)
    if not r.ok:
        raise StepFail("start_stop_play(true): %s" % r.brief())
    run.playing = True
    run.save_current()
    return wait_client(run, run.cfg["client_timeout_s"])


def stop_play(run):
    if not run.studio_id:
        return
    r = run.tool("start_stop_play", is_start=False, timeout=60)
    run.playing = False
    run.save_current()
    if not r.ok:
        log.warning("stop play: %s", r.brief())
    time.sleep(3)


def step_play(run):
    if run.dry:
        return "skip", {"dry_run": True}
    t0 = time.time()
    ready = start_play(run)
    play_t0 = time.time()
    secs = run.cfg["stats_seconds"]
    sample = lambda: {k: _r(v) for k, v in run.need_luau("client_stats", "Client", timeout=secs + 40, seconds=secs).items()}
    boot = sample()  # right after the client is up: overlaps the BorderTerrain voxel generation
    settled, settle = None, None
    if run.run_kind != "full":
        run.note("play fps: partial run, no settled sample (boot figure only)")
    else:
        try:
            settle = perf_terrain_wait(run, play_t0, run.cfg["play_bt_max_s"], run.cfg["play_settle_s"])
            if settle["bt_set"]:
                settled = sample()
            else:
                run.note("play fps: BorderTerrain not set within %ss, boot figure used" % run.cfg["play_bt_max_s"])
        except Exception as e:  # StepFail included: the settled part never fails the step
            run.note("play fps: settled sample failed (%s), boot figure used" % (str(e)[:150] or repr(e)))
            settled = None
    chosen = settled or boot
    run.perf["frame_time_ms"] = chosen.get("frame_time_ms")
    run.perf["memory_mb"] = chosen.get("memory_mb")
    run.perf["play"] = chosen
    run.perf["play_boot"], run.perf["play_settled"], run.perf["play_settle"] = boot, settled, settle
    if ready.get("store_status") not in (None, "Memory", "Unavailable"):
        run.note("DataStoreStatus in play = %s (expected Memory)" % ready.get("store_status"))
    run.note("frame time is Studio play-mode on the PC (window may be throttled when unfocused); "
             "play fps %s (boot %s, taken during BorderTerrain generation)" % (
                 "%s settled" % chosen.get("fps") if settled else "%s boot only" % boot.get("fps"), boot.get("fps")))
    return "pass", {"client": ready, "seconds_to_client": round(time.time() - t0, 1), "stats": chosen, "stats_boot": boot,
                    "stats_settled": settled, "settle": settle, "fps_source": "settled" if settled else "boot"}


def _r(v):
    return round(v, 2) if isinstance(v, float) else v


def ui_probe(run):
    return run.need_luau("ui_probe", "Client", timeout=30)


def step_onboarding(run):
    if run.dry:
        return "skip", {"dry_run": True}
    before = ui_probe(run)
    detail = {"step_id": before.get("step_id"), "counter": before.get("tutorial_counter"),
              "title": before.get("tutorial_title"), "card_visible": before.get("tutorial_visible")}
    if not before.get("tutorial_visible"):
        return "fail", dict(detail, error="tutorial card not shown for a fresh profile")
    # No MCP mouse input (it moves the real OS cursor): hide through the in-engine hook / Visible.
    hidden, via = set_visible(run, "TutorialOverlay", False)
    detail.update(hide_method=via, card_visible_after_hide=not hidden)
    if not hidden:
        return "fail", dict(detail, error="could not hide the tutorial card in-engine")
    return "pass", detail


def set_visible(run, name, show):
    """luau/panel_visible on SlimeUI.<name>. Returns (ends in the wanted state, method)."""
    ok, d = run.luau("panel_visible", "Client", timeout=15, panel=name, show=show)
    time.sleep(0.4)
    p = ui_probe(run)
    via = d.get("via", "visible_fallback") if ok and isinstance(d, dict) else "error: %s" % str(d)[:120]
    if name == "TutorialOverlay":
        return bool(p.get("tutorial_visible")) == show, via
    return (name in (p.get("open_panels") or [])) == show, via


def step_shop(run):
    if run.dry:
        return "skip", {"dry_run": True}
    p = ui_probe(run)
    detail = {"open_before": p.get("shop_open"), "inset": p.get("inset"), "viewport": p.get("viewport")}
    if p.get("shop_open"):
        return "fail", dict(detail, error="shop already open before opening it")
    # No input injection at all: VirtualInputManager is not allowed in execute_luau (lacking capability
    # RobloxScript) and StudioMCP user_mouse_input moves the real OS cursor.
    opened, via = set_visible(run, "ShopPanel", True)
    methods = {"open": via, "virtual_input_manager": "not tried: lacking capability RobloxScript in execute_luau",
               "mcp_mouse": "never used: moves the OS cursor"}
    run.extra["input_methods"] = methods
    p = ui_probe(run)
    detail.update(methods=methods, open_method=via, open_after=p.get("shop_open"), open_panels=p.get("open_panels"))
    if not p.get("shop_open"):
        return "fail", dict(detail, error="PcwOpen hook / Visible did not open the shop")
    if via != "pcw_open_hook":
        return "warn", dict(detail, why="shop opened with Visible=true, not the PcwOpen hook (menu state not open)")
    return "pass", detail


def cas_close(run):
    """Esc without input: the Studio-only SlimeUI PcwPress='Escape' hook runs the game's CloseMenu action
    handler (the one the CAS binding uses). Tests the close logic, not real key routing."""
    ok, d = run.luau("cas_close", "Client", timeout=15)
    time.sleep(0.8)
    info = {"method": "pcw_press_hook"}
    if ok and isinstance(d, dict):
        info.update(called=d.get("called"), error=d.get("error"), bound=d.get("bound"), result=d.get("result"))
    else:
        info.update(called=False, error=str(d)[:200])
    return bool(info["called"]), info


def step_esc(run):
    if run.dry:
        return "skip", {"dry_run": True}
    p = ui_probe(run)
    if not p.get("shop_open"):
        return "skip", {"reason": "shop not open"}
    methods = run.extra.setdefault("input_methods", {})
    called, info = cas_close(run)
    after = ui_probe(run)
    detail = {"key": info, "method": "pcw_press_hook", "tests": "close logic, not real key routing",
              "open_after": after.get("shop_open"),
              "open_panels": after.get("open_panels")}
    methods["esc"] = "pcw_press_hook (close logic, not real key routing): " + ("closed" if called and not after.get("shop_open") else
                                              ("no effect" if called else "hook failed: %s" % info.get("error")))
    if not called:
        close_panel(run, "ShopPanel")  # tidy up for the next steps
        return "fail", dict(detail, error="PcwPress hook failed: %s" % info.get("error"))
    if after.get("shop_open"):
        close_panel(run, "ShopPanel")
        return "fail", dict(detail, error="CloseMenu action (PcwPress hook) did not close the shop")
    return "pass", detail


def converge_viewport(run, hwnd, target):
    """Resizes the Studio window until the play viewport is `target` (or as close as Studio allows)."""
    samples, best = [], None
    client = run.on_desktop(win32.client_size, hwnd)
    vp = _viewport(run)
    samples.append((client, vp))
    guess = (target[0] + client[0] - vp[0], target[1] + client[1] - vp[1])
    for _ in range(run.cfg["device_iterations"]):
        reached = run.on_desktop(win32.set_client_size, hwnd, guess[0], guess[1])
        time.sleep(1.2)
        vp = _viewport(run)
        samples.append((reached, vp))
        err = viewport_error(vp, target)
        if best is None or err < best[0]:
            best = (err, reached, vp)
        if err == 0:
            break
        nxt = next_client_guess(target, samples)
        if nxt == guess or (len(samples) >= 3 and samples[-1][0] == samples[-2][0]):
            break  # Studio / Windows clamps the window: closest reachable
        guess = nxt
    if best and best[2] != vp:
        run.on_desktop(win32.set_client_size, hwnd, best[1][0], best[1][1])
        time.sleep(1.2)
        vp = _viewport(run)
    return vp, [list(s[0]) + list(s[1]) for s in samples]


def _viewport(run):
    d = run.need_luau("client_ready", "Client", timeout=20)
    v = d.get("viewport") or [0, 0]
    return int(round(v[0])), int(round(v[1]))


def capture_frame(run, device, **rec):
    """StudioMCP screen_capture of the game viewport (GUI included, play mode too) -> <sha>-<device>.jpg
    plus a report.frames entry. No window capture and no crop. A blank frame (Pillow check) is retried
    up to 3 times, then rejected. `rec` goes into the frames entry (todo, kind, ...)."""
    time.sleep(0.6)
    img, stats, blank, err = None, None, True, "no image"
    for attempt in range(3):
        run.frame_seq += 1
        shot = run.tool("screen_capture", timeout=60, capture_id="pcw-%s-%d-%d" % (device, run.frame_seq, int(time.time())))
        img = shot.image_bytes() if shot.ok else None
        if not img:
            err = "screen_capture returned no image (%s)" % shot.brief(120)
            time.sleep(1.0)
            continue
        stats = imaging.jpeg_stats(img[1])
        blank = bool(stats) and imaging.is_blank(stats)
        if not blank:
            break
        err = "blank frame"
        time.sleep(1.0)
    info = {"method": "mcp_screen_capture", "stats": stats, "size": stats and [stats["w"], stats["h"]]}
    name = "%s-%s.jpg" % (run.sha, device)
    reasons = []
    if not img:
        reasons.append("capture failed")
    elif blank:
        reasons.append("blank frame")
    if img:
        path = os.path.join(run.outdir, name if not reasons else name.replace(".jpg", "-rejected.jpg"))
        with open(path, "wb") as f:
            f.write(img[1])
    if reasons:
        info["rejected"] = reasons
        run.note("%s frame rejected: %s (%s)" % (device, ", ".join(reasons), err))
        status = "blank" if "blank frame" in reasons else "missing"
        run.add_frame(device, status=status, error=", ".join(reasons), **rec)
    else:
        info["file"] = name
        run.add_frame(device, name, method=info["method"], size=info["size"], **rec)
    return info


def step_devices(run):
    if run.dry:
        return "skip", {"dry_run": True}
    hwnd = run.hwnd
    if not hwnd:
        win = run.desktop().main_window(tracked_pids(run.paths))
        hwnd = run.hwnd = win and win["hwnd"]
    if not hwnd:
        raise StepFail("no Studio window to resize")
    results, failed = {}, []
    menus, phone, menu_s, perf_s, filled = {}, {}, 0.0, 0.0, False
    try:
        for device, tw, th in run.cfg["devices"]:
            if run.remaining() < 45:
                results[device] = {"skipped": "run budget"}
                run.note("device %s skipped: run budget" % device)
                continue
            vp, samples = converge_viewport(run, hwnd, (tw, th))
            res = {"target": [tw, th], "viewport": list(vp), "exact": tuple(vp) == (tw, th), "samples": samples}
            if not res["exact"]:
                run.note("%s: viewport %dx%d is the closest Studio allows to %dx%d" % (device, vp[0], vp[1], tw, th))
            hud = run.need_luau("hud_check", "Client", timeout=30)
            res["hud"] = hud
            if hud.get("offscreen") or hud.get("missing"):
                failed.append(device)
                res["error"] = "off-screen %s missing %s" % (hud.get("offscreen"), hud.get("missing"))
            res["idle"] = close_all_panels(run)  # idle HUD: every panel closed, nothing else hidden
            res["frame"] = capture_frame(run, device, kind="device")
            results[device] = res
            t1 = time.time()
            menus[device] = menus_at_device(run, device)
            menu_s += time.time() - t1
            if device.startswith("phone"):
                t1 = time.time()
                phone[device] = phone_perf_at_device(run, device, first=not filled)
                filled = True
                perf_s += time.time() - t1
    finally:
        if filled:
            try:
                run.luau("slime_fill", "Server", timeout=20, target=0)
            except Exception as e:
                run.note("could not remove the phone_perf slime clones: %r" % (e,))
    set_menus_and_perf_steps(run, menus, phone, menu_s, perf_s)
    detail = {"devices": results}
    if failed:
        return "fail", dict(detail, error="HUD/nav off-screen or missing at: %s" % ", ".join(failed))
    if not any(r.get("hud") for r in results.values()):
        return "fail", dict(detail, error="no device size was checked")
    return "pass", detail


def menus_at_device(run, device):
    """Opens every menu panel at the current size, measures it, captures it and closes it again.

    Opening: MCP click on the nav icon when the cursor guard allows, else the Visible fallback
    (open_panel). Returns {panel key: menu_record}. Frames: <sha>-menu-<panel>-<device>.jpg.
    """
    out = {}
    for key in run.cfg["menu_panels"]:
        panel = panel_for(key)
        fid = "menu-%s-%s" % (key, device)
        if run.remaining() < 40:
            out[key] = menu_record(None, error="run budget")
            continue
        frame, m, err, opened = None, None, None, None
        try:
            opened = open_panel(run, key)
            if not opened["method"]:
                err = "could not open %s" % panel
            else:
                time.sleep(0.5)  # let the panel's own layout settle
                m = run.need_luau("menu_measure", "Client", timeout=20, panel=panel)
                run.luau("ui_isolate", "Client", timeout=15, keep=panel, hide=True)
                try:
                    info = capture_frame(run, fid, kind="menu", panel=panel, for_device=device,
                                         open_method=opened["method"])
                    frame = info.get("file")
                finally:
                    run.luau("ui_isolate", "Client", timeout=15, keep=panel, hide=False)
        except Exception as e:
            err = repr(e)[:200]
        finally:
            if opened and opened.get("method") and opened["method"] != "already open":
                try:
                    close_panel(run, panel)
                except Exception as e:
                    run.note("menu %s/%s: close failed: %r" % (device, key, e))
        rec = menu_record(m, frame, err)
        if opened and opened.get("method"):
            rec["open_method"] = opened["method"]
        out[key] = rec
    return out


def phone_perf_at_device(run, device, first):
    """Phone size: >= phone_min_slimes animated slimes near the camera, then RenderStepped dt over
    stats_seconds. slime_fill (Server) clones wild/pad slimes around the character when short."""
    res = {"pass": False}
    if run.remaining() < 40:
        res["error"] = "run budget"
        return res
    seconds = run.cfg["stats_seconds"]
    try:
        want = run.cfg["phone_min_slimes"] + 4  # a few extra: only the 16 nearest animate
        ok, fill = run.luau("slime_fill", "Server", timeout=30, target=want)
        res["fill"] = fill if ok else str(fill)[:200]
        if ok and fill.get("error"):
            run.note("phone_perf %s: slime fill: %s" % (device, fill["error"]))
        time.sleep(1.5)  # replication, then SlimeLifeRunner picks 4 rigs per 0.25 s tick
        stats = run.need_luau("phone_perf", "Client", timeout=seconds + 60, seconds=seconds)
        res.update({k: _r(stats.get(k)) for k in ("avg_ms", "p95_ms", "max_ms", "fps", "memory_mb", "animating",
                                                  "animating_at_start", "slimes_near", "frames", "viewport")})
        info = capture_frame(run, "phone-perf-" + device, kind="perf", for_device=device)
        res["frame"] = info.get("file")
        ok, problems = phone_perf_verdict(stats, run.cfg["phone_min_fps"], run.cfg["phone_min_slimes"])
        res["pass"] = ok
        if problems:
            res["problems"] = problems
            run.note("phone_perf %s: %s" % (device, "; ".join(problems)))
    except Exception as e:
        res["error"] = repr(e)[:200]
    return res


def set_menus_and_perf_steps(run, menus, phone, menu_s, perf_s):
    """The menus and phone_perf steps run inside the devices loop; this records them as steps + report keys."""
    run.extra["menus"] = menus
    bad = menus_failed(menus)
    ok = bool(menus) and not bad
    run.steps["menus"] = {"status": "pass" if ok else "fail", "seconds": round(menu_s, 1), "detail": dict(
        {"panels": list(run.cfg["menu_panels"]), "devices": list(menus)},
        **({} if ok else {"error": "not on screen with a visible close button: %s" % ", ".join(bad or ["nothing measured"])}))}
    run.note("menus are content-sized cards since #76 (not full-window): frac_w / frac_h are reported, "
             "only on-screen + a visible close button decide pass")
    run.perf["phone"] = phone
    badp = [d for d, r in phone.items() if not r.get("pass")]
    okp = bool(phone) and not badp
    run.steps["phone_perf"] = {"status": "pass" if okp else "fail", "seconds": round(perf_s, 1), "detail": dict(
        {"min_fps": run.cfg["phone_min_fps"], "devices": list(phone)},
        **({} if okp else {"error": "avg FPS below %s or not measured at: %s" % (
            run.cfg["phone_min_fps"], ", ".join(badp or ["any phone size"]))}))}
    run.note("phone_perf is Studio on the PC (own desktop, unfocused), not real phone hardware")


def _body(name):
    with open(os.path.join(HERE, "luau", name + ".luau"), encoding="utf-8") as f:
        return f.read()


def step_twoplayer(run):
    if run.dry:
        return "skip", {"dry_run": True}
    if run.playing:
        stop_play(run)
    detail, tried = {}, []
    # (a) a scriptable multi-client API? Probe only.
    ok, probe = run.luau("testservice_probe", "Edit", timeout=20)
    detail["a_probe"] = probe
    tried.append("a: no multi-client API in StudioTestService/TestService (probe only)")
    # (b) a command-line test server + clients (-task StartServer / StartClient) is removed: it
    # opened extra visible Studio windows, which breaks "runs in the background".
    tried.append("b: removed (extra -task StartServer/StartClient Studio windows were visible)")
    # (c) two stand-in sessions on the real server modules inside a play session.
    if run.remaining() < 60:
        tried.append("c: skipped (run budget)")
        run.note("two_player not run: " + " | ".join(tried))
        return "warn", dict(detail, mode="not run", tried=tried)
    start_play(run)
    try:
        d = run.need_luau("server_steal_sim", "Server", timeout=40)
    finally:
        stop_play(run)
    passed = bool(d.get("distinct_plots") and d.get("grab_ok") and d.get("deposit_ok")
                  and d.get("thief_has") and not d.get("victim_has"))
    detail.update(mode="c-server-sim", tried=tried, result=d, pass_=passed,
                  assertion="two stand-in sessions get distinct plots; thief steals + deposits victim's slime")
    run.note("two_player ran mode c (pure server modules in one play session), not two real clients")
    return ("pass" if passed else "fail"), detail


# H1 HUD: the left column is Plot, Rebirth, Goals, SlimeDex, Codes (Shop / Merge / Top panels have no nav button; PcwOpen opens them)
UI_SHOT_BUTTONS = {"dex": "Nav.Dex", "rebirth": "Nav.Rebirth", "goals": "Nav.Goals", "plot": "Nav.Plot", "codes": "Nav.Codes"}
UI_SHOT_PANELS = {"leaders": "LeaderboardPanel", "worldshop": "WorldShopPanel"}  # else <Key>Panel (src/ui/Panels: Widgets.panel names)


def panel_for(key):
    k = str(key).lower()
    return UI_SHOT_PANELS.get(k, k[:1].upper() + k[1:] + "Panel")


def close_all_panels(run):
    """PcwOpen='' (setOpen(nil)): closes whichever menu is open. Returns the panels still open (should be [])."""
    run.luau("panel_visible", "Client", timeout=15, panel="ShopPanel", show=False)
    time.sleep(0.4)
    left = ui_probe(run).get("open_panels") or []
    for panel in list(left):
        run.luau("panel_visible", "Client", timeout=15, panel=panel, show=False)
    if left:
        time.sleep(0.4)
        left = ui_probe(run).get("open_panels") or []
    if left:
        run.note("panels still open before the idle device frame: %s" % ", ".join(left))
    return left


def open_panel(run, key):
    """Opens a SlimeUI panel for a ui shot. Returns {panel, method, tried}; method None = not opened.

    No input injection: luau/panel_visible sets the Studio-only SlimeUI attribute PcwOpen (method
    "pcw_open_hook": setOpen ran, contents rendered); if that does not show the panel it sets
    <Key>Panel.Visible directly ("visible_fallback": contents can be stale).
    """
    panel = panel_for(key)
    res = {"panel": panel, "method": None, "tried": []}
    p = ui_probe(run)
    if panel in (p.get("open_panels") or []):
        res["method"] = "already open"
        return res
    ok, d = run.luau("panel_visible", "Client", timeout=15, panel=panel, show=True)
    time.sleep(0.4)
    p = ui_probe(run)
    res["tried"].append({"path": "panel_visible", "result": d if ok else str(d)[:160]})
    if panel in (p.get("open_panels") or []):
        res["method"] = "pcw_open_hook" if ok and isinstance(d, dict) and d.get("via") == "pcw_open_hook" else "visible_fallback"
    return res


def press_check(run, opened, key, expect="closed"):
    """The Esc test without key injection: cas_close (the Studio-only PcwPress='Escape' hook running the game's
    CloseMenu action handler) with the panel open, then asserts the panel closed. A panel opened by the Visible fallback has no game
    state behind it, so the action cannot close it: inconclusive."""
    panel = opened["panel"]
    out = {"key": key, "panel": panel, "expect": expect, "method": "pcw_press_hook"}
    if opened["method"] == "visible_fallback":
        return dict(out, status="warn", why="panel opened by Visible=true; the game's menu state is not open")
    ok, info = cas_close(run)
    p = ui_probe(run)
    is_open = panel in (p.get("open_panels") or [])
    out.update(key_ok=ok, key_call=info, open_after=is_open)
    if not ok:
        close_panel(run, panel)
        return dict(out, status="fail", why="PcwPress hook failed: %s" % (info.get("error"),))
    if is_open != (expect == "open"):
        close_panel(run, panel)  # tidy up for the next shot
        return dict(out, status="fail")
    return dict(out, status="pass")


def close_panel(run, panel):
    """PcwOpen='' (setOpen(nil)), then Visible=false. Returns the method that closed it."""
    ok, d = run.luau("panel_visible", "Client", timeout=15, panel=panel, show=False)
    time.sleep(0.4)
    if panel not in (ui_probe(run).get("open_panels") or []):
        return d.get("via", "visible_fallback") if ok and isinstance(d, dict) else "visible_fallback"
    run.luau("panel_visible", "Client", timeout=15, panel=panel, show=False)
    return "visible_fallback"


def bug_probe(run, shot, res, sid):
    """Advisory bug probe of a world shot (Merijn's bug list). shot["bug_probe"] = {bug, title, luau?, ctx?, args?, timeout?,
    summary?}: runs luau/<luau> on ctx (Server | Client) and expects {ok: bool|null, summary, detail}; without `luau` it is a
    frame-only entry (ok null, summary from the shot). ADVISORY: a false ok or an error is a note, never a step or run failure
    and never a publish-gate input (the bug probes of open bugs fail on purpose). Result lands in res["bug"]."""
    bp = shot["bug_probe"]
    rec = {"id": bp.get("bug"), "ok": None, "summary": str(bp.get("summary") or ""), "detail": {}}
    if bp.get("luau"):
        try:
            out = run.need_luau(bp["luau"], bp.get("ctx", "Server"), int(bp.get("timeout", 30)), **(bp.get("args") or {}))
            rec.update(ok=out.get("ok"), summary=str(out.get("summary") or "")[:300], detail=out.get("detail") or {})
        except Exception as e:
            rec.update(ok=False, summary="probe error: %s" % repr(e)[:200])
    if rec["ok"] is False:
        run.note("bug %s (shot %s): %s" % (rec["id"], sid, rec["summary"][:160]))
    res["bug"] = rec


def bug_record(run, shot, res, sid):
    """Adds the shot's bug probe result to the report's top-level `bugs` list (build_report)."""
    rec = res.get("bug")
    if rec:
        run.extra.setdefault("bugs", []).append({
            "id": rec["id"], "title": shot["bug_probe"].get("title"), "ok": rec["ok"], "summary": rec["summary"],
            "shot": sid, "frame": (res.get("frame") or {}).get("file")})


def step_shots(run):
    """Soft: proof frames from shots/*.json (bots add theirs in PRs). Missing targets are notes, never failures.

    ui shots open a panel (open_panel), hide the tutorial card and every other panel (ui_isolate,
    restored after) and capture the viewport with the UI. world shots hide every ScreenGui,
    BillboardGui and ProximityPrompt, move the character behind the camera, lock the camera with a
    render step (shot_camera) on the target's Server bounding box and capture the viewport. Every shot adds a report.frames entry with its todo and status.
    """
    if run.dry:
        return "skip", {"dry_run": True}
    shots, shot_notes = load_shots(repo=run.paths.repo)
    for n in shot_notes:
        run.note(n)
    if not shots:
        return "skip", {"reason": "shots/ missing or empty"}
    results, world_mode, pad_seat, cur_device = [], False, None, None
    weather_pinned = False
    for shot in shots:
        if run.shot_filter is not None and shot.get("id") not in run.shot_filter:
            continue  # partial run: not selected, no frame entry
        sid = re.sub(r"[^A-Za-z0-9_.-]", "_", str(shot.get("id", "shot")))
        fid = "shot-" + sid
        todo = shot_todo(shot)
        res = {"id": sid, "todo": todo, "note": shot.get("note")}
        results.append(res)
        if run.remaining() < 90:
            res["skipped"] = "run budget"
            run.add_frame(fid, status="missing", todo=todo, kind="shot", error="run budget")
            continue
        want = shot.get("device")
        if want and want != cur_device and run.hwnd:
            # optional per-shot viewport: a device name from cfg["devices"] (desktop / phone-portrait / phone-landscape)
            for device, tw, th in run.cfg["devices"]:
                if device == want:
                    res["viewport"] = list(converge_viewport(run, run.hwnd, (tw, th))[0])
                    cur_device = want
        ferr = shot_flags_error(shot)
        if ferr:
            res["error"] = "bad flags: " + ferr
            run.add_frame(fid, status="missing", todo=todo, kind="shot", error=res["error"])
            continue
        try:
            if shot.get("flags"):  # forced FEATURES flags (Studio only); cleared again after the capture
                res["flags"] = run.need_luau("flag_set", "Server", timeout=15, names=",".join(shot_flags(shot)), on=True)
                time.sleep(1.0)  # attribute replication to the Client + one feature refresh
            if shot.get("kind") == "ui":
                if world_mode:
                    run.luau("shot_camera_reset", "Client", timeout=15)
                    world_mode = False
                key = shot.get("open")
                if shot.get("expect_no_overlay"):  # idle HUD: no backdrop / card may be shown (v28 blocker)
                    over = ui_probe(run).get("overlays") or []
                    res["overlays"] = over
                    if over:
                        res["error"] = "overlay visible with no menu open: %s" % ", ".join(over)
                if shot.get("rebirth_slime"):  # v29: force the required-slime state (owned / missing) in Studio
                    res["rebirth_slime"] = run.need_luau("rebirth_slime", "Client", timeout=15, state=shot["rebirth_slime"])
                if shot.get("friend_bonus"):  # v29 #4: fake N friends in the server (badge + income line)
                    res["friend_bonus"] = run.need_luau("friend_bonus", "Client", timeout=15, count=int(shot["friend_bonus"]))
                if shot.get("admin_event"):  # v29 #10: fake a live admin event banner (Studio only)
                    res["admin_event"] = run.need_luau("admin_event", "Client", timeout=15, event=shot["admin_event"])
                if shot.get("weekend"):  # competitor-gaps #17: fake a live x2 Weekend window (Studio only; H1 HUD: not shown)
                    res["weekend"] = run.need_luau("weekend", "Client", timeout=15, on=True)
                if shot.get("rain"):  # H1 HUD: fake a running Slime Rain for the bottom-right status slot (Studio only)
                    res["rain"] = run.need_luau("rain", "Client", timeout=15, on=True)
                if shot.get("tooltip"):  # B8: open the tooltip of a bottom-right status icon ("Rain" | "Event" | "Friend")
                    tip = res["tooltip"] = run.need_luau("tooltip", "Client", timeout=15, id=shot["tooltip"])
                    if not (tip.get("tooltip") and tip.get("visible") and tip.get("on_screen")):
                        res["error"] = "status tooltip not shown on screen: %s" % tip
                if shot.get("steal_alert"):  # v21: fake a theft of my slime: edge flash, arrow, join notice (Studio only)
                    sa = res["steal_alert"] = run.need_luau("steal_alert", "Client", timeout=15, on=True)
                    if not sa.get("fx") or not sa.get("arrow_visible"):
                        res["error"] = "steal alert fx not drawn (fx %s, arrow %s)" % (sa.get("fx"), sa.get("arrow_visible"))
                if shot.get("weekly_event"):  # v21: the server's WeeklyEvent attribute must be present and well formed
                    res["weekly_event"] = run.need_luau("weekly_event", "Client", timeout=15)
                    if not res["weekly_event"].get("ok"):
                        res["error"] = "WeeklyEvent attribute missing or malformed: %s" % res["weekly_event"].get("raw")
                if shot.get("events_board"):  # v21: the HUD events board banner must be visible with at least one event
                    res["events_board"] = run.need_luau("events_board", "Client", timeout=15)
                    if not res["events_board"].get("ok"):
                        res["error"] = "events board banner missing or empty: %s" % res["events_board"].get("lines")
                if shot.get("profiler_readout"):  # ServerProfiler flag: the workspace ProfilerSummary line must appear
                    res["profiler_readout"] = run.need_luau("profiler_readout", "Server", timeout=60, wait=float(shot["profiler_readout"]))
                    if not res["profiler_readout"].get("ok"):
                        res["error"] = "ProfilerSummary attribute missing: %s" % res["profiler_readout"].get("raw")
                if shot.get("audio_panel"):  # Audio flag: the Sound icon button (idle visible) + Sound card with its sliders must exist, then open it
                    res["audio_panel"] = run.need_luau("audio_panel", "Client", timeout=15, on=True)
                    if not res["audio_panel"].get("ok") or not res["audio_panel"].get("button_idle_visible"):
                        res["error"] = "audio panel missing: %s" % json.dumps(res["audio_panel"])[:160]
                if shot.get("plot_skin"):  # gaps #15: fake the plot skin picker (Studio only)
                    res["plot_skin"] = run.need_luau("plot_skin", "Client", timeout=15, skin=shot["plot_skin"])
                if shot.get("merge_vat"):  # v19: the 3-slime vat panel (and the vat mesh on my plot), Studio only
                    res["merge_vat"] = run.need_luau("merge_vat", "Client", timeout=15, on=True)
                if shot.get("rain_magnet"):  # v19: the Rain Magnet shop row (and the plot prop), Studio only
                    res["rain_magnet"] = run.need_luau("rain_magnet", "Client", timeout=15, on=True)
                if shot.get("world_shop"):  # CONTRACT.md §27: which world shop the WorldShop card shows (Studio only)
                    res["world_shop"] = run.need_luau("world_shop", "Client", timeout=15, shop=shot["world_shop"])
                if shot.get("dex_rows"):  # v29 menus: fake a long Dex list (Studio only)
                    res["dex_rows"] = run.need_luau("dex_rows", "Client", timeout=15, count=int(shot["dex_rows"]))
                if shot.get("dex_weather"):  # TODO 21: Wet / Frozen discovered in the real player data (Studio hook)
                    res["dex_weather"] = run.need_luau("pcw_attr", "Server", timeout=15, name="PcwDexWeather", value=True)
                    time.sleep(0.6)  # State push
                if shot.get("plot_slime"):  # fake owned slime so the Appraise button shows
                    res["plot_slime"] = run.need_luau("plot_slime", "Client", timeout=15, state="1")
                opened = open_panel(run, key) if key else None
                if shot.get("welcome_back"):  # v20: the welcome-back card from a faked State.welcomeBack (Studio only)
                    wb = res["welcome_back"] = run.need_luau("welcome_back", "Client", timeout=15, on=True)
                    if not wb.get("visible"):
                        res["error"] = "welcome-back card not visible"
                if shot.get("daily_popup"):  # v29 menus: the Daily popup over the idle HUD (Studio only)
                    res["daily_popup"] = run.need_luau("daily_popup", "Client", timeout=15, on=True)
                if opened:
                    res["open"] = opened
                    if not opened["method"]:
                        res["missing"] = "could not open %s" % opened["panel"]
                        run.add_frame(fid, status="missing", todo=todo, kind="shot", error=res["missing"])
                        continue
                    if opened["method"] == "visible_fallback":
                        run.note("shot %s: no click opened %s; set Visible directly" % (sid, opened["panel"]))
                if opened and shot.get("press"):
                    res["press"] = press_check(run, opened, shot["press"], shot.get("expect", "closed"))
                    if res["press"]["status"] != "pass":
                        res["error"] = "%s did not leave %s %s" % (shot["press"], opened["panel"], shot.get("expect", "closed"))
                if opened and shot.get("scroll_to"):  # card below the scroll fold at small viewports
                    res["scroll"] = run.luau("panel_scroll", "Client", timeout=15, panel=opened["panel"], target=shot["scroll_to"])[1]
                if opened and shot.get("scroll_row"):  # v29 menus: Dex list scrolled to a row; its preview must be live
                    sr = res["scroll_row"] = run.need_luau("panel_scroll_row", "Client", timeout=15, panel=opened["panel"], row=int(shot["scroll_row"]))
                    if not sr.get("row_found") or not sr.get("row_live"):
                        res["error"] = "row %s has no live preview (found %s, live previews %s)" % (shot["scroll_row"], sr.get("row_found"), sr.get("live"))
                keep = opened["panel"] if opened and not shot.get("press") else ""
                if shot.get("daily_popup"):
                    keep = "DailyPopup"
                if shot.get("welcome_back"):
                    keep = "WelcomePanel"
                if shot.get("audio_panel"):  # ui_isolate hides every *Panel, which would close the opened SoundPanel
                    keep = "SoundPanel"
                ok, iso = run.luau("ui_isolate", "Client", timeout=15, keep=keep, hide=True)
                res["isolated"] = iso if ok else str(iso)[:160]
                try:
                    if shot.get("hold"):  # hold ring mid-hold (B1): hold the fill half full AFTER the isolate, capture, release
                        h = res["hold"] = run.need_luau("hold_fill", "Client", timeout=15, name=shot["hold"], on=True)
                        if not h.get("found"):
                            res["error"] = "no visible HoldFill on a button named %s" % shot["hold"]
                        elif not h.get("on_screen") or abs((h.get("fraction") or 0) - 0.5) > 0.1:
                            res["error"] = "hold ring not ~50%% and on screen (fraction %s, on_screen %s)" % (
                                h.get("fraction"), h.get("on_screen"))
                    res["frame"] = capture_frame(run, fid, todo=todo, kind="shot",
                                                 open_method=opened and opened["method"])
                finally:
                    run.luau("ui_isolate", "Client", timeout=15, keep=keep, hide=False)
                    if shot.get("hold"):
                        run.luau("hold_fill", "Client", timeout=15, name=shot["hold"], on=False)
                if opened and not shot.get("press") and opened["method"] != "already open":
                    res["closed_by"] = close_panel(run, opened["panel"])
                if shot.get("rebirth_slime"):
                    run.luau("rebirth_slime", "Client", timeout=15, state="")
                if shot.get("friend_bonus"):
                    run.luau("friend_bonus", "Client", timeout=15, count=0)
                if shot.get("admin_event"):
                    run.luau("admin_event", "Client", timeout=15, event="")
                if shot.get("weekend"):
                    run.luau("weekend", "Client", timeout=15, on=False)
                if shot.get("rain"):
                    run.luau("rain", "Client", timeout=15, on=False)
                if shot.get("tooltip"):
                    run.luau("tooltip", "Client", timeout=15, id="")
                if shot.get("steal_alert"):
                    run.luau("steal_alert", "Client", timeout=15, on=False)
                if shot.get("plot_skin"):
                    run.luau("plot_skin", "Client", timeout=15, skin="classic")
                if shot.get("plot_slime"):
                    run.luau("plot_slime", "Client", timeout=15, state="")
                if shot.get("dex_rows"):
                    run.luau("dex_rows", "Client", timeout=15, count=0)
                if shot.get("daily_popup"):
                    run.luau("daily_popup", "Client", timeout=15, on=False)
                if shot.get("welcome_back"):
                    run.luau("welcome_back", "Client", timeout=15, on=False)
                if shot.get("dex_weather"):
                    run.luau("pcw_attr", "Server", timeout=15, name="PcwDexWeather", value=False)
                if shot.get("tutorial_arrow"):
                    run.luau("arrow_step", "Client", timeout=15, step="")
            else:
                if shot.get("pos"):
                    eye, at = shot["pos"], shot.get("look") or [0, 0, 0]
                else:
                    ok, t = run.luau("shot_find", "Server", timeout=30, target=shot.get("target", ""),
                                     index=int(shot.get("index", 1)))
                    aim = None
                    if ok and t.get("found") and shot.get("aim"):
                        ok2, a = run.luau("shot_find", "Server", timeout=30, target=shot["aim"], index=1)
                        if ok2 and a.get("found"):
                            aim = a["pos"]
                        else:
                            ok = False
                    if not ok or not t.get("found"):
                        res["missing"] = "target %r (index %s%s) not found" % (
                            shot.get("target"), shot.get("index", 1), ", aim %r" % shot["aim"] if shot.get("aim") else "")
                        run.add_frame(fid, status="missing", todo=todo, kind="shot", error=res["missing"])
                        continue
                    res["target"] = {k: t.get(k) for k in ("path", "pos", "size", "front")}
                    if shot.get("from"):
                        eye, at = shot_camera_from(t, shot["from"], aim, shot.get("dist"), shot.get("height"))
                    else:
                        eye, at = shot_camera(t)
                world_mode = True
                res["camera"] = cam = run.need_luau("shot_camera", "Client", timeout=25, eye=eye, at=at, fov=float(shot.get("fov") or 0))
                if not cam.get("locked"):
                    run.note("shot %s: camera drifted %.2f studs from the render-step lock" % (sid, cam.get("drift") or -1))
                if shot.get("seat") and (res.get("target") or {}).get("path"):
                    # a slime seated on the pad (reused or cloned on the Server), so the frame shows the seat height
                    res["seat"] = run.need_luau("slime_seat", "Server", timeout=30, path=res["target"]["path"])
                    time.sleep(0.6)  # replication
                elif shot.get("anim") and pad_seat is None and (res.get("target") or {}).get("path"):
                    # optional uploaded-animation check: a rigged slime must sit on the pad (PcwPad clone)
                    pad_seat = run.need_luau("pad_seat", "Server", timeout=30, path=res["target"]["path"])
                    res["pad_seat"] = pad_seat
                if shot.get("plot_skin"):  # gaps #15: Plot_1 wears the skin (floor, fence tint, decor mesh), Studio only
                    res["plot_skin"] = run.need_luau("plot_skin", "Client", timeout=15, skin=shot["plot_skin"])
                if shot.get("fountain_tier"):  # v19: the fountain wears this tier's glow, Studio only
                    res["fountain_tier"] = run.need_luau("fountain_tier", "Client", timeout=15, tier=int(shot["fountain_tier"]))
                if shot.get("merge_vat"):  # v19: the vat mesh over Plot_1's vat disc, Studio only
                    res["merge_vat"] = run.need_luau("merge_vat", "Client", timeout=15, on=True)
                if shot.get("rain_magnet"):  # v19: the magnet prop beside Plot_1's vat, Studio only
                    res["rain_magnet"] = run.need_luau("rain_magnet", "Client", timeout=15, on=True)
                if shot.get("grow"):  # v29 #11: real growth on the pad 1 slime (Studio hook); WorldView draws it
                    # no watcher seat clone may stand on the pad: the frame must show the slime WorldView renders
                    if (res.get("target") or {}).get("path"):
                        res["seat_cleared"] = run.need_luau("seat_clear", "Server", timeout=15)  # PcwSeat + PcwPad clones
                        pad_seat = None
                    res["grow"] = run.need_luau("pcw_attr", "Server", timeout=15, name="PcwGrowth", value=int(shot["grow"]))
                    gw = run.need_luau("growth_wait", "Server", timeout=30, path=(res.get("target") or {}).get("path", ""), wait=12)
                    res["growth"] = gw
                    if gw.get("found") and gw.get("pos"):
                        # aim the camera at the real slime model
                        # frame bottom (slime base) to top (the label height) from outside the grown slime:
                        # aim at the vertical midpoint, back off along the pad front far enough for the whole span
                        px, py, pz = gw["pos"]
                        lp = gw.get("label_pos")
                        top = lp[1] + 0.8 if lp else py + 7.0
                        mid = (py + top) / 2.0
                        span = max(top - py, 4.0)
                        f = res["target"].get("front") or [0, 0, 1]
                        fl = math.hypot(f[0], f[2]) or 1.0
                        back = max(float(shot.get("dist") or 0), span * 1.9)  # ~60 deg vertical FOV, 1.9x span fits
                        eye = (px + f[0] / fl * back, mid + 1.0, pz + f[2] / fl * back)
                        at = (px, mid, pz)
                        res["framing"] = {"span": round(span, 2), "back": round(back, 2)}
                        res["aim"] = run.need_luau("shot_aim", "Client", timeout=25, eye=eye, at=at)
                        time.sleep(1.0)  # BillboardGui replication to the Client
                    else:
                        res["error"] = "pad slime has no Growth / LabelHeight attribute (%s)" % json.dumps(gw)[:160]
                if shot.get("habitat") and (res.get("target") or {}).get("path"):
                    # morph proof: the Client sets the pad's Habitat and waits `wait` s (mid-morph < 1, done >= 1.2)
                    res["habitat"] = run.need_luau("habitat_set", "Client", timeout=30, path=res["target"]["path"],
                                                   habitat=shot["habitat"], wait=float(shot.get("wait", 1.5)),
                                                   leave=bool(shot.get("leave")))
                if shot.get("despawn_fx") and (res.get("target") or {}).get("path"):
                    # v30 C8: the Client puts the seated slime in its despawn window and samples it for `wait` s;
                    # ok only if nothing faded / blinked and no Highlight appeared
                    res["despawn_fx"] = run.need_luau("despawn_fx", "Client", timeout=30, path=res["target"]["path"],
                                                      wait=float(shot.get("wait", 1.5)))
                    if not res["despawn_fx"].get("ok"):
                        run.note("shot %s: despawn FX faded or highlighted the slime (%s)" % (sid, res["despawn_fx"]))
                if not shot.get("weather") and weather_pinned:
                    # a weather / snow shot pinned WeatherDebug + SnowCoverDebug on the Client; later shots must not stay frosted.
                    # Pin the cover at 0 (not -1): an unpinned level would melt over SnowCover.MELT_SECONDS (35 s) and the next
                    # frames would still be half white. The end-of-run cleanup drops the pin (cover -1).
                    run.luau("weather_set", "Client", timeout=15, weather="", wait=0.1, cover=0)
                    weather_pinned = False
                if shot.get("weather"):
                    weather_pinned = True
                    # weather proof: the Client forces WeatherDebug (client-only attribute) and waits `wait` s for the tween in
                    res["weather"] = run.need_luau("weather_set", "Client", timeout=30, weather=shot["weather"],
                                                   wait=float(shot.get("wait", 2.5)),
                                                   cover=float(shot.get("snow_cover", -1)))
                    if not res["weather"].get("ok"):
                        run.note("shot %s: no weather emitter active (%s)" % (sid, res["weather"].get("rates")))
                if shot.get("revenge_plot"):
                    # v21 Revenge: the Client gets RevengePlots (client-only Player attribute) and must draw ONE
                    # RevengeHighlight on that plot's Base
                    res["revenge"] = run.need_luau("revenge_set", "Client", timeout=30, plot=int(shot["revenge_plot"]),
                                                   wait=float(shot.get("wait", 1.5)))
                    if not res["revenge"].get("ok"):
                        run.note("shot %s: no single RevengeHighlight on plot %s (%s)" % (
                            sid, shot["revenge_plot"], res["revenge"].get("highlights")))
                if shot.get("motion") and (res.get("target") or {}).get("path"):
                    # motion proof: the Client plays Idle / Hop / LookLeft / LookRight on the pad's slime through
                    # SlimeLifeRunner (SlimeMotor on the Motor6Ds) and compares the pose before / `wait` s later;
                    # ok only when the slime is driven (LifeMode) and the pose really changed
                    res["motion"] = run.need_luau("slime_motion", "Client", timeout=30, path=res["target"]["path"],
                                                  kind=shot["motion"], wait=float(shot.get("wait", 0.35)))
                    if shot["motion"] == "Tiers":
                        run.note("shot %s: slime LOD tiers %s" % (sid, res["motion"].get("tiers")))
                    if not res["motion"].get("ok") and shot["motion"] == "Tiers":
                        run.note("shot %s: slime has no LifeTier (mode %s)" % (sid, res["motion"].get("mode")))
                    elif not res["motion"].get("ok"):
                        run.note("shot %s: slime not moving (mode %s, moved %s)" % (
                            sid, res["motion"].get("mode"), res["motion"].get("moved")))
                if shot.get("slide_walk"):
                    # B6 / bug 9 (walkable slide): HARD = can_climb and cannot_enter_from_side; the other checks are notes
                    res["slide_walk"] = run.need_luau("slide_walk", "Server", timeout=60)
                    if not res["slide_walk"].get("ok"):
                        run.note("shot %s: the slide cannot be climbed or can be entered from the side: %s" % (
                            sid, str(res["slide_walk"].get("violations") or res["slide_walk"].get("error"))[:200]))
                    for soft in res["slide_walk"].get("soft_failed") or []:
                        run.note("shot %s: slide (soft) %s" % (sid, str(soft)[:200]))
                if shot.get("ring_slimes"):
                    # v30 C3: no wild slime inside the plaza's landing ring over a few seconds (soft: a note)
                    res["ring_slimes"] = run.need_luau("ring_slimes", "Server", timeout=30)
                    if not res["ring_slimes"].get("ok"):
                        run.note("shot %s: wild slime inside the landing ring: %s" % (
                            sid, str(res["ring_slimes"].get("violations") or res["ring_slimes"].get("error"))[:200]))
                if shot.get("wild_pace"):
                    # v30 C9: a lane slime's displacement over N s vs the Config pace (soft: needs a live wild on the lane)
                    res["wild_pace"] = run.need_luau("wild_pace", "Server", timeout=30, seconds=float(shot["wild_pace"]))
                    if not res["wild_pace"].get("ok"):
                        run.note("shot %s: wild pace off: %s" % (sid, str(res["wild_pace"])[:200]))
                if shot.get("mesh_slots_max"):
                    # perf proof (SOFT since the 500 MeshParts budget): the same Server count as step_perf, a warning above the limit
                    ms = res["mesh_slots"] = run.need_luau("perf_server", "Server", timeout=30)
                    ms["max"] = int(shot["mesh_slots_max"])
                    ms["ok"] = 0 < (ms.get("mesh_slots") or 0) <= ms["max"]
                    if not ms["ok"]:
                        run.note("shot %s: mesh slots %s not in 1..%s" % (sid, ms.get("mesh_slots"), ms["max"]))
                if shot.get("runtime_parts_max"):
                    # perf proof (HARD): world BaseParts (transients excluded), parade lane and slide colliders spawned
                    rp = res["runtime_parts"] = run.need_luau("perf_server", "Server", timeout=30)
                    rp["max"] = int(shot["runtime_parts_max"])
                    rp["ok"] = (0 < (rp.get("runtime_parts") or 0) <= rp["max"]
                                and bool(rp.get("parade_lane")) and bool(rp.get("slide_colliders")))
                    if not rp["ok"]:
                        run.note("shot %s: runtime parts %s not in 1..%s (parade lane %s, slide colliders %s)" % (
                            sid, rp.get("runtime_parts"), rp["max"], rp.get("parade_lane"), rp.get("slide_colliders")))
                if shot.get("mesh_stand"):
                    # bug 11 part 1: balls dropped onto / pushed into the converted (MeshAssets.COLLISION) props must not pass through
                    res["mesh_stand"] = run.need_luau("mesh_stand", "Server", timeout=40, meshes=",".join(shot["mesh_stand"]))
                    if not res["mesh_stand"].get("ok"):
                        run.note("shot %s: mesh collision: %s" % (sid, str(res["mesh_stand"].get("summary") or res["mesh_stand"].get("error"))[:200]))
                if shot.get("fountain_walk"):
                    # C10: free balls dropped over the whole fountain top (eave, dome, basin) must never sink into it
                    # "fountain_split": true = the same grid against the FEATURES.FountainSplit tower pieces (a draft experiment:
                    # ADVISORY, a violation is a note only; the plain colliders shot stays the HARD one)
                    split = bool(shot.get("fountain_split"))
                    res["fountain_walk"] = run.need_luau("fountain_walk", "Server", timeout=60, split=split)
                    res["fountain_split"] = split
                    if not res["fountain_walk"].get("ok"):
                        run.note("shot %s: sank into the fountain top%s: %s" % (
                            sid, " (split pieces, advisory)" if split else "",
                            str(res["fountain_walk"].get("violations") or res["fountain_walk"].get("error"))[:200]))
                if shot.get("anim") and (res.get("target") or {}).get("path"):
                    # optional uploaded-animation proof: the Client plays it on the pad slime's Animator, waits `wait` s
                    res["anim"] = run.need_luau("slime_anim", "Client", timeout=30, path=res["target"]["path"],
                                                anim=shot["anim"], id=shot["animId"], wait=float(shot.get("wait", 0.5)))
                if shot.get("tutorial_arrow"):
                    # v30 C11: force a TutorialArrow towards a far target; fx_streaks below must see it capped
                    res["tutorial_arrow"] = run.need_luau("arrow_step", "Client", timeout=30, step=shot["tutorial_arrow"])
                    if not res["tutorial_arrow"].get("found"):
                        run.note("shot %s: no TutorialArrow Beam for step %s" % (sid, shot["tutorial_arrow"]))
                if shot.get("fx_streaks"):
                    # v30 C11 night proof: no Beam / Trail / Neon part longer than `fx_streaks` studs anywhere in the workspace
                    res["fx_streaks"] = run.need_luau("fx_streaks", "Client", timeout=30, max=float(shot["fx_streaks"]))
                    if not res["fx_streaks"].get("ok"):
                        run.note("shot %s: streak longer than %s studs: %s" % (sid, shot["fx_streaks"], json.dumps(res["fx_streaks"].get("bad"))[:200]))
                if shot.get("bug_probe"):  # advisory bug probe (never fails the step), see bug_probe()
                    bug_probe(run, shot, res, sid)
                if shot.get("clock") is not None:
                    # daytime shot: the Server's DayNight cycle rewrites ClockTime, so pin it (Studio hook), restore after
                    res["clock"] = run.need_luau("pcw_clock", "Server", timeout=15, time=float(shot["clock"]))
                try:
                    res["frame"] = capture_frame(run, fid, todo=todo, kind="shot",
                                                 target=(res.get("target") or {}).get("path"))
                finally:
                    live = [f for f in shot_flags(shot) if f not in BOOT_FLAGS]
                    if live:
                        run.luau("flag_set", "Server", timeout=15, names=",".join(live), on=False)
                    if shot.get("clock") is not None:
                        run.luau("pcw_clock", "Server", timeout=15, time=False)
                bug_record(run, shot, res, sid)
                if shot.get("plot_skin"):
                    run.luau("plot_skin", "Client", timeout=15, skin="classic")
                if shot.get("fountain_tier"):
                    run.luau("fountain_tier", "Client", timeout=15, tier=0)
                if shot.get("merge_vat"):
                    run.luau("merge_vat", "Client", timeout=15, on=False)
                if shot.get("rain_magnet"):
                    run.luau("rain_magnet", "Client", timeout=15, on=False)
        except Exception as e:
            res["error"] = repr(e)[:200]
            if not res.get("frame"):
                run.add_frame(fid, status="missing", todo=todo, kind="shot", error=res["error"])
    try:
        run.luau("shot_camera_reset", "Client", timeout=15)
    except Exception:
        pass
    if cur_device and cur_device != run.cfg["devices"][0][0] and run.hwnd:
        converge_viewport(run, run.hwnd, tuple(run.cfg["devices"][0][1:]))  # back to the first (desktop) size
    if any(shot.get("revenge_plot") for shot in shots):
        try:
            run.luau("revenge_set", "Client", timeout=15, plot=0, wait=0.1)  # drop the RevengePlots preview
        except Exception:
            pass
    used_flags = sorted({f for shot in shots if not shot_flags_error(shot) for f in shot_flags(shot)})
    if used_flags:
        try:
            run.luau("flag_set", "Server", timeout=15, names=",".join(used_flags), on=False)  # drop every PcwFlag_ override
        except Exception:
            pass
    if any(shot.get("weather") for shot in shots):
        try:
            run.luau("weather_set", "Client", timeout=15, weather="", wait=0.1, cover=-1)  # drop the WeatherDebug preview
        except Exception:
            pass
    if any(shot.get("fountain_tier") for shot in shots):
        try:
            run.luau("fountain_tier", "Client", timeout=15, tier=0)  # drop the PcwFountainTier override
        except Exception:
            pass
    if any(shot.get("merge_vat") for shot in shots):
        try:
            run.luau("merge_vat", "Client", timeout=15, on=False)  # drop the PcwMergeVat override
        except Exception:
            pass
    if any(shot.get("rain_magnet") for shot in shots):
        try:
            run.luau("rain_magnet", "Client", timeout=15, on=False)  # drop the PcwRainMagnet override
        except Exception:
            pass
    if any(shot.get("world_shop") for shot in shots):
        try:
            run.luau("world_shop", "Client", timeout=15, shop="")  # drop the PcwWorldShop override
        except Exception:
            pass
    if any(shot.get("plot_skin") for shot in shots):
        try:
            run.luau("plot_skin", "Client", timeout=15, skin="")  # drop the PcwPlotSkin override (shots set "classic" first)
        except Exception:
            pass
    if any(r.get("seat") for r in results):
        try:
            run.luau("slime_seat", "Server", timeout=15, path="")  # drop the PcwSeat clones
        except Exception:
            pass
    done = len([r for r in results if (r.get("frame") or {}).get("file")])
    tool_errors = shot_tool_errors(results)
    if len(tool_errors) > SHOT_TOOL_ERROR_MAX:
        run.note("shots: %d of %d shots could not run (luau / MCP call failed), e.g. %s: %s" % (
            len(tool_errors), len(shots), tool_errors[0],
            next((str(r.get("error"))[:160] for r in results if r.get("id") == tool_errors[0]), "")))
        return "fail", {"captured": done, "total": len(shots), "shots": results, "shot_tool_errors": len(tool_errors)}
    if any(r.get("fountain_walk") and not r.get("fountain_split") and not r["fountain_walk"].get("ok") for r in results):
        return "fail", {"captured": done, "total": len(shots), "shots": results, "fountain_walk_failed": True}
    if any(r.get("runtime_parts") and not r["runtime_parts"].get("ok") for r in results):
        return "fail", {"captured": done, "total": len(shots), "shots": results, "runtime_parts_failed": True}
    pressed = [r for r in results if r.get("press")]
    if any(r["press"]["status"] != "pass" for r in pressed):
        return "warn", {"captured": done, "total": len(shots), "shots": results, "press_failed": True}
    if any(r.get("slide_walk") and not r["slide_walk"].get("ok") for r in results):
        return "fail", {"captured": done, "total": len(shots), "shots": results, "slide_walk_failed": True}
    if any(r.get("mesh_slots") and not r["mesh_slots"].get("ok") for r in results):
        return "warn", {"captured": done, "total": len(shots), "shots": results, "mesh_slots_warned": True}
    return "pass" if (done or pressed) else "warn", {"captured": done, "total": len(shots), "shots": results}


def watcher_studio_pids(paths):
    """RobloxStudioBeta processes whose command line references this watcher's home (builds dir)."""
    try:
        out = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "Get-CimInstance Win32_Process -Filter \"name='RobloxStudioBeta.exe'\" | "
             "ForEach-Object { \"$($_.ProcessId)`t$($_.CommandLine)\" }"],
            capture_output=True, text=True, timeout=30, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        ).stdout
    except Exception:
        return set()
    home = str(paths.home).lower()
    pids = set()
    for line in out.splitlines():
        pid, _, cmd = line.partition("\t")
        if pid.strip().isdigit() and home in cmd.lower():
            pids.add(int(pid))
    return pids


def step_close(run):
    if run.dry:
        return "skip", {"dry_run": True}
    detail = {}
    if run.studio_id and run.mcp:
        try:
            con = run.tool("get_console_output", timeout=20)
            with open(os.path.join(run.outdir, "%s-console.txt" % run.sha), "w", encoding="utf-8") as f:
                f.write(con.text)
            detail["console_lines"] = len(con.text.splitlines())
            detail["console_errors"] = len([ln for ln in con.text.splitlines() if re.search(r"(?i)\berror\b", ln)])
        except Exception as e:
            log.warning("console: %r", e)
        if run.playing:
            try:
                stop_play(run)
            except Exception:
                pass
    pids = tracked_pids(run.paths)
    run.our_pids |= pids
    # Close WITHOUT saving and without any prompt: WM_CLOSE would raise Studio's
    # "Save changes?" dialog, so terminate our process trees directly (TerminateProcess
    # never shows UI and never activates a window). The .rbxl is a throwaway build.
    killed = [p for p in pids if win32.pid_alive(p) and win32.kill_pid(p, tree=True)]
    time.sleep(2)
    # Verify: none of our pids, and no Studio process whose command line opens a watcher
    # build (e.g. a child that escaped the tree) is left. Kill leftovers.
    leftovers = sorted(p for p in pids if win32.pid_alive(p))
    stray = watcher_studio_pids(run.paths)
    for p in set(leftovers) | stray:
        win32.kill_pid(p, tree=True)
    time.sleep(1)
    remaining = sorted(p for p in (set(leftovers) | stray) if win32.pid_alive(p))
    detail.update(leftovers=leftovers, stray=sorted(stray), remaining=remaining)
    if remaining:
        run.note("close: Studio processes still alive after kill: %s" % remaining)
    save_pids(run.paths, set())
    run.studio_id, run.hwnd = None, None
    run.save_current()
    run.close()
    detail.update(closed=sorted(pids), killed=killed)
    return ("fail" if detail.get("remaining") else "pass"), detail


# ---------------------------------------------------------------------------
# Report + sync
# ---------------------------------------------------------------------------

def build_report(run):
    steps = {k: run.steps[k] for k in STEP_ORDER if k in run.steps}
    status = "fail" if run.focus_stolen else overall_status(steps)
    return {
        "sha": run.sha,
        "status": status,
        "run_kind": run.run_kind,
        "publishable": run.run_kind == "full",
        "run_plan": run.run_plan,
        "checked_at": utc_now(),
        "studio_version": run.studio_version,
        "notes": "; ".join(run.notes) if run.notes else "",
        "duration_s": round(time.time() - run.t0, 1),
        "steps": steps,
        "perf": run.perf,
        "geometry": run.extra.get("geometry"),
        "bugs": run.extra.get("bugs", []),  # advisory bug probes (shots with bug_probe): {id, title, ok, summary, shot, frame}
        "frames": list(run.frames),
        "input_methods": run.extra.get("input_methods"),
        "menus": run.extra.get("menus"),
        "background": {"foreground_at_start": list(run.fg_start) if run.fg_start else None,
                       "focus_stolen": list(run.focus_stolen), "mcp_input": False},
        "watcher_version": VERSION,
    }


def report_path(run):
    return os.path.join(run.outdir, "%s.json" % run.sha)


def run_step(run, name, fn):
    if run.remaining() <= 0 and name not in ("close",):
        run.steps[name] = {"status": "skip", "seconds": 0, "detail": {"reason": "run budget exceeded"}}
        return False
    t0 = time.time()
    log.info("== step %s", name)
    try:
        status, detail = fn(run)
    except StudioBusy:
        raise
    except StepFail as e:
        status, detail = "fail", {"error": str(e)}
    except Exception as e:
        status, detail = "fail", {"error": "%r" % (e,), "trace": traceback.format_exc()[-1500:]}
    if run.check_focus(name):
        detail = dict(detail, focus_stolen=True)
    run.steps[name] = {"status": status, "seconds": round(time.time() - t0, 1), "detail": detail}
    log.info("== step %s: %s (%.1fs) %s", name, status, time.time() - t0, str(detail.get("error", ""))[:300])
    return status in ("pass", "warn")


def partial_plan(run):
    """After the build (repo at run.sha): the plan for a partial run, or a plan with run_kind "full" (upgrade)
    when there is no usable base or the changed paths need a full run. Returns (plan, base)."""
    base = (read_json(run.paths.st("last-full.json"), {}) or {}).get("sha")
    fail = lambda why: ({"run_kind": "full", "reason": why, "shots": [], "steps": [], "changed": 0,
                         "full_paths": [], "unknown_paths": []}, base)
    if not base:
        return fail("no previous full run (state/last-full.json)")
    if run.git("merge-base", "--is-ancestor", base, run.sha, check=False).returncode != 0:
        return fail("last full sha %s is not an ancestor" % base[:12])
    d = run.git("diff", "--name-only", base, run.sha, check=False)
    if d.returncode != 0:
        return fail("git diff %s..%s failed" % (base[:12], run.sha[:12]))
    changed = [x for x in d.stdout.splitlines() if x.strip()]
    shots, _ = load_shots(repo=run.paths.repo)
    smap_file = data_path(run.paths.repo, "shot-map.json")[0]
    smap = read_json(smap_file)
    if not smap or not shots:
        return fail("shot-map.json or shots/ unreadable")
    return plan_run(changed, shots, smap, run.cfg["partial_max_files"]), base


def record_full_done(paths, sha):
    write_json(paths.st("last-full.json"), {"sha": sha, "at": utc_now()})
    done = [x for x in (read_json(paths.st("full-done.json"), []) or []) if x != sha] + [sha]
    write_json(paths.st("full-done.json"), done[-50:])


def full_run(paths, cfg, sha, dry=False, run_kind="full", full_reason="manual"):
    """Steps 1-8 for one sha. Returns (report, busy). run_kind "partial" is upgraded to full when the plan says so."""
    run = Run(paths, cfg, sha, dry)
    run.run_kind = run_kind
    run.record_foreground()
    busy = False
    base = None
    run.run_plan = {"run_kind": run_kind, "reason": full_reason, "base": None, "changed": None,
                    "steps": list(STEP_ORDER), "full_paths": [], "unknown_paths": []}
    try:
        ok = run_step(run, "build", step_build)
        if ok and run_kind == "partial":
            plan, base = partial_plan(run)
            if plan["run_kind"] == "full":
                log.info("partial run upgraded to full: %s", plan["reason"])
                run.run_kind = "full"
                run.run_plan.update(reason="upgraded from partial: " + plan["reason"], base=base, changed=plan.get("changed"),
                                    full_paths=plan["full_paths"], unknown_paths=plan["unknown_paths"])
            else:
                run.run_kind = "partial"
                run.shot_filter = set(plan["shots"])
                run.run_plan = dict(plan, base=base)
                log.info("partial run: %d shots, steps %s (%s)", len(plan["shots"]), ",".join(plan["steps"]), plan["reason"])
        ok = ok and run_step(run, "launch", step_launch)
        if ok:
            if run_step(run, "play", step_play):
                run_step(run, "perf", step_perf)
                run_step(run, "geometry", step_geometry)
                run_step(run, "onboarding", step_onboarding)
                run_step(run, "shop", step_shop)
                run_step(run, "esc", step_esc)
                if run.run_kind == "partial" and "devices" not in run.run_plan["steps"]:
                    skip = {"status": "skip", "seconds": 0, "detail": {"partial": True, "reason": "partial run: not selected"}}
                    for name in DEVICE_STEPS:
                        run.steps[name] = dict(skip, detail=dict(skip["detail"]))
                else:
                    run_step(run, "devices", step_devices)
                if run.remaining() > 200:
                    run_step(run, "shots", step_shots)
            run_step(run, "two_player", step_twoplayer)
    except StudioBusy as e:
        busy = True
        run.steps["launch"] = {"status": "fail", "seconds": 0, "detail": {"error": str(e)}}
        run.note(str(e))
    finally:
        if not dry:
            try:
                run_step(run, "close", step_close)
            except Exception:
                log.exception("close")
        run.close()
    for name in STEP_ORDER:
        if name not in SOFT_STEPS:
            run.steps.setdefault(name, {"status": "skip", "seconds": 0, "detail": {"reason": "earlier step failed"}})
    if dry:
        run.note("dry-run: nothing was executed")
    close = run.steps.pop("close", None)
    report = build_report(run)
    if close:
        report["close"] = close
    write_json(report_path(run), report)
    log.info("report %s: %s %s (%ss) %s", report_path(run), report["run_kind"], report["status"], report["duration_s"], report["notes"][:300])
    if (not dry and run.run_kind == "full" and run.steps.get("shots", {}).get("status") not in (None, "skip")):
        record_full_done(paths, sha)
    return report, busy


def _stage_report(run, src_dir, sha, report, rdir):
    """Copies out/<sha> into the reports clone (frames -> JPEG with Pillow). Returns the synced report."""
    dest = os.path.join(rdir, "studio-reports")
    frames_dir = os.path.join(dest, sha)
    shutil.rmtree(frames_dir, ignore_errors=True)
    os.makedirs(frames_dir, exist_ok=True)
    synced = []
    for rec in report.get("frames", []):
        rec = dict(rec) if isinstance(rec, dict) else {"id": rec, "file": rec, "status": "captured"}
        name = rec.get("file")
        src = os.path.join(src_dir, name) if name else None
        if src and os.path.isfile(src):
            out = name
            if name.endswith(".png") and imaging.have_pillow():
                out = name[:-4] + ".jpg"
                imaging.to_jpeg(src, os.path.join(frames_dir, out), run.cfg["jpeg_quality"])
            else:
                shutil.copy2(src, os.path.join(frames_dir, out))
            rec["file"] = out
        elif name:
            rec.update(file=None, status="missing", error="frame file not found at sync")
        synced.append(rec)
    synced_report = dict(copy.deepcopy(report), frames=synced, frames_dir="%s/" % sha)
    names = {r["id"]: r["file"] for r in synced if isinstance(r, dict) and r.get("file")}
    for dev, panels in (synced_report.get("menus") or {}).items():
        for key, r in panels.items():
            if r.get("frame"):
                r["frame"] = names.get("menu-%s-%s" % (key, dev))
    for dev, r in ((synced_report.get("perf") or {}).get("phone") or {}).items():
        if r.get("frame"):
            r["frame"] = names.get("phone-perf-" + dev)
    write_json(os.path.join(dest, "%s.json" % sha), synced_report)
    return synced_report


def ensure_reports_clone(run, rdir, branch):
    """The git repo in reports\\ (origin = the repo clone's origin); created on first use."""
    url = run.git("remote", "get-url", run.cfg["remote"]).stdout.strip()
    if not os.path.isdir(os.path.join(rdir, ".git")):
        os.makedirs(rdir, exist_ok=True)
        run.git("init", "-q", "-b", branch, cwd=rdir)
        run.git("remote", "add", "origin", url, cwd=rdir)
    else:
        run.git("remote", "set-url", "origin", url, cwd=rdir)


def fetch_candidates(paths, cfg):
    """(requests, full_reports): shas publish.sh asked a full run for (studio-reports/requests/<sha>.json on the
    reports branch), and those of them that already have a report with run_kind "full". Any git failure gives
    empty sets: the loop must never crash on this."""
    requests, full = set(), set()
    try:
        run = Run(paths, cfg, None)
        branch, rdir = cfg["reports_branch"], paths.reports
        ensure_reports_clone(run, rdir, branch)
        if run.git("fetch", "-q", "origin", branch, cwd=rdir, check=False, timeout=120).returncode != 0:
            return set(), set()
        ls = run.git("ls-tree", "--name-only", "FETCH_HEAD", "studio-reports/requests/", cwd=rdir, check=False)
        if ls.returncode != 0:
            return set(), set()
        for line in ls.stdout.splitlines():
            m = re.fullmatch(r"(?:.*/)?([0-9a-f]{40})\.json", line.strip())
            if m:
                requests.add(m.group(1))
        for sha in requests:
            r = run.git("show", "FETCH_HEAD:studio-reports/%s.json" % sha, cwd=rdir, check=False)
            if r.returncode == 0:
                try:
                    if json.loads(r.stdout).get("run_kind") == "full":
                        full.add(sha)
                except Exception:
                    pass
    except Exception:
        log.exception("fetch_candidates")
        return set(), set()
    return requests, full


def recent_main(paths, cfg):
    """main's first-parent shas, newest first (cfg full_request_depth); [] on any git failure."""
    try:
        run = Run(paths, cfg, None)
        if run.git("fetch", "-q", cfg["remote"], cfg["branch"], check=False, timeout=180).returncode != 0:
            return []
        r = run.git("rev-list", "--first-parent", "-n", str(cfg["full_request_depth"]), "FETCH_HEAD", check=False)
        return r.stdout.split() if r.returncode == 0 else []
    except Exception:
        log.exception("recent_main")
        return []


def sync_report(paths, cfg, sha, dry=False):
    """Commits out/<sha> to the orphan `studio-reports` branch and pushes (retries: fetch, rebase / restage)."""
    src_dir = os.path.join(paths.out, sha)
    report = read_json(os.path.join(src_dir, "%s.json" % sha))
    if not report:
        raise StepFail("no report for %s" % sha)
    run = Run(paths, cfg, None, dry)
    if dry:
        log.info("dry-run: would push %s to %s", sha, cfg["reports_branch"])
        return True
    branch, rdir = cfg["reports_branch"], paths.reports
    ensure_reports_clone(run, rdir, branch)
    ident = ["-c", "user.name=pc-watcher", "-c", "user.email=pc-watcher@users.noreply.github.com"]

    def reset_to_remote():
        """Local branch = origin/<branch>, or a fresh orphan when the branch does not exist yet."""
        if run.git("fetch", "-q", "origin", branch, cwd=rdir, check=False).returncode == 0:
            run.git("checkout", "-q", "-f", "-B", branch, "FETCH_HEAD", cwd=rdir)
        else:
            run.git("symbolic-ref", "HEAD", "refs/heads/" + branch, cwd=rdir)
        run.git("clean", "-q", "-ffdx", cwd=rdir, check=False)

    for attempt in range(1, cfg["push_retries"] + 1):
        reset_to_remote()
        synced = _stage_report(run, src_dir, sha, report, rdir)
        run.git("add", "-A", "studio-reports", cwd=rdir)
        if run.git("diff", "--cached", "--quiet", cwd=rdir, check=False).returncode == 0:
            log.info("sync: %s already up to date on %s", sha[:12], branch)
            return True
        run.git(*ident, "commit", "-q", "-m", "studio-report %s %s %s" % (
            sha[:12], synced["status"], "full" if synced.get("run_kind") == "full" else "partial"), cwd=rdir)
        r = run.git("push", "-q", "origin", "HEAD:refs/heads/" + branch, cwd=rdir, timeout=180, check=False)
        if r.returncode == 0:
            log.info("sync: pushed %s (try %d)", sha[:12], attempt)
            return True
        log.warning("push try %d failed: %s", attempt, (r.stderr or "").strip()[-300:])
        time.sleep(5 * attempt)  # then re-fetch, restage on top of the new remote head and retry
    return False


def sync_pending(paths, cfg):
    """Retries reports whose push failed earlier (state/unsynced.json)."""
    pending = read_json(paths.st("unsynced.json"), []) or []
    left = []
    for sha in pending:
        try:
            if not sync_report(paths, cfg, sha):
                left.append(sha)
        except Exception:
            log.exception("sync %s", sha)
            left.append(sha)
    if pending != left:
        write_json(paths.st("unsynced.json"), left)


def mark_unsynced(paths, sha):
    pending = read_json(paths.st("unsynced.json"), []) or []
    if sha not in pending:
        write_json(paths.st("unsynced.json"), pending + [sha])


def remote_sha(paths, cfg):
    run = Run(paths, cfg, None)
    r = run.git("ls-remote", cfg["remote"], "refs/heads/" + cfg["branch"], timeout=60)
    sha = parse_ls_remote(r.stdout, cfg["branch"])
    if not sha:
        raise StepFail("ls-remote gave no %s" % cfg["branch"])
    return sha


# ---------------------------------------------------------------------------
# Perf measurement mode (`watcher.py perf`): run_kind "perf", never publishable
# ---------------------------------------------------------------------------

PERF_RING = 140.0  # WorldLayout.PLOT_RING_RADIUS
PERF_CAMERA = {"centre": [0.0, 0.0, 0.0], "radius": round(PERF_RING * 0.8, 1), "height": 40.0, "start_angle_rad": 0.0,
               "path": "one full orbit around the plaza centre over the window, angle = 2*pi*t/seconds, looking at the centre"}
PERF_POSE_ANGLE = 0.7854  # the proof frame's camera: an eighth of the way round
PERF_VIEWPORT = (1920, 1080)
PERF_SKILLS = ("rbx-device-simulator-lua", "rbx-perf-profiling")


def perf_frame_stats(dts):
    """Frame time stats from a list of frame times in ms. low1 / low01 = 1000 / mean of the worst 1% / 0.1% frames."""
    xs = sorted(float(x) for x in dts if x is not None and x > 0)
    n = len(xs)
    if not n:
        return {"frames": 0, "avg_fps": None, "avg_frame_ms": None, "p50_ms": None, "p95_ms": None, "p99_ms": None,
                "max_ms": None, "low1_fps": None, "low01_fps": None}

    def pct(p):
        return xs[min(n - 1, max(0, int(math.ceil(n * p)) - 1))]

    def low(frac):
        k = max(1, int(math.ceil(n * frac)))
        return 1000.0 / (sum(xs[-k:]) / k)

    mean = sum(xs) / n
    return {"frames": n, "avg_fps": round(1000.0 / mean, 2), "avg_frame_ms": round(mean, 3),
            "p50_ms": pct(0.5), "p95_ms": pct(0.95), "p99_ms": pct(0.99), "max_ms": xs[-1],
            "low1_fps": round(low(0.01), 2), "low01_fps": round(low(0.001), 2)}


def perf_client_record(raw):
    """perf_window result -> report client block (frame stats instead of the raw dt list)."""
    rec = {k: v for k, v in (raw or {}).items() if k != "dts_ms"}
    rec.update(perf_frame_stats((raw or {}).get("dts_ms") or []))
    return rec


def perf_build_report(sha, studio_version, seconds, variants, phone, notes, duration_s, error=None, pc=None, partial=False,
                      extra=None):
    """The perf report: run_kind always "perf", publishable always False, status "measured", "partial" (written while the run
    is still going) or "error" (never "pass")."""
    rep = {
        "sha": sha, "run_kind": "perf", "publishable": False,
        "status": "error" if error or not variants else ("partial" if partial else "measured"),
        "checked_at": utc_now(), "studio_version": studio_version, "watcher_version": VERSION,
        "seconds": seconds, "camera_path": dict(PERF_CAMERA, viewport=list(PERF_VIEWPORT)),
        "pc": pc or {}, "variants": variants, "phone": phone or {"skipped": True, "reason": "not requested (--phone)"},
        "notes": list(notes), "duration_s": duration_s,
    }
    rep.update(extra or {})
    if error:
        rep["error"] = str(error)[:500]
    return rep


def _fmt(v, nd=1):
    if v is None:
        return "n/a"
    if isinstance(v, float):
        return ("%." + str(nd) + "f") % v
    return str(v)


PERF_MEM_NAMES = ("PlaceMemory", "GraphicsParts", "GraphicsMeshParts", "GraphicsTerrain", "TerrainVoxels", "PhysicsParts",
                  "Instances", "LuaHeap", "GraphicsTexture")


def perf_parse_qualities(text):
    """--quality "10,1" -> [10, 1] (order kept, duplicates dropped, 1..21). ValueError on anything else."""
    out = []
    for x in str(text).split(","):
        if not x.strip():
            continue
        q = int(x)
        if not 1 <= q <= 21:
            raise ValueError("quality level %d outside 1..21" % q)
        if q not in out:
            out.append(q)
    if not out:
        raise ValueError("--quality needs at least one level")
    return out


def _enum_level(s):
    """'Enum.QualityLevel.Level10' / 'Enum.SavedQualitySetting.QualityLevel1' -> 10 / 1 (None when not a level)."""
    m = re.search(r"(\d+)\s*$", str(s or ""))
    return int(m.group(1)) if m else None


def perf_quality_record(level, raw, err=None):
    """perf_quality result -> {requested, rendering_quality, saved_quality, errors, label, applied}. label is the level when
    either route read back as requested, else "unset (Automatic)"."""
    raw = raw or {}
    rend, saved = raw.get("rendering_quality"), raw.get("saved_quality")
    ok_r, ok_s = _enum_level(rend) == level, _enum_level(saved) == level
    if ok_r and ok_s:
        label = str(level)
    elif ok_r or ok_s:
        label = "%d (%s only)" % (level, "rendering" if ok_r else "saved")
    else:
        label = "unset (Automatic)"
    errors = dict(raw.get("errors") or {})
    if err:
        errors["call"] = str(err)[:200]
    return {"requested": level, "rendering_quality": rend, "saved_quality": saved, "errors": errors,
            "label": label, "applied": ok_r or ok_s}


def perf_windows(v):
    """A variant's measurement windows [(quality record or None, client block)]; the phone block has a single `client`."""
    if v.get("windows"):
        return [(w.get("quality"), w.get("client") or {}) for w in v["windows"]]
    return [(None, v["client"])] if v.get("client") else []


def _qreq(q):
    return q.get("requested") if q else None


def perf_base_p95(rep, qreq):
    """p95 of the plain "base" variant's window at the requested quality qreq (None when missing)."""
    for v in rep.get("variants") or []:
        if v.get("label") == "base":
            for q, c in perf_windows(v):
                if _qreq(q) == qreq and c.get("p95_ms") is not None:
                    return c["p95_ms"]
    return None


def perf_delta_p95(rep, v, q, c):
    base = perf_base_p95(rep, _qreq(q))
    if v.get("label") in (None, "base", "base-early") or base is None or c.get("p95_ms") is None:
        return None
    return round(c["p95_ms"] - base, 2)


PERF_VERDICT_MIN_FILL = 0.9


def perf_added_parts(rep, v):
    """Extra BaseParts the stress clones really added for variant v: the clone count from perf_stress
    (total_extra_parts), else the server runtime_parts delta vs the settled base; None if unknown."""
    st = v.get("stress") or {}
    if isinstance(st.get("total_extra_parts"), (int, float)):
        return int(st["total_extra_parts"])
    base = next((b for b in rep.get("variants") or [] if b.get("label") == "base"), None)
    rp = lambda x: (((x or {}).get("server") or {}).get("perf") or {}).get("runtime_parts")
    if base is not None and isinstance(rp(v), (int, float)) and isinstance(rp(base), (int, float)):
        return int(rp(v) - rp(base))
    return None


def perf_verdict(rep):
    """The cap-3000 verdict line: +1000 vs base at quality 1 (p95 < 1 ms more AND draw calls <= 500), n/a on missing
    data, and INCONCLUSIVE (never PASS) unless the clones really added >= 90% of the 1000-part target."""
    d1 = dc = added = None
    target = 1000
    for v in rep.get("variants") or []:
        if v.get("label") == "+1000":
            target = v.get("extra_target") or 1000
            added = perf_added_parts(rep, v)
            for q, c in perf_windows(v):
                if _qreq(q) == 1:
                    d1, dc = perf_delta_p95(rep, v, q, c), (c.get("render") or {}).get("SceneDrawcallCount")
    yn = lambda ok: "n/a" if ok is None else ("yes" if ok else "no")
    p_ok = None if d1 is None else d1 < 1.0
    d_ok = None if dc is None else dc <= 500
    filled = added is not None and added >= PERF_VERDICT_MIN_FILL * target
    if p_ok is None or d_ok is None:
        res = "n/a"
    elif not filled:
        res = "INCONCLUSIVE (only %s of %d parts added, need >= %d%%)" % (
            _fmt(added, 0), target, int(PERF_VERDICT_MIN_FILL * 100))
    else:
        res = "PASS" if (p_ok and d_ok) else "FAIL"
    return "+1000 (%s parts added): Δp95 = %s ms (<1 ms? %s), draw calls at Q1 = %s (<=500? %s) -> 3000 cap %s" % (
        _fmt(added, 0), _fmt(d1, 2), yn(p_ok), _fmt(dc, 0), yn(d_ok), res)


def _sec_ms(x):
    """Stats.*FrameTime / HeartbeatTime are seconds; the report shows ms."""
    return None if not isinstance(x, (int, float)) else x * 1000.0


def perf_mem_cat(block, name):
    return ((block or {}).get("memory_categories") or {}).get(name)


def perf_row(rep, label, v, q, c):
    perf = (v.get("server") or {}).get("perf") or {}
    mem = (v.get("server") or {}).get("mem") or {}
    r = c.get("render") or {}
    return [label, q["label"] if q else "-", _fmt(perf.get("runtime_parts")), _fmt(perf_added_parts(rep, v) if v.get("label") not in (None, "base", "base-early") else None, 0), _fmt(perf.get("mesh_slots")),
            _fmt(c.get("avg_fps")), _fmt(c.get("low1_fps")), _fmt(c.get("p95_ms"), 2), _fmt(perf_delta_p95(rep, v, q, c), 2),
            _fmt(c.get("p99_ms"), 2), _fmt(_sec_ms(r.get("RenderCPUFrameTime")), 2), _fmt(_sec_ms(r.get("RenderGPUFrameTime")), 2),
            _fmt(r.get("SceneDrawcallCount"), 0), _fmt(r.get("ShadowsDrawcallCount"), 0),
            _fmt(r.get("SceneTriangleCount"), 0), _fmt(perf_mem_cat(c, "PlaceMemory"), 0),
            _fmt(perf_mem_cat(mem, "PlaceMemory"), 0)]


def perf_report_md(rep):
    """Markdown for <sha>-perf.md: one row per variant x quality window (+ phone), n/a where a number could not be read."""
    head = ["variant", "quality", "runtime parts", "parts added", "mesh slots", "avg fps", "1% low fps", "p95 ms", "Δp95 vs base", "p99 ms",
            "CPU ms", "GPU ms", "draw calls", "shadow draw calls", "triangles", "PlaceMemory MB (client)",
            "PlaceMemory MB (server)"]
    rows, unavailable, qlines, extras = [], {}, [], []
    for v in rep.get("variants") or []:
        label = v.get("label") or ("base" if not v.get("extra_target") else "+%d" % v["extra_target"])
        if v.get("skipped"):
            extras.append("%s: skipped (%s)" % (label, v.get("reason")))
            continue
        for q, c in perf_windows(v):
            rows.append(perf_row(rep, label, v, q, c))
            unavailable.update(c.get("render_unavailable") or {})
            if q:
                qlines.append("%s Q%s: rendering=%s saved=%s%s" % (label, q["requested"], q.get("rendering_quality"),
                              q.get("saved_quality"), " errors=%s" % json.dumps(q["errors"]) if q.get("errors") else ""))
        if v.get("note"):
            extras.append("%s: %s" % (label, v["note"]))
    ph = rep.get("phone") or {}
    if ph.get("client"):
        rows.append(perf_row(rep, "phone (emulated, base)", ph, None, ph["client"]))
        unavailable.update(ph["client"].get("render_unavailable") or {})
    lines = ["# Perf measurement %s" % (rep.get("sha") or "")[:12], "",
             "status: **%s** (run_kind perf, not publishable)  " % rep.get("status"),
             "seconds per window: %s, Studio %s, watcher %s" % (rep.get("seconds"), rep.get("studio_version"),
                                                                 rep.get("watcher_version")), "",
             "**" + perf_verdict(rep) + "**", "",
             "| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
    lines += ["| " + " | ".join(r) + " |" for r in rows]
    lines.append("")
    named = [(v.get("label"), c, (v.get("server") or {}).get("mem")) for v in rep.get("variants") or []
             if not v.get("skipped") for _q, c in perf_windows(v)[:1]]
    if any(perf_mem_cat(c, n) is not None or perf_mem_cat(m, n) is not None for _l, c, m in named for n in PERF_MEM_NAMES):
        lines += ["Memory by Stats category, MB (first quality window; n/a = category not present):", "",
                  "| variant | side | " + " | ".join(PERF_MEM_NAMES) + " |", "|" + "---|" * (2 + len(PERF_MEM_NAMES))]
        for label, c, m in named:
            for side, blk in (("client", c), ("server", m)):
                lines.append("| %s | %s | %s |" % (label, side, " | ".join(_fmt(perf_mem_cat(blk, n), 1) for n in PERF_MEM_NAMES)))
        lines.append("")
    if qlines:
        lines += ["Graphics quality read-back:"] + ["- " + x for x in qlines] + [""]
    if rep.get("settle"):
        s = rep["settle"]
        lines += ["Terrain settle: BorderTerrain set at %s s after play start, then %s s settle (boot-time = base-early, "
                  "settled = base)." % (_fmt(s.get("bt_set_at_s")), _fmt(s.get("settle_s"), 0)), ""]
    if extras:
        lines += ["Extras:"] + ["- " + x for x in extras] + [""]
    if unavailable:
        lines.append("n/a: render stats the client could not read: " + "; ".join(
            "%s (%s)" % (k, str(v)[:80]) for k, v in sorted(unavailable.items())))
        lines.append("")
    if ph.get("skipped"):
        lines.append("phone: skipped (%s)" % ph.get("reason"))
        lines.append("")
    pc = rep.get("pc") or {}
    if pc:
        lines.append("PC: %s" % ", ".join("%s %s" % (k, v) for k, v in sorted(pc.items()) if v))
        lines.append("")
    lines.append("Notes:")
    lines += ["- " + n for n in (rep.get("notes") or [])]
    lines += ["- Studio play mode on the PC (hidden desktop, 1920x1080 viewport), not a real client; numbers compare "
              "variants against each other on this PC only.",
              "- studio_process_mb (in the json) is Studio's whole process, NOT a client figure; the memory columns are "
              "the PlaceMemory category.",
              "- terrain-off vs terrain-on is an A/B inside the same play session (Terrain:Clear, nothing saved)."]
    if rep.get("error"):
        lines += ["", "error: %s" % rep["error"]]
    return "\n".join(lines) + "\n"


def perf_write(outdir, sha, rep):
    """Incremental write: <sha>-perf.json and .md (called after every window so partial results exist)."""
    write_json(os.path.join(outdir, "%s-perf.json" % sha), rep)
    with open(os.path.join(outdir, "%s-perf.md" % sha), "w", encoding="utf-8") as f:
        f.write(perf_report_md(rep))


def perf_sync_path(sha):
    """Location in the reports branch: the branch ROOT perf/<sha>/, never under studio-reports/ (box mirror, publish.sh
    and fetch_candidates only look there)."""
    return "perf/%s" % sha


def perf_pc_info():
    """cpu / gpu / ram_gb, best effort (wmic, then PowerShell; plain platform values elsewhere)."""
    info = {"cpu": platform.processor() or platform.machine(), "gpu": None, "ram_gb": None, "os": platform.platform()}
    if os.name != "nt":
        return info

    def q(args):
        try:
            r = subprocess.run(args, capture_output=True, text=True, timeout=30, creationflags=win32.NO_WINDOW)
            return [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]
        except Exception:
            return []

    def ps(cmd):
        return q(["powershell", "-NoProfile", "-NonInteractive", "-Command", cmd])

    cpu = q(["wmic", "cpu", "get", "name"])[1:] or ps("(Get-CimInstance Win32_Processor).Name")
    gpu = q(["wmic", "path", "win32_videocontroller", "get", "name"])[1:] or ps("(Get-CimInstance Win32_VideoController).Name")
    ram = q(["wmic", "computersystem", "get", "totalphysicalmemory"])[1:] or ps("(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory")
    if cpu:
        info["cpu"] = cpu[0]
    if gpu:
        info["gpu"] = "; ".join(gpu)
    try:
        info["ram_gb"] = round(int(ram[0]) / 2 ** 30, 1)
    except Exception:
        pass
    return info


def perf_set_quality(run, level):
    """Client: apply graphics quality `level` (level 0 = restore the originals). Returns the quality record."""
    ok, d = run.luau("perf_quality", "Client", 40, level=level)
    return perf_quality_record(level, d if ok and isinstance(d, dict) else None, None if ok else str(d)[:200])


def perf_measure(run, v, seconds, qualities, flush, frame_tag=None):
    """Server numbers once, then the camera-orbit window once per quality level; flush() after each window."""
    cam = PERF_CAMERA
    time.sleep(5)  # replication + streaming settle
    perf = run.need_luau("perf_server", "Server", 60)
    mem = run.need_luau("perf_mem", "Server", 60)
    v["server"] = {"perf": perf, "mem": mem}
    v.setdefault("windows", [])
    for level in qualities:
        q = perf_set_quality(run, level)
        raw = run.need_luau("perf_window", "Client", seconds + 30, seconds=seconds, centre=tuple(cam["centre"]),
                            radius=cam["radius"], height=cam["height"])
        v["windows"].append({"quality": q, "client": perf_client_record(raw)})
        flush()
    if frame_tag:
        try:
            run.need_luau("perf_pose", "Client", 30, on=True, angle=PERF_POSE_ANGLE, centre=tuple(cam["centre"]),
                          radius=cam["radius"], height=cam["height"])
            v["frame"] = capture_frame(run, frame_tag, kind="perf", extra=v.get("extra_target") or 0).get("file")
        except Exception as e:
            run.note("%s proof frame failed: %r" % (frame_tag, e))
            v["frame"] = None
        finally:
            try:
                run.luau("perf_pose", "Client", 30, on=False, angle=0.0, centre=tuple(cam["centre"]),
                         radius=cam["radius"], height=cam["height"])
            except Exception:
                pass
        flush()
    return v


def perf_variant(run, n, seconds, qualities, variants, flush, hold_frame=True):
    """One priority variant: stress to >= n extra parts (cumulative), then perf_measure."""
    v = {"label": "base" if not n else "+%d" % n, "extra_target": n}
    variants.append(v)
    v["stress"] = run.need_luau("perf_stress", "Server", 180, target=n)
    return perf_measure(run, v, seconds, qualities, flush, "perf-%d" % n if hold_frame else None)


def perf_terrain_wait(run, play_t0, max_s=120, settle_s=60, poll_s=2):
    """Poll luau/perf_terrain_attr until the border terrain is done: Workspace BorderTerrainReady == true (#267), else the
    older workspace.Terrain BorderTerrain == true; for up to max_s, then settle_s more. Returns {bt_set, bt_set_at_s
    (since play_t0, ~poll_s resolution), bt_source ("BorderTerrainReady" | "BorderTerrain"), settle_s, max_s}."""
    t0 = time.time()
    rec = {"bt_set": False, "bt_set_at_s": None, "bt_source": None, "settle_s": 0, "max_s": max_s}
    while True:
        ok, d = run.luau("perf_terrain_attr", "Server", 30)
        if ok and isinstance(d, dict) and d.get("set"):
            rec["bt_set"], rec["bt_set_at_s"] = True, round(time.time() - play_t0, 1)
            rec["bt_source"] = d.get("source") or "BorderTerrain"
            break
        if time.time() - t0 >= max_s:
            break
        time.sleep(poll_s)
    if rec["bt_set"]:
        time.sleep(settle_s)
        rec["settle_s"] = settle_s
    else:
        run.note("BorderTerrainReady / BorderTerrain attribute not true after %ss: no settle wait" % max_s)
    return rec


def perf_extras(run, opts, seconds, qualities, variants, flush):
    """Optional extras after the priority variants, each its own labelled variant; a failing extra is recorded, not fatal."""
    def clean():
        try:
            run.luau("perf_clean", "Server", 60)
        except Exception as e:
            run.note("perf clone cleanup failed: %r" % (e,))

    def guarded(v, f):
        try:
            f()
        except StudioBusy:
            raise
        except Exception as e:
            v["error"] = str(e)[:300]
            run.note("%s failed: %s" % (v["label"], v["error"]))
            flush()

    if opts.get("meshparts"):
        n = opts["meshparts"]
        clean()
        v = {"label": "+%d meshparts" % n, "extra_target": 0, "extra_meshparts": n}
        variants.append(v)

        def go():
            v["stress"] = run.need_luau("perf_meshclone", "Server", 180, target=n)
            perf_measure(run, v, seconds, qualities, flush)
        guarded(v, go)
    if opts.get("unique_meshes"):
        n = opts["unique_meshes"]
        clean()
        v = {"label": "+%d unique meshes" % n, "extra_target": 0}
        variants.append(v)

        def go():
            r = run.need_luau("perf_unique", "Server", 180, count=n)
            v["stress"] = r
            if r.get("skipped"):
                v["skipped"], v["reason"] = True, r.get("reason")
                flush()
            else:
                perf_measure(run, v, seconds, qualities, flush)
        guarded(v, go)
    if opts.get("terrain_off"):
        clean()
        on = {"label": "terrain-on", "extra_target": 0, "note": "A/B in the same play session, window taken just before Terrain:Clear"}
        variants.append(on)
        guarded(on, lambda: perf_measure(run, on, seconds, qualities, flush))
        off = {"label": "terrain-off", "extra_target": 0,
               "note": "A/B in the same play session: workspace.Terrain:Clear() (play only, nothing saved) after terrain-on"}
        variants.append(off)

        def go():
            off["clear"] = run.need_luau("perf_terrain_clear", "Server", 60)
            perf_measure(run, off, seconds, qualities, flush)
        guarded(off, go)
    clean()


def perf_phone_skills(run):
    """--phone, before the variants: both skill texts into out/perf/<sha>/skills/*.md. Returns (record, texts)."""
    sdir = os.path.join(run.outdir, "skills")
    os.makedirs(sdir, exist_ok=True)
    texts, errors = {}, {}
    for name in PERF_SKILLS:
        try:
            r = run.session().call("skill", {"skill_name": name}, timeout=60)
            if not r.ok:
                r = run.tool("skill", timeout=60, skill_name=name)
            if r.ok and r.text:
                texts[name] = r.text
                with open(os.path.join(sdir, name + ".md"), "w", encoding="utf-8") as f:
                    f.write(r.text)
            else:
                errors[name] = r.brief(200)
        except Exception as e:
            errors[name] = repr(e)[:200]
    return {"skills_fetched": sorted(texts), "skill_errors": errors}, texts


def perf_phone(run, seconds, pre):
    """--phone, after the variants: the base window once more under device emulation, only when the device simulator
    skill documents a Luau emulator API usable from execute_luau. Best effort, labelled in the report."""
    out, texts = pre
    errors = out["skill_errors"]
    text = texts.get("rbx-device-simulator-lua", "")
    if not re.search(r"StudioDeviceEmulatorService|DeviceEmulator", text):
        return dict(out, skipped=True, reason="the rbx-device-simulator-lua skill documents no Luau device emulator API "
                    "usable from execute_luau (input / plugin UI only)" if text else "skill text not available: %s" % errors)
    m = re.search(r"SetDeviceById\(\s*[\"']([^\"']+)", text)
    device = m.group(1) if m else ""
    emu = None
    for dm in ("Client", "Server", "Edit"):
        ok, d = run.luau("perf_phone_emulate", dm, 30, device=device)
        if ok:
            emu = dict(d, datamodel=dm)
            if d.get("emulated"):
                break
    if not emu or not emu.get("emulated"):
        return dict(out, skipped=True, reason="emulator call did not succeed", emulate=emu)
    cam = PERF_CAMERA
    raw = run.need_luau("perf_window", "Client", seconds + 30, seconds=seconds, centre=tuple(cam["centre"]),
                        radius=cam["radius"], height=cam["height"])
    return dict(out, emulated=True, emulate=emu, extra_target=0, client=perf_client_record(raw),
                note="Studio device emulator via execute_luau, best effort; still a PC render, not phone hardware")


def sync_perf(paths, cfg, sha, files_dir, report, dry=False):
    """Pushes files_dir (report json + md + frames) to branch studio-reports at perf/<sha>/ from <home>/perf-reports."""
    run = Run(paths, cfg, None, dry)
    sub = perf_sync_path(sha)
    if dry:
        log.info("dry-run: would push %s to %s:%s", sha, cfg["reports_branch"], sub)
        return True
    branch, rdir = cfg["reports_branch"], paths.perf_reports
    ensure_reports_clone(run, rdir, branch)
    ident = ["-c", "user.name=pc-watcher", "-c", "user.email=pc-watcher@users.noreply.github.com"]
    for attempt in range(1, cfg["push_retries"] + 1):
        if run.git("fetch", "-q", "origin", branch, cwd=rdir, check=False).returncode == 0:
            run.git("checkout", "-q", "-f", "-B", branch, "FETCH_HEAD", cwd=rdir)
        else:
            run.git("symbolic-ref", "HEAD", "refs/heads/" + branch, cwd=rdir)
        run.git("clean", "-q", "-ffdx", cwd=rdir, check=False)
        dest = os.path.join(rdir, *sub.split("/"))
        shutil.rmtree(dest, ignore_errors=True)
        os.makedirs(dest, exist_ok=True)
        for name in sorted(os.listdir(files_dir)):
            src = os.path.join(files_dir, name)
            if os.path.isfile(src):
                if name.endswith(".png") and imaging.have_pillow():
                    imaging.to_jpeg(src, os.path.join(dest, name[:-4] + ".jpg"), cfg["jpeg_quality"])
                else:
                    shutil.copy2(src, os.path.join(dest, name))
            elif os.path.isdir(src):
                shutil.copytree(src, os.path.join(dest, name))
        run.git("add", "-A", sub, cwd=rdir)
        if run.git("diff", "--cached", "--quiet", cwd=rdir, check=False).returncode == 0:
            log.info("perf sync: %s already up to date on %s", sha[:12], branch)
            return True
        run.git(*ident, "commit", "-q", "-m", "perf-report %s run_kind=perf" % sha[:12], cwd=rdir)
        r = run.git("push", "-q", "origin", "HEAD:refs/heads/" + branch, cwd=rdir, timeout=180, check=False)
        if r.returncode == 0:
            log.info("perf sync: pushed %s (try %d)", sha[:12], attempt)
            return True
        log.warning("perf push try %d failed: %s", attempt, (r.stderr or "").strip()[-300:])
        time.sleep(5 * attempt)
    return False


def cmd_perf(paths, cfg, sha, extras, seconds, sync, wait_lock_s, phone, dry, qualities=(10, 1), opts=None):
    """Perf measurement for one sha: build, play, then a fixed camera orbit per extra-parts variant. Own report under
    out/perf/<sha>/, pushed to perf/<sha>/ on the reports branch. Shares only run.lock with the loop."""
    lock = Lock(paths.st("run.lock"))
    waited = time.time()
    while not lock.acquire():
        if time.time() - waited >= wait_lock_s:
            log.error("perf: run.lock still held after %ss, giving up", wait_lock_s)
            return 3
        log.info("perf: another run holds %s, waiting (polling every 15 s)", lock.path)
        time.sleep(15)
    run = None
    try:
        sha = sha or remote_sha(paths, cfg)
        seconds = max(30, int(seconds))
        extras = sorted(set(int(x) for x in extras) | {0})
        run = Run(paths, cfg, sha, dry, kind="perf")
        run.cfg = dict(cfg, run_budget_s=10 ** 6)  # the 15 min full-run budget does not apply
        log.info("perf %s: extras %s, %ss per window", sha, extras, seconds)
        run.record_foreground()
        opts = opts or {}
        qualities = list(qualities)
        variants, phone_rec, error, phone_pre, settle = [], None, None, None, None
        pc_info = perf_pc_info()
        rep_extra = {"qualities": qualities, "extras_requested": dict(opts)}

        def flush(final=False):
            """Rewrites <sha>-perf.json/.md (status "partial" until final)."""
            extra = dict(rep_extra, settle=settle,
                         variants_frames=[f for f in (v.get("frame") for v in variants) if f])
            rep = perf_build_report(sha, run.studio_version, seconds, variants, phone_rec, run.notes,
                                    round(time.time() - run.t0, 1), error, pc_info, partial=not final, extra=extra)
            perf_write(run.outdir, sha, rep)
            return rep

        try:
            step_build(run)
            if dry:
                raise StepFail("dry-run: build only")
            step_launch(run)
            start_play(run)
            play_t0 = time.time()
            hwnd = run.hwnd or (run.desktop().main_window(tracked_pids(paths)) or {}).get("hwnd")
            if hwnd:
                vp, _ = converge_viewport(run, hwnd, PERF_VIEWPORT)
                run.note("viewport %dx%d (wanted %dx%d)" % (vp[0], vp[1], PERF_VIEWPORT[0], PERF_VIEWPORT[1]))
            else:
                run.note("no Studio window found: viewport left as is")
            if phone:
                try:
                    phone_pre = perf_phone_skills(run)
                except Exception as e:
                    phone_pre = ({"skills_fetched": [], "skill_errors": {"all": repr(e)[:200]}}, {})
            # boot-time window (first quality only), then wait for BorderTerrain + settle before the priority variants
            early = {"label": "base-early", "extra_target": 0, "stress": None}
            variants.append(early)
            perf_measure(run, early, seconds, qualities[:1], flush)
            settle = perf_terrain_wait(run, play_t0)
            flush()
            for n in extras:
                perf_variant(run, n, seconds, qualities, variants, flush)
            if any(opts.get(k) for k in ("meshparts", "unique_meshes", "terrain_off")):
                perf_extras(run, opts, seconds, qualities, variants, flush)
            try:
                run.luau("perf_clean", "Server", 60)
            except Exception as e:
                run.note("perf clone cleanup failed: %r" % (e,))
            if phone:
                phone_rec = perf_phone(run, seconds, phone_pre)
        except StudioBusy as e:
            error = "studio busy: %s" % e
        except StepFail as e:
            error = str(e)
        except Exception as e:
            error = "%r" % (e,)
            log.error("perf: %s", traceback.format_exc()[-1500:])
        finally:
            if not dry:
                try:
                    perf_set_quality(run, 0)  # restore the original quality settings (no-op if play is gone)
                except Exception:
                    pass
                try:
                    step_close(run)
                except Exception:
                    log.exception("close")
            run.close()
        rep = flush(final=True)
        log.info("perf report %s: %s (%ss)", run.outdir, rep["status"], rep["duration_s"])
        if sync and cfg["sync"] and not dry and rep["status"] == "measured":
            try:
                if not sync_perf(paths, cfg, sha, run.outdir, rep):
                    log.error("perf sync failed (report stays in %s)", run.outdir)
                    return 1
            except Exception:
                log.exception("perf sync")
                return 1
        return 0 if rep["status"] == "measured" else 1
    finally:
        lock.release()


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_once(paths, cfg, sha, dry, sync=True, run_kind="full", full_reason="manual"):
    lock = Lock(paths.st("run.lock"))
    if not lock.acquire():
        log.error("another watcher run holds %s", lock.path)
        return 3, None  # nothing ran (busy None): the loop retries next tick instead of marking the sha done
    try:
        sha = sha or remote_sha(paths, cfg)
        log.info("run %s (%s: %s)", sha, run_kind, full_reason)
        report, busy = full_run(paths, cfg, sha, dry, run_kind=run_kind, full_reason=full_reason)
        if sync and cfg["sync"] and not dry:
            try:
                synced = sync_report(paths, cfg, sha)
            except Exception:
                log.exception("sync")
                synced = False
            if not synced:
                log.error("sync failed for %s (report stays in %s; retried next loop)", sha, paths.out)
                mark_unsynced(paths, sha)
        return (0 if report["status"] == "pass" else 1), busy
    finally:
        lock.release()


def cmd_loop(paths, cfg, dry):
    loop_lock = Lock(paths.st("loop.lock"), max_age=10 ** 9)
    if not loop_lock.acquire():
        log.error("a watcher loop is already running (%s)", loop_lock.path)
        return 3
    log.info("loop: polling %s/%s every %ss (partial_runs %s, full_schedule %s)",
             cfg["remote"], cfg["branch"], cfg["poll_s"], cfg["partial_runs"], cfg.get("full_schedule"))
    busy_until = 0
    loop_t0 = time.time()
    attempted = {}  # sha -> time of the last full attempt (a failed run that never synced must not spin)
    try:
        while True:
            try:
                if cfg["sync"] and not dry:
                    sync_pending(paths, cfg)
                tip = remote_sha(paths, cfg)
                now = time.time()
                seen = read_json(paths.st("tip-seen.json"), {}) or {}
                if seen.get("sha") != tip:
                    seen = {"sha": tip, "at": now}
                    write_json(paths.st("tip-seen.json"), seen)
                last = read_json(paths.st("last-sha.json"), {}) or {}
                requests, remote_full = fetch_candidates(paths, cfg)
                full_done = set(read_json(paths.st("full-done.json"), []) or []) | remote_full
                full_done |= {k for k, t in attempted.items() if now - t < 1800}
                order = recent_main(paths, cfg) if requests - full_done else []
                sched_slot = due_schedule_slot(now, cfg.get("full_schedule"),
                                               (read_json(paths.st("schedule-done.json"), {}) or {}).get("slot"),
                                               cfg.get("full_schedule_grace_s", 10800))
                if sched_slot and tip in full_done and not dry:  # the tip already has a full report: slot satisfied
                    write_json(paths.st("schedule-done.json"), {"slot": sched_slot, "sha": tip, "at": utc_now()})
                    log.info("loop: schedule slot %s satisfied (tip %s already has a full report)", sched_slot, tip[:12])
                    sched_slot = None
                kind, sha, why = choose_work(tip, last.get("sha"), last.get("ts", loop_t0), requests, full_done, order,
                                             now, cfg, seen.get("at", now), sched_slot)
                if kind is None:
                    log.info("loop: %s (tip %s)", why, tip[:12])
                elif now < busy_until:
                    log.info("loop: %s %s (%s) held back: studio busy", kind, sha[:12], why)
                else:
                    log.info("loop: %s run of %s (%s)", kind, sha[:12], why)
                    rc, busy = cmd_once(paths, cfg, sha, dry, sync=True, run_kind=kind, full_reason=why)
                    if busy is None:  # run.lock held by another run (e.g. a manual `once`): retry next tick
                        log.info("loop: run.lock held by another run; %s %s retried next tick", kind, sha[:12])
                    elif busy:
                        busy_until = time.time() + cfg["busy_retry_s"]
                        log.info("studio busy; retry %s in %ss", sha[:12], cfg["busy_retry_s"])
                    else:
                        if kind == "full":
                            attempted[sha] = now
                        if sched_slot and why.startswith("scheduled full") and not dry:
                            write_json(paths.st("schedule-done.json"), {"slot": sched_slot, "sha": sha, "at": utc_now()})
                            log.info("loop: schedule slot %s done (full run of %s)", sched_slot, sha[:12])
                        if not dry and sha == tip:  # a full run of an older requested sha leaves last-sha alone
                            write_json(paths.st("last-sha.json"), {"sha": sha, "at": utc_now(), "ts": time.time()})
            except Exception:
                log.exception("loop iteration")
            time.sleep(cfg["poll_s"])
    except KeyboardInterrupt:
        return 0
    finally:
        loop_lock.release()


STEP_FNS = {
    "build": step_build, "launch": step_launch, "perf": step_perf, "geometry": step_geometry, "play": step_play,
    "devices": step_devices, "shots": step_shots, "twoplayer": step_twoplayer, "close": step_close,
}


def cmd_step(paths, cfg, name, sha, dry):
    if name == "sync":
        sha = sha or (read_json(paths.st("current.json"), {}) or {}).get("sha")
        if not sha:
            log.error("step sync needs --sha")
            return 2
        return 0 if sync_report(paths, cfg, sha, dry) else 1
    if name == "build" and not sha:
        sha = remote_sha(paths, cfg)
    run = Run(paths, cfg, sha, dry)
    run.record_foreground()
    run.load_current()
    if not run.sha:
        log.error("no sha: pass --sha or run `step build` first")
        return 2
    if name not in ("build", "launch", "close") and not run.studio_id and not dry:
        log.error("no watcher Studio in state/current.json: run `step launch` first")
        return 2
    if name not in ("build", "launch") and run.studio_id and not dry:
        found, _, _ = find_our_studio(run, run.session())
        if found:
            run.studio_id = found["id"]
    if name == "play":
        steps = [("play", step_play), ("perf", step_perf), ("geometry", step_geometry), ("onboarding", step_onboarding), ("shop", step_shop),
                 ("esc", step_esc)]
    elif name in ("perf", "geometry", "devices", "shots"):
        steps = [(name, STEP_FNS[name])]
        if not dry:
            ok, d = run.luau("client_ready", "Client", timeout=15)
            if not (ok and d.get("ready")):
                start_play(run)
    else:
        steps = [(name, STEP_FNS[name])]
    try:
        for sname, fn in steps:
            run.steps.pop(sname, None)
            try:
                run_step(run, sname, fn)
            except StudioBusy as e:
                run.steps[sname] = {"status": "fail", "detail": {"error": str(e)}}
    finally:
        run.save_current() if name != "close" else None
        run.close()
    print(json.dumps({"steps": run.steps, "perf": run.perf, "frames": run.frames, "notes": run.notes,
                      "focus_stolen": run.focus_stolen, "mcp_input": False}, indent=2, default=str))
    if run.focus_stolen:
        return 1
    return 0 if all(s["status"] in ("pass", "warn", "skip") for s in run.steps.values()) else 1


def cmd_mcp(paths, cfg, tool, args_json):
    run = Run(paths, cfg, None)
    run.load_current()
    args = json.loads(args_json) if args_json else {}
    for k, v in list(args.items()):
        if v == "$studio":
            args[k] = run.studio_id
    try:
        if tool == "tools":
            print(json.dumps(run.session().schemas, indent=2))
            return 0
        r = run.session().call(tool, args, timeout=120)
        out = {"isError": r.is_error, "error": r.error, "text": r.text, "structured": r.structured,
               "images": [(m, len(d)) for m, d in r.images]}
        print(json.dumps(out, indent=2, default=str)[:200000])
        return 0 if r.ok else 1
    finally:
        run.close()


def cmd_capture(paths, cfg, out):
    run = Run(paths, cfg, None)
    run.load_current()
    if not run.studio_id:
        print("no watcher Studio in state/current.json")
        return 1
    try:
        shot = run.tool("screen_capture", timeout=60, capture_id="pcw-capture-%d" % int(time.time()))
        img = shot.image_bytes()
        if not img:
            print("capture failed: %s" % shot.brief(200))
            return 1
        out = out or os.path.join(paths.out, "capture-test.jpg")
        with open(out, "wb") as f:
            f.write(img[1])
        stats = imaging.jpeg_stats(img[1])
        print(json.dumps({"file": out, "method": "mcp_screen_capture", "mime": img[0], "bytes": len(img[1]),
                          "blank": bool(stats) and imaging.is_blank(stats), "stats": stats}, indent=2))
        return 0
    finally:
        run.close()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--home", default=os.environ.get("PCW_HOME", r"C:\gate\pc-watcher"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_once = sub.add_parser("once")
    p_once.add_argument("--sha")
    p_once.add_argument("--no-sync", action="store_true")
    p_once.add_argument("--kind", choices=("full", "partial"), default="full")
    p_once.add_argument("--reason", default="manual")
    p_perf = sub.add_parser("perf", help="perf measurement (run_kind perf, never publishable)")
    p_perf.add_argument("--sha")
    p_perf.add_argument("--extra", default="0,500,1000", help="comma list of extra runtime parts, cumulative (0 = base)")
    p_perf.add_argument("--seconds", type=int, default=30)
    p_perf.add_argument("--no-sync", action="store_true")
    p_perf.add_argument("--wait-lock-s", type=int, default=3600)
    p_perf.add_argument("--phone", action="store_true")
    p_perf.add_argument("--quality", default="10,1", help="graphics quality levels (1-21), one orbit window per level and variant")
    p_perf.add_argument("--meshparts", type=int, default=0, help="extra: clone N existing MeshParts (same MeshIds)")
    p_perf.add_argument("--unique-meshes", type=int, default=0, help="extra, best effort: N MeshParts with a new MeshId at runtime")
    p_perf.add_argument("--terrain-off", action="store_true", help="extra: terrain-on vs terrain-off A/B (Terrain:Clear, play only)")
    sub.add_parser("loop")
    p_step = sub.add_parser("step")
    p_step.add_argument("name", choices=sorted(list(STEP_FNS) + ["sync"]))
    p_step.add_argument("--sha")
    sub.add_parser("tools")
    p_mcp = sub.add_parser("mcp")
    p_mcp.add_argument("tool")
    p_mcp.add_argument("args", nargs="?")
    p_cap = sub.add_parser("capture")
    p_cap.add_argument("--out")
    sub.add_parser("selftest")
    a = ap.parse_args(argv)

    if a.cmd == "selftest":
        import selftest
        return selftest.main()
    paths = Paths(a.home)
    setup_logging(paths, a.verbose)
    cfg = load_config(paths)
    win32.set_dpi_aware()
    log.info("pc-watcher %s: %s (home %s%s)", VERSION, a.cmd, paths.home, ", dry-run" if a.dry_run else "")
    sha = getattr(a, "sha", None)
    if sha and not re.fullmatch(r"[0-9a-f]{40}", sha):
        log.error("--sha must be a full 40-char sha")
        return 2
    if a.cmd == "once":
        return cmd_once(paths, cfg, a.sha, a.dry_run, sync=not a.no_sync, run_kind=a.kind, full_reason=a.reason)[0]
    if a.cmd == "perf":
        try:
            extras = [int(x) for x in a.extra.split(",") if x.strip()]
        except ValueError:
            log.error("--extra must be a comma list of integers")
            return 2
        try:
            qualities = perf_parse_qualities(a.quality)
        except ValueError as e:
            log.error("--quality: %s", e)
            return 2
        opts = {k: v for k, v in (("meshparts", a.meshparts), ("unique_meshes", a.unique_meshes),
                                  ("terrain_off", a.terrain_off)) if v}
        return cmd_perf(paths, cfg, a.sha, extras, a.seconds, not a.no_sync, a.wait_lock_s, a.phone, a.dry_run, qualities, opts)
    if a.cmd == "loop":
        return cmd_loop(paths, cfg, a.dry_run)
    if a.cmd == "step":
        return cmd_step(paths, cfg, a.name, a.sha, a.dry_run)
    if a.cmd == "tools":
        return cmd_mcp(paths, cfg, "tools", None)
    if a.cmd == "mcp":
        return cmd_mcp(paths, cfg, a.tool, a.args)
    if a.cmd == "capture":
        return cmd_capture(paths, cfg, a.out)
    return 2


def _main_logged(argv=None):
    """pythonw has no stderr: log any crash before exiting (a silent perf crash once released run.lock unnoticed)."""
    try:
        return main(argv)
    except SystemExit:
        raise
    except Exception:
        log.exception("watcher crashed")
        raise


if __name__ == "__main__":
    sys.exit(_main_logged())
