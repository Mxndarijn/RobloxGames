"""WalkCheck: drops wild slimes at awkward spots in a real Studio playtest and records how they walk back to the lane.

    python tools/walkcheck/run.py --studio NAME [--cases id,id] [--out DIR] [--no-shots]

Needs a Studio in play mode on the memory store (CLAUDE.md hard rule), reachable over StudioMCP (pc-watcher's
mcp_client); --studio names exactly one connected Studio (its place name). Mute the playtest first.
Each case in cases.json: the Server arms a recorder (arm.server.luau), the Client grabs a lane slime, carries it to the
spot and sends the real "Drop" request (drop.client.luau), Studio takes one screenshot mid-walk, and
the recorder samples the slime every Heartbeat until it is back on the lane. Checks per case:
  inside   a solid part within 60% of the body's half size (walks through things)
  floats   more than 1 stud over the ground under it, off the lane, after the fall
  back     reached the lane (within HALF_WIDTH) and stayed there
  detour   walked distance vs the straight line to the nearest lane point
Writes DIR/results.json, DIR/report.html (top view of every path) and DIR/<case>.jpg, DIR defaulting to
tools/walkcheck/out. Dev tool only.
"""
import argparse
import html
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))
sys.path.insert(0, os.path.join(REPO, "tools", "pipeline", "pc-watcher"))
import mcp_client  # noqa: E402

INSIDE_SHARE = 0.02  # more than 2% of frames inside a solid part = walks through
FLOAT_FRAMES = 10  # more frames than this floating = floats
DETOUR_WARN = 3.0
POP_STUDS = 10  # a move this far between two 0.1 s samples is a pop (Carry.pop), not a walk


