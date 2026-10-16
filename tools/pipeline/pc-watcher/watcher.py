#!/usr/bin/env python3
"""Steal a Slime PC watcher: Studio checks for every new origin/main sha, on Merijn's PC.

  watcher.py loop                       poll `git ls-remote` every 60 s, run new shas
  watcher.py once [--sha SHA]           full run for one sha (default: origin/main), ignores last-sha
  watcher.py step build|launch|perf|play|devices|twoplayer|close|sync [--sha SHA]
  watcher.py tools                      dump StudioMCP tool schemas (needs a running Studio for most calls)
  watcher.py mcp TOOL [JSON_ARGS]       one raw tools/call ("$studio" in args = the watcher's studio id)
  watcher.py capture [--out f.png]      capture the watcher's Studio window client area
  watcher.py selftest                   pure checks, any OS
Global flags: --home DIR (default C:\\gate\\pc-watcher or $PCW_HOME), --dry-run, -v.

Studio is driven only through StudioMCP.exe (stdio JSON-RPC) plus Win32 for window size and
capture. It runs in the background: Studio starts minimized-not-active, lives off-screen, is
captured with PrintWindow and never gets focus or real mouse/keyboard input (README "Runs in the
background"). See README.md for the flow, report format and limits.
"""

import argparse
import copy
import datetime
import json
import logging
import logging.handlers
import math
import os
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
    "run_budget_s": 600,
    "mesh_slot_budget": 400,
    "launch_timeout_s": 120,
    "client_timeout_s": 90,
    "stats_seconds": 5,
    "devices": [["desktop", 1920, 1080], ["phone-portrait", 390, 844], ["phone-landscape", 844, 390]],
    "device_iterations": 5,
    "menu_panels": ["plot", "merge", "shop", "rebirth", "goals", "dex", "leaders", "guide"],  # src/ui/init.client allPanels
    "phone_min_fps": 30,  # phone_perf fails below this average FPS (Studio on a PC, not phone hardware)
    "phone_min_slimes": 16,  # SlimeLife.MAX_ACTIVE: animating slimes wanted near the camera
    # kind (mouse_down, mouse_up, key_down, key_up) -> action template, "$x" / "$y" / "$key" filled in.
    # Empty = built from the tool's inputSchema (see mcp_client.build_action).
    "input_overrides": {},
    "reports_branch": "studio-reports",
    "push_retries": 3,
    "jpeg_quality": 80,
    "sync": True,
}

# A step outside these that ends "fail" still fails the run; these also fail it when skipped.
HARD_STEPS = ("build", "launch", "perf", "geometry", "play", "onboarding", "shop", "esc", "devices", "menus", "phone_perf")
STEP_ORDER = ("build", "launch", "perf", "geometry", "play", "onboarding", "shop", "esc", "devices", "menus", "phone_perf", "two_player", "shots")
SOFT_STEPS = ("shots",)  # never fail the run; missing = fine
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


