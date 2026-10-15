# UI plan (Steal a Slime)

**Owner:** Jolt (UI). **Status:** items 1–2 done, item 3 partly done (`jolt/full-window-menus`); the rest is still planned.

Related: `CONTRACT.md` (§2 UI, State shape), `UI-CONTRACT-GAPS.md` (closed contract gaps), `../../../roadmap-v17-v22.md` (release roadmap, workspace root).

## 2026-10-15: Merijn's menu notes

1. **Full-window menus: done.** Every nav menu (Plot, Merge, Shop, Rebirth, Goals, SlimeDex, Top) opens as one full-window panel (`Layout.panelFor` = `screen.panel`): right of the nav, from under the HUD down to the bottom touch inset. The carry and tutorial cards draw above it (ZINDEX), so Drop / Slap / Hide stay tappable. Close: an **X** top-right on every panel (`Widgets.panel`, `Layout.panelClose`, 55 design px ≥ 44 screen px), plus **Esc / gamepad B** (`ContextActionService` "CloseMenu"). All three call `setOpen(nil)`. Checked at 5 viewports in `tests/ui/LayoutAssert.spec`.
2. **Dex → SlimeDex: done** for everything players see (nav label, panel title, goals, rewards copy, rebirth disclaimer). Internal key `Dex` and State fields (`state.dex`, `dexTotal`) are unchanged.
3. **SlimeDex pictures: partly done.** Each discovered slime has a row with a square picture. The picture comes from `SlimeDex.IMAGES` (by dexKey, then tier + mutation); if there is none, a placeholder swatch in the mutation or rarity colour is shown. Each tier has one **silhouette** row (dark fill, "?", no names) with the count still to find; we don't list the 720 locked keys one by one.

Still planned:
- Upload slime thumbnails and fill `SlimeDex.IMAGES` (it is empty, so every row shows the placeholder swatch for now).
- ViewportFrame of the real model: slime models are built server-side (`src/server`), so the client has nothing to render. This needs a shared or client model builder first (Phoenix / Archer).
- Landscape phones (844x390): the two-row HUD leaves the menu body only about 140 design px tall. Consider a one-row compact HUD, or hiding the HUD while a menu is open.
- Toasts (top-right) can draw over a menu's X for a few seconds. Their frames don't block taps, but consider moving them while a menu is open.
