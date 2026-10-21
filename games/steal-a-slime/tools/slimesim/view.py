"""Turns SlimeSim traces (tools/slimesim, JSON) into one self-contained HTML viewer.

    python tools/slimesim/view.py TRACE.json [AFTER.json] [-o out.html] [--title "..."]

With two traces the viewer shows them side by side on one shared playhead (before / after). Standard library only.
"""
import argparse
import json
import os

PAGE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>__TITLE__</title>
<style>
:root{--bg:#f6f5f2;--panel:#fff;--ink:#1f2328;--muted:#6a6f76;--line:#d9d6cf;--lane:#bfe8f2;--laneEdge:#7cc8da;--accent:#2f6fdf;--warn:#d9534f}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#15171a;--panel:#1d2024;--ink:#e6e6e6;--muted:#9aa0a6;--line:#30343a;--lane:#1d4e5a;--laneEdge:#2f7f92;--accent:#7aa7ff;--warn:#ff7b72}}
:root[data-theme="dark"]{--bg:#15171a;--panel:#1d2024;--ink:#e6e6e6;--muted:#9aa0a6;--line:#30343a;--lane:#1d4e5a;--laneEdge:#2f7f92;--accent:#7aa7ff;--warn:#ff7b72}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--ink);font:14px/1.45 system-ui,-apple-system,Segoe UI,sans-serif}
header{padding:14px 16px 6px}h1{font-size:18px;margin:0 0 4px}p.sub{margin:0;color:var(--muted)}
.bar{display:flex;flex-wrap:wrap;gap:8px;align-items:center;padding:8px 16px;position:sticky;top:0;background:var(--bg);z-index:2;border-bottom:1px solid var(--line)}
button,select{font:inherit;padding:5px 10px;border-radius:8px;border:1px solid var(--line);background:var(--panel);color:var(--ink);cursor:pointer}
input[type=range]{flex:1;min-width:160px}
.grid{display:grid;grid-template-columns:repeat(var(--cols),minmax(0,1fr));gap:12px;padding:12px 16px}
.card{background:var(--panel);border:1px solid var(--line);border-radius:12px;padding:10px;min-width:0}
.card h2{font-size:15px;margin:0 0 6px}
canvas{width:100%;display:block;border-radius:8px;background:var(--bg)}
table{border-collapse:collapse;width:100%;font-size:12.5px;font-variant-numeric:tabular-nums}
td,th{padding:3px 6px;border-bottom:1px solid var(--line);text-align:right}td:first-child,th:first-child{text-align:left}
.bad{color:var(--warn);font-weight:600}.legend{display:flex;flex-wrap:wrap;gap:10px;color:var(--muted);font-size:12px;margin-top:6px}
.legend span::before{content:"";display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:4px;vertical-align:-1px;background:var(--c)}
@media (max-width:820px){.grid{grid-template-columns:1fr}}
</style></head><body>
<header><h1>__TITLE__</h1><p class="sub">Top-down view of the goo lane from the simulation. Click a slime to follow its timeline. Dots: where the slime is drawn (last second). Grey squares: where its name tag and Buy card hang (the replicated Body). A line joins each slime to its tag.</p></header>
<div class="bar">
<button id="play">Pause</button>
<select id="speed"><option value="0.1">0.1x</option><option value="0.25">0.25x</option><option value="0.5">0.5x</option><option value="1" selected>1x</option></select>
<button id="prev" title="previous frame (←)">◀</button><button id="next" title="next frame (→)">▶</button>
<input id="scrub" type="range" min="0" value="0">
<span id="clock" style="font-variant-numeric:tabular-nums;min-width:70px"></span>
<label><input type="checkbox" id="trails" checked> trails</label>
<select id="zoom"><option value="10">far</option><option value="18" selected>mid</option><option value="30">close</option></select>
</div>
<div class="grid" id="panes"></div>
<div class="grid" style="--cols:1"><div class="card"><h2>Metrics</h2><div id="metrics"></div></div></div>
<script>
const TRACES = __DATA__;
const NAMES = __NAMES__;
const COLORS = {bubbles:"#58b6f0",gummy:"#7cd36b",moo:"#e7e2dc",mochi:"#f3d6e4",froggo:"#4fae5c",pebble:"#a8a8a8",lop:"#f1c6f0",whiskers:"#f0b46a",bumble:"#f2d14b",octo:"#c88ce8"};
const css = n => getComputedStyle(document.documentElement).getPropertyValue(n).trim();
const nFrames = Math.min(...TRACES.map(t => t.player.length));
document.documentElement.style.setProperty("--cols", TRACES.length);
const scrub = document.getElementById("scrub"); scrub.max = nFrames - 1;
let frame = 0, playing = true, speed = 1, acc = 0, selected = null, last = performance.now();
const panes = TRACES.map((t, k) => {
  const card = document.createElement("div"); card.className = "card";
  card.innerHTML = `<h2>${NAMES[k]}</h2><canvas class="top" height="520"></canvas><canvas class="time" height="170"></canvas>
  <div class="legend"><span style="--c:#3fae6a">lift</span><span style="--c:#e0533c">facing off its jump (air)</span><span style="--c:#f0a030">slime to tag gap</span><span style="--c:#8a63d2">turn rate / 10</span></div>`;
  document.getElementById("panes").appendChild(card);
  const top = card.querySelector(".top"), time = card.querySelector(".time");
  top.addEventListener("click", e => pick(k, e));
  return {t, top, time};
});
function fr(s, f){ const i = f - (s.first - 1); return (i >= 0 && i < s.frames.length) ? s.frames[i] : null; }
function view(p, w, h){ const z = +document.getElementById("zoom").value; const pl = p.t.player[frame];
  return {s:z, ox:w/2 - pl[0]*z, oy:h/2 - pl[1]*z}; }
function pick(k, e){
  const p = panes[k], r = p.top.getBoundingClientRect(), dpr = p.top.width / r.width;
  const v = view(p, p.top.width, p.top.height); const mx = (e.clientX - r.left) * dpr, my = (e.clientY - r.top) * dpr;
  let best = null, bd = 1e9;
  for (const [id, s] of Object.entries(p.t.slimes)) { const f = fr(s, frame); if (!f) continue;
    const d = Math.hypot(f[0]*v.s + v.ox - mx, f[1]*v.s + v.oy - my); if (d < bd) { bd = d; best = id; } }
  if (bd < 60) selected = best; draw();
}
function size(c){ const r = c.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
  const w = Math.round(r.width * dpr), h = Math.round(+c.getAttribute("height") * dpr * (r.width / c.width || 1));
  if (c.width !== w) { c.width = w; c.height = Math.round(w * (c === c.parentNode.querySelector(".top") ? 0.62 : 0.2)); } }
function drawTop(p){
  const c = p.top, g = c.getContext("2d"); size(c); const W = c.width, H = c.height; const v = view(p, W, H);
  g.clearRect(0,0,W,H); g.fillStyle = css("--bg"); g.fillRect(0,0,W,H);
  const X = x => x*v.s + v.ox, Y = z => z*v.s + v.oy;
  // lane band
  g.lineCap = "round"; g.lineJoin = "round"; g.strokeStyle = css("--laneEdge"); g.lineWidth = 10.6*v.s; g.beginPath();
  p.t.lane.forEach((q,i) => i ? g.lineTo(X(q[0]),Y(q[1])) : g.moveTo(X(q[0]),Y(q[1]))); g.stroke();
  g.strokeStyle = css("--lane"); g.lineWidth = 10*v.s; g.stroke();
  const trails = document.getElementById("trails").checked;
  const list = Object.entries(p.t.slimes).map(([id,s]) => [id,s,fr(s,frame)]).filter(e => e[2]);
  // trails
  if (trails) for (const [id,s] of list) { const col = COLORS[s.species] || "#888";
    for (let k = 1; k <= 60; k += 1) { const q = fr(s, frame - k); if (!q) break;
      g.globalAlpha = 0.5 * (1 - k/60); g.fillStyle = col; g.beginPath(); g.arc(X(q[0]),Y(q[1]),Math.max(1.5,0.07*v.s),0,7); g.fill();
      g.fillStyle = "#777"; g.fillRect(X(q[4])-2, Y(q[5])-2, 4, 4); } g.globalAlpha = 1; }
  // slimes, back to front
  list.sort((a,b) => a[2][1]-b[2][1]);
  for (const [id,s,f] of list) {
    const col = COLORS[s.species] || "#888", r = s.radius*v.s, sy = f[7] || 1, lift = f[2];
    const x = X(f[0]), y = Y(f[1]);
    g.fillStyle = "rgba(0,0,0,0.18)"; g.beginPath(); g.ellipse(x, y, r*1.05, r*0.55, 0, 0, 7); g.fill();
    const by = y - lift*v.s*0.9 - r*sy*0.6;
    g.fillStyle = col; g.strokeStyle = id === selected ? css("--accent") : "rgba(0,0,0,0.35)"; g.lineWidth = id === selected ? 3 : 1.2;
    g.beginPath(); g.ellipse(x, by, r/Math.sqrt(sy), r*sy, 0, 0, 7); g.fill(); g.stroke();
    // facing: two eyes on the side it looks to (yaw 0 = -Z = up on screen)
    const a = f[3], fx = -Math.sin(a), fz = -Math.cos(a), sx = -fz, sz = fx;
    for (const side of [-1,1]) { g.fillStyle = "#222"; g.beginPath();
      g.arc(x + (fx*0.55 + sx*0.28*side)*r, by + (fz*0.55 + sz*0.28*side)*r*0.6, Math.max(1.6, r*0.12), 0, 7); g.fill(); }
    // name tag on the Body
    const tx = X(f[4]), ty = Y(f[5]) - 2.6*v.s - r;
    g.strokeStyle = "rgba(120,120,120,0.7)"; g.lineWidth = 1; g.beginPath(); g.moveTo(tx, ty+8); g.lineTo(x, by - r*sy); g.stroke();
    g.fillStyle = "rgba(30,30,30,0.72)"; const tw = Math.max(46, 3.4*v.s); g.fillRect(tx - tw/2, ty - 9, tw, 18);
    g.fillStyle = "#fff"; g.font = `${Math.max(10, 0.55*v.s)}px system-ui`; g.textAlign = "center"; g.textBaseline = "middle";
    g.fillText(s.species + (f[11] ? " " + f[11] : ""), tx, ty);
    g.fillStyle = css("--muted"); g.font = "10px system-ui"; g.fillText(f[8][0].toUpperCase(), x, y + r*0.9);
  }
  // player
  const pl = p.t.player[frame]; g.fillStyle = "#2f6fdf"; g.strokeStyle = "#fff"; g.lineWidth = 2;
  g.beginPath(); g.roundRect(X(pl[0]) - 0.9*v.s, Y(pl[1]) - 0.9*v.s, 1.8*v.s, 1.8*v.s, 4); g.fill(); g.stroke();
}
function series(s){ const out = {lift:[],crab:[],gap:[],turn:[]}; const dt = 1/60;
  for (let i = 0; i < s.frames.length; i++) { const f = s.frames[i], b = s.frames[i-1]; const k = i + s.first - 1;
    out.lift.push([k, f[2]]); out.gap.push([k, Math.hypot(f[0]-f[4], f[1]-f[5])]);
    if (b) { const vx = (f[0]-b[0])/dt, vz = (f[1]-b[1])/dt, sp = Math.hypot(vx,vz);
      let d = Math.abs(((f[3]-b[3]) + Math.PI) % (2*Math.PI) - Math.PI); if (d > Math.PI) d = 2*Math.PI - d; out.turn.push([k, d/dt/10]);
      if (f[8] === "air" && sp > 2) { let o = Math.abs(((f[3] - Math.atan2(-vx,-vz)) % (2*Math.PI) + 3*Math.PI) % (2*Math.PI) - Math.PI); out.crab.push([k, o]); } } }
  return out; }
function drawTime(p){
  const c = p.time, g = c.getContext("2d"); size(c); const W = c.width, H = c.height; g.clearRect(0,0,W,H);
  const s = selected && p.t.slimes[selected]; g.fillStyle = css("--muted"); g.font = "12px system-ui"; g.textAlign = "left";
  if (!s) { g.fillText("Click a slime to see its timeline", 8, 18); return; }
  const S = series(s), X = k => k / (nFrames-1) * W, Y = v => H - 6 - Math.min(v, 4) / 4 * (H - 24);
  g.fillText(`${selected} ${s.species} (${s.gait}, ${s.temper}) — scale 0..4`, 8, 14);
  const line = (pts, col, dots) => { g.strokeStyle = col; g.fillStyle = col; g.lineWidth = 1.5; g.beginPath();
    pts.forEach((q,i) => { if (dots) { g.fillRect(X(q[0])-1, Y(q[1])-1, 2, 2); } else (i ? g.lineTo(X(q[0]),Y(q[1])) : g.moveTo(X(q[0]),Y(q[1]))); }); if (!dots) g.stroke(); };
  line(S.gap, "#f0a030"); line(S.turn, "#8a63d2"); line(S.lift, "#3fae6a"); line(S.crab, "#e0533c", true);
  g.strokeStyle = css("--ink"); g.lineWidth = 1; g.beginPath(); g.moveTo(X(frame),0); g.lineTo(X(frame),H); g.stroke(); }
function draw(){ panes.forEach(p => { drawTop(p); drawTime(p); }); scrub.value = frame;
  document.getElementById("clock").textContent = (frame/60).toFixed(2) + " s"; }
function metrics(){ const rows = [["glide irregularity p50 / p95","glide_irregularity",["p50","p95"]],["name tag irregularity p50","tag_irregularity",["p50"]],
  ["tag to slime gap p50 / p95 / max (studs)","tag_offset",["p50","p95","max"]],["facing off its jump in the air p50 / p90 (rad)","crab",["p50","p90"]],
  ["air frames facing > 0.8 rad off","crab",["share_over_0_8"]],["turn rate p95 / p99 (rad/s)","turn",["p95","p99"]],["snaps > 8 rad/s per s","turn",["flips_per_s"]],["overlap frames / worst","overlap",["frames","worst"]]];
  let h = "<table><tr><th></th>" + NAMES.map(n => `<th>${n}</th>`).join("") + "</tr>";
  for (const [label, key, sub] of rows) h += `<tr><td>${label}</td>` + TRACES.map(t => `<td>${sub.map(s => t.metrics[key][s]).join(" / ")}</td>`).join("") + "</tr>";
  document.getElementById("metrics").innerHTML = h + "</table>"; }
function tick(now){ const dt = (now - last) / 1000; last = now;
  if (playing) { acc += dt * 60 * speed; while (acc >= 1) { acc -= 1; frame = (frame + 1) % nFrames; } }
  draw(); requestAnimationFrame(tick); }
document.getElementById("play").onclick = e => { playing = !playing; e.target.textContent = playing ? "Pause" : "Play"; };
document.getElementById("speed").onchange = e => speed = +e.target.value;
document.getElementById("prev").onclick = () => { playing = false; frame = Math.max(0, frame-1); document.getElementById("play").textContent = "Play"; };
document.getElementById("next").onclick = () => { playing = false; frame = Math.min(nFrames-1, frame+1); document.getElementById("play").textContent = "Play"; };
scrub.oninput = e => { frame = +e.target.value; };
addEventListener("keydown", e => { if (e.key === " ") { e.preventDefault(); document.getElementById("play").click(); }
  if (e.key === "ArrowLeft") document.getElementById("prev").click(); if (e.key === "ArrowRight") document.getElementById("next").click(); });
// start on the slime the player walks with
(() => { const t = TRACES[0], pl = t.player[0]; let best = null, bd = 1e9;
  for (const [id,s] of Object.entries(t.slimes)) { const f = fr(s, 60); if (!f) continue; const d = Math.hypot(f[0]-t.player[60][0], f[1]-t.player[60][1]); if (d < bd) { bd = d; best = id; } }
  selected = best; })();
metrics(); requestAnimationFrame(tick);
</script></body></html>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("traces", nargs="+")
    ap.add_argument("-o", "--out")
    ap.add_argument("--title", default="Slime motion simulation")
    ap.add_argument("--names", nargs="*")
    a = ap.parse_args()
    traces = []
    for path in a.traces:
        with open(path, encoding="utf-8") as f:
            traces.append(json.load(f))
    names = a.names or [os.path.splitext(os.path.basename(p))[0] for p in a.traces]
    out = a.out or os.path.splitext(a.traces[-1])[0] + ".html"
    page = (PAGE.replace("__TITLE__", a.title)
            .replace("__NAMES__", json.dumps(names))
            .replace("__DATA__", json.dumps(traces, separators=(",", ":"))))
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(page)
    print(out, f"{os.path.getsize(out) // 1024} KB")


if __name__ == "__main__":
    main()
