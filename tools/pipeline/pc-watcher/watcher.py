"""Steal a Slime PC watcher (MVP): on each new origin/main sha, build, open in Studio, play, measure,
screenshot, and push a JSON report + frames to the orphan branch `studio-reports`.

  python watcher.py once [--sha SHA] [--no-sync]
  python watcher.py loop
  python watcher.py shots-only [--sha TAG]     (against an already running Studio, play already started)

Runs on the Windows PC only (Studio + Win32). See README.md.
"""

import argparse
import datetime
import json
import logging
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import imaging  # noqa: E402
import mcp_client  # noqa: E402
import win32  # noqa: E402

ROOT = os.environ.get("PCW_ROOT", r"C:\gate\pc-watcher")
REPO = os.path.join(ROOT, "repo")
ROJO = os.path.join(ROOT, "bin", "rojo.exe")
BUILDS = os.path.join(ROOT, "builds")
REPORTS = os.path.join(ROOT, "reports")  # git clone, branch studio-reports
REPORT_DIR = os.path.join(REPORTS, "studio-reports")
LAST_SHA = os.path.join(ROOT, "last-sha")
PIDS_FILE = os.path.join(ROOT, "studio-pids.json")
LOCK = os.path.join(ROOT, "watcher.lock")
LOG_DIR = os.path.join(ROOT, "logs")
GAME = "games/steal-a-slime"
SHOTS = os.path.join(HERE, "shots.json")
BRANCH = "main"
REPORT_BRANCH = "studio-reports"
POLL_S = 60
MESH_BUDGET = 400
KEEP_BUILDS = 5
UI_NAME = "SlimeUI"
ONBOARD_WORDS = ["next", "continue", "ok", "skip", "got it", "start"]

GIT_ENV = dict(os.environ, GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="never")
log = logging.getLogger("pcw")


# ---------------------------------------------------------------------------
# Luau snippets (bodies for mcp_client.wrap_luau: must `return` a table)
# ---------------------------------------------------------------------------

LUA_HELPERS = r"""
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local VIM = game:GetService("VirtualInputManager")
local function slimeUI()
	local pg = Players.LocalPlayer:WaitForChild("PlayerGui", 10)
	return pg and pg:FindFirstChild("__UI__")
end
local function shown(g)
	if g.AbsoluteSize.X <= 0 or g.AbsoluteSize.Y <= 0 then return false end
	local a = g
	while a do
		if a:IsA("GuiObject") and not a.Visible then return false end
		if a:IsA("LayerCollector") then return a.Enabled end
		a = a.Parent
	end
	return false
end
local function label(b)
	local t = ""
	if b:IsA("TextButton") then t = b.Text end
	return string.lower(b.Name .. " " .. t)
end
local function findButton(words)
	local ui = slimeUI()
	if not ui then return nil end
	for _, w in words do
		for _, b in ui:GetDescendants() do
			local hit = if #w <= 2 then string.find(label(b), "%f[%w]" .. w .. "%f[%W]") else string.find(label(b), w, 1, true)
			if b:IsA("GuiButton") and shown(b) and hit then return b end
		end
	end
	return nil
end
local function click(b)
	local inset = GuiService:GetGuiInset()
	local sg = b:FindFirstAncestorWhichIsA("ScreenGui")
	local dy = if sg and sg.IgnoreGuiInset then 0 else inset.Y
	local x = b.AbsolutePosition.X + b.AbsoluteSize.X / 2
	local y = b.AbsolutePosition.Y + b.AbsoluteSize.Y / 2 + dy
	VIM:SendMouseButtonEvent(x, y, 0, true, game, 1)
	task.wait(0.08)
	VIM:SendMouseButtonEvent(x, y, 0, false, game, 1)
	return { name = b:GetFullName(), x = math.floor(x), y = math.floor(y) }
end
local function openPanels()
	local ui = slimeUI()
	local out = {}
	if not ui then return out end
	for _, f in ui:GetDescendants() do
		if f:IsA("GuiObject") and string.find(string.lower(f.Name), "panel$") and shown(f) then
			table.insert(out, f.Name)
		end
	end
	return out
end
""".replace("__UI__", UI_NAME)

LUA_SERVER_PERF = r"""
local meshes, parts, uniq, nuniq = 0, 0, {}, 0
for _, d in workspace:GetDescendants() do
	if d:IsA("BasePart") then parts += 1 end
	if d:IsA("MeshPart") then
		meshes += 1
		if not uniq[d.MeshId] then uniq[d.MeshId] = true; nuniq += 1 end
	end
end
return { mesh_parts = meshes, unique_meshes = nuniq, base_parts = parts }
"""

