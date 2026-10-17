# UI plan (Steal a Slime)

**Owner:** Jolt (UI). **Status:** items 1–2 done, item 3 partly done (`jolt/full-window-menus`); the rest is still planned.

Related: `CONTRACT.md` (§2 UI, State shape), `UI-CONTRACT-GAPS.md` (closed contract gaps), `../../../roadmap-v17-v22.md` (release roadmap, workspace root).

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
