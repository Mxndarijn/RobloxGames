"""Frame-stepped capture. python clip.py <shotname> [startframe]  (shots defined in shots.py)"""
import sys, os, time, json, math
import drv
import shots

FPS = 30

def lerp(a, b, t): return [a[i] + (b[i] - a[i]) * t for i in range(3)]
def ease(t): return t * t * (3 - 2 * t)

def cam_at(keys, t):
    """keys: list of (time, pos, at). Smooth (eased) between keys; Catmull-Rom on positions."""
    if t <= keys[0][0]: return keys[0][1], keys[0][2]
    if t >= keys[-1][0]: return keys[-1][1], keys[-1][2]
    for i in range(len(keys) - 1):
        t0, t1 = keys[i][0], keys[i + 1][0]
        if t0 <= t <= t1:
            u = (t - t0) / (t1 - t0)
            return lerp(keys[i][1], keys[i + 1][1], u), lerp(keys[i][2], keys[i + 1][2], u)

def fmt(v): return ",".join("%.3f" % x for x in v)

def run(name, start=0):
    shot = shots.SHOTS[name]
    out = os.path.join(os.environ["VIDEO_WORK"], "clips", name)  # frames stay outside the repo
    os.makedirs(out, exist_ok=True)
    s = drv.session()
    if shot.get("pre_req"):
        s.luau(drv.SID, "workspace:SetAttribute('VClock', nil) workspace:SetAttribute('VServer', nil) return {}", datamodel="Server")
        s.luau(drv.SID, "workspace:SetAttribute('VidRes', '') workspace:SetAttribute('VidReq', [==[" + shot["pre_req"] + "]==]) return {}", datamodel="Server")
        time.sleep(shot.get("pre_wait", 5))
        print("pre", s.luau(drv.SID, "return {r = workspace:GetAttribute('VidRes')}", datamodel="Server")[1])
    s.luau(drv.SID, "game.Lighting:SetAttribute('PcwClock', %r) return {}" % shot.get("clock", 13.5), datamodel="Server")
    ok, base, _ = s.luau(drv.SID, """
        local c, v = workspace:GetAttribute("VClock"), workspace:GetAttribute("VServer")
        if type(c) ~= "number" then c = os.clock() end
        if type(v) ~= "number" then v = workspace:GetServerTimeNow() end
        workspace:SetAttribute("VClock", c) workspace:SetAttribute("VServer", v)
        return {c = c, v = v}""", datamodel="Server")
    assert ok, base
    ctl = open(os.path.join(os.path.dirname(__file__), "..", "lua", "ctl.luau")).read().replace("%%HIDECHAR%%", "true" if shot.get("hidechar") else "false")
    print("ctl", s.luau(drv.SID, ctl + "", datamodel="Client")[1])
    s.luau(drv.SID, "workspace:SetAttribute('VHideBB', %s) workspace:SetAttribute('VKeepGui', %s) return {}" % ("true" if shot.get("hidebb", True) else "false", repr(shot["keepgui"]) if shot.get("keepgui") else "nil"), datamodel="Client")
    if shot.get("setup_server"):
        print("setup_server", s.luau(drv.SID, shot["setup_server"], datamodel="Server", timeout=120)[1])
    if shot.get("setup_client"):
        print("setup_client", s.luau(drv.SID, shot["setup_client"], datamodel="Client", timeout=120)[1])
    n = int(shot["dur"] * FPS)
    c0, v0 = base["c"], base["v"]
    t_start = time.time()
    for k in range(start, n):
        t = k / FPS
        dc = c0 + 1.0 / FPS * (k + 1)
        dv = v0 + 1.0 / FPS * (k + 1)
        sx = shot.get("server_frame", lambda t, k: "")(t, k)
        ok, r, _ = s.luau(drv.SID, "workspace:SetAttribute('VClock', %r) workspace:SetAttribute('VServer', %r) %s return {}" % (dc, dv, sx), datamodel="Server")
        if not ok: print("server frame", k, r)
        if "cam" in shot:
            p, a = shot["cam"](t)
        else:
            p, a = cam_at(shot["keys"], t)
        cx = shot.get("client_frame", lambda t, k: "")(t, k)
        body = """
            local RS = game:GetService("RunService")
            workspace:SetAttribute("VCamPos", Vector3.new(%s)) workspace:SetAttribute("VCamAt", Vector3.new(%s))
            local t0 = os.clock()
            while workspace:GetAttribute("VServer") ~= %r and os.clock() - t0 < 3 do RS.RenderStepped:Wait() end
            %s
            RS.RenderStepped:Wait() RS.RenderStepped:Wait()
            return {}""" % (fmt(p), fmt(a), dv, cx)
        ok, r, _ = s.luau(drv.SID, body, datamodel="Client")
        if not ok: print("client frame", k, r)
        drv.shot(s, os.path.join(out, "f%04d.jpg" % k))
        if k % 15 == 0:
            el = time.time() - t_start
            print("frame %d/%d  %.2fs/frame" % (k, n, el / (k - start + 1)), flush=True)
    s.close()

if __name__ == "__main__":
    run(sys.argv[1], int(sys.argv[2]) if len(sys.argv) > 2 else 0)