def read(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return f.read()


def luau_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return json.dumps(v)
    if isinstance(v, list):
        return "{" + ", ".join(luau_value(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ", ".join("[%s] = %s" % (json.dumps(k), luau_value(x)) for k, x in v.items()) + "}"
    if v is None:
        return "nil"
    raise TypeError(v)


def script(case, name):
    return "local CASE = %s\n%s\n%s" % (luau_value(case), read("common.luau"), read(name))


def background(case, name, job):
    """The script run in a task, its result in _G.WalkCheckJobs[job] (a long glide outlasts one MCP call)."""
    body = script(case, name).replace("\n", "\n\t\t")
    slot = "_G.WalkCheckJobs[%s]" % json.dumps(job)
    return (
        "_G.WalkCheckJobs = _G.WalkCheckJobs or {}\n"
        "%s = { state = 'running' }\n"
        "task.spawn(function()\n\tlocal ok, r = pcall(function()\n\t\t%s\n\tend)\n"
        "\t%s = if ok then (r or {}) else { error = tostring(r) }\nend)\n"
        "return { started = true }" % (slot, body, slot)
    )


def job_result(job):
    return "return _G.WalkCheckJobs and _G.WalkCheckJobs[%s] or { state = 'missing' }" % json.dumps(job)


class Studio:
    def __init__(self, needle):
        self.s = mcp_client.McpSession(
            os.path.join(mcp_client.find_studio_dir(), "StudioMCP.exe"), client_name="walkcheck"
        ).start()
        studios, _ = self.s.list_studios()
        # Several sessions share this PC: only ever touch the one Studio named here.
        pick = [x for x in studios if needle.lower() in x.get("blob", "").lower()]
        if len(pick) != 1:
            sys.exit("--studio must name exactly one connected Studio; connected: %s" % [x.get("blob") for x in studios])
        self.sid = pick[0]["id"]
        state = self.s.call("get_studio_state", {"studio_id": self.sid}, timeout=30).text
        if "Client" not in state:
            sys.exit("Studio is not in play mode: start a playtest on the memory store first")

    def luau(self, body, dm, timeout=120):
        ok, data, res = self.s.luau(self.sid, body, dm, timeout=timeout)
        if not ok:
            raise RuntimeError("luau failed: %s" % (data,))
        return data

    def shot(self, path):
        r = self.s.call("screen_capture", {"studio_id": self.sid, "capture_id": "walkcheck"}, timeout=60)
        img = r.image_bytes()
        if img:
            with open(path, "wb") as f:
                f.write(img[1])

    def close(self):
        self.s.close()


def verdict(r):
    if r.get("error"):
        return "skip", [r["error"]]
    if r.get("state") != "done":
        return "skip", ["no result (%s)" % r.get("state")]
    out = []
    frames = max(1, r.get("frames", 1))
    if r["insideFrames"] / frames > INSIDE_SHARE:
        names = ", ".join(h[0] for h in r.get("hits", [])[:3])
        out.append("walks through (%d%% of frames; %s)" % (round(100 * r["insideFrames"] / frames), names))
    if r["floatFrames"] > FLOAT_FRAMES:
        out.append("floats (up to %.1f studs over the ground)" % r["maxFloat"])
    if r.get("reachedAt") is None:
        out.append("never back on the lane (%s)" % r.get("ended"))
    path = r.get("path") or []
    pops = [b[0] for a, b in zip(path, path[1:]) if ((b[1] - a[1]) ** 2 + (b[3] - a[3]) ** 2) ** 0.5 > POP_STUDS]
    if pops:
        out.append("popped onto the lane at %.1f s" % pops[0])
    detour = r["walked"] / max(1.0, r["straight"])
    if detour > DETOUR_WARN and not pops:
        out.append("long detour (%.1fx the straight line)" % detour)
    bad = [x for x in out if not x.startswith("long detour") and not x.startswith("popped")]
    return ("fail" if bad else "warn" if out else "pass"), out


def svg_for(r, lane):
    path = r.get("path") or []
    if not path:
        return ""
    xs = [p[1] for p in path]
    zs = [p[3] for p in path]
    pad = 14
    x0, x1, z0, z1 = min(xs) - pad, max(xs) + pad, min(zs) - pad, max(zs) + pad
    side = max(x1 - x0, z1 - z0, 40)
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    x0, z0 = cx - side / 2, cz - side / 2
    parts = []
    parts.append('<svg viewBox="%.1f %.1f %.1f %.1f" class="top">' % (x0, z0, side, side))
    parts.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" class="bg"/>' % (x0, z0, side, side))
    pts = " ".join("%.1f,%.1f" % (p[0], p[1]) for p in lane)
    parts.append('<polyline points="%s" class="lane"/>' % pts)
    for f in r.get("feet", []):
        x, z, ex, ez, top, name = f
        if top < 0.9:
            continue  # floor and goo, not obstacles
        parts.append(
            '<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" class="solid"><title>%s (top %.1f)</title></rect>'
            % (x - ex / 2, z - ez / 2, ex, ez, html.escape(name), top)
        )
    for a, b in zip(path, path[1:]):
        cls = "in" if b[4] else "fl" if b[5] > 1 else "ok"
        parts.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="p %s"/>' % (a[1], a[3], b[1], b[3], cls))
    d = r["drop"]
    parts.append('<circle cx="%.1f" cy="%.1f" r="%.1f" class="drop"/>' % (d[0], d[2], side / 80))
    parts.append("</svg>")
    return "".join(parts)


def report(results, lane, out):
    rows = []
    cards = []
    counts = {"pass": 0, "warn": 0, "fail": 0, "skip": 0}
    for case, r in results:
        v, notes = verdict(r)
        counts[v] += 1
        reached = r.get("reachedAt")
        rows.append(
            "<tr><td><a href='#%s'>%s</a></td><td><span class='v %s'>%s</span></td><td>%s</td><td class='n'>%s</td>"
            "<td class='n'>%s</td><td class='n'>%s</td></tr>"
            % (
                case["id"], case["id"], v, v, html.escape("; ".join(notes) or "-"),
                "%.1f s" % reached if reached is not None else "-",
                "%d%%" % round(100 * r["insideFrames"] / max(1, r["frames"])) if "frames" in r else "-",
                "%.1f" % r["maxFloat"] if "maxFloat" in r else "-",
            )
        )
        shot = case["id"] + ".jpg"
        img = "<img src='%s' alt='%s mid-walk'>" % (shot, case["id"]) if os.path.exists(os.path.join(out, shot)) else ""
        cards.append(
            "<section id='%s'><h2>%s <span class='v %s'>%s</span></h2><p>%s</p><div class='pair'>%s%s</div></section>"
            % (case["id"], case["id"], v, v, html.escape(case["what"]), svg_for(r, lane), img)
        )
    page = """<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>WalkCheck</title>
<style>
body{font:14px system-ui,sans-serif;margin:24px;background:#f4f6f5;color:#18211f}
table{border-collapse:collapse;background:#fff}td,th{padding:6px 10px;border-bottom:1px solid #dde4e2;text-align:left;vertical-align:top}
.n{font-variant-numeric:tabular-nums;white-space:nowrap}
.v{font:600 11px monospace;padding:2px 7px;border-radius:9px}.pass{background:#dcefdc;color:#2f7d3a}
.warn{background:#f5ead0;color:#8a5f00}.fail{background:#f6e0da;color:#b4442f}.skip{background:#e4e8e7;color:#556}
section{margin-top:28px}.pair{display:flex;gap:12px;flex-wrap:wrap}.pair>*{width:min(440px,100%%);height:auto}
svg.top{background:#fff;border:1px solid #dde4e2}.bg{fill:#eef2ef}.lane{fill:none;stroke:#7fd3bf;stroke-width:10;stroke-linejoin:round;opacity:.6}
.solid{fill:#8a9894;opacity:.55}.p{stroke-width:.8;stroke-linecap:round}.ok{stroke:#1d7a62}.in{stroke:#d23b1f;stroke-width:1.4}
.fl{stroke:#d99a00;stroke-width:1.2}.drop{fill:#18211f}
</style>
<h1>WalkCheck</h1><p>%s pass · %s warn · %s fail · %s skipped. Top view: grey = solid parts, teal band = lane,
path green = fine, <b style="color:#d23b1f">red</b> = inside a solid part, <b style="color:#d99a00">amber</b> = floating.</p>
<div style="overflow-x:auto"><table><tr><th>Case</th><th>Result</th><th>Why</th><th>Back on lane</th><th>Inside</th><th>Max float</th></tr>%s</table></div>%s
""" % (counts["pass"], counts["warn"], counts["fail"], counts["skip"], "".join(rows), "".join(cards))
    with open(os.path.join(out, "report.html"), "w", encoding="utf-8", newline="") as f:
        f.write(page)
    return counts


LANE_POINTS = """
local ParadeLane = require(game:GetService("ReplicatedStorage").Shared.ParadeLane)
local out = {}
for i = 0, 240 do
	local x, z = ParadeLane.pointAt(ParadeLane.LENGTH * i / 240)
	table.insert(out, { math.floor(x * 10) / 10, math.floor(z * 10) / 10 })
end
return out
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--studio", required=True)
    ap.add_argument("--cases")
    ap.add_argument("--out", default=os.path.join(HERE, "out"))
    ap.add_argument("--no-shots", action="store_true")
    ap.add_argument("--report-only", action="store_true", help="rebuild report.html from DIR/results.json")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    cases = json.loads(read("cases.json"))
    if a.cases:
        want = a.cases.split(",")
        cases = [c for c in cases if c["id"] in want]
    if a.report_only:
        with open(os.path.join(a.out, "results.json"), encoding="utf-8") as f:
            saved = json.load(f)
        print(report([(c, r) for c, r in saved["cases"]], saved["lane"], a.out))
        return

    st = Studio(a.studio)
    results = []
    try:
        lane = st.luau(LANE_POINTS, "Server")
        for case in cases:
            print("==", case["id"], flush=True)
            r = None
            try:
                armed = st.luau(script(case, "arm.server.luau"), "Server")
                if not armed.get("armed"):
                    r = {"error": armed.get("error", "not armed")}
                else:
                    job = "%s-%d" % (case["id"], int(time.time() * 1000))
                    st.luau(background(case, "drop.client.luau", job), "Client")
                    t = time.time()
                    dropped = {"state": "running"}
                    while dropped.get("state") == "running" and time.time() - t < 600:
                        time.sleep(1)
                        dropped = st.luau(job_result(job), "Client")
                    if dropped.get("state") == "running":
                        dropped = {"error": "client step took over 600 s"}
                    if dropped.get("error"):
                        r = {"error": dropped["error"]}
                    else:
                        print("   dropped", dropped.get("species"), "size %.1f" % (dropped.get("size") or 0), flush=True)
                        if not a.no_shots:
                            # the player's own follow camera: a script-set camera is undone by Studio after each
                            # execute_luau, and one left pointing away hides every prompt (no more grabs)
                            time.sleep(1.5)
                            st.shot(os.path.join(a.out, case["id"] + ".jpg"))
                        t = time.time()
                        while time.time() - t < case.get("seconds", 60) + 60:
                            r = st.luau(script(case, "collect.server.luau"), "Server")
                            if r.get("state") == "done":
                                break
                            time.sleep(2)
                        r = dict(r, species=dropped.get("species"), size=dropped.get("size"))
            except Exception as e:  # one broken case must not stop the rest
                r = {"error": "harness: %s" % e}
            v, notes = verdict(r)
            print("  ", v, "; ".join(notes), flush=True)
            results.append((case, r))
    finally:
        st.close()
    with open(os.path.join(a.out, "results.json"), "w", encoding="utf-8", newline="") as f:
        json.dump({"lane": lane, "cases": results}, f, indent=1)
    print(report(results, lane, a.out))


if __name__ == "__main__":
    main()