def cursor_delta(before, after):
    """(dx, dy, distance in px) between two GetCursorPos points."""
    dx, dy = after[0] - before[0], after[1] - before[1]
    return dx, dy, math.hypot(dx, dy)


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
    """Eye/at for a shots.json "from" entry: the eye stands `dist` studs from the target (flat) on the side
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
    """TODO item number(s) of a shots.json entry: its "todo", else "TODO 6/13:" at the start of its note."""
    if shot.get("todo"):
        return str(shot["todo"])
    m = re.match(r"\s*TODO\s+([\d/]+)", str(shot.get("note") or ""))
    return m.group(1) if m else None


def viewport_error(vp, target):
    return abs(vp[0] - target[0]) + abs(vp[1] - target[1])


def overall_status(steps):
    for name, s in steps.items():
        st = s.get("status")
        if name in SOFT_STEPS:
            continue
        if st == "fail":
            return "fail"
        if name in HARD_STEPS and st not in ("pass", "warn"):
            return "fail"
    for name in HARD_STEPS:
        if name not in steps:
            return "fail"
    return "pass"


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


def write_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=False)
        f.write("\n")
    os.replace(tmp, path)


class Lock:
    """Exclusive lock file holding our pid; a lock whose pid is gone (or older than max_age) is stale."""

    def __init__(self, path, max_age=1800):
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
    def __init__(self, paths, cfg, sha, dry=False):
        self.paths, self.cfg, self.sha, self.dry = paths, cfg, sha, dry
        self.t0 = time.time()
        self.notes = []
        self.steps = {}
        self.perf = {"mesh_slots": None, "unique_meshes": None, "budget": cfg["mesh_slot_budget"],
                     "frame_time_ms": None, "memory_mb": None}
        self.frames = []
        self.extra = {}
        self.studio_dir = None
        self.studio_version = None
        self.mcp = None
        self.studio_id = None
        self.hwnd = None
        self.rbxl = os.path.join(paths.builds, "%s.rbxl" % sha) if sha else None
        self.outdir = os.path.join(paths.out, "dry-run" if dry else "", sha) if sha else None
        self.playing = False
        self.our_pids = set()  # every Studio pid this run started (focus guard)
        self.fg_start = None  # (hwnd, pid) of the foreground window when the run began
        self.focus_stolen = []  # "FOCUS STOLEN at step X"
        self.input_ok = True  # MCP input allowed (off once a call moved the OS cursor)
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

    def _mcp_input(self, what, fn):
        """One StudioMCP input call with the OS-cursor guard.

        user_mouse_input / user_keyboard_input inject into the engine, not via OS SendInput. The
        cursor position is read before and after; if it moved, MCP input is off for the rest of
        the run and callers fall back to setting panels Visible.
        """
        if not self.input_ok:
            return False, {"error": "mcp input disabled: mcp input moved OS cursor"}
        before = _cursor()
        ok, info = fn()
        after = _cursor()
        if before is not None and after is not None and before != after:
            self.input_ok = False
            dx, dy, dist = cursor_delta(before, after)
            info["os_cursor_moved"] = [list(before), list(after)]
            info["os_cursor_delta_px"] = [dx, dy, round(dist, 1)]
            self.extra.setdefault("cursor_events", []).append(
                {"call": what, "before": list(before), "after": list(after), "delta": [dx, dy], "dist_px": round(dist, 1)})
            self.note("mcp input moved OS cursor (%s: %s -> %s, delta %+d,%+d = %.0f px; a small delta can be the "
                      "user moving the mouse); MCP input disabled for the rest of the run, panels set Visible "
                      "instead" % (what, before, after, dx, dy, dist))
        return ok, info

    def click(self, x, y):
        return self._mcp_input("click %d,%d" % (round(x), round(y)),
                               lambda: self.session().click(self.studio_id, x, y, self.cfg["input_overrides"]))

    def key(self, key):
        return self._mcp_input("key " + key,
                               lambda: self.session().key(self.studio_id, key, self.cfg["input_overrides"]))

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

    def luau(self, name, datamodel="Edit", timeout=60, **subs):
        with open(os.path.join(HERE, "luau", name + ".luau"), encoding="utf-8") as f:
            body = f.read()
        for k, v in subs.items():
            body = body.replace("%%" + k.upper() + "%%", luau_literal(v))
        ok, data, _ = self.session().luau(self.studio_id, body, datamodel, timeout=timeout)
        log.debug("luau %s/%s ok=%s %s", name, datamodel, ok, json.dumps(data)[:600])
        return ok, data

    def need_luau(self, name, datamodel="Edit", timeout=60, **subs):
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

    def close(self):
        if self.mcp:
            self.mcp.close()
            self.mcp = None


def _cursor():
    if os.name != "nt":
        return None
    try:
        return win32.cursor_pos()
    except Exception:
        return None


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
    proc = win32.launch_background([exe, run.rbxl], cwd=run.studio_dir)  # SW_SHOWMINNOACTIVE
    ours = {proc.pid}
    run.our_pids |= ours

    def grow(pids):
        # Only processes descending from the one we started (never a Studio the user opens meanwhile).
        return win32.descendants(win32.process_table(), pids) & (set(win32.list_pids()) | pids)

    save_pids(run.paths, ours)
    log.info("launched Studio pid %s (minimized, not activated): %s", proc.pid, run.rbxl)
    mcp = run.session()
    deadline = time.time() + run.cfg["launch_timeout_s"]
    found, last = None, None
    while time.time() < deadline:
        ours = grow(ours)
        run.our_pids |= ours
        save_pids(run.paths, ours)
        park_window(run, ours)
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
        win = park_window(run, ours)
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


def park_window(run, pids):
    """Finds the Studio main window of `pids` (iconic ones too) and moves it off-screen, un-minimized,
    without activating it (win32.place_offscreen). Returns the window row or None."""
    try:
        win = win32.studio_main_window(pids)
        if not win:
            return None
        for p in pids:
            win32.disable_power_throttling(p)
        if win["iconic"] or not win32.is_offscreen(win["hwnd"]):
            rect = win32.place_offscreen(win["hwnd"])
            log.info("parked Studio window %s (%r) off-screen at %s", win["hwnd"], win["title"], rect)
        return win
    except Exception as e:
        log.warning("park window: %r", e)
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
    if d.get("datastore_mode") != "Memory":
        raise StepFail("could not put the session on DataStoreMode=Memory")
    if d.get("datastore_mode_before") != "Memory":
        run.note("build lacked DataStoreMode=Memory; set it in the Edit session (not saved)")
    return d


def step_perf(run):
    """Mesh slots in the Server datamodel once MeshSwap has settled (Edit has none: see perf_server.luau)."""
    if run.dry:
        return "skip", {"dry_run": True}
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
                     "parts": d.get("parts"), "triangles": None})
    detail = dict(d, budget=budget, samples=counts, settled=settled, edit=run.extra.get("edit_counts"),
                  triangles="not available from Luau (pr-gate budget.sh counts FBX triangles)")
    if not settled:
        run.note("mesh count still changing after 45 s: %s" % counts[-4:])
    if (d.get("mesh_slots") or 0) > budget:
        return "fail", dict(detail, error="mesh slots %s > budget %s" % (d.get("mesh_slots"), budget))
    if not d.get("mesh_slots"):
        return "fail", dict(detail, error="no MeshParts in the play world (MeshSwap did not run?)")
    return "pass", detail


def step_geometry(run):
    """Facing / centring numbers (checks.json, luau/geometry) for #75; report.geometry = {check: {pass, items}}."""
    if run.dry:
        return "skip", {"dry_run": True}
    checks = read_json(os.path.join(HERE, "checks.json"), None)
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
        return "fail", {"error": "geometry failed: %s" % json.dumps(bad)[:400], "failed": sorted(bad)}
    return "pass", {"checks": {k: len(v["items"]) for k, v in verdict.items()}}


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
    stats = run.need_luau("client_stats", "Client", timeout=run.cfg["stats_seconds"] + 40,
                          seconds=run.cfg["stats_seconds"])
    run.perf["frame_time_ms"] = _r(stats.get("frame_time_ms"))
    run.perf["memory_mb"] = _r(stats.get("memory_mb"))
    run.perf["play"] = {k: _r(v) for k, v in stats.items()}
    if ready.get("store_status") not in (None, "Memory", "Unavailable"):
        run.note("DataStoreStatus in play = %s (expected Memory)" % ready.get("store_status"))
    run.note("frame time is Studio play-mode on the PC (window may be throttled when unfocused)")
    return "pass", {"client": ready, "seconds_to_client": round(time.time() - t0, 1), "stats": run.perf["play"]}


