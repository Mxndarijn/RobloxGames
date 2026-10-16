#!/usr/bin/env python3
"""Pytest-free checks of the watcher's pure parts. Runs on any OS (no Studio, no Win32):

  python selftest.py          (or: python watcher.py selftest)

Exit 0 when every check passes. Also py_compiles every .py here and checks each luau/*.luau
placeholder the watcher fills.
"""

import glob
import json
import math
import os
import py_compile
import re
import sys
import tempfile
import tokenize

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import imaging  # noqa: E402
import mcp_client  # noqa: E402
import watcher  # noqa: E402
import win32  # noqa: E402

FAILS = []


def check(name, cond, detail=""):
    print("%s %s%s" % ("ok  " if cond else "FAIL", name, (" - " + str(detail)) if detail and not cond else ""))
    if not cond:
        FAILS.append(name)


def t_png():
    w, h = 7, 5
    px = bytes((x * 30 + y * 7) % 256 for y in range(h) for x in range(w) for _ in range(3))
    data = imaging.encode_png(w, h, px)
    w2, h2, mode, px2 = imaging.decode_png(data)
    check("png roundtrip", (w2, h2, mode, px2) == (w, h, "RGB", px))
    bgra = bytes([10, 20, 30, 255] * 4)
    check("bgra->rgb", imaging.bgra_to_rgb(2, 2, bgra) == bytes([30, 20, 10] * 4))
    flat = imaging.frame_stats(64, 64, bytes([128] * 64 * 64 * 3))
    check("blank: flat grey", imaging.is_blank(flat), flat)
    noisy = bytes((i * 2654435761 >> 7) & 255 for i in range(64 * 64 * 3))
    st = imaging.frame_stats(64, 64, noisy)
    check("blank: noise is not blank", not imaging.is_blank(st), st)


def t_crop():
    w, h = 50, 40
    px = bytearray(b"\x10\x20\x30" * w * h)
    for y in range(5, 35):
        for x in range(7, 47):
            px[(y * w + x) * 3:(y * w + x) * 3 + 3] = b"\xff\x00\xff"
    px[(6 * w + 8) * 3:(6 * w + 8) * 3 + 3] = b"\x00\x00\x00"  # a top-bar icon over the probe
    rect = imaging.find_colour_rect(w, h, bytes(px))
    check("probe rect", rect == (7, 5, 40, 30), rect)
    soft = bytes(250 if b == 255 else b for b in px)
    check("probe rect tolerance", imaging.find_colour_rect(w, h, soft, tol=10) == (7, 5, 40, 30))
    check("probe absent", imaging.find_colour_rect(w, h, b"\x10\x20\x30" * w * h) is None)
    cw, ch, crop = imaging.crop_rgb(w, h, bytes(px), 7, 5, 40, 30)
    check("crop", (cw, ch, len(crop)) == (40, 30, 40 * 30 * 3) and crop[-3:] == b"\xff\x00\xff")


def t_marked():
    payload = {"ok": True, "data": {"n": 3, "s": "a\"b"}}
    raw = json.dumps(payload)
    text = "noise @@PCW:abc@@%s@@END@@ tail" % raw
    check("marker raw", mcp_client.extract_marked(text, "abc") == payload)
    quoted = json.dumps("@@PCW:abc@@%s@@END@@" % raw)  # text was a JSON string
    check("marker quoted", mcp_client.extract_marked(quoted, "abc") == payload)
    check("marker other nonce", mcp_client.extract_marked(text, "zzz") is None)
    code = mcp_client.wrap_luau("return { a = 1 }", "n1")
    check("wrap has marker + pcall", "@@PCW:n1@@" in code and "pcall(function()" in code)


