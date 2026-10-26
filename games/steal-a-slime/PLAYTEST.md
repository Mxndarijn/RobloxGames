# Steal a Slime: play-test checklist (Merijn)

**Build:** place version **10** (published 2026-10-15 00:28 CEST via Open Cloud, `versionType=Published`, commit `f7f7f38`), universe 10770917350, place 135787188192378. v9 was the void fix.
**Data:** real DataStores (`StealASlime_v1` + OrderedDataStore `StealASlime_TotalEarned`). The built place has no `DataStoreMode = "Memory"` attribute, so progress persists between sessions.

## How to join

1. Open https://www.roblox.com/games/135787188192378 and press **Play**. (If the page says it's private, set the experience to Public or add testers under Creator Hub → the experience → Access.)
2. For steal tests you need **two accounts** (second device, or a friend). Both join the same server: the second player uses **Join** from the first player's profile, or simply join while the server is quiet (max 8 per server).
3. You spawn on your own plot's base. HUD buttons: **Lock**, **+Pad**, **Daily**; nav tabs **Plot / Merge / Rebirth / Dex / Top**. While carrying: **Drop** and **SLAP!** buttons.

Tick each box; note anything odd with the time and what you did (the server prints `[Server] ...` warnings to the F9 dev console → Server tab).

## New in v10 (try these first)

- **Prettier map (Archer):** rim rocks around the crater, a ring path, rocks / crystals / mushrooms, torches, glowing lava cracks, edge boulders, lights. Client-side volcano smoke, embers and an **eruption burst** every 9–16 s (every 3–6 s during Slime Rain). Slime Rain now also drops big goo blobs and tints the screen.
- **Shop stand** next to the volcano (striped awning, jelly shop sign). Walk up: **E = Speed Coil ($1,500)**, **F = Longer locks**. The HUD **Shop** panel now has working **Longer locks** and **Speed Coil** rows (no more "Coming soon").
  - [ ] Buy the Speed Coil: a coil tool appears in your Backpack, you run faster (19 vs 16) only while you **hold** it (equipped); in the Backpack or while carrying it does nothing. It comes back after a reset and after rejoining; the row says **Owned**.
  - [ ] Buy Longer locks: each level (max 5, $500 → $100K) makes every Lock 15 s longer; the Lock row's duration goes up. Both upgrades survive a **rebirth** and a rejoin.