def _r(v):
    return round(v, 2) if isinstance(v, float) else v


def ui_probe(run):
    return run.need_luau("ui_probe", "Client", timeout=30)


def click_points(t):
    """Click centres to try for a ui_probe target: with the GuiInset, then without it if that differs."""
    pts = [("inset", t["cx"], t["cy"])]
    if t.get("rx") is not None and (round(t["rx"]), round(t["ry"])) != (round(t["cx"]), round(t["cy"])):
        pts.append(("no_inset", t["rx"], t["ry"]))
    return pts


def click_target(run, probe, path, check=None):
    """MCP user_mouse_input click on a ui_probe target. Returns (ok, info, probe_after).

    Clicks the centre with the GuiInset added; when `check(probe_after)` is False it retries at the
    centre without the GuiInset (StudioMCP may count y from below the top bar). Every attempt's
    coordinates, actions and MCP results are logged and kept in info["attempts"].
    """
    t = (probe.get("targets") or {}).get(path) or {}
    if not t.get("found") or not t.get("shown"):
        return False, {"error": "%s not on screen (%s)" % (path, t)}, probe
    if not run.input_ok:
        return False, {"error": "mcp input disabled: mcp input moved OS cursor"}, probe
    attempts, ok, after = [], False, probe
    for mode, x, y in click_points(t)[:2 if check else 1]:
        if not run.input_ok:
            break
        ok, info = run.click(x, y)
        time.sleep(0.7)
        after = ui_probe(run)
        info.update(at=[round(x), round(y)], inset=mode, ok=ok)
        if check:
            info["effect"] = bool(check(after))
        log.info("click %s at %s (%s): ok=%s effect=%s results=%s", path, info["at"], mode, ok,
                 info.get("effect"), info.get("results"))
        attempts.append(info)
        if not check or info["effect"]:
            break
    if not attempts:
        return False, {"error": "mcp input disabled: mcp input moved OS cursor"}, after
    last = attempts[-1]
    out = {"at": last["at"], "inset": last["inset"], "attempts": attempts}
    if check:
        out["effect"] = last["effect"]
    return ok, out, after


def step_onboarding(run):
    if run.dry:
        return "skip", {"dry_run": True}
    before = ui_probe(run)
    detail = {"step_id": before.get("step_id"), "counter": before.get("tutorial_counter"),
              "title": before.get("tutorial_title"), "card_visible": before.get("tutorial_visible")}
    if not before.get("tutorial_visible"):
        return "fail", dict(detail, error="tutorial card not shown for a fresh profile")
    ok, info, after = click_target(run, before, "TutorialOverlay.Hide", lambda q: not q.get("tutorial_visible"))
    detail["hide_click"] = info
    detail["card_visible_after_hide"] = after.get("tutorial_visible")
    if after.get("tutorial_visible") and not run.input_ok:
        hidden = set_visible(run, "TutorialOverlay", False)
        detail.update(hide_method="visible_fallback", card_visible_after_hide=not hidden)
        if hidden:
            return "warn", dict(detail, why="mcp input moved OS cursor: card hidden with Visible=false, Hide not clicked")
    if after.get("tutorial_visible"):
        return "fail", dict(detail, error="clicking Hide did not hide the tutorial card")
    return "pass", detail


