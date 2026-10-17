# UI plan (Steal a Slime)

**Owner:** Jolt (UI). **Status:** items 1–2 done, item 3 partly done (`jolt/full-window-menus`); the rest is still planned.

Related: `CONTRACT.md` (§2 UI, State shape), `UI-CONTRACT-GAPS.md` (closed contract gaps), `../../../roadmap-v17-v22.md` (release roadmap, workspace root).

## 2026-10-18: Merijn's UI fixes (B2, B4, B5, B6, B7, B8; `/workspace/roblox/bugs-oct18/BUGS.md`, `ui_reference.png`)

- **B7 no top bar.** The lock block, Lock / Extend, Buy pad and Daily buttons and the pad hint banner are gone (`LockHud` deleted); lock / extend / buy stay in the world (pads, gate prompts). The tutorial's Lock and Buy pad steps no longer get a "tap here" hint (Hint only points at the Rebirth tile) and their text drops "top bar". The daily popup still opens through `PopupQueue`. Server untouched.
- **B6 no toasts.** `Toasts` / `ToastQueue` / `ItemIcons.forToast` are deleted. A `Notify` only plays its sound (`init.client playNotifySound`); request failures only `warn`. The top-centre banners (steal alert, Mystery Egg hatch, events board) stay: they are not top-right.
- **B5 nav tiles.** The left nav is a bare 2-column grid of rounded square tiles (the item picture on the tile, the label under it, the SlimeDex % badge on its tile corner): `Layout.NAV`, `Layout.navTile / navButtons`. Same five buttons. No collapse toggle. Landscape phones take more columns (`short`). On phones an open menu hides the tiles and uses their width.
- **B4 bigger clusters.** `Layout.MONEY` / `Layout.STATUS` roughly double the H1 sizes (desktop: 260 x 94 money, 92 x 88 status slots; phone: 196 x 80 and 62 x 64), still lifted `TOUCH_RISE` above the touch strip.
- **B8 tooltip.** A status icon is a button: mouse hover (PC) or a tap (touch; a second tap or a tap elsewhere closes it) opens a card above it with name, effect and time left (`HudClusters.tooltip / nextTooltip`, `Layout.tooltipBox / tooltipRect`, kept on screen). Studio hook: SlimeUI attribute `PcwTooltip` = "Rain" | "Event" | "Friend".
- **B2 board.** The Top Earners list is drawn straight on the board's cream face (`Props.BOARD_PALETTE`, `WorldLeaderboard.PALETTE`): no black backing, no extra parts.
- Renders: `lune run ../../tools/pr-gate/rhr_hud.luau <dir>` then `rhr ui <dir>/<case>.rbxmx --viewport WxH --background d9c48a` (cases `390x844`, `844x390`, `1920x1080`, each with a `-tooltip` twin).

## 2026-10-17: Merijn's HUD v2 (PR H1; spec `/workspace/roblox/bugs-oct17/HUD-DESIGN.md`)

H1 = HUD layout only (the two in-world shops are H2). Left column: Plot, Rebirth, Goals, SlimeDex, Codes (Merge, Shop, Top buttons and their badges are gone; the Merge / Shop / Top panels stay as nav-less cards, the Shop still opens from the ShopStand prompt). Bottom-left (`Layout.moneyCluster`, `HudClusters.money`): Money, Income/s, Rebirths. Bottom-right (`Layout.statusCluster`, `HudClusters.status`): icon + timer slots for Slime Rain, the live server modifier / admin event and the friend boost; never the weekend boost. Boss / Legendary-drop notices (RareAnnounce) and the next-spawn chip are gone. On phones both clusters sit `Layout.TOUCH_RISE` screen px above the touch-controls strip and the carry / tutorial cards sit above them. Still in the top bar / banner stack because they have no slot yet (Merijn to decide, see `/workspace/roblox/glitch-hud-inventory.md`): lock block, Lock, Buy pad, Daily, steal alert, egg hatch, pad hint, events board, toasts, sound button. The `Income` / `FriendBoost` icons are placeholder tiles until Archer renders them (ITEM-ICONS-NEEDED.md). Studio hook: SlimeUI attribute `PcwRain` fakes a running Slime Rain.

## 2026-10-15: Merijn's menu notes

1. **Full-window menus: done.** Every nav menu (Plot, Merge, Shop, Rebirth, Goals, SlimeDex, Top) opens as one full-window panel (`Layout.panelFor` = `screen.panel`): right of the nav, from under the HUD down to the bottom touch inset. The carry and tutorial cards draw above it (ZINDEX), so Drop / Slap / Hide stay tappable. Close: an **X** top-right on every panel (`Widgets.panel`, `Layout.panelClose`, 55 design px ≥ 44 screen px), plus **gamepad B** (`ContextActionService` "CloseMenu"; and Esc while a menu is open: `Layout.CLOSE_WITH_ESCAPE`, on since v27; with no menu open Esc passes on to the Roblox menu). All call `setOpen(nil)`. Checked at 5 viewports in `tests/ui/LayoutAssert.spec`.
2. **Dex → SlimeDex: done** for everything players see (nav label, panel title, goals, rewards copy, rebirth disclaimer). Internal key `Dex` and State fields (`state.dex`, `dexTotal`) are unchanged.
3. **SlimeDex pictures: partly done.** Each discovered slime has a row with a square picture. The picture comes from `SlimeDex.IMAGES` (by dexKey, then tier + mutation); if there is none, a placeholder swatch in the mutation or rarity colour is shown. Each tier has one **silhouette** row (dark fill, "?", no names) with the count still to find; we don't list the 720 locked keys one by one. Without an image, the first `SlimePreview.MAX_LIVE` rows show a ViewportFrame preview (#28/#32). Each mutation has a `SlimePreview.FINISHES` look, and v29 adds them for the v28 Rainbow (bands), Crystal (glass + shard) and Eclipse (corona) mutations. The dexKey has no species, so named roster slimes share their tier + mutation row.

Still planned:
- Upload slime thumbnails and fill `SlimeDex.IMAGES` (it is empty, so every row shows the placeholder swatch for now).
- ViewportFrame of the real model: slime models are built server-side (`src/server`), so the client has nothing to render. This needs a shared or client model builder first (Phoenix / Archer).
- Landscape phones (844x390): the two-row HUD leaves the menu body only about 140 design px tall. Consider a one-row compact HUD, or hiding the HUD while a menu is open.
- Toasts (top-right) can draw over a menu's X for a few seconds. Their frames don't block taps, but consider moving them while a menu is open.
