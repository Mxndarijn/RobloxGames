"""Tiny driver: python drv.py luau <Client|Server> <file.luau> [k=v ...]  |  shots <outdir> <n> [stepluau]"""
import sys, os, time, json, glob
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "..", "..", "..", "..", "tools", "pipeline", "pc-watcher"))
import mcp_client
SID = None
def session():
    global SID
    d = mcp_client.find_studio_dir()
    s = mcp_client.McpSession(os.path.join(d, "StudioMCP.exe")).start()
    r = s.call("list_roblox_studios", {}, timeout=30)
    for st in json.loads(r.text)["studios"]:
        if st.get("name") == "video.rbxl": SID = st["id"]
    assert SID, r.text
    return s
def sub(body, kv):
    for k, v in kv.items(): body = body.replace("%%" + k + "%%", v)
    return body
def shot(s, path):
    r = s.call("screen_capture", {"studio_id": SID, "capture_id": "v"}, timeout=60)
    ib = r.image_bytes()
    if not ib: raise RuntimeError(r.brief())
    open(path, "wb").write(ib[1])
if __name__ == "__main__":
    s = session()
    cmd = sys.argv[1]
    if cmd == "luau":
        kv = dict(a.split("=", 1) for a in sys.argv[4:])
        ok, data, r = s.luau(SID, sub(open(sys.argv[3], encoding="utf8").read(), kv), datamodel=sys.argv[2], timeout=300)
        print(json.dumps({"ok": ok, "data": data}, indent=1, default=str)[:4000])
    elif cmd == "play":
        print(s.call("start_stop_play", {"studio_id": SID, "is_start": sys.argv[2] == "1"}, timeout=120).text)
        if sys.argv[2] == "1":
            time.sleep(6)
            print(s.luau(SID, open(os.path.join(HERE, "..", "lua", "mute.luau")).read(), datamodel="Client")[1])
    elif cmd == "req":
        cmds = sys.argv[2]
        body = "workspace:SetAttribute('VidRes', '') workspace:SetAttribute('VidReq', [==[" + cmds + "]==]) return {}"
        print(s.luau(SID, body, datamodel="Server")[1])
        for i in range(120):
            time.sleep(1)
            ok, d, _ = s.luau(SID, "return {r = workspace:GetAttribute('VidRes')}", datamodel="Server")
            if d and d.get("r"):
                for line in json.loads(d["r"]): print(line[:400])
                break
    elif cmd == "shot":
        shot(s, sys.argv[2]); print("ok")
    elif cmd == "speed":
        t = time.time()
        for i in range(int(sys.argv[3])):
            shot(s, os.path.join(sys.argv[2], "s%03d.png" % i))
        print("per frame", (time.time() - t) / int(sys.argv[3]))
    s.close()