def t_studios():
    listing = json.dumps({"studios": [
        {"studio_id": "11111111-1111-1111-1111-111111111111", "name": "Test Experience"},
        {"studio_id": "22222222-2222-2222-2222-222222222222", "name": "%s.rbxl" % ("ab" * 20)},
    ]})
    st = mcp_client.parse_studios(listing)
    check("parse json studios", [s["id"][:2] for s in st] == ["11", "22"], st)
    pick = mcp_client.pick_studio(st, ["ab" * 20 + ".rbxl"])
    check("pick ours by file name", pick and pick["id"].startswith("22"))
    text = "Studio 33333333-3333-3333-3333-333333333333 place foo.rbxl\nnothing here"
    st2 = mcp_client.parse_studios(text)
    check("parse text studios", len(st2) == 1 and "foo.rbxl" in st2[0]["blob"], st2)
    check("no pick for strangers", mcp_client.pick_studio(st, ["deadbeef"]) is None)


def t_watcher():
    sha = "a" * 40
    ls = "%s\trefs/heads/main\n%s\trefs/heads/mainline\n" % (sha, "b" * 40)
    check("ls-remote main", watcher.parse_ls_remote(ls, "main") == sha)
    check("ls-remote missing", watcher.parse_ls_remote(ls, "dev") is None)
    entries = [("b%d" % i, i) for i in range(8)]
    check("prune keeps newest 5", sorted(watcher.builds_to_prune(entries, 5)) == ["b0", "b1", "b2"])
    proj = {"name": "x", "tree": {"$className": "DataModel", "Workspace": {"$className": "Workspace",
                                                                          "$properties": {"A": 1}}}}
    tp = watcher.test_project(proj)
    check("test project memory attr", tp["tree"]["Workspace"]["$attributes"] == {"DataStoreMode": "Memory"}
          and "$attributes" not in proj["tree"]["Workspace"])
    # Viewport = client - (468, 216): one step from the first guess.
    g = watcher.next_client_guess((390, 844), [((1000, 800), (532, 584))])
    check("viewport guess 1:1", g == (858, 1060), g)
    # 2x scale (viewport moves half as fast as the client): secant finds it.
    g2 = watcher.next_client_guess((500, 500), [((1000, 1000), (400, 400)), ((1100, 1100), (450, 450))])
    check("viewport guess secant", g2 == (1200, 1200), g2)
    ok = {k: {"status": "pass"} for k in watcher.HARD_STEPS}
    check("status pass", watcher.overall_status(dict(ok, two_player={"status": "warn"})) == "pass")
    check("status soft fail ignored", watcher.overall_status(dict(ok, shots={"status": "fail"})) == "pass")
    check("status slide_walk fail is hard", watcher.overall_status(dict(ok, shots={"status": "fail", "detail": {"slide_walk_failed": True}})) == "fail")
    check("status 2p fail", watcher.overall_status(dict(ok, two_player={"status": "fail"})) == "fail")
    check("status skip hard", watcher.overall_status(dict(ok, esc={"status": "skip"})) == "fail")
    check("status missing hard", watcher.overall_status({"build": {"status": "pass"}}) == "fail")
    check("luau literal", watcher.luau_literal((1, 2.5, 3)) == "1.0, 2.5, 3.0" and watcher.luau_literal("a\"b") == '"a\\"b"'
          and watcher.luau_literal(7) == "7")
    eye, at = watcher.shot_camera({"pos": [0, 0, 0], "look": [0, 0, -1], "size": [10, 4, 10]})
    check("shot camera in front", at == (0, 0, 0) and eye[2] < 0 and eye[1] > 0, eye)
    # 35 deg down from max(extent) * 1.8 + 15 = 33 studs.
    eye, at = watcher.shot_camera({"pos": [10, 5, 0], "look": [1, 0, 0], "size": [10, 4, 2]})
    dx, dy = eye[0] - at[0], eye[1] - at[1]
    check("shot camera distance", abs((dx * dx + dy * dy) ** 0.5 - 33) < 1e-6 and abs(eye[2]) < 1e-9, eye)
    check("shot camera pitch 35", abs(watcher.math.degrees(watcher.math.atan2(dy, dx)) - 35) < 1e-6, (dx, dy))
    eye, _ = watcher.shot_camera({"pos": [0, 0, 0], "look": [0, -1, 0], "size": [4, 4, 4]})
    check("shot camera straight-down look", eye[1] > 0 and eye[2] > 0, eye)
    check("shot todo", watcher.shot_todo({"todo": "6/13"}) == "6/13"
          and watcher.shot_todo({"note": "TODO 11: bench"}) == "11" and watcher.shot_todo({"note": "x"}) is None)
    check("panel names", watcher.panel_for("dex") == "DexPanel" and watcher.panel_for("Leaders") == "LeaderboardPanel")
    check("two_player mode b removed", not any(k.startswith("twoplayer_") for k in watcher.DEFAULTS)
          and not hasattr(watcher, "twoplayer_cmdline"))
    m = {"found": True, "shown": True, "on_screen": True, "size": [195, 422], "viewport": [390, 844],
         "close": {"found": True, "shown": True, "on_screen": True}}
    r = watcher.menu_record(m, "f.jpg")
    check("menu record card", r == {"frac_w": 0.5, "frac_h": 0.5, "on_screen": True, "close_button": True,
                                    "frame": "f.jpg"}, r)
    off = dict(m, on_screen=False, close={"found": True, "shown": True, "on_screen": False})
    r2 = watcher.menu_record(off)
    check("menu record off-screen", not r2["on_screen"] and not r2["close_button"])
    check("menu record missing", not watcher.menu_record(None)["on_screen"])
    check("menus_failed", watcher.menus_failed({"d": {"shop": r, "dex": r2, "gone": watcher.menu_record(None)}})
          == ["d/dex", "d/gone"])
    check("phone perf pass", watcher.phone_perf_verdict({"fps": 45.0, "animating": 16}, 30, 16) == (True, []))
    ok, pr = watcher.phone_perf_verdict({"fps": 24.0, "animating": 9}, 30, 16)
    check("phone perf fail", not ok and len(pr) == 2, pr)
    check("phone perf animating only warns", watcher.phone_perf_verdict({"fps": 60.0, "animating": 3}, 30, 16)[0])
    check("menus/phone_perf are hard steps", all(s in watcher.HARD_STEPS and s in watcher.STEP_ORDER
                                                 for s in ("menus", "phone_perf")))
    check("title ok", watcher.frame_title_ok("abc - Roblox Studio", []) and not watcher.frame_title_ok("Notepad", ["zz"]))