def set_visible(run, name, show):
    """luau/panel_visible on SlimeUI.<name>; True when it ends in the wanted state."""
    run.luau("panel_visible", "Client", timeout=15, panel=name, show=show)
    time.sleep(0.4)
    p = ui_probe(run)
    if name == "TutorialOverlay":
        return bool(p.get("tutorial_visible")) == show
    return (name in (p.get("open_panels") or [])) == show


def step_shop(run):
    if run.dry:
        return "skip", {"dry_run": True}
    p = ui_probe(run)
    detail = {"open_before": p.get("shop_open"), "inset": p.get("inset"), "viewport": p.get("viewport")}
    if p.get("shop_open"):
        return "fail", dict(detail, error="shop already open before any click")
    # VirtualInputManager is not tried: the first PC run (c39fc38) got "cannot call
    # 'SendMouseButtonEvent' (lacking capability RobloxScript)" from execute_luau, same for SendKeyEvent.
    methods = {"virtual_input_manager": "not tried: lacking capability RobloxScript in execute_luau"}
    # StudioMCP user_mouse_input on the HUD Shop button, then the nav Shop button.
    for path in ("Hud.Shop", "Nav.Shop"):
        if p.get("shop_open"):
            break
        ok, info, p = click_target(run, p, path, lambda q: q.get("shop_open"))
        methods["mcp_mouse:" + path] = dict(info, result=("works (%s)" % info["inset"] if p.get("shop_open")
                                                         else "no effect") if ok else "click failed")
    run.extra["input_methods"] = methods
    detail.update(methods=methods, open_after=p.get("shop_open"), open_panels=p.get("open_panels"))
    if not p.get("shop_open") and not run.input_ok:
        opened = set_visible(run, "ShopPanel", True)
        methods["visible_fallback"] = "opened" if opened else "no effect"
        detail["open_after"] = opened
        if opened:
            return "warn", dict(detail, why="mcp input moved OS cursor: shop opened with Visible=true, not a click")
    if not p.get("shop_open"):
        return "fail", dict(detail, error="no click opened the shop")
    return "pass", detail


def step_esc(run):
    if run.dry:
        return "skip", {"dry_run": True}
    p = ui_probe(run)
    if not p.get("shop_open"):
        return "skip", {"reason": "shop not open"}
    methods = run.extra.setdefault("input_methods", {})
    if not run.input_ok:
        closed = set_visible(run, "ShopPanel", False)
        methods["mcp_keyboard:Escape"] = "not pressed: mcp input disabled (moved OS cursor)"
        return ("warn" if closed else "fail"), {
            "key": None, "open_after": not closed, "why": "mcp input moved OS cursor: Escape not tested, "
                                                          "shop closed with Visible=false"}
    # StudioMCP user_keyboard_input goes into the engine, not OS SendInput (cursor guard in run.key).
    ok, info = run.key("Escape")
    time.sleep(0.8)
    after = ui_probe(run)
    detail = {"key": info, "open_after": after.get("shop_open"), "open_panels": after.get("open_panels")}
    methods["mcp_keyboard:Escape"] = ("works" if not after.get("shop_open") else "no effect") if ok else info
    if after.get("shop_open") and not run.input_ok:
        set_visible(run, "ShopPanel", False)
        return "warn", dict(detail, why="mcp input moved OS cursor during Escape; shop closed with Visible=false")
    if after.get("shop_open"):
        click_target(run, after, "ShopPanel.Close", lambda q: not q.get("shop_open"))  # tidy up for the next steps
        return "fail", dict(detail, error="Escape did not close the shop")
    return "pass", detail


def tutorial_advance(run):
    """Soft: grab a wild slime with a real E press and see the tutorial step move on."""
    try:
        before = ui_probe(run).get("step_id")
        ok, d = run.luau("grab_attempt", "Client", timeout=20)
        if not ok or not d.get("moved"):
            return {"ran": False, "why": str(d)[:200]}
        time.sleep(1.0)
        if not run.input_ok:
            return {"ran": False, "why": "mcp input disabled (moved OS cursor)"}
        run.key("E")
        time.sleep(2.0)
        after = ui_probe(run)
        res = {"ran": True, "slime": d.get("name"), "price": d.get("price"), "step_before": before,
               "step_after": after.get("step_id"), "carrying": after.get("carrying")}
        res["advanced"] = before != after.get("step_id")
        return res
    except Exception as e:
        return {"ran": False, "why": repr(e)[:200]}


