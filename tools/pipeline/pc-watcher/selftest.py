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
import time
import tokenize

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import imaging  # noqa: E402
import mcp_client  # noqa: E402
import watcher  # noqa: E402
import win32  # noqa: E402

FAILS = []
BUDGETS = json.load(open(os.path.join(HERE, "budgets.json"), encoding="utf-8"))


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
        "shot_camera": {"EYE", "AT", "FOV"}, "menu_measure": {"PANEL"}, "slime_fill": {"TARGET"},
        "phone_perf": {"SECONDS"}, "perf_stress": {"TARGET"}, "perf_quality": {"LEVEL"}, "perf_terrain_attr": set(), "perf_terrain_clear": set(), "perf_meshclone": {"TARGET"}, "perf_unique": {"COUNT"}, "perf_mem": set(), "perf_clean": set(), "perf_window": {"SECONDS", "CENTRE", "RADIUS", "HEIGHT"}, "perf_pose": {"ANGLE", "ON", "CENTRE", "RADIUS", "HEIGHT"}, "perf_phone_emulate": {"DEVICE"}, "fountain_walk": set(), "habitat_set": {"PATH", "HABITAT", "WAIT", "LEAVE"}, "weather_set": {"WEATHER", "WAIT", "COVER"}, "slime_motion": {"PATH", "KIND", "WAIT"}, "slime_seat": {"PATH"}, "slide_walk": set(), "ring_slimes": set(), "despawn_fx": {"PATH", "WAIT"}, "wild_pace": {"SECONDS"}, "mesh_stand": {"MESHES"}, "revenge_set": {"PLOT", "WAIT"},
        "hold_fill": {"NAME", "ON"}, "seat_clear": set(), "shot_aim": {"EYE", "AT"}, "growth_wait": {"PATH", "WAIT"},
        "slime_anim": {"PATH", "ANIM", "ID", "WAIT"}, "pad_seat": {"PATH"}, "rebirth_slime": {"STATE"}, "badge_toast": {"NAME"}, "friend_bonus": {"COUNT"}, "plot_slime": {"STATE"}, "admin_event": {"EVENT"}, "panel_scroll": {"PANEL", "TARGET"}, "pcw_attr": {"NAME", "VALUE"}, "pcw_clock": {"TIME"}, "weekend": {"ON"}, "rain": {"ON"}, "steal_alert": {"ON"}, "fx_streaks": {"MAX"}, "plot_skin": {"SKIN"}, "fountain_tier": {"TIER"}, "merge_vat": {"ON"}, "rain_magnet": {"ON"}, "world_shop": {"SHOP"}, "arrow_step": {"STEP"}, "dex_rows": {"COUNT"}, "panel_scroll_row": {"PANEL", "ROW"}, "daily_popup": {"ON"}, "welcome_back": {"ON"}, "flag_set": {"NAMES", "ON"}, "profiler_readout": {"WAIT"}, "audio_panel": {"ON"}, "bug_text_scan": {"PATTERN", "SHOW"}, "bug08_lock_enter": {"PART"}, "bug11_char_walk": {"PART"},
    }
    for f in sorted(glob.glob(os.path.join(HERE, "luau", "*.luau"))):
        name = os.path.splitext(os.path.basename(f))[0]
        with open(f, encoding="utf-8") as fh:
            src = fh.read()
        found = set(re.findall(r"%%([A-Z]+)%%", src))
        check("luau %s placeholders" % name, found == used.get(name, set()), found)
        if name == "pad_seat":
            check("luau pad_seat returns seat_y and pad_top_y", "seat_y =" in src and "pad_top_y =" in src)
        quoted = [l for l in src.splitlines() if not l.lstrip().startswith("--") and re.search(r"[\"']%%[A-Z]+%%[\"']", l)]
        check("luau %s has no quoted placeholders (luau_literal already quotes strings)" % name, not quoted, quoted)
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
    check("slide_walk checks the solid slide block: enter / climb (HARD) and stand / ride / reach (soft)",
          all(x in sw for x in ("cannot_enter", "cannot_climb", "cannot_stand_on", "slimes_still_ride", "bottom_reachable", "SlideFill", "soft_failed", "violations")), None)
    check("slide_walk's HARD ok is only cannot_enter and cannot_climb",
          'name == "cannot_enter" or name == "cannot_climb"' in sw and "ok = #violations == 0" in sw)
    def shared_body(path):
        t = open(os.path.join(HERE, "luau", path), encoding="utf-8").read()
        return t.split("-- ==== shared slide probe body", 1)[1].split("-- ==== end of shared body ====")[0]
    check("bug09_slide_stand shares slide_walk's probe body", shared_body("slide_walk.luau") == shared_body("bug09_slide_stand.luau"))
    check("a failing slide_walk fails the run (hard), not just warns",
          'return "fail", {"captured": done, "total": len(shots), "shots": results, "slide_walk_failed": True}'
          in open(os.path.join(HERE, "watcher.py"), encoding="utf-8").read())
    rings = [s for s in shots if s.get("ring_slimes")]
    check("a ring_slimes shot samples wild slimes against the landing ring (v30 C3)",
          len(rings) == 1 and rings[0].get("todo") == "v30 C3"
          and all(x in open(os.path.join(HERE, "luau", "ring_slimes.luau"), encoding="utf-8").read() for x in ("OUTER", '"Riding"')), rings)
    stands = [s for s in shots if s.get("mesh_stand")]
    check("mesh_stand shots (bug 11 part 1) walk into / stand on >= 2 Hull, >= 2 Box and every PCD converted mesh",
          len(stands) >= 3 and all(isinstance(s["mesh_stand"], list) and s["mesh_stand"] for s in stands), [s["id"] for s in stands])
    paces = [s for s in shots if s.get("wild_pace")]
    check("a wild_pace shot measures a lane slime's displacement against the Config pace (v30 C9)",
          len(paces) == 1 and float(paces[0]["wild_pace"]) > 0 and paces[0].get("todo") == "v30-c9", paces)
    caps = [s for s in shots if s.get("mesh_slots_max")]
    check("a mesh_slots_max shot compares the play-world mesh slots with the 500 soft budget (warn only)",
          len(caps) == 1 and caps[0]["mesh_slots_max"] == 500 and caps[0].get("todo") == "border-v3", caps)
    wsrc = open(os.path.join(HERE, "watcher.py"), encoding="utf-8").read()
    check("a failing mesh_slots_max shot only warns (MeshParts are soft); old mesh_slots_failed reports still fail",
          'mesh_slots_warned": True' in wsrc and 'mesh_slots_failed": True' not in wsrc
          and watcher.overall_status({"shots": {"status": "pass", "detail": {"mesh_slots_failed": True}}}) == "fail"
          and watcher.overall_status(dict({n: {"status": "pass"} for n in watcher.HARD_STEPS},
                                          shots={"status": "warn", "detail": {"mesh_slots_warned": True}})) == "pass")
    rcaps = [s for s in shots if s.get("runtime_parts_max")]
    check("a runtime_parts_max shot asserts world BaseParts <= the fixed 3000 cap (hard)",
          len(rcaps) == 1 and rcaps[0]["runtime_parts_max"] == BUDGETS["runtime_parts"]["fail"] == 3000, rcaps)
    check("a failing runtime_parts_max shot fails the run (hard)",
          'runtime_parts_failed": True' in open(os.path.join(HERE, "watcher.py"), encoding="utf-8").read()
          and watcher.overall_status({"shots": {"status": "pass", "detail": {"runtime_parts_failed": True}}}) == "fail")
    check("perf_server reports runtime_parts for every BasePart and the lane/collider presence",
          all(x in open(os.path.join(HERE, "luau", "perf_server.luau"), encoding="utf-8").read()
              for x in ("runtime_parts = runtimeParts", "parade_lane", "slide_colliders", "runtime_parts_transient"))
          and watcher.DEFAULTS["runtime_part_budget"] == 3000)
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
    rev = [s for s in shots if s.get("revenge_plot")]
    check("a revenge_plot shot aims at that plot and waits briefly (v21 Revenge)",
          len(rev) == 1 and rev[0].get("target") == "Plot_%d" % rev[0]["revenge_plot"] and 0 < float(rev[0].get("wait", 0)) <= 4, rev)
    # bugs #13-15 (soft terrain ground): a raw camera (pos + look + fov) on the concept's eye, and the shot_camera template takes the fov
    gshot = [s for s in shots if s.get("id") == "bugs13-15-ground-eye"]
    def polar(deg, r, y):
        a = math.radians(deg)
        return [-math.sin(a) * r, y, -math.cos(a) * r]
    check("the bugs13-15 ground shot uses the concept camera (eye polar(-20, 89, 6), look polar(-40, 50, 2), vertical FOV of a 26 mm lens)",
          len(gshot) == 1 and gshot[0]["kind"] == "world"
          and all(abs(a - b) < 0.01 for a, b in zip(gshot[0]["pos"], polar(-20, 89, 6)))
          and all(abs(a - b) < 0.01 for a, b in zip(gshot[0]["look"], polar(-40, 50, 2)))
          and abs(gshot[0]["fov"] - math.degrees(2 * math.atan(math.tan(math.atan(18 / 26)) * 9 / 16))) < 0.1, gshot)
    sc = open(os.path.join(HERE, "luau", "shot_camera.luau"), encoding="utf-8").read()
    check("shot_camera sets the field of view only when asked and the reset restores it",
          "if fov > 0 then" in sc and "PcwFov" in sc
          and "PcwFov" in open(os.path.join(HERE, "luau", "shot_camera_reset.luau"), encoding="utf-8").read()
          and watcher.luau_literal(42.6) == "42.6", None)
    # the snow_cover shots (SnowGround v2) pin the ground snow: Snow = settling, Clear = melting
    snow_shots = [s for s in shots if "snow_cover" in s]
    weathers = {s["weather"]: s for s in shots if s.get("weather") and "snow_cover" not in s}
    check("weather shots cover Rain, Snow and Starfall with a short wait",
          set(weathers) == {"Rain", "Snow", "Starfall"} and all(0 < float(s.get("wait", 0)) <= 4 for s in weathers.values()), sorted(weathers))
    snow_ids = {s["id"] for s in snow_shots}
    check("ground snow shots 18c cover settle mid, settle full and melt mid on pc and phone (SnowGround v2)",
          snow_ids == {"18c-snow-ground-%s-%s" % (k, d) for k in ("settle-mid", "settle-full", "melt-mid") for d in ("pc", "phone")}
          and all(0 <= float(s["snow_cover"]) <= 1 and 0 < float(s.get("wait", 0)) <= 4 for s in snow_shots)
          and all((s["weather"] == "Clear") == s["id"].startswith("18c-snow-ground-melt") for s in snow_shots), sorted(snow_ids))
    devs = {(s["weather"], s.get("device")) for s in shots if s.get("weather")}
    check("every weather type has a phone and a desktop shot",
          all((w, d) in devs for w in ("Rain", "Snow", "Starfall") for d in ("desktop", "phone-portrait")), sorted(devs, key=str))
    check("LOD tier shots at near, mid and far camera distances",
          sorted(s["dist"] for s in shots if s.get("motion") == "Tiers" and "dist" in s) == [20, 60, 70])
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
    check("shops_face_centre checks the world shop stands (ShopStand fallback)", names["names"] == ["ItemShopStand", "UpgradeShopStand", "ShopStand"] and names["min_items"] == 1 and names["min_dot"] == 0.9, names)