def t_win32_pure():
    rows = win32.parse_tasklist_csv('"RobloxStudioBeta.exe","1234","Console","1","500,000 K"\n"x.exe","9","S","0","1 K"\n')
    check("tasklist csv", rows == [("RobloxStudioBeta.exe", 1234), ("x.exe", 9)], rows)
    table = [(10, 1, "a"), (11, 10, "b"), (12, 11, "c"), (13, 2, "d")]
    check("descendants", win32.descendants(table, [10]) == {10, 11, 12})
    check("title has place", win32.title_has_place("abc.rbxl - Roblox Studio") and not win32.title_has_place("Roblox Studio"))


def t_background():
    """Runs in the background: window pick (iconic too), focus guard, own-desktop launch, and
    no focus-stealing / OS-input / window-capture call left in the code."""
    row = dict(owned=False, visible=False, iconic=False, w=0, h=0, nw=0, nh=0)
    iconic = dict(row, hwnd=1, title="abc.rbxl - Roblox Studio", iconic=True, w=160, h=28, nw=1600, nh=900)
    splash = dict(row, hwnd=2, title="", visible=True, w=500, h=300, nw=500, nh=300)
    tool = dict(row, hwnd=3, title="Roblox Studio", owned=True, visible=True, w=1900, h=1000, nw=1900, nh=1000)
    ime = dict(row, hwnd=4, title="Default IME", nw=0, nh=0)
    pick = win32.pick_main_window([splash, tool, ime, iconic])
    check("main window: iconic Studio title wins", pick and pick["hwnd"] == 1, pick)
    hidden = dict(iconic, iconic=False, hwnd=5)
    check("main window: hidden window still found", (win32.pick_main_window([hidden]) or {}).get("hwnd") == 5)
    check("main window: untitled fallback", (win32.pick_main_window([splash]) or {}).get("hwnd") == 2)
    check("main window: owned only = none", win32.pick_main_window([tool]) is None)
    check("focus stolen", win32.focus_stolen(42, {41, 42}) and not win32.focus_stolen(7, {41, 42})
          and not win32.focus_stolen(0, {0}))
    st = {k: {"status": "pass"} for k in watcher.HARD_STEPS}
    run = watcher.Run.__new__(watcher.Run)
    run.steps, run.focus_stolen, run.notes, run.perf, run.frames, run.extra = st, ["FOCUS STOLEN at step devices"], [], {}, [], {}
    run.sha, run.studio_version, run.t0, run.fg_start = "a" * 40, None, 0, None
    rep = watcher.build_report(run)
    check("focus stolen fails the run", rep["status"] == "fail" and rep["background"]["focus_stolen"], rep["background"])
    banned = {"SetForegroundWindow", "BringWindowToTop", "SetActiveWindow", "SetFocus", "ShowWindow", "keybd_event",
              "SendInput", "mouse_event", "SetCursorPos", "BitBlt", "bring_to_front", "maximize", "restore",
              "SW_MAXIMIZE", "SW_RESTORE", "SetForegroundWindow", "place_offscreen", "hide_taskbar_button", "PrintWindow",
              "capture_client", "launch_background", "twoplayer_cmdline", "user_mouse_input", "user_keyboard_input",
              "mouse_down", "mouse_up", "key_down", "key_up", "mouseButtonDown", "keyboardInput"}
    for f in ("win32.py", "watcher.py", "mcp_client.py"):
        with open(os.path.join(HERE, f), encoding="utf-8") as fh:
            toks = list(tokenize.generate_tokens(fh.readline))
        # Names and exact quoted names ("ShowWindow" in a ctypes signature); comments/docstrings may explain.
        hits = ["%s:%d %s" % (f, t.start[0], t.string) for t in toks
                if (t.type == tokenize.NAME and t.string in banned)
                or (t.type == tokenize.STRING and t.string.strip("\"'") in banned)]
        check("no focus/OS-input calls in %s" % f, not hits, hits[:3])