- **Tutorial for new players:** a card (6 steps: grab → bring home → lock → merge → steal → rebirth) and a **yellow-green arrow beam** from you to the next target (volcano, your plot, LockButton, MergeVat, another player's plot). Each step completes from actually doing it; a later action skips ahead. A "Tutorial complete!" toast at the end. Players with older saves (slimes or rebirths) don't get it; use a fresh/alt account to see it.
- **World leaderboard board** ("Top Earners") stands near the volcano and fills with the global top 10 (refresh every 60 s; your own row highlighted).
- **Tutorial guide NPC** ("Guide", slime hat) stands near the hub spawn; decorative.
- **Effects:** sparkles on depositing a slime, a puff when a steal starts, a swirl + flash at the MergeVat on merge, a golden column on rebirth (everyone nearby sees them).
- **Slime Rain heads-up:** a toast 1 minute before each rain.
- **Extras (on, each can be switched off in `Config.FEATURES`):**
  - [ ] **Boss Slime**: 8 min after a server starts, then every 15 min, a huge free Epic-or-better mutated slime drops ("A BOSS SLIME erupted…", prompt says "BOSS …"). It lives 2 min. Race for it; the catcher is announced to everyone.
  - [ ] **Follow pet**: your favourite (or best) slime follows you as a small bouncing copy. Others see their own pets too. Star a different favourite: the pet changes within a second.
  - [ ] **Day/night**: a 12-minute day cycle (about 3.5 min of night). Check the map stays readable at night (torches/crystals glow).
  - Minimap data exists for a future UI minimap; nothing to see yet.

What to report for v10: shop prompt or panel purchases that don't charge / don't stick after rejoin, walk speed wrong after carrying, the tutorial arrow pointing at the wrong thing or never advancing, leaderboard board staying on "No entries yet" for > 2 min, missing or stuck effects, pets stuck / floating far away, night too dark, any `[Server]` warning in F9 → Server.

## Checklist

### Void fix (new in v9: players fell into the void and kept dying)
- [ ] Join a fresh server: you land on solid ground (your plot's Base, or the yellow **HubSpawn** pad near the volcano) and do **not** fall or respawn in a loop.
- [ ] The grass Ground, the volcano and all 8 plots are there the moment you spawn (they ship in the place file now, not built later by the server).
- [ ] Walk off the edge of the map (or jump off far out): a few studs below the floor you're put back on your own plot with a "Whoa! Back to safety." toast, alive, carried slime still in your arms.
- [ ] Reset your character: you respawn on your plot, standing.
- [ ] F9 → Server: no `FallenPartsDestroyHeight ... above the kill plane` or `WorldBuilder.build failed` warnings.

### Carry
- [ ] Every ~4 s a wild slime drops from the volcano and lands around it (max 18 alive; each disappears after ~75 s).
- [ ] Walk up: prompt says **Grab** (free, ~1 in 100) or **Buy $N**. Press **E**.
- [ ] A bought slime costs cash once; drop it (**Drop** button) and grab it again: free the second time.
- [ ] While carrying: the slime sits above your head, you walk slower (rarer = slower), tools are unequipped, and you can't grab a second one.
- [ ] Reset your character while carrying: the slime is dropped.

### Home zone
- [ ] Walk into your own plot with a slime: it's deposited on a free pad and starts earning (cash goes up every second).
- [ ] With all pads full, walking in keeps the slime in your arms and shows one red "plot full" toast per visit. **+Pad** unlocks the next pad (4 at start, max 8).

### Steal lock (2 accounts)
- [ ] On join your plot is locked for 45 s (HUD lock shows a countdown, then **OPEN**). Player B sees no usable Steal prompt on your slimes while locked.
- [ ] **Owner never sees a Steal prompt on their own slimes** (new in v7, see Known risks).
- [ ] Press **Lock** (or the LockButton on the plot): costs cash, adds 60 s (+10 s per rebirth), never more than 5 min remaining.
- [ ] When unlocked, B holds **E** (0.4 s) on your slime: it's stolen. You get an alarm toast and the slime shows as "being stolen".

### Escape home
- [ ] B carries a stolen slime: overlay shows "STOLEN - escapes in Ns! Run home!". B is slowed more the longer they hold it.
- [ ] Wait it out (15–25 s, shorter for rarer): the slime wriggles free and bounces back to your pad (~1.5 s, can't be stolen/sold/merged mid-bounce).
- [ ] Owner presses **SLAP!** near B (within ~10 studs): the slime escapes home. Cooldown 1.5 s.
- [ ] B reaches their own plot first: the slime moves to B's plot permanently. Owner gets a toast; B's **Steals** stat goes up.
- [ ] B leaves the game while carrying your slime: it returns to you.

### Merge
- [ ] **Merge** tab: pick two slimes of the same tier → **Merge** → one slime of the next tier.
- [ ] The **MergeVat** prompt on your plot ("Auto-merge") merges a matching pair automatically, or tells you there's no pair.
- [ ] A slime being stolen can't be selected.

### Rebirth
- [ ] Earn $5,000 (cost ×3 per rebirth). **Rebirth** tab shows cost and keeper.
- [ ] Star a favourite on the **Plot** tab, rebirth: cash and slimes wiped, the favourite kept (or your best slime if none starred), income multiplier +0.5, leaderstats **Rebirths** +1, lock buys 10 s more.

### Slime Rain
- [ ] First rain **5 min after the server starts**, then every hour, lasting 3 min. A global toast announces it; rain particles and a HUD countdown appear.
- [ ] During rain: drops keep the normal pace (~every 4 s), rarer tiers are clearly more common (over half the drops are Rare or better).
- Tip: to see rain on demand, be first into a fresh server (or wait for the hourly one; the HUD shows the next rain time).

### Offline income
- [ ] Note your income per second, leave for ≥ 5 min, rejoin: a toast pays ~50 % of income × time away (capped at 2 h).

### Leaderboard
- [ ] **leaderstats** (Tab key player list) shows **Cash**, **Rebirths**, **Steals**.
- [ ] **Top** tab shows the global board by total earned; it fills on join and refreshes every 60 s. Both accounts should appear after their first save (≤ 60 s).

### Saving after rejoin
- [ ] Note cash, slimes (with pads), pads unlocked, rebirths, favourite, Dex count, daily streak. Leave, wait ~10 s, rejoin: everything matches (cash may be higher from offline income).
- [ ] Rejoin immediately (< 5 s): data still loads (session lock retries up to 5 times); you shouldn't be kicked. If you are kicked with a load error, note it.
- [ ] **Daily**: claim once; a second claim the same day is refused; streak survives rejoin.

## Known risks

- **Owner-hidden Steal prompt.** The server names every slime prompt `GrabPrompt` and sets `HideFromUserId = <owner>` on Steal prompts (CONTRACT.md §5.2); the UI's PromptHide script hides it for the owner. You should **not** see "Steal" on your own pad slimes, while the second account does. If the owner sees it, report it (pressing it is still refused with "that's your own slime").
- **DataStore status is visible.** If DataStores fail, the server no longer falls back silently: it warns `[Server] DataStoreStatus = ...` (F9 → Server tab) and sets the workspace attribute **`DataStoreStatus`**. Check it in the F9 console (Server, command bar): `print(workspace:GetAttribute("DataStoreStatus"))`. `Ok` = saving works; `Unavailable` = memory fallback, **nothing saves**; `Error` = the last load/save failed (goes back to `Ok` on the next good save). Note the value at join and after a rejoin.
- **Slime mesh look.** Slimes should use Jolt's uploaded slime mesh (asset 103340234939607) coloured by rarity, instead of plain balls. Look at the wild slimes around the volcano/spawn area and your pad slimes (Plot tab). To confirm which look the server picked: `print(workspace:GetAttribute("SlimeLook"))` in the F9 Server console → `Mesh` or `Procedural`. `Procedural` (with a `[Server] slime mesh ... unavailable` warning) means the asset couldn't be loaded and the old procedural slimes are used; report it with the warning text. In Studio (Play, Server view) a mesh slime `Workspace.WildSlimes.Slime_<id>` has a MeshPart **`Mesh`** next to an invisible `Body`; report if the mesh's baked eyes double up with the procedural eyes, it sits sideways, or its colour ignores rarity. Needs a build that includes SlimeMesh (v7 does not).
- **Rain timing** is per server (5 min after start), so a long-running server may be up to an hour from the next rain.
- **Untested in a live engine:** carry welds, HomeZone detection, prompt hold durations, slap reach and walk speeds were only unit-tested on the pure logic; physics/feel needs your eyes.
- **Rejoin to a different server** within a few seconds can briefly hit the session lock of the old server (load retries with backoff; stale after 180 s).
- No Robux products yet; volcano tiers, 3-slime vat and floor/bouncer upgrades are out of scope.