def t_budgets():
    import time
    D, B = watcher.DEFAULTS, BUDGETS
    check("DEFAULTS fallbacks equal budgets.json (single source)",
          (D["runtime_part_budget"], D["runtime_part_warn"], D["unique_mesh_budget"], D["world_triangle_budget"], D["mesh_slot_budget"])
          == (B["runtime_parts"]["fail"], B["runtime_parts"]["warn"], B["unique_meshes"]["fail"], B["world_triangles"]["fail"],
              B["mesh_parts"]["warn"]), (D, B))

    class Paths:
        repo = None

    class FakeRun:
        dry = False

        def __init__(self, probe, repo=None):
            self.probe, self.notes, self.extra = probe, [], {}
            self.cfg = dict(D)
            self.paths = Paths()
            self.paths.repo = repo
            self.perf = {}

        def need_luau(self, *a, **k):
            return dict(self.probe)

        def note(self, m):
            self.notes.append(m)

    base = {"mesh_slots": 391, "unique_meshes": 93, "runtime_parts": 2203, "parts": 2300}
    real_sleep, time.sleep = time.sleep, lambda s: None
    try:
        def perf(**kw):
            r = FakeRun(dict(base, **kw))
            st, det = watcher.step_perf(r)
            return st, det, r
        st, det, r = perf()
        check("perf: 2203 parts / 93 unique / 391 MeshParts pass without warnings", st == "pass" and "warnings" not in det, (st, det))
        check("perf: report keys keep their meaning and add the new ones",
              r.perf["budget"] == 500 and r.perf["runtime_part_budget"] == 3000 and r.perf["runtime_part_warn"] == 2900
              and r.perf["unique_mesh_budget"] == 120 and r.perf["triangles"] is None and r.perf["unique_meshes"] == 93, r.perf)
        st, det, r = perf(runtime_parts=2950)
        check("perf: 2950 parts passes with a warning", st == "pass" and len(det["warnings"]) == 1 and r.notes, (st, det))
        check("perf: 2900 parts is not yet a warning", "warnings" not in perf(runtime_parts=2900)[1])
        check("perf: 3000 parts passes (fail is strictly above)", perf(runtime_parts=3000)[0] == "pass")
        check("perf: 3001 parts fails", perf(runtime_parts=3001)[0] == "fail")
        check("perf: 121 unique meshes fails", perf(unique_meshes=121)[0] == "fail")
        st, det, _ = perf(mesh_slots=501)
        check("perf: 501 MeshParts only warns", st == "pass" and det["warnings"], (st, det))
        check("perf: unique_meshes absent (old probe) is unknown, not a failure",
              perf(unique_meshes=None)[0] == "pass")
        r = FakeRun({k: v for k, v in base.items() if k != "unique_meshes"})
        check("perf: probe without the unique_meshes key passes", watcher.step_perf(r)[0] == "pass")
        check("perf: no MeshParts still fails", perf(mesh_slots=0)[0] == "fail")
        with tempfile.TemporaryDirectory() as repo:
            d = os.path.join(repo, "tools", "pipeline", "pc-watcher")
            os.makedirs(d)
            with open(os.path.join(d, "budgets.json"), "w", encoding="utf-8") as fh:
                json.dump({"runtime_parts": {"fail": 3500, "warn": 3400}}, fh)
            r = FakeRun(dict(base, runtime_parts=3200), repo)
            check("budgets.json in the repo checkout overlays DEFAULTS (a cap bump is a JSON change)",
                  watcher.step_perf(r)[0] == "pass" and r.perf["runtime_part_budget"] == 3500, r.perf)
            with open(os.path.join(d, "budgets.json"), "w", encoding="utf-8") as fh:
                fh.write("{broken")
            r = FakeRun(dict(base, runtime_parts=3001), repo)
            check("a broken budgets.json falls back to DEFAULTS", watcher.step_perf(r)[0] == "fail" and r.perf["runtime_part_budget"] == 3000)
    finally:
        time.sleep = real_sleep


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