def t_desktop():
    src = open(os.path.join(HERE, "win32.py"), encoding="utf-8").read()
    for needle in ("CreateDesktopW", "CreateProcessW", "lpDesktop", "OpenDesktopW", "SetThreadDesktop", "EnumDesktopWindows"):
        check("win32 uses %s" % needle, needle in src)
    wsrc = open(os.path.join(HERE, "watcher.py"), encoding="utf-8").read()
    check("launch on the Studio desktop", "launch_on_desktop" in wsrc and "screen_capture" in wsrc)
    luau = open(os.path.join(HERE, "luau", "cas_close.luau"), encoding="utf-8").read()
    check("esc uses the PcwPress hook", "PcwPress" in luau and ":CallFunction(" not in luau)


def t_lock():
    d = tempfile.mkdtemp()
    p = os.path.join(d, "x.lock")
    a, b = watcher.Lock(p), watcher.Lock(p)
    check("lock first", a.acquire())
    check("lock second refused", not b.acquire())
    a.release()
    check("lock after release", b.acquire())
    b.release()
    with open(p, "w") as f:
        json.dump({"pid": 999999999, "at": 0}, f)
    check("stale lock taken", a.acquire())
    a.release()


def t_files():
    for f in glob.glob(os.path.join(HERE, "*.py")):
        try:
            py_compile.compile(f, doraise=True, cfile=os.path.join(tempfile.mkdtemp(), "x.pyc"))
            ok = True
        except py_compile.PyCompileError as e:
            ok = False
            print(e)
        check("py_compile %s" % os.path.basename(f), ok)
    used = {
        "client_stats": {"SECONDS"}, "shot_find": {"TARGET", "INDEX"}, "geometry": {"CHECKS"},
        "panel_visible": {"PANEL", "SHOW"}, "ui_isolate": {"KEEP", "HIDE"},
        "shot_camera": {"EYE", "AT"}, "menu_measure": {"PANEL"}, "slime_fill": {"TARGET"},
        "phone_perf": {"SECONDS"}, "fountain_walk": set(), "habitat_set": {"PATH", "HABITAT", "WAIT", "LEAVE"}, "weather_set": {"WEATHER", "WAIT", "COVER"}, "slime_motion": {"PATH", "KIND", "WAIT"}, "slime_seat": {"PATH"}, "slide_walk": set(), "ring_slimes": set(), "despawn_fx": {"PATH", "WAIT"}, "wild_pace": {"SECONDS"},
        "hold_fill": {"NAME", "ON"}, "seat_clear": set(), "shot_aim": {"EYE", "AT"}, "growth_wait": {"PATH", "WAIT"},
        "slime_anim": {"PATH", "ANIM", "ID", "WAIT"}, "pad_seat": {"PATH"}, "rebirth_slime": {"STATE"}, "badge_toast": {"NAME"}, "friend_bonus": {"COUNT"}, "plot_slime": {"STATE"}, "admin_event": {"EVENT"}, "panel_scroll": {"PANEL", "TARGET"}, "pcw_attr": {"NAME", "VALUE"}, "pcw_clock": {"TIME"}, "weekend": {"ON"}, "fx_streaks": {"MAX"}, "plot_skin": {"SKIN"},
    }
    for f in sorted(glob.glob(os.path.join(HERE, "luau", "*.luau"))):
        name = os.path.splitext(os.path.basename(f))[0]
        with open(f, encoding="utf-8") as fh:
            src = fh.read()
        found = set(re.findall(r"%%([A-Z]+)%%", src))
        check("luau %s placeholders" % name, found == used.get(name, set()), found)
        if name == "pad_seat":
            check("luau pad_seat returns seat_y and pad_top_y", "seat_y =" in src and "pad_top_y =" in src)
        check("luau %s returns" % name, re.search(r"^return ", src, re.M) is not None)
    shots, shot_notes = watcher.load_shots()
    check("shots/*.json load as a list with ids", bool(shots) and not shot_notes and all("id" in s for s in shots), shot_notes)
    files = sorted(glob.glob(os.path.join(HERE, "shots", "*.json")), key=lambda p: (int(re.match(r"\d+", os.path.basename(p)).group()) if re.match(r"\d+", os.path.basename(p)) else 10**9, os.path.basename(p)))
    per_file = [json.load(open(f, encoding="utf-8")) for f in files]
    file_ids = [s["id"] for d in per_file for s in (d if isinstance(d, list) else [d])]
    check("shot ids are unique across files", len(file_ids) == len(set(file_ids)),
          sorted({i for i in file_ids if file_ids.count(i) > 1}))
    check("shot order matches filename order", file_ids == [s["id"] for s in shots])
    # NN is an ordering hint only: parallel PRs often pick the same next number, which must not break install
    check("shot filenames start with an <NN>- order prefix",
          all(re.match(r"\d+-", os.path.basename(f)) for f in files))
    check("shots/*.json has the idle-HUD overlay guard",
          any(s.get("kind") == "ui" and not s.get("open") and s.get("expect_no_overlay") for s in shots))
    holds = [s for s in shots if s.get("hold")]
    check("a ui shot shows a hold ring mid-hold on an important button",
          any(s.get("kind") == "ui" and s.get("open") and s["hold"] for s in holds), holds)
    motions = {s["motion"]: s for s in shots if s.get("motion")}
    check("motion shots cover idle squish, hop, look left and look right and the LOD tier counts",
          set(motions) == {"Idle", "Hop", "LookLeft", "LookRight", "Tiers"}, sorted(motions))
    check("luau slime_motion reports the LOD tier counts", "LifeTier" in open(os.path.join(HERE, "luau", "slime_motion.luau"), encoding="utf-8").read())
    check("motion shots seat a slime and wait", all(s.get("seat") and float(s.get("wait", 0)) > 0 for s in motions.values()))
    walks = [s for s in shots if s.get("slide_walk")]
    check("a slide_walk shot proves nobody falls through the slide, top to bottom",
          len(walks) == 1 and walks[0].get("target") == "slide" and walks[0].get("todo") == "B6", walks)
    sw = open(os.path.join(HERE, "luau", "slide_walk.luau"), encoding="utf-8").read()
    check("slide_walk is dense (joins, k=1.0, launched balls, no self-collision) and counts joint fillers",
          all(x in sw for x in ("0.98, 1 }", "AssemblyLinearVelocity", "SlideJoint", "escaped(")), None)
    check("a failing slide_walk fails the run (hard), not just warns",
          'return "fail", {"captured": done, "total": len(shots), "shots": results, "slide_walk_failed": True}'
          in open(os.path.join(HERE, "watcher.py"), encoding="utf-8").read())
    rings = [s for s in shots if s.get("ring_slimes")]
    check("a ring_slimes shot samples wild slimes against the landing ring (v30 C3)",
          len(rings) == 1 and rings[0].get("todo") == "v30 C3"
          and "OUTER" in open(os.path.join(HERE, "luau", "ring_slimes.luau"), encoding="utf-8").read(), rings)
    paces = [s for s in shots if s.get("wild_pace")]
    check("a wild_pace shot measures a lane slime's displacement against the Config pace (v30 C9)",
          len(paces) == 1 and float(paces[0]["wild_pace"]) > 0 and paces[0].get("todo") == "v30-c9", paces)
    caps = [s for s in shots if s.get("mesh_slots_max")]
    check("a mesh_slots_max shot asserts the play-world mesh slots <= 400 (hard)",
          len(caps) == 1 and caps[0]["mesh_slots_max"] <= 400 and caps[0].get("todo") == "border-v3", caps)
    check("a failing mesh_slots_max shot fails the run (hard)",
          'mesh_slots_failed": True' in open(os.path.join(HERE, "watcher.py"), encoding="utf-8").read()
          and watcher.overall_status({"shots": {"status": "pass", "detail": {"mesh_slots_failed": True}}}) == "fail")
    fwalks = [s for s in shots if s.get("fountain_walk")]
    check("a fountain_walk shot proves nobody sinks into the fountain top (C10)",
          len(fwalks) == 1 and fwalks[0].get("target") == "FountainMesh", fwalks)
    fw = open(os.path.join(HERE, "luau", "fountain_walk.luau"), encoding="utf-8").read()
    check("fountain_walk is dense (polar grid, resting + rolling, character-sized balls, no self-collision)",
          all(x in fw for x in ("ri * 0.5", "AssemblyLinearVelocity", "{ 2, 4 }", "CollisionGroupSetCollidable", "TopCollider")), None)
    check("a failing fountain_walk fails the run (hard), not just warns",
          '"fountain_walk_failed": True}' in open(os.path.join(HERE, "watcher.py"), encoding="utf-8").read())
    dfx = [s for s in shots if s.get("despawn_fx")]
    check("a despawn_fx shot seats a slime and samples it briefly (v30 C8)",
          len(dfx) == 1 and dfx[0].get("seat") and 0 < float(dfx[0].get("wait", 0)) <= 4, dfx)
    weathers = {s["weather"]: s for s in shots if s.get("weather")}
    check("weather shots cover Rain, Snow and Starfall with a short wait",
          set(weathers) == {"Rain", "Snow", "Starfall"} and all(0 < float(s.get("wait", 0)) <= 4 for s in weathers.values()), sorted(weathers))
    devs = {(s["weather"], s.get("device")) for s in shots if s.get("weather")}
    check("every weather type has a phone and a desktop shot",
          all((w, d) in devs for w in ("Rain", "Snow", "Starfall") for d in ("desktop", "phone-portrait")), sorted(devs, key=str))
    check("LOD tier shots at near, mid and far camera distances",
          sorted(s["dist"] for s in shots if s.get("motion") == "Tiers" and "dist" in s) == [20, 60, 120])
    known = {d[0] for d in watcher.DEFAULTS["devices"]} if hasattr(watcher, "DEFAULTS") else None
    check("shot devices are known device names", known is None or all(s["device"] in known for s in shots if s.get("device")), known)
    habitats = [s for s in shots if s.get("habitat")]
    types = {s["habitat"] for s in habitats}
    check("every habitat type has a shot with a slime seated on it",
          len(types) >= 9 and all(any(s["habitat"] == t and s.get("seat") for s in habitats) for t in types), sorted(types))
    check("no shot plays the uploaded animations", not [s for s in shots if s.get("anim") or s.get("animId")])