LUA_CLIENT_PERF = r"""
local RS = game:GetService("RunService")
local total, frames = 0, 0
local conn = RS.RenderStepped:Connect(function(dt) total += dt; frames += 1 end)
task.wait(3)
conn:Disconnect()
local vp = workspace.CurrentCamera.ViewportSize
return {
	frame_time_ms = if frames > 0 then total / frames * 1000 else nil,
	frames = frames,
	memory_mb = game:GetService("Stats"):GetTotalMemoryUsageMb(),
	viewport = { math.floor(vp.X), math.floor(vp.Y) },
}
"""

LUA_HUD = LUA_HELPERS + r"""
local ui = slimeUI()
local vp = workspace.CurrentCamera.ViewportSize
local res = { viewport = { math.floor(vp.X), math.floor(vp.Y) }, found = ui ~= nil, checked = 0, offenders = {} }
if not ui then return res end
local inset = GuiService:GetGuiInset()
local dy = if ui.IgnoreGuiInset then 0 else inset.Y
for _, b in ui:GetDescendants() do
	if b:IsA("GuiButton") and shown(b) then
		res.checked += 1
		local p, s = b.AbsolutePosition, b.AbsoluteSize
		local x0, y0 = p.X, p.Y + dy
		if x0 < -1 or y0 < -1 or x0 + s.X > vp.X + 1 or y0 + s.Y > vp.Y + 1 then
			table.insert(res.offenders, { name = b:GetFullName(), x = x0, y = y0, w = s.X, h = s.Y })
		end
	end
end
return res
"""

LUA_ONBOARD = LUA_HELPERS + r"""
local clicks = {}
for _ = 1, 8 do
	local b = findButton(__WORDS__)
	if not b then break end
	table.insert(clicks, click(b))
	task.wait(0.7)
end
return { clicks = clicks, panels = openPanels() }
"""

LUA_OPEN = LUA_HELPERS + r"""
local b = findButton(__WORDS__)
if not b then return { clicked = false, panels = openPanels() } end
local c = click(b)
task.wait(0.8)
return { clicked = true, button = c, panels = openPanels() }
"""

LUA_ESCAPE = LUA_HELPERS + r"""
local before = openPanels()
VIM:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
task.wait(0.08)
VIM:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
task.wait(0.6)
local menu = GuiService.MenuIsOpen
if menu then -- nothing of ours consumed Escape: the Roblox menu opened, close it again
	VIM:SendKeyEvent(true, Enum.KeyCode.Escape, false, game)
	task.wait(0.08)
	VIM:SendKeyEvent(false, Enum.KeyCode.Escape, false, game)
	task.wait(0.4)
end
return { before = before, after = openPanels(), roblox_menu = menu }
"""

# Server sees the whole world (client may be streaming), so locate targets there.
LUA_FIND = r"""
local pat = string.lower(%s)
local exact, loose
for _, d in workspace:GetDescendants() do
	if (d:IsA("Model") or d:IsA("BasePart")) and not game:GetService("Players"):GetPlayerFromCharacter(d) then
		local n = string.lower(d.Name)
		if n == pat then exact = d; break end
		if not loose and string.find(n, pat, 1, true) then loose = d end
	end
end
local hit = exact or loose
if not hit then return { found = false } end
local cf, size
if hit:IsA("Model") then cf, size = hit:GetBoundingBox() else cf, size = hit.CFrame, hit.Size end
local p, lv = cf.Position, cf.LookVector
return { found = true, path = hit:GetFullName(), pos = { p.X, p.Y, p.Z }, look = { lv.X, lv.Y, lv.Z },
	size = { size.X, size.Y, size.Z } }
"""

LUA_CAMERA = r"""
local eye, at = Vector3.new(%s), Vector3.new(%s)
pcall(function() game:GetService("Players").LocalPlayer:RequestStreamAroundAsync(at, 5) end)
local cam = workspace.CurrentCamera
cam.CameraType = Enum.CameraType.Scriptable
cam.CFrame = CFrame.lookAt(eye, at)
task.wait(1)
return { ok = true }
"""

LUA_CAMERA_RESET = r"""
workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
return { ok = true }
"""


def lua_str(s):
    return json.dumps(s)  # JSON string literal is a valid Luau string literal for plain text


def lua_list(words):
    return "{ " + ", ".join(lua_str(w) for w in words) + " }"