def t_flags():
    ok = lambda f: watcher.shot_flags_error({"flags": f})
    check("flags: absent is fine", watcher.shot_flags_error({}) is None)
    check("flags: a known flag forced on is fine", ok({"MergeVat3": True}) is None)
    check("flags: every FLAG_NAMES entry is accepted", all(ok({n: True}) is None for n in watcher.FLAG_NAMES))
    check("flags: unknown name rejected", "Nope" in (ok({"Nope": True}) or "") and "unknown" in (ok({"Nope": True}) or ""))
    check("flags: default-on flag name rejected", ok({"Weather": True}) is not None)
    check("flags: false / non-bool rejected (a shot only forces on)", ok({"Audio": False}) is not None and ok({"Audio": 1}) is not None)
    check("flags: empty / list rejected", ok({}) is not None and ok(["Audio"]) is not None)
    check("flags: boot flags are a subset", set(watcher.BOOT_FLAGS) <= set(watcher.FLAG_NAMES))
    check("flags: boot_flags collects only valid boot flags",
          watcher.boot_flags([{"flags": {"Audio": True, "MergeVat3": True}}, {"flags": {"Bogus": True}}, {}]) == ["Audio"])
    fo = os.path.join(HERE, "..", "..", "..", "games", "steal-a-slime", "src", "shared", "FeatureOverride.luau")
    if os.path.exists(fo):  # absent in the installed app copy (install.ps1 runs selftest there); CI checks it
        with open(fo, encoding="utf-8") as f:
            lua = f.read()
        block = re.search(r"FeatureOverride\.FLAGS = table\.freeze\(\{(.*?)\}\)", lua, re.S)
        lua_names = tuple(re.findall(r'"(\w+)"', block.group(1))) if block else ()
        check("flags: FLAG_NAMES matches src/shared/FeatureOverride.FLAGS", lua_names == watcher.FLAG_NAMES, lua_names)
    shots, _ = watcher.load_shots()
    forced = [s for s in shots if s.get("flags")]
    check("flags: every shot's flags field is valid", all(watcher.shot_flags_error(s) is None for s in forced))
    covered = {f for s in forced for f in s["flags"]}
    check("flags: every FEATURES flag has a shot", covered == set(watcher.FLAG_NAMES), sorted(set(watcher.FLAG_NAMES) - covered))
    for name in watcher.FLAG_NAMES:
        devs = {s.get("device") for s in forced if name in s["flags"]}
        check("flags: %s has a desktop shot" % name, "desktop" in devs, devs)
        ui = [s for s in forced if name in s["flags"] and s.get("kind") == "ui"]
        check("flags: %s ui shots include a phone-portrait one" % name,
              name in ("ServerProfiler",) or any(s.get("device") == "phone-portrait" for s in ui) or not ui, devs)


def t_partial():
    G = "games/steal-a-slime/"
    gm = watcher.path_glob_match
    check("glob ** zero dirs", gm("a/b.luau", "a/**/b.luau") and gm("a/x/y/b.luau", "a/**/b.luau"))
    check("glob * no slash", gm("a/b.md", "a/*.md") and not gm("a/x/b.md", "a/*.md") and gm("x/y/z.md", "**/*.md") and gm("z.md", "**/*.md"))
    check("glob ? and literal dot", gm("a1.lua", "a?.lua") and not gm("a1xlua", "a?.lua") and not gm("a/b.lua", "a?b.lua"))
    check("glob ** tail", gm("docs/a/b/c.txt", "docs/**") and not gm("docsx/a", "docs/**"))
    shots, notes = watcher.load_shots(repo=None)
    smap = watcher.read_json(watcher.data_path(None, "shot-map.json")[0])
    check("shot-map loads", bool(shots) and isinstance(smap, dict) and smap.get("rules"))
    ids = [s["id"] for s in shots]
    check("shot-map smoke ids exist", all(i in ids for i in smap["smoke"]), [i for i in smap["smoke"] if i not in ids])
    for rule in smap["rules"]:
        bad = []
        for g in rule.get("shots", []):
            if not any(watcher.shot_selected_by(s, {"shots": [g]}) for s in shots):
                bad.append(g)
        for k in rule.get("keys", []):
            if not any(k in s for s in shots):
                bad.append("key " + k)
        for k in rule.get("kinds", []):
            if not any(s.get("kind") == k for s in shots):
                bad.append("kind " + k)
        check("shot-map rule '%s' selectors match shots" % rule["name"], not bad and bool(rule.get("paths")), bad)
    names = [r["name"] for r in smap["rules"]]
    check("shot-map rule names unique", len(names) == len(set(names)))

    def plan(paths, n=60):
        return watcher.plan_run(paths, shots, smap, n)

    budget = [s["id"] for s in shots if "runtime_parts_max" in s or "mesh_slots_max" in s]
    check("budget shots exist", len(budget) == 2, budget)
    docs = plan(["docs/release-pipeline.md", G + "tools/pipeline/publish.sh", "tools/pr-gate/x.sh", G + "CLAUDE.md"])
    check("plan docs-only: partial, smoke + budget, no devices", docs["run_kind"] == "partial" and "devices" not in docs["steps"]
          and set(docs["shots"]) == set(smap["smoke"]) | set(budget), docs)
    check("plan docs-only: shots in shot order", docs["shots"] == [i for i in ids if i in docs["shots"]])
    shop = plan([G + "src/ui/Panels/Shop.luau"])
    check("plan shop panel", shop["run_kind"] == "partial" and "devices" in shop["steps"]
          and any("shop" in i for i in shop["shots"]) and set(budget) <= set(shop["shots"]), shop)
    pc = plan(["tools/pipeline/pc-watcher/watcher.py"])
    check("plan watcher.py -> full", pc["run_kind"] == "full" and pc["full_paths"], pc)
    check("plan Economy.luau -> full (unknown)", plan([G + "src/shared/Economy.luau"])["run_kind"] == "full"
          and plan([G + "src/shared/Economy.luau"])["unknown_paths"] == [G + "src/shared/Economy.luau"])
    check("plan Config.luau -> full", plan([G + "src/shared/Config.luau"])["run_kind"] == "full")
    check("plan 61 files -> full", plan(["docs/f%d.md" % i for i in range(61)])["run_kind"] == "full"
          and plan(["docs/f%d.md" % i for i in range(60)])["run_kind"] == "partial")
    border = plan([G + "src/server/BorderTerrainView.luau"])
    check("plan BorderTerrainView -> border shots, no ui", border["run_kind"] == "partial" and "devices" not in border["steps"]
          and any("border" in i for i in border["shots"])
          and not any(s["kind"] == "ui" and s["id"] in border["shots"] and s["id"] not in smap["smoke"] for s in shots), border)
    mixed = plan([G + "src/ui/Panels/Shop.luau", G + "src/shared/Economy.luau"])
    check("plan: one unknown path makes the run full", mixed["run_kind"] == "full")
    check("plan: modeling-kit out -> world, kit sources ignored",
          plan(["shared/modeling-kit/out/x.fbx"])["run_kind"] == "partial" and len(plan(["shared/modeling-kit/out/x.fbx"])["shots"]) > 100
          and len(plan(["shared/modeling-kit/models/a.json", "shared/modeling-kit/README.md"])["shots"]) == len(docs["shots"]))
    check("plan: weather in server", any("weather" in i.lower() for i in plan([G + "src/server/WeatherService.luau"])["shots"]))
    check("plan: empty diff = partial smoke", plan([])["run_kind"] == "partial")

    cfg = dict(watcher.DEFAULTS)
    t, l = "t" * 40, "l" * 40
    r1, r2 = "1" * 40, "2" * 40
    cw = watcher.choose_work
    check("work: request beats new tip", cw(t, l, 0, {r1}, set(), [t, r1], 1000, cfg, 1000) == ("full", r1, "candidate request"))
    check("work: newest request first, done ones skipped", cw(t, t, 0, {r1, r2}, {r2}, [t, r2, r1], 5, cfg, 0)[:2] == ("full", r1)
          and cw(t, t, 0, {r1, r2}, set(), [t, r2, r1], 5, cfg, 0)[:2] == ("full", r2))
    check("work: request outside depth ignored", cw(t, t, 0, {r1}, set(), ["x%d" % i for i in range(8)] + [r1], 5, cfg, 0)[0] is None)
    check("work: waits for candidate signal", cw(t, l, 0, set(), set(), [t], 1100, cfg, 1000) == (None, None, "waiting for candidate signal"))
    check("work: partial after wait", cw(t, l, 0, set(), set(), [t], 1000 + cfg["candidate_wait_s"], cfg, 1000)[:2] == ("partial", t))
    check("work: partial_runs off -> full", cw(t, l, 0, set(), set(), [t], 1001, dict(cfg, partial_runs=False), 1000)[:2] == ("full", t))
    check("work: idle tip -> full", cw(t, t, 0, set(), set(), [t], cfg["full_idle_s"], cfg, 0)[:2] == ("full", t)
          and cw(t, t, 0, set(), {t}, [t], 10 ** 6, cfg, 0)[0] is None and cw(t, t, 100, set(), set(), [t], 200, cfg, 0)[0] is None)

    ok = {k: {"status": "pass"} for k in watcher.HARD_STEPS}
    part = {"status": "skip", "detail": {"partial": True}}
    check("status partial-skipped devices pass", watcher.overall_status(dict(ok, devices=part, menus=part, phone_perf=part)) == "pass")
    check("status plain skip of hard step fails", watcher.overall_status(dict(ok, devices={"status": "skip", "detail": {}})) == "fail")
    check("status partial skip of a failed step still fails", watcher.overall_status(dict(ok, devices=part, esc={"status": "fail"})) == "fail")
    run = watcher.Run(watcher.Paths(tempfile.mkdtemp()), dict(watcher.DEFAULTS), None, True)
    rep = watcher.build_report(run)
    check("report always has run_kind/publishable/run_plan", rep["run_kind"] == "full" and rep["publishable"] is True and "run_plan" in rep)
    run.run_kind = "partial"
    rep = watcher.build_report(run)
    check("partial report not publishable", rep["run_kind"] == "partial" and rep["publishable"] is False)