def converge_viewport(run, hwnd, target):
    """Resizes the Studio window until the play viewport is `target` (or as close as Studio allows)."""
    samples, best = [], None
    client = win32.client_size(hwnd)
    vp = _viewport(run)
    samples.append((client, vp))
    guess = (target[0] + client[0] - vp[0], target[1] + client[1] - vp[1])
    for _ in range(run.cfg["device_iterations"]):
        reached = win32.set_client_size(hwnd, guess[0], guess[1])
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
        win32.set_client_size(hwnd, best[1][0], best[1][1])
        time.sleep(1.2)
        vp = _viewport(run)
    return vp, [list(s[0]) + list(s[1]) for s in samples]


def _viewport(run):
    d = run.need_luau("client_ready", "Client", timeout=20)
    v = d.get("viewport") or [0, 0]
    return int(round(v[0])), int(round(v[1]))


PROBE_RGB = (255, 0, 255)  # luau/viewport_probe.luau


def viewport_rect(run, hwnd):
    """(x, y, w, h) of the game viewport inside the Studio client area, or None.

    Shows a full-screen magenta ScreenGui (luau/viewport_probe), captures the window and takes the
    magenta bounding box. Cached per client-area size (devices resizes the window).
    """
    client = list(win32.client_size(hwnd))
    cached = run.extra.get("viewport_rect")
    if cached and cached.get("client") == client:
        return cached.get("rect")
    res = {"client": client, "rect": None}
    try:
        ok, d = run.luau("viewport_probe", "Client", timeout=20, show=True)
        if not ok:
            res["error"] = str(d)[:200]
        else:
            res["viewport"] = d.get("viewport")
            time.sleep(0.4)
            cap = win32.capture_client(hwnd)
            res["method"] = cap["method"]
            if cap["rgb"] is not None:
                rect = imaging.find_colour_rect(cap["w"], cap["h"], cap["rgb"], PROBE_RGB, tol=12)
                res["rect"] = list(rect) if rect else None
    finally:
        run.luau("viewport_probe", "Client", timeout=20, show=False)
    vp = res.get("viewport")
    if res["rect"] and vp and vp[0] > 0:
        res["scale"] = round(res["rect"][2] / float(vp[0]), 3)  # capture px per viewport px (DPI)
    if not res["rect"]:
        run.note("viewport probe not found in the capture (%s): frames stay full-window" % res.get("error", "no magenta"))
    run.extra["viewport_rect"] = res
    log.info("viewport rect %s", res)
    return res["rect"]


def capture_frame(run, hwnd, device, crop=False, **rec):
    """Captures the Studio client area to <sha>-<device>.png and adds a report.frames entry.

    crop=True cuts the frame to the game viewport (viewport_rect); device frames stay full-window.
    `rec` goes into the frames entry (todo, kind, ...).
    """
    rect = viewport_rect(run, hwnd) if crop else None
    time.sleep(0.6)
    title = win32.title_of(hwnd)
    cap = win32.capture_client(hwnd)  # PrintWindow(PW_RENDERFULLCONTENT): off-screen, unfocused
    for _ in range(3):  # throttled/stale off-screen window: nudge a repaint (no activation) and retry
        if cap["rgb"] is not None and not cap["blank"]:
            break
        win32.nudge_repaint(hwnd)
        time.sleep(1.0)
        cap = win32.capture_client(hwnd)
    info = {"method": cap["method"], "title": title, "stats": cap["stats"], "tried": cap["tried"],
            "size": [cap["w"], cap["h"]]}
    if rect and cap["rgb"] is not None:
        try:
            w, h, rgb = imaging.crop_rgb(cap["w"], cap["h"], cap["rgb"], *rect)
            stats = imaging.frame_stats(w, h, rgb)
            cap = dict(cap, w=w, h=h, rgb=rgb, stats=stats, blank=imaging.is_blank(stats))
            info.update(crop=list(rect), size=[w, h], stats=stats)
        except ValueError as e:
            info["crop_error"] = str(e)
    reasons = []
    if cap["rgb"] is None:
        reasons.append("capture failed")
    if cap["blank"]:
        reasons.append("blank frame")
    if not frame_title_ok(title, [run.sha[:7]]):
        reasons.append("window title %r is not Studio" % title)
    name = "%s-%s.png" % (run.sha, device)
    if cap["rgb"] is not None:
        path = os.path.join(run.outdir, name if not reasons else name.replace(".png", "-rejected.png"))
        imaging.save_png(path, cap["w"], cap["h"], cap["rgb"])
    if reasons:
        info["rejected"] = reasons
        run.note("%s frame rejected: %s" % (device, ", ".join(reasons)))
        status = "blank" if "blank frame" in reasons else "missing"
        run.add_frame(device, status=status, error=", ".join(reasons), **rec)
    else:
        info["file"] = name
        run.add_frame(device, name, method=cap["method"], size=info["size"], crop=info.get("crop"), **rec)
    return info