def t_data_path():
    import tempfile
    with tempfile.TemporaryDirectory() as repo:
        p, src = watcher.data_path(repo, "checks.json")
        check("data_path falls back to app copy", src == "app" and p == os.path.join(HERE, "checks.json"), (p, src))
        d = os.path.join(repo, "tools", "pipeline", "pc-watcher")
        os.makedirs(os.path.join(d, "shots"))
        with open(os.path.join(d, "checks.json"), "w", encoding="utf-8") as fh:
            fh.write("{}")
        p, src = watcher.data_path(repo, "checks.json")
        check("data_path prefers the repo copy", src == "repo" and p == os.path.join(d, "checks.json"), (p, src))
        p, src = watcher.data_path(repo, "shots")
        check("data_path resolves shots/ in the repo", src == "repo" and p == os.path.join(d, "shots"), (p, src))
        check("load_shots(repo=) reads the repo folder (empty -> None)", watcher.load_shots(repo=repo)[0] is None)
    check("data_path without a repo uses the app copy", watcher.data_path(None, "checks.json")[1] == "app")
    names = json.load(open(os.path.join(HERE, "checks.json"), encoding="utf-8"))["shops_face_centre"]
    check("shops_face_centre checks ShopStand only", names["names"] == ["ShopStand"] and names["min_items"] == 1 and names["min_dot"] == 0.9, names)