def t_perf():
    import inspect
    e = watcher.perf_frame_stats([])
    check("perf stats empty", e["frames"] == 0 and e["avg_fps"] is None and e["low1_fps"] is None)
    one = watcher.perf_frame_stats([20.0])
    check("perf stats one frame", one["frames"] == 1 and one["avg_fps"] == 50.0 and one["low1_fps"] == 50.0
          and one["p99_ms"] == 20.0)
    dts = [10.0] * 99 + [50.0]  # 100 frames: worst 1% = the one 50 ms frame
    st = watcher.perf_frame_stats(dts)
    check("perf stats avg / low1", st["avg_fps"] == round(1000 / 10.4, 2) and st["low1_fps"] == 20.0 and st["max_ms"] == 50.0
          and st["p50_ms"] == 10.0 and st["p99_ms"] == 10.0, st)
    big = watcher.perf_frame_stats([16.0] * 1999 + [100.0])  # worst 0.1% = 2 frames
    check("perf stats low01", big["low01_fps"] == round(1000 / 58.0, 2), big)
    def win(q, p95, dc, ps=None):
        return {"quality": watcher.perf_quality_record(q, {"rendering_quality": "Enum.QualityLevel.Level%02d" % q,
                                                           "saved_quality": "Enum.SavedQualitySetting.QualityLevel%d" % q}),
                "client": {"avg_fps": 58.3, "low1_fps": 40.0, "p95_ms": p95, "p99_ms": 31.5,
                           "memory_categories": {"PlaceMemory": 321.0} if ps else None,
                           "render": {"SceneDrawcallCount": dc, "ShadowsDrawcallCount": 90.0, "RenderCPUFrameTime": 0.00512},
                           "render_unavailable": {"SceneTriangleCount": "not a valid member"}}}

    def vs(d1, dc1, added=1000):
        base = {"label": "base", "extra_target": 0, "windows": [win(10, 12.0, 900.0, 1), win(1, 8.0, 300.0)],
                "server": {"perf": {"runtime_parts": 2730, "mesh_slots": 300}, "mem": {"memory_categories": {"PlaceMemory": 100.0}}}}
        p = {"label": "+1000", "extra_target": 1000, "windows": [win(10, 14.0, 1200.0), win(1, 8.0 + d1, dc1)],
             "stress": {"target": 1000, "total_extra_parts": added} if added is not None else None,
             "server": {"perf": {"runtime_parts": 2730 + 561}}}
        return [{"label": "base-early", "extra_target": 0, "windows": [win(10, 20.0, 1.0)]}, base, p]
    rep = watcher.perf_build_report("a" * 40, "v", 30, vs(0.4, 450.0), None, ["n1"], 12.0, pc={"cpu": "x"})
    md = watcher.perf_report_md(rep)
    check("perf md table", "| base |" in md and "| +1000 |" in md and "| base-early |" in md and "n/a" in md
          and "SceneTriangleCount" in md and "n1" in md and "p95 ms" in md and "\u0394p95 vs base" in md
          and "PlaceMemory MB (client)" in md and "PlaceMemory MB (server)" in md and "client MB" not in md, md)
    check("perf verdict pass", watcher.perf_verdict(rep) == "+1000 (1000 parts added): \u0394p95 = 0.40 ms (<1 ms? yes), draw calls at Q1 = 450 (<=500? yes) -> 3000 cap PASS",
          watcher.perf_verdict(rep))
    check("perf md CPU ms converted from seconds", "| 5.12 |" in md and "| 0.01 |" not in md, md)
    check("perf md parts added column", "parts added" in md, md)
    pv90 = watcher.perf_verdict(watcher.perf_build_report("a" * 40, "v", 30, vs(0.4, 450.0, 900), None, [], 1.0))
    check("perf verdict pass at exactly 90% fill", pv90.endswith("PASS"), pv90)
    iv = watcher.perf_verdict(watcher.perf_build_report("a" * 40, "v", 30, vs(0.4, 450.0, 561), None, [], 1.0))
    check("perf verdict never PASS under 90% fill", "PASS" not in iv and "INCONCLUSIVE (only 561 of 1000 parts added" in iv, iv)
    fv = watcher.perf_verdict(watcher.perf_build_report("a" * 40, "v", 30, vs(0.4, 450.0, None), None, [], 1.0))
    check("perf verdict falls back to runtime_parts delta", "INCONCLUSIVE (only 561 of 1000" in fv and "PASS" not in fv, fv)
    check("perf verdict fail p95", watcher.perf_verdict(watcher.perf_build_report("a" * 40, "v", 30, vs(1.5, 450.0), None, [], 1.0)).endswith("FAIL"))
    check("perf verdict fail draw calls", "(<=500? no) -> 3000 cap FAIL" in watcher.perf_verdict(
        watcher.perf_build_report("a" * 40, "v", 30, vs(0.2, 501.0), None, [], 1.0)))
    nv = watcher.perf_verdict(watcher.perf_build_report("a" * 40, "v", 30, vs(0.2, 100.0)[:2], None, [], 1.0))
    check("perf verdict n/a", nv.endswith("n/a") and "n/a ms" in nv and "Q1 = n/a" in nv, nv)
    check("perf delta ignores base-early", watcher.perf_delta_p95(rep, rep["variants"][0], rep["variants"][0]["windows"][0]["quality"],
          rep["variants"][0]["windows"][0]["client"]) is None)
    check("perf quality parse", watcher.perf_parse_qualities("10,1") == [10, 1] and watcher.perf_parse_qualities("1, 3,6,3") == [1, 3, 6])
    for bad in ("", "0", "22", "x"):
        try:
            watcher.perf_parse_qualities(bad)
            check("perf quality parse rejects %r" % bad, False)
        except ValueError:
            check("perf quality parse rejects %r" % bad, True)
    qa = watcher.perf_quality_record(1, {"rendering_quality": "Enum.QualityLevel.Level01", "saved_quality": "Enum.SavedQualitySetting.QualityLevel1"})
    qn = watcher.perf_quality_record(10, {"rendering_quality": "Enum.QualityLevel.Automatic", "saved_quality": "Enum.SavedQualitySetting.Automatic"})
    qh = watcher.perf_quality_record(1, {"rendering_quality": "Enum.QualityLevel.Level01", "saved_quality": "Enum.SavedQualitySetting.QualityLevel10"})
    check("perf quality record", qa["label"] == "1" and qa["applied"] and qn["label"] == "unset (Automatic)" and not qn["applied"]
          and qh["label"] == "1 (rendering only)")
    d = tempfile.mkdtemp()
    watcher.perf_write(d, "e" * 40, dict(rep, status="partial"))
    check("perf incremental write", os.path.isfile(os.path.join(d, "e" * 40 + "-perf.json")) and
          "status: **partial**" in open(os.path.join(d, "e" * 40 + "-perf.md"), encoding="utf-8").read())
    skip = watcher.perf_report_md(dict(rep, variants=[{"label": "+10 unique meshes", "skipped": True, "reason": "no API"}]))
    check("perf skipped extra in md", "+10 unique meshes: skipped (no API)" in skip)
    check("perf report kind", rep["run_kind"] == "perf" and rep["publishable"] is False and rep["status"] == "measured"
          and "frames_reviewed" not in rep and "pass" not in json.dumps(rep["status"]))
    err = watcher.perf_build_report("a" * 40, None, 30, [], None, [], 1.0, error="boom")
    check("perf error report", err["status"] == "error" and err["run_kind"] == "perf" and err["publishable"] is False)
    src = inspect.getsource(watcher.cmd_perf) + inspect.getsource(watcher.sync_perf) + inspect.getsource(watcher.perf_variant)
    check("perf never names loop state", not any(n in src for n in ("last-sha", "last-full", "full-done", "tip-seen", "unsynced")), src[:0])
    check("perf sync path", watcher.perf_sync_path("b" * 40) == "perf/" + "b" * 40 and not watcher.perf_sync_path("c").startswith("studio-reports"))
    run = watcher.Run(watcher.Paths(tempfile.mkdtemp()), dict(watcher.DEFAULTS), "d" * 40, kind="perf")
    check("perf outdir", run.run_kind == "perf" and run.outdir.replace("\\", "/").endswith("out/perf/" + "d" * 40))
    cam = watcher.PERF_CAMERA
    for name, subs in (("perf_stress", {"target": 500}), ("perf_quality", {"level": 10}), ("perf_meshclone", {"target": 100}),
                       ("perf_unique", {"count": 10}), ("perf_window", {"seconds": 30, "centre": tuple(cam["centre"]),
                       "radius": cam["radius"], "height": cam["height"]})):
        body = open(os.path.join(HERE, "luau", name + ".luau"), encoding="utf-8").read()
        for k, v in subs.items():
            body = body.replace("%%" + k.upper() + "%%", watcher.luau_literal(v))
        check("luau %s filled" % name, "%%" not in body)
    inst_path = os.path.join(HERE, "install.ps1")
    if os.path.exists(inst_path):  # absent in the installed app copy (install.ps1 runs selftest from <Home>\app)
        inst = open(inst_path, encoding="utf-8").read()
        check("install copies luau", "luau\\*.luau" in inst)
        # every file this selftest opens from HERE must be one install.ps1 copies, or be guarded like this one
        copied = {"budgets.json", "checks.json", "shot-map.json"}
        guarded = {"install.ps1"}
        me = open(os.path.abspath(__file__), encoding="utf-8").read()
        named = set(re.findall(r'os\.path\.join\(HERE, "([^"/\\]+)"\)', me))
        missing = sorted(n for n in named if not n.endswith(".py") and n not in copied | guarded
                         and n not in ("luau", "shots") and ("Copy-Item -Force (Join-Path $PSScriptRoot \"%s\")" % n) not in inst)
        check("selftest only opens files the installed app has (install.ps1 copies them)", not missing, missing)