def step_devices(run):
    if run.dry:
        return "skip", {"dry_run": True}
    hwnd = run.hwnd
    if not hwnd:
        win = win32.studio_main_window(tracked_pids(run.paths))
        hwnd = run.hwnd = win and win["hwnd"]
    if not hwnd:
        raise StepFail("no Studio window to resize")
    if not win32.is_offscreen(hwnd):
        win32.place_offscreen(hwnd)
    x, y, w, h = win32.window_rect(hwnd)
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
            res["frame"] = capture_frame(run, hwnd, device, kind="device")
            results[device] = res
            t1 = time.time()
            menus[device] = menus_at_device(run, hwnd, device)
            menu_s += time.time() - t1
            if device.startswith("phone"):
                t1 = time.time()
                phone[device] = phone_perf_at_device(run, hwnd, device, first=not filled)
                filled = True
                perf_s += time.time() - t1
    finally:
        if filled:
            try:
                run.luau("slime_fill", "Server", timeout=20, target=0)
            except Exception as e:
                run.note("could not remove the phone_perf slime clones: %r" % (e,))
        try:
            win32.set_window_rect(hwnd, x, y, w, h)  # back to the off-screen rect; never maximized
        except Exception as e:
            run.note("could not put the Studio window back to its off-screen rect: %r" % (e,))
    set_menus_and_perf_steps(run, menus, phone, menu_s, perf_s)
    detail = {"devices": results}
    if failed:
        return "fail", dict(detail, error="HUD/nav off-screen or missing at: %s" % ", ".join(failed))
    if not any(r.get("hud") for r in results.values()):
        return "fail", dict(detail, error="no device size was checked")
    return "pass", detail


def menus_at_device(run, hwnd, device):
    """Opens every menu panel at the current size, measures it, captures it and closes it again.

    Opening: MCP click on the nav icon when the cursor guard allows, else the Visible fallback
    (open_panel). Returns {panel key: menu_record}. Frames: <sha>-menu-<panel>-<device>.png.
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
                    info = capture_frame(run, hwnd, fid, crop=True, kind="menu", panel=panel, for_device=device,
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


def phone_perf_at_device(run, hwnd, device, first):
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
        info = capture_frame(run, hwnd, "phone-perf-" + device, crop=True, kind="perf", for_device=device)
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
    run.note("phone_perf is Studio on the PC (unfocused, off-screen window), not real phone hardware")


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


UI_SHOT_BUTTONS = {"shop": "Nav.Shop", "dex": "Nav.Dex", "rebirth": "Nav.Rebirth", "goals": "Nav.Goals",
                   "plot": "Nav.Plot", "merge": "Nav.Merge", "leaders": "Nav.Leaders"}
UI_SHOT_PANELS = {"leaders": "LeaderboardPanel"}  # else <Key>Panel (src/ui/Panels: Widgets.panel names)


def panel_for(key):
    k = str(key).lower()
    return UI_SHOT_PANELS.get(k, k[:1].upper() + k[1:] + "Panel")


def open_panel(run, key):
    """Opens a SlimeUI panel for a ui shot. Returns {panel, method, tried}; method None = not opened.

    1) MCP user_mouse_input on its nav icon (Nav.<Key>), then a HUD button (Hud.<Key>) if any;
    2) fallback: luau/panel_visible sets <Key>Panel.Visible directly (no UI open hook exists),
       so the panel's update() did not run and its contents can be stale.
    """
    k = str(key).lower()
    panel = panel_for(k)
    nav = UI_SHOT_BUTTONS.get(k, "Nav." + k[:1].upper() + k[1:])
    res = {"panel": panel, "method": None, "tried": []}
    p = ui_probe(run)
    if panel in (p.get("open_panels") or []):
        res["method"] = "already open"
        return res
    for path in (nav, "Hud." + nav.split(".", 1)[1]):
        t = (p.get("targets") or {}).get(path) or {}
        if not t.get("found"):
            continue
        ok, info, p = click_target(run, p, path, lambda q: panel in (q.get("open_panels") or []))
        opened = panel in (p.get("open_panels") or [])
        res["tried"].append({"path": path, "click_ok": ok, "opened": opened, "error": info.get("error"),
                             "attempts": info.get("attempts")})
        if opened:
            res["method"] = "mcp_click:%s:%s" % (path, info["inset"])
            return res
    ok, d = run.luau("panel_visible", "Client", timeout=15, panel=panel, show=True)
    time.sleep(0.4)
    p = ui_probe(run)
    res["tried"].append({"path": "panel_visible", "result": d if ok else str(d)[:160]})
    if panel in (p.get("open_panels") or []):
        res["method"] = "pcw_open_hook" if ok and isinstance(d, dict) and d.get("via") == "pcw_open_hook" else "visible_fallback"
    return res


def press_check(run, opened, key, expect="closed"):
    """Presses `key` (MCP user_keyboard_input, Client datamodel) with the panel open and asserts it closed.
    A panel opened by the Visible fallback has no game state behind it, so the key cannot close it: inconclusive."""
    panel = opened["panel"]
    out = {"key": key, "panel": panel, "expect": expect}
    if opened["method"] == "visible_fallback":
        return dict(out, status="warn", why="panel opened by Visible=true; the game's menu state is not open")
    if not run.input_ok:
        return dict(out, status="warn", why="mcp input disabled (moved OS cursor)")
    ok, info = run.key(key)
    time.sleep(0.8)
    p = ui_probe(run)
    is_open = panel in (p.get("open_panels") or [])
    out.update(key_ok=ok, key_call=info, open_after=is_open)
    if not ok:
        return dict(out, status="fail", why="key call failed: %s" % (info,))
    if is_open != (expect == "open"):
        close_panel(run, panel)  # tidy up for the next shot
        return dict(out, status="fail")
    return dict(out, status="pass")


def close_panel(run, panel):
    """Escape (MCP key); then the panel's Close button; then Visible=false. Returns the method that closed it."""
    if run.input_ok:
        run.key("Escape")
        time.sleep(0.6)
        p = ui_probe(run)
        if p.get("menu_open") and run.input_ok:  # nothing of ours took Escape: the Roblox menu opened, close it again
            run.key("Escape")
            time.sleep(0.6)
            p = ui_probe(run)
        if panel not in (p.get("open_panels") or []):
            return "escape"
    else:
        p = ui_probe(run)
    ok, _, p = click_target(run, p, panel + ".Close", lambda q: panel not in (q.get("open_panels") or []))
    if ok and panel not in (p.get("open_panels") or []):
        return "close_button"
    run.luau("panel_visible", "Client", timeout=15, panel=panel, show=False)
    return "visible_fallback"