def shot_camera(target):
    """Server bounding box -> (eye, at): in front of the target, raised, 1.6x its size back."""
    px, py, pz = target["pos"]
    lx, _, lz = target["look"]
    size = max(target["size"])
    dist = max(size * 1.6, 14.0)
    flat = (lx * lx + lz * lz) ** 0.5 or 1.0
    eye = (px + lx / flat * dist, py + dist * 0.45, pz + lz / flat * dist)
    return eye, (px, py, pz)


# ---------------------------------------------------------------------------
# Small utilities
# ---------------------------------------------------------------------------

def run(cmd, cwd=None, timeout=300, check=True):
    log.info("$ %s", " ".join(cmd))
    r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, env=GIT_ENV,
                       creationflags=win32.NO_WINDOW if os.name == "nt" else 0)
    if check and r.returncode != 0:
        raise RuntimeError("%s failed (%d): %s" % (cmd[0], r.returncode, (r.stderr or r.stdout)[-600:]))
    return r


def read(path, default=None):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return default


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def remote_sha():
    r = run(["git", "ls-remote", "origin", "refs/heads/" + BRANCH], cwd=REPO, timeout=60)
    return r.stdout.split()[0] if r.stdout.strip() else None


class Lock:
    def __enter__(self):
        os.makedirs(ROOT, exist_ok=True)
        if os.path.exists(LOCK) and time.time() - os.path.getmtime(LOCK) > 1800:
            os.remove(LOCK)  # stale (crashed run)
        self.fd = os.open(LOCK, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.write(self.fd, str(os.getpid()).encode())
        return self

    def __exit__(self, *exc):
        os.close(self.fd)
        os.remove(LOCK)


# ---------------------------------------------------------------------------
# Run state
# ---------------------------------------------------------------------------

class Run:
    def __init__(self, sha):
        self.sha = sha
        self.t0 = time.time()
        self.notes = []
        self.steps = {}
        self.perf = {"budget": MESH_BUDGET}
        self.frames = []
        self.hard_fail = False
        self.studio_dir = mcp_client.find_studio_dir()
        self.mcp = None
        self.studio_id = None
        self.pids = []
        self.hwnd = None
        self.frame_dir = os.path.join(REPORT_DIR, sha)

    def step(self, name, ok, detail=None, hard=True):
        self.steps[name] = {"ok": bool(ok), "detail": detail}
        log.info("step %s: %s %s", name, "ok" if ok else "FAIL", json.dumps(detail, default=str)[:400])
        if not ok and hard:
            self.hard_fail = True
        return ok

    def note(self, msg):
        log.info("note: %s", msg)
        self.notes.append(msg)

    def luau(self, body, datamodel, timeout=60):
        ok, data, _ = self.mcp.luau(self.studio_id, body, datamodel=datamodel, timeout=timeout)
        return ok, data

    # --- capture ---
    def capture(self, fid):
        """Studio client area -> <sha>/<sha>-<fid>.jpg. Returns the frame record."""
        rec = {"id": fid, "file": None, "ok": False}
        if not self.hwnd:
            rec["error"] = "no studio window"
            self.frames.append(rec)
            return rec
        try:
            win32.bring_to_front(self.hwnd)
            time.sleep(0.3)
            got = win32.capture_client(self.hwnd)
        except Exception as e:
            rec["error"] = repr(e)
            self.frames.append(rec)
            return rec
        rec.update({"method": got["method"], "w": got["w"], "h": got["h"], "stats": got["stats"]})
        if got["rgb"] is None or got["blank"]:
            rec["error"] = "blank frame (%s)" % "; ".join(got["tried"])
            self.frames.append(rec)
            return rec
        os.makedirs(self.frame_dir, exist_ok=True)
        base = os.path.join(self.frame_dir, "%s-%s" % (self.sha, fid))
        imaging.save_png(base + ".png", got["w"], got["h"], got["rgb"])
        if imaging.to_jpeg(base + ".png", base + ".jpg", 80):
            os.remove(base + ".png")
            rec["file"] = os.path.basename(base) + ".jpg"
        else:
            rec["file"] = os.path.basename(base) + ".png"
        rec["ok"] = True
        self.frames.append(rec)
        return rec

    def report(self):
        status = "fail" if self.hard_fail else "pass"
        return {
            "sha": self.sha,
            "status": status,
            "checked_at": now_iso(),
            "studio_version": os.path.basename(self.studio_dir) if self.studio_dir else None,
            "notes": self.notes,
            "duration_s": round(time.time() - self.t0, 1),
            "perf": self.perf,
            "steps": self.steps,
            "frames": self.frames,
        }


# ---------------------------------------------------------------------------
# Steps
# ---------------------------------------------------------------------------

def step_build(r):
    run(["git", "fetch", "--quiet", "origin", BRANCH], cwd=REPO, timeout=180)
    run(["git", "checkout", "--quiet", "--force", "--detach", r.sha], cwd=REPO)
    os.makedirs(BUILDS, exist_ok=True)
    out = os.path.join(BUILDS, r.sha + ".rbxl")
    run([ROJO, "build", os.path.join(REPO, GAME, "default.project.json"), "-o", out], timeout=120)
    olds = sorted((os.path.join(BUILDS, f) for f in os.listdir(BUILDS) if f.endswith(".rbxl")),
                  key=os.path.getmtime)
    for old in olds[:-KEEP_BUILDS]:
        os.remove(old)
    r.step("build", True, out)
    return out


def tracked_pids():
    try:
        return json.loads(read(PIDS_FILE, "[]"))
    except ValueError:
        return []


def step_launch(r, rbxl):
    if not r.studio_dir:
        return r.step("launch", False, "Studio not found under %LOCALAPPDATA%\\Roblox\\Versions")
    for pid in tracked_pids():  # leftovers from a crashed run of ours
        if win32.pid_alive(pid):
            win32.kill_pid(pid)
    time.sleep(1)
    before = set(win32.list_pids())
    if before:
        return r.step("launch", False, "studio busy: user Studio running (pids %s)" % sorted(before))
    p = subprocess.Popen([os.path.join(r.studio_dir, win32.STUDIO_IMAGE), rbxl])
    r.pids = [p.pid]
    write(PIDS_FILE, json.dumps(r.pids))
    r.mcp = mcp_client.McpSession(os.path.join(r.studio_dir, "StudioMCP.exe")).start()
    name = os.path.basename(rbxl)
    deadline = time.time() + 120
    while time.time() < deadline:
        studios, _ = r.mcp.list_studios()
        hit = mcp_client.pick_studio(studios, [name, r.sha])
        if hit:
            r.studio_id = hit["id"]
            break
        time.sleep(2)
    r.pids = sorted(set(r.pids) | (set(win32.list_pids()) - before))
    write(PIDS_FILE, json.dumps(r.pids))
    if not r.studio_id:
        return r.step("launch", False, "MCP did not list %s within 120s" % name)
    win = win32.studio_main_window(r.pids)
    r.hwnd = win["hwnd"] if win else None
    return r.step("launch", True, {"studio_id": r.studio_id, "pids": r.pids, "window": win and win["title"]})


def step_play(r):
    res = r.mcp.call("start_stop_play", {"studio_id": r.studio_id, "is_start": True}, timeout=60)
    if not res.ok:
        return r.step("play", False, res.brief())
    time.sleep(3)
    deadline = time.time() + 60
    while time.time() < deadline:
        ok, data = r.luau("return { ready = #workspace:GetChildren() }", "Server", timeout=20)
        if ok:
            return r.step("play", True, res.brief(80))
        time.sleep(2)
    return r.step("play", False, "Server datamodel not reachable after play start")


def step_perf(r):
    ok, data = r.luau(LUA_SERVER_PERF, "Server")
    if ok:
        r.perf.update(data)
        r.step("perf_meshes", data["mesh_parts"] <= MESH_BUDGET, data)
    else:
        r.step("perf_meshes", False, data)
    ok, data = r.luau(LUA_CLIENT_PERF, "Client", timeout=30)
    if ok:
        r.perf.update({k: data.get(k) for k in ("frame_time_ms", "memory_mb")})
        r.perf["viewport"] = data.get("viewport")
    r.step("perf_client", ok, data, hard=False)


def step_hud(r, tag):
    ok, data = r.luau(LUA_HUD, "Client")
    good = ok and data.get("found") and not data.get("offenders")
    r.step("hud_" + tag, good, data)
    return data if ok else None


def step_devices(r):
    try:
        orig = win32.window_rect(r.hwnd)
        maxed = win32.is_maximized(r.hwnd)
        got = win32.set_client_size(r.hwnd, 1920, 1080, 0, 0)
        time.sleep(1.5)
        hud = step_hud(r, "pc")
        r.capture("pc")
        r.note("pc: window client %sx%s, game viewport %s (Studio device emulator state decides the viewport)"
               % (got[0], got[1], hud and hud.get("viewport")))
        if maxed:
            win32.maximize(r.hwnd)
        else:
            win32.set_window_rect(r.hwnd, *orig)
        time.sleep(1.5)
    except Exception as e:
        r.step("devices", False, repr(e), hard=False)
    hud = step_hud(r, "current")
    r.capture("current")
    r.note("phone sizes not driven: device emulator is not scriptable; captured current viewport %s"
           % (hud and hud.get("viewport")))


def step_onboarding_shop(r):
    ok, data = r.luau(LUA_ONBOARD.replace("__WORDS__", lua_list(ONBOARD_WORDS)), "Client", timeout=40)
    r.step("onboarding", ok, data, hard=False)
    r.capture("onboarding")
    ok, data = r.luau(LUA_OPEN.replace("__WORDS__", lua_list(["shop"])), "Client")
    opened = ok and data.get("clicked") and any("shop" in p.lower() for p in data.get("panels", []))
    r.step("shop", opened, data)
    r.capture("shop")
    ok, data = r.luau(LUA_ESCAPE, "Client")
    r.step("esc", ok and not any("shop" in p.lower() for p in data.get("after", [])), data, hard=False)


def run_shots(r):
    try:
        with open(SHOTS, encoding="utf-8") as f:
            shots = json.load(f)
    except (OSError, ValueError) as e:
        r.note("shots.json unreadable: %r" % (e,))
        return
    done = 0
    for s in shots:
        sid = s.get("id", "shot")
        try:
            if s.get("kind") == "world":
                if "pos" in s:
                    eye, at = s["pos"], s.get("look", [0, 0, 0])
                else:
                    ok, t = r.luau(LUA_FIND % lua_str(s.get("target", "")), "Server")
                    if not ok or not t.get("found"):
                        r.note("shot %s: target %r not found" % (sid, s.get("target")))
                        continue
                    eye, at = shot_camera(t)
                ok, err = r.luau(LUA_CAMERA % (", ".join("%.2f" % v for v in eye),
                                               ", ".join("%.2f" % v for v in at)), "Client")
                if not ok:
                    r.note("shot %s: camera failed: %s" % (sid, err))
                    continue
                rec = r.capture(sid)
            else:
                if s.get("open"):
                    ok, data = r.luau(LUA_OPEN.replace("__WORDS__", lua_list([s["open"].lower()])), "Client")
                    if not (ok and data.get("clicked")):
                        r.note("shot %s: no visible button matching %r" % (sid, s["open"]))
                        continue
                rec = r.capture(sid)
                if s.get("open"):
                    r.luau(LUA_ESCAPE, "Client")
            if rec["ok"]:
                done += 1
            else:
                r.note("shot %s: %s" % (sid, rec.get("error")))
        except Exception as e:
            r.note("shot %s: %r" % (sid, e))
    r.luau(LUA_CAMERA_RESET, "Client")
    r.step("shots", True, "%d/%d captured" % (done, len(shots)), hard=False)


def step_two_player(r):
    r.step("two_player", True, "TODO: not run in MVP", hard=False)
    r.note("two_player: not run (TODO)")


def step_close(r):
    if r.mcp and r.studio_id:
        try:
            r.mcp.call("start_stop_play", {"studio_id": r.studio_id, "is_start": False}, timeout=30)
        except Exception as e:
            log.warning("stop play: %r", e)
    if r.mcp:
        r.mcp.close()
    if r.hwnd:
        try:
            win32.post_close(r.hwnd)
        except Exception:
            pass
    deadline = time.time() + 15
    while time.time() < deadline and any(win32.pid_alive(p) for p in r.pids):
        time.sleep(1)
    for p in r.pids:
        if win32.pid_alive(p):
            win32.kill_pid(p)  # also kills the "save changes?" prompt
    write(PIDS_FILE, "[]")


def write_report(r):
    os.makedirs(REPORT_DIR, exist_ok=True)
    rep = r.report()
    write(os.path.join(REPORT_DIR, r.sha + ".json"), json.dumps(rep, indent=2, default=str))
    log.info("report %s: %s (%ss)", r.sha, rep["status"], rep["duration_s"])
    return rep


# ---------------------------------------------------------------------------
# Sync to the orphan branch
# ---------------------------------------------------------------------------

def ensure_reports_repo():
    if os.path.isdir(os.path.join(REPORTS, ".git")):
        return
    url = run(["git", "remote", "get-url", "origin"], cwd=REPO).stdout.strip()
    os.makedirs(REPORTS, exist_ok=True)
    run(["git", "init", "--quiet"], cwd=REPORTS)
    run(["git", "remote", "add", "origin", url], cwd=REPORTS)
    exists = run(["git", "ls-remote", "origin", "refs/heads/" + REPORT_BRANCH], cwd=REPORTS, timeout=60).stdout
    if exists.strip():
        run(["git", "fetch", "--quiet", "origin", REPORT_BRANCH], cwd=REPORTS, timeout=180)
        run(["git", "checkout", "--quiet", "-B", REPORT_BRANCH, "FETCH_HEAD"], cwd=REPORTS)
    else:
        run(["git", "checkout", "--quiet", "--orphan", REPORT_BRANCH], cwd=REPORTS)


def sync(sha):
    ensure_reports_repo()
    run(["git", "add", "studio-reports"], cwd=REPORTS)
    if run(["git", "diff", "--cached", "--quiet"], cwd=REPORTS, check=False).returncode == 0:
        log.info("sync: nothing to commit")
    else:
        run(["git", "-c", "user.name=pc-watcher", "-c", "user.email=pc-watcher@localhost",
             "commit", "--quiet", "-m", "studio report %s" % sha], cwd=REPORTS)
    for attempt in range(3):
        if run(["git", "push", "origin", "HEAD:" + REPORT_BRANCH], cwd=REPORTS, timeout=180,
               check=False).returncode == 0:
            return True
        log.warning("push failed (attempt %d), pull --rebase", attempt + 1)
        run(["git", "pull", "--rebase", "--quiet", "origin", REPORT_BRANCH], cwd=REPORTS, timeout=180, check=False)
    return False


# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def once(sha=None, do_sync=True):
    sha = sha or remote_sha()
    r = Run(sha)
    log.info("=== run %s (studio %s)", sha, r.studio_dir)
    try:
        ensure_reports_repo()
    except Exception as e:
        r.note("reports repo setup failed: %r" % (e,))
    try:
        rbxl = step_build(r)
        if step_launch(r, rbxl) and step_play(r):
            for fn in (step_perf, step_devices, step_onboarding_shop, run_shots, step_two_player):
                try:
                    fn(r)
                except Exception as e:
                    r.step(fn.__name__, False, repr(e))
    except Exception as e:
        log.exception("run failed")
        r.step("error", False, repr(e))
    finally:
        try:
            step_close(r)
        except Exception as e:
            r.note("close: %r" % (e,))
    rep = write_report(r)
    if do_sync:
        try:
            if not sync(sha):
                log.error("sync: push failed after 3 attempts")
        except Exception as e:
            log.error("sync failed: %r", e)
    return rep


def loop():
    while True:
        try:
            sha = remote_sha()
            if sha and sha != read(LAST_SHA):
                with Lock():
                    once(sha)
                write(LAST_SHA, sha)
        except Exception:
            log.exception("loop iteration failed")
        time.sleep(POLL_S)


def shots_only(tag):
    """Attach to the running Studio (play already started) and run only the shot list."""
    r = Run(tag)
    r.mcp = mcp_client.McpSession(os.path.join(r.studio_dir, "StudioMCP.exe")).start()
    studios, _ = r.mcp.list_studios()
    if not studios:
        raise SystemExit("no Studio listed by MCP")
    r.studio_id = studios[0]["id"]
    win = win32.studio_main_window(win32.list_pids())
    r.hwnd = win["hwnd"] if win else None
    try:
        run_shots(r)
    finally:
        r.mcp.close()
    rep = write_report(r)
    print(json.dumps({"frames": rep["frames"], "notes": rep["notes"]}, indent=2))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("once")
    p.add_argument("--sha")
    p.add_argument("--no-sync", action="store_true")
    sub.add_parser("loop")
    p = sub.add_parser("shots-only")
    p.add_argument("--sha", default="manual-" + time.strftime("%Y%m%d-%H%M%S"))
    a = ap.parse_args(argv)

    os.makedirs(LOG_DIR, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        handlers=[logging.FileHandler(os.path.join(LOG_DIR, "watcher.log"), encoding="utf-8"),
                  logging.StreamHandler()],
    )
    try:
        win32.set_dpi_aware()
    except Exception:
        pass
    if a.cmd == "once":
        with Lock():
            rep = once(a.sha, not a.no_sync)
        print(json.dumps({"sha": rep["sha"], "status": rep["status"]}))
    elif a.cmd == "loop":
        loop()
    else:
        shots_only(a.sha)


if __name__ == "__main__":
    main()