def t_lock_age():
    d = tempfile.mkdtemp()
    path = os.path.join(d, "run.lock")
    with open(path, "w") as f:
        json.dump({"pid": os.getpid(), "at": time.time() - 1900}, f)  # a live run 31.7 min in
    check("lock: a live 32-min-old run.lock is not stolen", watcher.Lock(path).acquire() is False)
    with open(path, "w") as f:
        json.dump({"pid": os.getpid(), "at": time.time() - 7300}, f)
    check("lock: older than 2 h counts as stale (pid reuse guard)", watcher.Lock(path).acquire() is True)


def t_perf_e2e():
    """cmd_perf end to end with every Studio/MCP call faked: catches a broken body (NameError etc.)."""
    import types
    home = tempfile.mkdtemp()
    w = watcher
    saved = {k: getattr(w, k) for k in ("step_build", "step_launch", "start_play", "step_close", "converge_viewport",
                                        "capture_frame", "perf_pc_info", "tracked_pids")}
    saved_luau, saved_need, saved_sleep = w.Run.luau, w.Run.need_luau, w.time.sleep
    calls = []

    def fake_luau(self, name, datamodel="Edit", timeout=60, **subs):
        calls.append(name)
        if name == "perf_window":
            return True, {"frames": 100, "dts_ms": [16.0] * 99 + [40.0], "avg_fps": 60.0, "p95_ms": 17.0,
                          "render": {"SceneDrawcallCount": 300}}
        if name == "perf_terrain_attr":
            return True, {"set": True}
        if name == "perf_stress":
            return True, {"added_parts": subs.get("target", 0), "clones": 1}
        return True, {"runtime_parts": 2200, "mesh_slots": 390}

    try:
        w.step_build = w.step_launch = lambda run: None
        w.start_play = lambda run: {}
        w.step_close = lambda run: ("pass", {})
        w.converge_viewport = lambda run, hwnd, target: ((1920, 1080), None)
        w.capture_frame = lambda run, tag, **kw: {"file": tag + ".jpg"}
        w.perf_pc_info = lambda: {"cpu": "test"}
        w.tracked_pids = lambda paths: []
        w.Run.luau = fake_luau
        w.Run.need_luau = lambda self, name, dm="Edit", timeout=60, **subs: fake_luau(self, name, dm, timeout, **subs)[1]
        w.time.sleep = lambda s: None
        paths = w.Paths(home)
        cfg = dict(w.DEFAULTS, sync=False)
        orig_run = w.Run

        class FakeRun(orig_run):
            def __init__(self, *a, **k):
                orig_run.__init__(self, *a, **k)
                self.hwnd = 1

            def record_foreground(self):
                pass

            def check_focus(self, where):
                return False
        w.Run = FakeRun
        try:
            rc = w.cmd_perf(paths, cfg, "a" * 40, [0, 500, 1000], 30, False, 5, False, False, qualities=(10, 1), opts={})
        finally:
            w.Run = orig_run
        outdir = os.path.join(home, "out", "perf", "a" * 40)
        rep = json.load(open(os.path.join(outdir, "a" * 40 + "-perf.json")))
        labels = [v["label"] for v in rep["variants"]]
        check("perf e2e: rc 0 and status measured", rc == 0 and rep["status"] == "measured", (rc, rep.get("status"), rep.get("error")))
        check("perf e2e: variants base-early/base/+500/+1000", labels == ["base-early", "base", "+500", "+1000"], labels)
        check("perf e2e: run_kind perf, not publishable", rep["run_kind"] == "perf" and rep["publishable"] is False)
        check("perf e2e: md written", os.path.isfile(os.path.join(outdir, "a" * 40 + "-perf.md")))
        check("perf e2e: settle recorded", (rep.get("settle") or {}).get("bt_set") is True, rep.get("settle"))
        check("perf e2e: never touches loop state", not any(os.path.exists(paths.st(f)) for f in
              ("last-sha.json", "last-full.json", "full-done.json", "tip-seen.json", "unsynced.json")))
        check("perf e2e: run.lock released", not os.path.exists(paths.st("run.lock")))
    finally:
        for k, v in saved.items():
            setattr(w, k, v)
        w.Run.luau, w.Run.need_luau, w.time.sleep = saved_luau, saved_need, saved_sleep


