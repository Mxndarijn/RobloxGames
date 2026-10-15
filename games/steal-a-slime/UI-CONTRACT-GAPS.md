# UI ↔ CONTRACT gaps (for Phoenix / Archer)

**Owner:** Jolt (UI). **Date:** 2026-10-15.

> **Status (Phoenix, 2026-10-15): all five gaps are closed** in CONTRACT.md, `Remotes.ACTIONS`, `Types.State` and `Constants`, with the names asked for below: `BuyLockUpgrade` / `BuySpeedCoil` + `State.shop` (§3, §5.1), `State.tutorialStep` (§2 Tutorial, §5.1), `daily.day` (§5.1), `Constants.RAIN_ACTIVE_ATTRIBUTE` / `RAIN_ENDS_AT_ATTRIBUTE` / `RAIN_NEXT_AT_ATTRIBUTE` (§5.2), and a server-placed, server-filled `workspace.Map.LeaderboardBoard` (§5.3). `tests/Contract.spec.luau` checks the shop actions and rain names against `ShopCatalog` / `RainTimer`. Jolt: the `TODO(CONTRACT)` markers and fallbacks in src/ui can go whenever convenient; nothing in the UI has to change for it to work.

The overnight UI (Part 2) relies on a few things that CONTRACT.md doesn't define yet. The UI handles each one: until the server side lands, it shows a stub or uses a fallback. **No server behaviour is assumed.** When one of these lands in CONTRACT / Types / Remotes, fix it there and drop the entry here.

## 1. Shop actions (`src/ui/ShopCatalog.luau`, `Panels/Shop`)

Expected `Request` actions, none taking arguments:

| Action | Effect the UI expects |
|---|---|
| `"BuyLockUpgrade"` | Buys the next permanent lock-time upgrade level (each `Lock` lasts longer). |
| `"BuySpeedCoil"` | Buys the Speed Coil (faster WalkSpeed when not carrying; Archer has `Props.speedCoil()`). |

- Until these are in `Remotes.ACTIONS`, the rows show **"Coming soon"** and their buttons are disabled, because the UI's `send` asserts the action is known.
- The **"Lock base"** row already works. It uses the contracted `"Lock"` action, `state.lockCost` and `state.lockDuration`.
- If you pick different names, change `action` in `ShopCatalog.ITEMS`. That's one line per item.

Expected optional State field for prices and levels:

```luau
shop: { [itemId: string]: { price: number?, level: number?, maxLevel: number?, owned: boolean? } }?
-- itemIds: "LockUpgrade", "SpeedCoil"
-- price nil = maxed/owned or unknown; level >= maxLevel or owned = true shows "Max" / "Owned"
```

- If `shop` is missing but the action exists, the button shows **"Buy"** and the server decides.

## 2. Tutorial step (`src/ui/Tutorial.luau`, `Panels/TutorialOverlay`)

Expected optional State field: `tutorialStep: number?`.

- It's **1-based**. `nil`, `< 1` or `> #Tutorial.STEPS` (6) means no overlay (not started, or done).
- Step texts live client-side in `Tutorial.STEPS`: grab → bring home → lock → merge → steal & chase → rebirth.
- The server owns progression. The UI never advances it and has no "skip" action. "Hide" only hides the card locally until the step changes.
- The UI reads the field as `(state :: any).tutorialStep`. `Types.State` is untouched.
- Archer's `Props.tutorialNpc` / `tutorialArrow` aren't driven by the UI.

## 3. Daily popup day number (`src/ui/Daily.luau`)

- `State.daily.streak` is the streak of the **last** claim, and a missed day resets it. So the client can't tell which day today's claim counts as.
- The popup works around this by decoding the day from `amount` (`DAILY_BASE × day × rebirthMultiplier`).
- Nice to have: `daily.day: number`, the streak day the pending claim pays.

## 4. Rain attribute names (`src/ui/RainTimer.luau`)

- CONTRACT §5.2 documents `RainActive` / `RainEndsAt` / `RainNextAt`, and WorldView sets them, but they aren't in `Constants.luau`. `RainTimer.ATTRIBUTES` hardcodes them for now.
- Suggest adding `RAIN_ACTIVE_ATTRIBUTE`, `RAIN_ENDS_AT_ATTRIBUTE` and `RAIN_NEXT_AT_ATTRIBUTE` to Constants.
- The HUD prefers these attributes and falls back to `State.rain`.
- It also shows "Slime Rain in m:ss" during the last 10 min before a rain (`RainTimer.SOON_SECONDS`).

## 5. World leaderboard instance (`src/ui/WorldLeaderboard.luau`)

- **Nothing in the committed world places a leaderboard board yet.** Neither `world/*.rbxmx` nor WorldBuilder places one.
- The client binds (now, and later via `DescendantAdded`) any `SurfaceGui` under `workspace` that matches one of these:
  - It's named **`Leaderboard`**.
  - It sits inside a **Model named `LeaderboardBoard`** (or `Leaderboard`). This matches Archer's `Props.leaderboardBoard()`: `LeaderboardBoard` > `Board` > SurfaceGui `BoardGui` > `Content` > `Rows`.
- Rows go into the gui's descendant Frame **`Rows`**. If there isn't one, the client creates a `Rows` frame that fills the gui.
- Rows are `Row_<k>` with `Rank` / `Name` / `Value` labels (top 10), filled from the `Leaderboard` remote. The local player's row is highlighted.
- **Ask:** Archer/Phoenix, place one `Props.leaderboardBoard()` in the world (e.g. `workspace.Map.LeaderboardBoard` at a `WorldLayout.PROP_SPOTS` spot). Don't fill it on the server: each client renders it locally.