def step_shots(run):
    """Soft: proof frames from shots.json (bots add theirs in PRs). Missing targets are notes, never failures.

    ui shots open a panel (open_panel), hide the tutorial card and every other panel (ui_isolate,
    restored after) and capture the viewport with the UI. world shots hide every ScreenGui,
    BillboardGui and ProximityPrompt, move the character behind the camera, lock the camera with a
    render step (shot_camera) on the target's Server bounding box and capture the viewport. Every shot adds a report.frames entry with its todo and status.
    """
    if run.dry:
        return "skip", {"dry_run": True}
    shots = read_json(os.path.join(HERE, "shots.json"), None)
    if not isinstance(shots, list):
        return "skip", {"reason": "shots.json missing or unreadable"}
    hwnd = run.hwnd
    if not hwnd:
        return "skip", {"reason": "no Studio window"}
    results, world_mode = [], False
    for shot in shots:
        sid = re.sub(r"[^A-Za-z0-9_.-]", "_", str(shot.get("id", "shot")))
        fid = "shot-" + sid
        todo = shot_todo(shot)
        res = {"id": sid, "todo": todo, "note": shot.get("note")}
        results.append(res)
        if run.remaining() < 90:
            res["skipped"] = "run budget"
            run.add_frame(fid, status="missing", todo=todo, kind="shot", error="run budget")
            continue
        try:
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
                opened = open_panel(run, key) if key else None
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
                    continue
                keep = opened["panel"] if opened else ""
                ok, iso = run.luau("ui_isolate", "Client", timeout=15, keep=keep, hide=True)
                res["isolated"] = iso if ok else str(iso)[:160]
                try:
                    res["frame"] = capture_frame(run, hwnd, fid, crop=True, todo=todo, kind="shot",
                                                 open_method=opened and opened["method"])
                finally:
                    run.luau("ui_isolate", "Client", timeout=15, keep=keep, hide=False)
                if opened and opened["method"] != "already open":
                    res["closed_by"] = close_panel(run, opened["panel"])
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
                res["camera"] = cam = run.need_luau("shot_camera", "Client", timeout=25, eye=eye, at=at)
                if not cam.get("locked"):
                    run.note("shot %s: camera drifted %.2f studs from the render-step lock" % (sid, cam.get("drift") or -1))
                res["frame"] = capture_frame(run, hwnd, fid, crop=True, todo=todo, kind="shot",
                                             target=(res.get("target") or {}).get("path"))
        except Exception as e:
            res["error"] = repr(e)[:200]
            if not res.get("frame"):
                run.add_frame(fid, status="missing", todo=todo, kind="shot", error=res["error"])
    try:
        run.luau("shot_camera_reset", "Client", timeout=15)
    except Exception:
        pass
    done = len([r for r in results if (r.get("frame") or {}).get("file")])
    pressed = [r for r in results if r.get("press")]
    if any(r["press"]["status"] != "pass" for r in pressed):
        return "warn", {"captured": done, "total": len(shots), "shots": results, "press_failed": True,
                        "viewport_rect": run.extra.get("viewport_rect")}
    return "pass" if (done or pressed) else "warn", {"captured": done, "total": len(shots), "shots": results,
                                        "viewport_rect": run.extra.get("viewport_rect")}


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
        "checked_at": utc_now(),
        "studio_version": run.studio_version,
        "notes": "; ".join(run.notes) if run.notes else "",
        "duration_s": round(time.time() - run.t0, 1),
        "steps": steps,
        "perf": run.perf,
        "geometry": run.extra.get("geometry"),
        "frames": list(run.frames),
        "input_methods": run.extra.get("input_methods"),
        "menus": run.extra.get("menus"),
        "background": {"foreground_at_start": list(run.fg_start) if run.fg_start else None,
                       "focus_stolen": list(run.focus_stolen), "mcp_input": run.input_ok,
                       "cursor_events": run.extra.get("cursor_events", [])},
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


