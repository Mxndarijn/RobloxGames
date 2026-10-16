#!/usr/bin/env python3
"""Pytest-free checks of the watcher's pure parts. Runs on any OS (no Studio, no Win32):

  python selftest.py          (or: python watcher.py selftest)

Exit 0 when every check passes. Also py_compiles every .py here and checks each luau/*.luau
placeholder the watcher fills.
"""

import glob
import json
import os
import py_compile
import re
import sys
import tempfile

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


def t_actions():
    schema = {"properties": {"actions": {"type": "array", "items": {"oneOf": [
        {"properties": {"type": {"const": "mouseMove"}, "x": {}, "y": {}}, "required": ["type", "x", "y"]},
        {"properties": {"type": {"const": "mouseButtonDown"}, "button": {"enum": ["Left", "Right"]},
                        "position": {}}, "required": ["type", "position"]},
        {"properties": {"type": {"const": "mouseButtonUp"}, "button": {"enum": ["Left", "Right"]},
                        "position": {}}, "required": ["type"]},
    ]}}}}
    a = mcp_client.build_action(schema, "mouse_down", {"x": 5, "y": 6})
    check("schema mouse down", a == {"type": "mouseButtonDown", "position": {"x": 5, "y": 6}, "button": "Left"}, a)
    kschema = {"properties": {"actions": {"items": {"properties": {
        "action": {"enum": ["keyDown", "keyUp"]}, "key": {"enum": ["Down", "Escape", "E"]}}}}}}
    k = mcp_client.build_action(kschema, "key_down", {"key": "Escape"})
    check("schema key down (not the Down key)", k == {"action": "keyDown", "key": "Escape"}, k)
    d = mcp_client.build_action(None, "mouse_up", {"x": 1, "y": 2})
    check("default guess", d["type"] == "mouseButtonUp" and d["x"] == 1, d)
    o = mcp_client.build_action(schema, "key_up", {"key": "E"}, {"kind": "up", "k": "$key"})
    check("override template", o == {"kind": "up", "k": "E"}, o)


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
    check("fill args", watcher.fill_args(["-port", "$port", "$rbxl", "$nope"], {"port": "1", "rbxl": "f"})
          == ["-port", "1", "f", "$nope"])
    # Viewport = client - (468, 216): one step from the first guess.
    g = watcher.next_client_guess((390, 844), [((1000, 800), (532, 584))])
    check("viewport guess 1:1", g == (858, 1060), g)
    # 2x scale (viewport moves half as fast as the client): secant finds it.
    g2 = watcher.next_client_guess((500, 500), [((1000, 1000), (400, 400)), ((1100, 1100), (450, 450))])
    check("viewport guess secant", g2 == (1200, 1200), g2)
    ok = {k: {"status": "pass"} for k in watcher.HARD_STEPS}
    check("status pass", watcher.overall_status(dict(ok, two_player={"status": "warn"})) == "pass")
    check("status soft fail ignored", watcher.overall_status(dict(ok, shots={"status": "fail"})) == "pass")
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
    check("title ok", watcher.frame_title_ok("abc - Roblox Studio", []) and not watcher.frame_title_ok("Notepad", ["zz"]))


def t_win32_pure():
    rows = win32.parse_tasklist_csv('"RobloxStudioBeta.exe","1234","Console","1","500,000 K"\n"x.exe","9","S","0","1 K"\n')
    check("tasklist csv", rows == [("RobloxStudioBeta.exe", 1234), ("x.exe", 9)], rows)
    table = [(10, 1, "a"), (11, 10, "b"), (12, 11, "c"), (13, 2, "d")]
    check("descendants", win32.descendants(table, [10]) == {10, 11, 12})
    check("title has place", win32.title_has_place("abc.rbxl - Roblox Studio") and not win32.title_has_place("Roblox Studio"))


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
        "client_stats": {"SECONDS"}, "shot_find": {"TARGET"}, "viewport_probe": {"SHOW"},
        "panel_visible": {"PANEL", "SHOW"},
        "shot_camera": {"EYE", "AT"},
    }
    for f in sorted(glob.glob(os.path.join(HERE, "luau", "*.luau"))):
        name = os.path.splitext(os.path.basename(f))[0]
        with open(f, encoding="utf-8") as fh:
            src = fh.read()
        found = set(re.findall(r"%%([A-Z]+)%%", src))
        check("luau %s placeholders" % name, found == used.get(name, set()), found)
        check("luau %s returns" % name, re.search(r"^return ", src, re.M) is not None)
    shots = json.load(open(os.path.join(HERE, "shots.json"), encoding="utf-8"))
    check("shots.json is a list with ids", isinstance(shots, list) and all("id" in s for s in shots))


def main():
    for t in (t_png, t_crop, t_marked, t_studios, t_actions, t_watcher, t_win32_pure, t_lock, t_files):
        try:
            t()
        except Exception as e:  # a crashing group is a failure, keep going
            check(t.__name__ + " ran", False, repr(e))
    print("%d failed" % len(FAILS) if FAILS else "all ok")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
