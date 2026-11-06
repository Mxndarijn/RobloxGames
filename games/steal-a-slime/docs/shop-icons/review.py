"""Writes review.html for build.py: the three styles on the passes, then every icon by group, at full size and small."""
import html

GROUPS = [
    ("Game Passes", lambda i: i["kind"] == "pass"),
    ("Pet clouds", lambda i: i["key"].startswith("Seat_")),
    ("Plot bases", lambda i: i["key"].startswith("Base_")),
    ("Base skins", lambda i: i["key"].startswith("Skin_")),
    ("Hats", lambda i: i["key"].startswith("Hat_")),
    ("Lock styles", lambda i: i["key"].startswith("LockStyle_")),
    ("Bat skins", lambda i: i["key"].startswith("BatSkin_")),
    ("Carry trails", lambda i: i["key"].startswith("Trail_")),
    ("Bundles", lambda i: i["key"].endswith("Bundle")),
    ("Deposit fanfares (retired from the game, still on sale on Roblox)", lambda i: i.get("retired")),
    ("Boosts and quick buys", lambda i: not i["gift"]),
    ("Gifts (the item's icon plus one gift badge)", lambda i: i["gift"]),
]

STYLE_NAMES = {
    "A": ("Clean cut-out", "Transparent background, like the in-game icons. Roblox puts it on its own grey or white."),
    "B": ("Plum stage", "Full-bleed lilac backdrop with a soft glow: the colour of the Exclusive Shop's preview stage."),
    "C": ("Gold medal", "A round gold-rimmed medal with a dark goo-teal face. Same shape whether Roblox shows it square or round."),
}

CSS = """
:root{--bg:#0c3436;--card:#1c4849;--ink:#08262a;--text:#f1fff9;--muted:#bfebdd;--mint:#6cf2c2;--gold:#ffd23f}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.45 system-ui,Segoe UI,sans-serif}
main{max-width:1180px;margin:0 auto;padding:24px 16px 80px}h1{font-size:28px;margin:0 0 6px}h2{margin:36px 0 10px;font-size:21px}
p{color:var(--muted);max-width:820px}.box{background:var(--card);border-radius:14px;padding:14px 18px;margin:14px 0}
.box b{color:var(--gold)}code{background:var(--ink);padding:1px 5px;border-radius:5px;color:var(--mint)}
.styles{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px}@media(max-width:820px){.styles{grid-template-columns:1fr}}
.opt{background:var(--card);border-radius:14px;padding:12px}.opt h3{margin:0 0 4px}.opt p{font-size:13px;margin:0 0 10px}
.pgrid{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}.pgrid figure{margin:0;text-align:center;font-size:12px;color:var(--muted)}
.pgrid img{width:100%;aspect-ratio:1;border-radius:50%;background:#e9ecf0}
.dark .pgrid img{background:#232527}.smallrow{display:flex;flex-wrap:wrap;gap:6px;margin-top:10px;padding:8px;border-radius:10px;background:#e9ecf0}
.smallrow.d{background:#232527}.smallrow img{width:48px;height:48px;border-radius:50%}
.bar{position:sticky;top:0;z-index:2;background:var(--bg);padding:10px 0;border-bottom:1px solid #285f5f;display:flex;gap:10px;flex-wrap:wrap;align-items:center}
.bar label{background:var(--card);padding:8px 14px;border-radius:999px;cursor:pointer;min-height:44px;display:flex;align-items:center;gap:6px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(250px,100%),1fr));gap:12px}
.tile{background:var(--card);border-radius:14px;padding:10px}.tile .big{display:block;width:100%;aspect-ratio:1;border-radius:10px;
background:repeating-conic-gradient(#c8c8cd 0 25%,#9698a0 0 50%) 0 0/24px 24px}
.tile.round .big{border-radius:50%}.meta{display:flex;justify-content:space-between;gap:6px;margin-top:8px;align-items:flex-start}
.meta b{display:block;font-size:14px}.meta code{font-size:12px}.sm{display:flex;gap:4px}.sm img{width:48px;height:48px;border-radius:8px;background:#e9ecf0}
.sm img.d{background:#232527}.tile.round .sm img{border-radius:50%}.price{color:var(--gold);font-size:13px}
"""