def t_geometry():
    checks = json.load(open(os.path.join(HERE, "checks.json"), encoding="utf-8"))
    good = {
        "bench_faces_campfire": {"items": [{"name": "b", "dot": 0.99}]},
        "shops_face_centre": {"items": [{"name": "a", "dot": 1.0}, {"name": "b", "dot": 0.95}]},
        "silo_centred": {"items": [{"name": "s", "dist": 0.01}]},
        "plot_signs": {"items": [{"name": "p", "dot_out": 0.99, "dot_gate_front": 0.98, "mirrored": False, "enabled": True}]},
    }
    v = watcher.geometry_verdict(good, checks)
    check("geometry all pass", all(x["pass"] for x in v.values()), v)
    bad = json.loads(json.dumps(good))
    bad["bench_faces_campfire"]["items"][0]["dot"] = -0.99
    bad["silo_centred"]["items"][0]["dist"] = 7.9
    bad["plot_signs"]["items"][0]["mirrored"] = True
    bad["shops_face_centre"] = {"items": [], "errors": ["no shop instance found"]}
    v = watcher.geometry_verdict(bad, checks)
    check("geometry fails flagged", [k for k, x in v.items() if not x["pass"]] ==
          ["bench_faces_campfire", "shops_face_centre", "silo_centred", "plot_signs"], v)
    check("geometry missing check fails", not watcher.geometry_verdict({}, checks)["silo_centred"]["pass"])
    t = {"pos": [10, 0, 0], "look": [0, 0, -1], "front": [1, 0, 0], "size": [4, 4, 4]}
    eye, at = watcher.shot_camera_from(t, "front", dist=10, height=3)
    check("shot from front", eye == (20.0, 3.0, 0.0) and at == (10, 0, 0), eye)
    eye, _ = watcher.shot_camera_from(t, "centre", dist=10, height=3)
    check("shot from centre", abs(eye[0]) < 1e-9 + 0.0 or abs(eye[0] - 0.0) < 1e-6, eye)
    eye, at = watcher.shot_camera_from(t, "behind", aim=[0, 0, 0], dist=5, height=2)
    check("shot from behind aim", eye == (15.0, 2.0, 0.0) and at == (0, 0, 0), eye)
    eye, _ = watcher.shot_camera_from(t, "look", dist=5, height=0)
    check("shot from look", eye[2] == -5.0, eye)


def main():
    for t in (t_png, t_crop, t_marked, t_studios, t_watcher, t_win32_pure, t_background, t_desktop, t_lock,
              t_files, t_geometry, t_data_path):
        try:
            t()
        except Exception as e:  # a crashing group is a failure, keep going
            check(t.__name__ + " ran", False, repr(e))
    print("%d failed" % len(FAILS) if FAILS else "all ok")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
