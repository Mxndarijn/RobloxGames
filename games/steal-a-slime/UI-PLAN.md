# UI plan (Steal a Slime)

**Owner:** Jolt (UI). **Status: plan only, not implemented.** Nothing in `src/ui` changes for this doc; each item becomes a UI task when it is picked up.

Related: `CONTRACT.md` (§2 UI, State shape), `UI-CONTRACT-GAPS.md` (closed contract gaps), `/workspace/roblox/roadmap-v17-v22.md` (release roadmap).

## 2026-10-15: Merijn's menu notes (planned UX)

1. **Full-window menus.** Nav panels (Plot / Merge / Rebirth / Dex / Top / Shop) open as **full-window panels** instead of today's side panels, with a **clear close button** (big, top-right, always visible; same spot on every panel).
2. **Rename Dex → SlimeDex.** Spelled **SlimeDex**: nav label and panel title (today `Nav.luau` key `Dex`, label `"Dex"`; `Panels/Dex.luau`). Internal keys and State fields (`state.dex`, `dexTotal`) don't need to change.
3. **SlimeDex shows a picture of each slime.** Every entry gets an image slot (mesh viewport or thumbnail of that slime look); undiscovered entries keep a silhouette / locked state.

Open questions (decide when implementing): ViewportFrame vs pre-rendered thumbnails for the SlimeDex images (720 entries, performance on phones); how full-window panels coexist with the HUD carry buttons and tutorial card.