def full_run(paths, cfg, sha, dry=False):
    """Steps 1-8 for one sha. Returns (report, busy)."""
    run = Run(paths, cfg, sha, dry)
    run.record_foreground()
    busy = False
    try:
        ok = run_step(run, "build", step_build)
        ok = ok and run_step(run, "launch", step_launch)
        if ok:
            if run_step(run, "play", step_play):
                run_step(run, "perf", step_perf)
                run_step(run, "geometry", step_geometry)
                run_step(run, "onboarding", step_onboarding)
                run_step(run, "shop", step_shop)
                run_step(run, "esc", step_esc)
                if not dry and run.remaining() > 40:
                    run.steps["onboarding"].setdefault("detail", {})["advance"] = tutorial_advance(run)
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
    log.info("report %s: %s (%ss) %s", report_path(run), report["status"], report["duration_s"], report["notes"][:300])
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
    url = run.git("remote", "get-url", cfg["remote"]).stdout.strip()
    if not os.path.isdir(os.path.join(rdir, ".git")):
        os.makedirs(rdir, exist_ok=True)
        run.git("init", "-q", "-b", branch, cwd=rdir)
        run.git("remote", "add", "origin", url, cwd=rdir)
    else:
        run.git("remote", "set-url", "origin", url, cwd=rdir)
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
        run.git(*ident, "commit", "-q", "-m", "studio-report %s %s" % (sha[:12], synced["status"]), cwd=rdir)
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
# Commands
# ---------------------------------------------------------------------------

def cmd_once(paths, cfg, sha, dry, sync=True):
    lock = Lock(paths.st("run.lock"))
    if not lock.acquire():
        log.error("another watcher run holds %s", lock.path)
        return 3, False
    try:
        sha = sha or remote_sha(paths, cfg)
        log.info("run %s", sha)
        report, busy = full_run(paths, cfg, sha, dry)
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
    log.info("loop: polling %s/%s every %ss", cfg["remote"], cfg["branch"], cfg["poll_s"])
    busy_until = 0
    try:
        while True:
            try:
                if cfg["sync"] and not dry:
                    sync_pending(paths, cfg)
                sha = remote_sha(paths, cfg)
                last = (read_json(paths.st("last-sha.json"), {}) or {}).get("sha")
                if sha != last and time.time() >= busy_until:
                    _, busy = cmd_once(paths, cfg, sha, dry, sync=True)
                    if busy:
                        busy_until = time.time() + cfg["busy_retry_s"]
                        log.info("studio busy; retry %s in %ss", sha[:12], cfg["busy_retry_s"])
                    elif not dry:
                        write_json(paths.st("last-sha.json"), {"sha": sha, "at": utc_now()})
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
                      "focus_stolen": run.focus_stolen, "mcp_input": run.input_ok}, indent=2, default=str))
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
    win = win32.studio_main_window(tracked_pids(paths) or win32.list_pids())
    if not win:
        print("no Studio window")
        return 1
    cap = win32.capture_client(win["hwnd"])
    if cap["rgb"] is None:
        print("capture failed: %s" % cap["tried"])
        return 1
    out = out or os.path.join(paths.out, "capture-test.png")
    imaging.save_png(out, cap["w"], cap["h"], cap["rgb"])
    print(json.dumps({"file": out, "title": win["title"], "method": cap["method"], "blank": cap["blank"],
                      "stats": cap["stats"], "tried": cap["tried"]}, indent=2))
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--home", default=os.environ.get("PCW_HOME", r"C:\gate\pc-watcher"))
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("-v", "--verbose", action="store_true")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p_once = sub.add_parser("once")
    p_once.add_argument("--sha")
    p_once.add_argument("--no-sync", action="store_true")
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
        return cmd_once(paths, cfg, a.sha, a.dry_run, sync=not a.no_sync)[0]
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


if __name__ == "__main__":
    sys.exit(main())