JS = """
for (const r of document.querySelectorAll('input[name=style]')) r.addEventListener('change', () => {
  const s = r.value;
  for (const im of document.querySelectorAll('img[data-key]')) im.src = 'out/' + s + '/' + im.dataset.key + '.png';
  for (const a of document.querySelectorAll('a[data-key]')) a.href = 'out/' + s + '/' + a.dataset.key + '.png';
  try { localStorage.setItem('shopIconStyle', s) } catch (e) {}
});
try { const s = localStorage.getItem('shopIconStyle'); if (s) { const r = document.querySelector('input[value=' + s + ']'); if (r) { r.checked = true; r.dispatchEvent(new Event('change')) } } } catch (e) {}
"""


def e(s):
    return html.escape(str(s))


def tile(it, style="B"):
    k = e(it["key"])
    src = f"out/{style}/{k}.png"
    cls = "tile round" if it["kind"] == "pass" else "tile"
    return (f'<div class="{cls}"><a href="{src}" data-key="{k}" target="_blank"><img class="big" data-key="{k}" src="{src}" '
            f'alt="{e(it["name"])}" loading="lazy"></a><div class="meta"><div><b>{e(it["name"])}</b><code>{k}</code>'
            f'<div class="price">R$ {e(it["robux"])} &middot; {e(it["kind"])} {e(it["id"])}</div></div>'
            f'<div class="sm"><img data-key="{k}" src="{src}" alt=""><img class="d" data-key="{k}" src="{src}" alt=""></div></div></div>')


def write(items, path):
    passes = [i for i in items if i["kind"] == "pass"]
    n_prod = sum(1 for i in items if i["kind"] == "product")
    out = [f"<!doctype html><html lang=en><head><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>"
           f"<title>Store Icons Review</title><style>{CSS}</style></head><body><main>",
           "<h1>Steal a Slime: Roblox store icons</h1>",
           f"<p>{len(passes)} Game Passes and {n_prod} Developer Products. These replace the two placeholder pictures every "
           "pass and product uses today, in Roblox's purchase popup, the Store tab on the game page and the Roblox Shop. "
           "Nothing is uploaded yet.</p>",
           "<div class=box><b>Picked: style B, Plum stage</b> (Merijn, 2026-11-05). A and C stay below for reference.<br>"
           "Any icon to redo: name its key (the <code>code</code> under it).</div>",
           "<h2>1. Style options (on the 8 passes)</h2><p>Roblox crops pass icons to a circle, so they are shown round here. "
           "The bottom rows are the same icons at 48 px on a light and a dark page.</p><div class=styles>"]
    for s in ("A", "B", "C"):
        name, desc = STYLE_NAMES[s]
        figs = "".join(f'<figure><img src="out/{s}/{e(p["key"])}.png" alt=""><figcaption>{e(p["name"])}</figcaption></figure>' for p in passes)
        smalls = "".join(f'<img src="out/{s}/{e(p["key"])}.png" alt="">' for p in passes)
        out.append(f'<div class=opt><h3>{s}: {e(name)}</h3><p>{e(desc)}</p><div class=pgrid>{figs}</div>'
                   f'<div class=smallrow>{smalls}</div><div class="smallrow d">{smalls}</div></div>')
    out.append("</div>")
    out.append("<h2>2. Every icon</h2><p>Click an icon for the 512 &times; 512 file. Next to each: the 48 px size on a light "
               "and a dark page. Switch the style here:</p>")
    out.append('<div class=bar>' + "".join(
        f'<label><input type=radio name=style value={s}{" checked" if s == "B" else ""}> {s}: {e(STYLE_NAMES[s][0])}</label>' for s in ("A", "B", "C")) + "</div>")
    seen = set()
    for title, pred in GROUPS:
        g = [i for i in items if i["key"] not in seen and pred(i)]
        if not g:
            continue
        seen.update(i["key"] for i in g)
        out.append(f"<h2>{e(title)} ({len(g)})</h2><div class=grid>" + "".join(tile(i) for i in g) + "</div>")
    out.append("<h2>Not covered</h2><p>The Slime Club subscription's picture is set on the Creator Dashboard (no API) "
               "and is not part of this set.</p>")
    out.append(f"<script>{JS}</script></main></body></html>")
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(out))
