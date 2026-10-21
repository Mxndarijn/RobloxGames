"""SlimeCam: frame-perfect clips of slime motion from the real Roblox renderer.

    python tools/slimecam/capture.py SCENARIO --studio NAME [--seconds 4] [--fps 30] [--out DIR] [--no-tags]

Needs a Studio in play mode (Memory DataStore) with this game, reachable over StudioMCP (pc-watcher's mcp_client).
A scenario is tools/slimecam/scenarios/<name>.luau (Client): it sets the scene up and starts whatever the player does,
then returns. The recorder (recorder.luau) records every rendered frame for --seconds, then replays it: clones are
posed frame by frame and each one is captured with StudioMCP screen_capture. Writes DIR/frame_####.jpg, DIR/clip.mp4,
DIR/clip.gif and DIR/sheet.jpg (a contact sheet), DIR defaulting to tools/slimecam/out/<scenario>.
A scenario may have a <name>.server.luau that runs first in the Server datamodel.
Dev tool only.
"""
import argparse
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "pipeline", "pc-watcher"))
import mcp_client  # noqa: E402


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def luau(s, sid, body, dm="Client", timeout=120):
    ok, data, res = s.luau(sid, body, dm, timeout=timeout)
    if not ok:
        raise RuntimeError("luau failed: %s" % (data,))
    return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scenario")
    ap.add_argument("--studio", required=True, help="the place name of YOUR Studio (e.g. v5.rbxl)")
    ap.add_argument("--seconds", type=float, default=4)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--radius", type=float, default=70)
    ap.add_argument("--out")
    ap.add_argument("--no-tags", action="store_true")
    ap.add_argument("--ui", action="store_true", help="keep the ScreenGuis on")
    ap.add_argument("--set", action="append", default=[], help="KEY=VALUE: _G.KEY = \"VALUE\" before the scenario runs")
    a = ap.parse_args()

    out = a.out or os.path.join(HERE, "out", a.scenario + "".join("-" + kv.split("=", 1)[1] for kv in a.set))
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.startswith("frame_"):
            os.remove(os.path.join(out, f))

    s = mcp_client.McpSession(os.path.join(mcp_client.find_studio_dir(), "StudioMCP.exe"), client_name="slimecam").start()
    try:
        studios, _ = s.list_studios()
        # Several sessions share this PC: only ever touch the one Studio named here (it stops / starts play).
        pick = [x for x in studios if a.studio and a.studio.lower() in x.get("blob", "").lower()]
        if len(pick) != 1:
            sys.exit("--studio must name exactly one connected Studio; connected: %s"
                     % [x.get("blob") for x in studios])
        sid = pick[0]["id"]
        state = s.call("get_studio_state", {"studio_id": sid}, timeout=30).text
        if "Client" in state:
            # a fresh play session for every clip (a replay takes the live slimes out on the client)
            s.call("start_stop_play", {"studio_id": sid, "is_start": False}, timeout=120)
            time.sleep(3)
            state = ""
        if "Client" not in state:
            # Edit mode: the in-memory store first (CLAUDE.md hard rule), then play
            luau(s, sid, 'workspace:SetAttribute("DataStoreMode", "Memory") return true', "Edit")
            s.call("start_stop_play", {"studio_id": sid, "is_start": True}, timeout=120)
            time.sleep(12)
        server = os.path.join(HERE, "scenarios", a.scenario + ".server.luau")
        if os.path.isfile(server):
            print("server setup:", luau(s, sid, read(server), "Server"))
        luau(s, sid, read(os.path.join(HERE, "recorder.luau")))
        prefix = "".join('_G.%s = "%s"\n' % tuple(kv.split("=", 1)) for kv in a.set)
        body = read(os.path.join(HERE, "scenarios", a.scenario + ".luau"))
        print("scenario:", luau(s, sid, prefix + body, timeout=240))
        luau(s, sid, "return _G.SlimeCam.start(%s)" % a.radius)
        time.sleep(a.seconds)
        n = luau(s, sid, "return _G.SlimeCam.stop()")
        print("recorded frames:", n)
        opts = "{ tags = %s, ui = %s }" % ("false" if a.no_tags else "true", "true" if a.ui else "false")
        luau(s, sid, "return _G.SlimeCam.prepare(%s)" % opts)
        step = max(1, round(60 / a.fps))
        k, idx, t0 = 1, 0, time.time()
        while k <= n:
            luau(s, sid, "return _G.SlimeCam.pose(%d)" % k)
            res = s.call("screen_capture", {"studio_id": sid, "capture_id": "cam%d" % idx}, timeout=60)
            img = res.image_bytes()
            if img:
                with open(os.path.join(out, "frame_%04d.jpg" % idx), "wb") as f:
                    f.write(img[1])
                idx += 1
            k += step
        print("captured %d frames in %.0f s" % (idx, time.time() - t0))
        luau(s, sid, "return _G.SlimeCam.finish()")
    finally:
        s.close()

    ff = ["ffmpeg", "-v", "error", "-y", "-framerate", str(a.fps), "-i", os.path.join(out, "frame_%04d.jpg")]
    subprocess.run(ff + ["-vf", "scale=960:-2", "-pix_fmt", "yuv420p", os.path.join(out, "clip.mp4")], check=True)
    subprocess.run(ff + ["-vf", "fps=%d,scale=640:-1:flags=lanczos" % min(a.fps, 20), os.path.join(out, "clip.gif")], check=True)
    cols = 6
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", str(a.fps), "-i", os.path.join(out, "frame_%04d.jpg"),
                    "-vf", "select='not(mod(n\\,%d))',scale=480:-1,tile=%dx4" % (max(1, idx // 24), cols),
                    "-frames:v", "1", os.path.join(out, "sheet.jpg")], check=True)
    print(out)


if __name__ == "__main__":
    main()