def t_play_settle():
    """step_play: boot sample + (full runs only) a settled sample after BorderTerrain; falls back to boot, never fails."""
    w = watcher
    saved = (w.start_play, w.Run.luau, w.Run.need_luau, w.time.sleep, w.time.time)
    clock = [1000.0]
    try:
        w.start_play = lambda run: {"store_status": "Memory"}
        w.time.sleep = lambda s: clock.__setitem__(0, clock[0] + s)
        w.time.time = lambda: clock[0]

        def run_play(kind, set_after, settled_raises=False):
            """set_after: poll index (1-based) at which the attribute turns true; None = never."""
            calls = {"attr": 0, "stats": 0}

            def fake_luau(self, name, datamodel="Edit", timeout=60, **subs):
                assert name == "perf_terrain_attr", name
                calls["attr"] += 1
                on = set_after is not None and calls["attr"] >= set_after
                return True, {"set": on, "source": "BorderTerrainReady" if on else None}

            def fake_need(self, name, dm="Edit", timeout=60, **subs):
                assert name == "client_stats", name
                calls["stats"] += 1
                if calls["stats"] == 2 and settled_raises:
                    raise w.StepFail("client gone")
                return {"fps": 53.2 if calls["stats"] == 1 else 60.0, "frame_time_ms": 18.8 if calls["stats"] == 1 else 16.7,
                        "memory_mb": 900.0 + calls["stats"]}
            w.Run.luau, w.Run.need_luau = fake_luau, fake_need
            run = w.Run(w.Paths(tempfile.mkdtemp()), dict(w.DEFAULTS), "f" * 40, kind=kind)
            status, detail = w.step_play(run)
            return run, status, detail, calls

        run, st, d, calls = run_play("full", 3)
        check("play settle: full run -> settled", st == "pass" and d["fps_source"] == "settled" and d["stats"]["fps"] == 60.0
              and d["stats_boot"]["fps"] == 53.2 and d["stats_settled"]["fps"] == 60.0 and calls["stats"] == 2, d)
        check("play settle: perf.play is settled, play_boot is boot", run.perf["play"]["fps"] == 60.0 and run.perf["play_boot"]["fps"] == 53.2
              and run.perf["play_settled"]["fps"] == 60.0 and run.perf["frame_time_ms"] == 16.7 and run.perf["memory_mb"] == 902.0, run.perf)
        check("play settle: wait record", run.perf["play_settle"]["bt_set"] is True and d["settle"]["settle_s"] == w.DEFAULTS["play_settle_s"]
              and d["settle"]["bt_set_at_s"] is not None and d["settle"]["max_s"] == w.DEFAULTS["play_bt_max_s"], d["settle"])
        check("play settle: records BorderTerrainReady as the signal", d["settle"]["bt_source"] == "BorderTerrainReady", d["settle"])
        src = open(os.path.join(os.path.dirname(os.path.abspath(w.__file__)), "luau", "perf_terrain_attr.luau")).read()
        check("perf_terrain_attr prefers Workspace BorderTerrainReady, falls back to Terrain BorderTerrain",
              'workspace:GetAttribute("BorderTerrainReady")' in src and 'terrain:GetAttribute("BorderTerrain")' in src
              and "source" in src)
        check("play settle: note mentions boot vs settled", any("settled" in n and "boot" in n for n in run.notes), run.notes)

        run, st, d, calls = run_play("full", None)
        check("play settle: never true -> boot, no settled sample", st == "pass" and d["fps_source"] == "boot" and d["stats_settled"] is None
              and run.perf["play_settled"] is None and run.perf["play"]["fps"] == 53.2 and calls["stats"] == 1
              and any("BorderTerrain" in n for n in run.notes), (d, run.notes))
        check("play settle: polling bounded", 2 <= calls["attr"] <= w.DEFAULTS["play_bt_max_s"] // 2 + 2, calls)

        run, st, d, calls = run_play("partial", 1)
        check("play settle: partial run -> no attr polls, boot", st == "pass" and calls["attr"] == 0 and calls["stats"] == 1
              and d["fps_source"] == "boot" and d["settle"] is None and run.perf["play_settled"] is None and run.notes, (d, calls))

        run, st, d, calls = run_play("full", 1, settled_raises=True)
        check("play settle: settled sample raising -> still pass with boot", st == "pass" and d["fps_source"] == "boot"
              and d["stats"]["fps"] == 53.2 and d["stats_settled"] is None and any("settled sample failed" in n for n in run.notes), (st, d, run.notes))

        run = w.Run(w.Paths(tempfile.mkdtemp()), dict(w.DEFAULTS), "f" * 40, dry=True)
        check("play settle: dry run skips", w.step_play(run)[0] == "skip")
    finally:
        w.start_play, w.Run.luau, w.Run.need_luau, w.time.sleep, w.time.time = saved


def t_bugs():
    """Advisory bug probes (Merijn's 2026-10-17 list): shots with `bug_probe`, luau/bug*.luau, shot-map selection, report wiring."""
    shots, _ = watcher.load_shots(repo=None)
    smap = watcher.read_json(watcher.data_path(None, "shot-map.json")[0])
    probes = [s for s in shots if "bug_probe" in s and isinstance(s["bug_probe"].get("bug"), int)]  # "R1".. = t_release
    bugs = [s["bug_probe"].get("bug") for s in probes]
    check("bug probes: bugs 1-16 covered (8 and 11 are split over several shots; 17 = no probe, new UI)", sorted(set(bugs)) == list(range(1, 17)), bugs)
    check("bug probes: world shots with title, ctx Server|Client", all(
        s.get("kind") == "world" and s["bug_probe"].get("title") and s["bug_probe"].get("ctx", "Server") in ("Server", "Client") for s in probes))
    for s in probes:
        bp = s["bug_probe"]
        if not bp.get("luau"):
            check("bug %s frame-only entry has a summary" % bp["bug"], bool(bp.get("summary")))
            continue
        f = os.path.join(HERE, "luau", bp["luau"] + ".luau")
        check("bug %s luau/%s.luau exists" % (bp["bug"], bp["luau"]), os.path.isfile(f))
        if os.path.isfile(f):
            src = open(f, encoding="utf-8").read()
            check("bug %s luau returns ok / summary / detail" % bp["bug"], all(re.search(r"\b%s = " % k, src) for k in ("ok", "summary", "detail")))
            check("bug %s args fill exactly the luau placeholders" % bp["bug"],
                  {k.upper() for k in (bp.get("args") or {})} == set(re.findall(r"%%([A-Z]+)%%", src)))
    names = {os.path.basename(f) for f in glob.glob(os.path.join(HERE, "luau", "bug*.luau"))}
    used = {s["bug_probe"]["luau"] + ".luau" for s in probes if s["bug_probe"].get("luau")}
    check("every luau/bug*.luau is used by a shot", names == used, sorted(names ^ used))
    rules = smap["rules"]
    allbug = next((r for r in rules if r["name"] == "bug probes"), None)
    check("shot-map: 'bug probes' rule selects every bug shot", bool(allbug) and all(watcher.shot_selected_by(s, allbug) for s in probes))
    check("shot-map: 'bug probes' rule maps luau/bug*.luau and shots/*bug*", bool(allbug) and all(
        watcher._any_glob(p, allbug["paths"], smap) for p in ("tools/pipeline/pc-watcher/luau/bug12_glow.luau", "tools/pipeline/pc-watcher/shots/160-bug01-leaving-text.json")))
    other = [r for r in rules if r["name"] != "bug probes"]
    check("shot-map: every bug shot is also selected by a source-area rule", all(any(watcher.shot_selected_by(s, r) for r in other) for s in probes),
          [s["id"] for s in probes if not any(watcher.shot_selected_by(s, r) for r in other)])
    expect = {"bug08_lock_enter": ("owner_passes", "owner_passes_after_respawn", "non_owner_blocked", "eject_once", "thrown_slime_not_stuck", "enforceLocks", "LoadCharacter",
                            "fence_jump_over", "fence_push_through", "gate_post_squeeze", "corner_squeeze"),
              "bug09_slide_stand": ("cannot_enter", "cannot_climb", "cannot_stand_on", "slimes_still_ride", "bottom_reachable"),
              "bug10_fountain_statues": ("pushed_out_or_on_top", "jump_no_snag"),
              "bug11_char_walk": ("stile_over", "barn_loft", "fence_line_walk", "ranch_fence_stile", "ranch_barn_loft"),
              "bug11_collision_fidelity": ("CreateMeshPartAsync", "PreciseConvexDecomposition", "Hull", "parts_saved", "colliders", "mesh_pcd", "mesh_hull")}
    for name, words in expect.items():
        src = open(os.path.join(HERE, "luau", name + ".luau"), encoding="utf-8").read()
        check("%s has its checks (%s...)" % (name, words[0]), all(w in src for w in words), [w for w in words if w not in src])
        check("%s %s and restores" % (name, "lists every check as PASS / FAIL / n/a" if name != "bug11_collision_fidelity" else "reports the comparison in its summary"),
              (all(w in src for w in ('"PASS"', '"FAIL"', '"n/a"')) or name == "bug11_collision_fidelity") and "pcall" in src and "Destroy" in src)
    b08 = open(os.path.join(HERE, "luau", "bug08_lock_enter.luau"), encoding="utf-8").read()
    m = re.search(r"local ORDER = \{([^}]*)\}", b08)
    order = re.findall(r'"(\w+)"', m.group(1)) if m else []
    check("bug08 BASE_ORDER lists the five old checks only; other PARTs list just themselves", re.search(r'local BASE_ORDER = \{ "owner_passes", "owner_passes_after_respawn", "non_owner_blocked", "eject_once", "thrown_slime_not_stuck" \}', b08) is not None
          and "local ORDER = if PART == \"base\" then BASE_ORDER else { PART }" in b08)
    parts = {"bug08_lock_enter": {"base", "fence_jump_over", "fence_push_through", "gate_post_squeeze", "corner_squeeze"}, "bug11_char_walk": {"stile_over", "barn_loft", "fence_line_walk"}}
    for lname, want in parts.items():
        got = {s["bug_probe"]["args"]["PART"] for s in probes if s["bug_probe"].get("luau") == lname}
        lsrc = open(os.path.join(HERE, "luau", lname + ".luau"), encoding="utf-8").read()
        check("%s: one shot per PART %s" % (lname, sorted(want)), got == want, got)
        check("%s: every PART value appears in the luau" % lname, all(('"%s"' % w) in lsrc for w in want))
    check("every bug probe shot timeout <= 50 s (one execute_luau call must stay well under 60 s)", all(int(s["bug_probe"].get("timeout", 30)) <= 50 for s in probes),
          [s["id"] for s in probes if int(s["bug_probe"].get("timeout", 30)) > 50])
    check("PART shots (not base) have timeout <= 45", all(int(s["bug_probe"].get("timeout", 30)) <= 45 for s in probes if s["bug_probe"].get("args", {}).get("PART", "base") != "base"))
    check("bug11_char_walk is registered by a bug_probe shot (bug 11)", any(s["bug_probe"].get("luau") == "bug11_char_walk" and s["bug_probe"]["bug"] == 11 for s in probes))
    check("bug 11 is informational (ok nil)", "ok = nil," in open(os.path.join(HERE, "luau", "bug11_collision_fidelity.luau"), encoding="utf-8").read())
    G = "games/steal-a-slime/src/"
    for path, wanted in ((G + "server/PlotLockGuard.luau", 8), (G + "server/WorldView.luau", 8), (G + "server/MeshSwap.luau", 10),
                         (G + "shared/MeshAssets.luau", 11), (G + "shared/MeshAssets.luau", 9), (G + "server/MeshSwap.luau", 9),
                         (G + "visuals/shared/RareSpawn.luau", 12), (G + "shared/ParadeLane.luau", 4), (G + "server/Spawner.luau", 5),
                         (G + "shared/SlideColliders.luau", 9), (G + "server/FountainColliders.luau", 10),
                         (G + "server/PlotSigns.luau", 8), (G + "visuals/client/VatFx.luau", 16), (G + "visuals/shared/BorderTerrain.luau", 14)):
        picked = watcher.plan_run([path], shots, smap, 60)["shots"]
        sid = next(s["id"] for s in probes if s["bug_probe"]["bug"] == wanted)
        check("plan %s picks bug %d" % (path.rsplit("/", 1)[1], wanted), sid in picked, picked[:5])
    slide_sid = next(x["id"] for x in shots if x.get("slide_walk"))
    for path in (G + "shared/SlideColliders.luau", G + "server/FountainColliders.luau", G + "server/MeshSwap.luau", G + "shared/MeshAssets.luau"):
        check("plan %s picks the slide_walk shot" % path.rsplit("/", 1)[1], slide_sid in watcher.plan_run([path], shots, smap, 60)["shots"])
    # advisory: a failing / erroring probe is a note and a report entry, never an exception or a step failure
    run = watcher.Run(watcher.Paths(tempfile.mkdtemp()), dict(watcher.DEFAULTS), None, True)
    shot = {"bug_probe": {"bug": 99, "title": "t", "luau": "bug04_lane_smooth", "ctx": "Server"}}

    def fake(result):
        def need(name, ctx="Server", timeout=60, /, **subs):
            if isinstance(result, Exception):
                raise result
            return result
        return need
    for label, result, ok in (("ok false", {"ok": False, "summary": "bad", "detail": {"n": 1}}, False),
                              ("ok null", {"ok": None, "summary": "visual"}, None),
                              ("ok true", {"ok": True, "summary": "fine"}, True),
                              ("StepFail", watcher.StepFail("mcp down"), False)):
        run.need_luau = fake(result)
        res = {}
        watcher.bug_probe(run, shot, res, "s")
        watcher.bug_record(run, shot, res, "s")
        check("bug probe %s -> bug.ok %s" % (label, ok), res["bug"]["ok"] is ok, res)
    check("failing bug probes are notes", sum("bug 99" in n for n in run.notes) == 2, run.notes)
    rep = watcher.build_report(run)
    check("report.bugs lists every probe", [b["ok"] for b in rep["bugs"]] == [False, None, True, False]
          and set(rep["bugs"][0]) == {"id", "title", "ok", "summary", "shot", "frame"}, rep["bugs"])
    check("bug probes never decide the status", watcher.overall_status({k: {"status": "pass"} for k in watcher.HARD_STEPS}) == "pass")
    check("step_shots verdict ignores bug probes", "bug" not in "".join(l for l in open(os.path.join(HERE, "watcher.py"), encoding="utf-8").read().split("def step_shots")[1].split("def watcher_studio_pids")[0].splitlines() if l.strip().startswith("if any(r.get")))


def t_release():
    """Release probes R1-R7 (advisory, luau/rel_*.luau): one shot each, wired through the bug_probe mechanism and the shot-map."""
    shots, _ = watcher.load_shots(repo=None)
    smap = watcher.read_json(watcher.data_path(None, "shot-map.json")[0])
    probes = [s for s in shots if isinstance(s.get("bug_probe", {}).get("bug"), str)]
    check("release probes: R1..R7 once each", sorted(s["bug_probe"]["bug"] for s in probes) == ["R%d" % n for n in range(1, 8)], [s["bug_probe"]["bug"] for s in probes])
    expect = {"rel_stackguard_eject": ("Server", ("eject_from_centre", "eject_under_top", "[PCW StackGuard] eject", "EmergeMesh")),
              "rel_fountain_top_walk": ("Server", ("circle_complete", "reaches_slide", "MoveTo", "SLIDE_PATH")),
              "rel_merge_vat_plots": ("Server", ("vat_exists", "hull_collides", "sits_on_plot", "character_rests", "Hull")),
              "rel_border_walls": ("Server", ("wall_count", "all_collide", "no_gap", "walk_blocked", "48")),
              "rel_shop_counter": ("Server", ("item_blocked", "item_jump", "upgrade_blocked", "upgrade_jump", "ItemShopStand", "UpgradeShopStand")),
              "rel_shop_prompt_client": ("Client", ("item_shown", "item_opens", "upgrade_shown", "upgrade_opens", "InputHoldBegin", "InputHoldEnd", "PcwPress", "WorldShopPanel")),
              "rel_minimap_pin": ("Client", ("minimap_ui", "player_pin", "MinimapData", "no minimap UI"))}
    used = {s["bug_probe"].get("luau"): s for s in probes}
    check("release probes: every luau/rel_*.luau is used by a shot", set(used) == set(expect) == {os.path.basename(f)[:-5] for f in glob.glob(os.path.join(HERE, "luau", "rel_*.luau"))})
    rules = smap["rules"]
    bugrule = next(r for r in rules if r["name"] == "bug probes")
    for name, (ctx, words) in expect.items():
        shot = used.get(name)
        src = open(os.path.join(HERE, "luau", name + ".luau"), encoding="utf-8").read()
        check("%s: shot is a world shot, ctx %s, <= 40 s, no placeholders" % (name, ctx), bool(shot) and shot.get("kind") == "world" and shot["bug_probe"].get("ctx") == ctx
              and int(shot["bug_probe"].get("timeout", 30)) <= 40 and not re.search(r"%%[A-Z]+%%", src) and not shot["bug_probe"].get("args"))
        check("%s has its checks (%s...)" % (name, words[0]), all(w in src for w in words), [w for w in words if w not in src])
        check("%s lists every check as PASS / FAIL / n/a and restores" % name, all(w in src for w in ('"PASS"', '"FAIL"', '"n/a"', "ORDER", "finish(", "pcall", "ok = ", "summary = ", "detail = ")))
        check("%s is selected by the 'bug probes' rule and its paths" % name, bool(shot) and watcher.shot_selected_by(shot, bugrule) and watcher._any_glob(
            "tools/pipeline/pc-watcher/luau/%s.luau" % name, bugrule["paths"], smap) and watcher._any_glob("tools/pipeline/pc-watcher/shots/%s.json" % shot["id"].replace("rel-", "rel-"), bugrule["paths"], smap)
            if shot else False)
        if ctx == "Server" and name != "rel_minimap_pin":
            check("%s unanchors the real character with server ownership and restores it" % name, all(w in src for w in ("SetNetworkOwner(nil)", "SetNetworkOwnershipAuto", "startAnchored", "startCF", "Destroy")))
    G = "games/steal-a-slime/src/"
    for path, ids in ((G + "server/StackGuard.luau", ("rel-stackguard-eject",)), (G + "visuals/shared/WorldBorder.luau", ("rel-border-walls",)),
                      (G + "visuals/shared/MinimapData.luau", ("rel-minimap-pin",)), (G + "ui/Panels/WorldShop.luau", ("rel-shop-prompt-client", "rel-shop-counter")),
                      (G + "server/WorldProps.luau", ("rel-shop-counter", "rel-shop-prompt-client", "rel-merge-vat-plots"))):
        picked = watcher.plan_run([path], shots, smap, 60)["shots"]
        check("plan %s picks %s" % (path.rsplit("/", 1)[1], ", ".join(ids)), all(i in picked for i in ids), picked[:8])


def main():
    for t in (t_perf, t_perf_e2e, t_lock_age, t_png, t_crop, t_marked, t_studios, t_watcher, t_win32_pure, t_background, t_desktop, t_lock,
              t_files, t_geometry, t_data_path, t_budgets, t_flags, t_partial, t_bugs, t_release, t_play_settle):
        try:
            t()
        except Exception as e:  # a crashing group is a failure, keep going
            check(t.__name__ + " ran", False, repr(e))
    print("%d failed" % len(FAILS) if FAILS else "all ok")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
