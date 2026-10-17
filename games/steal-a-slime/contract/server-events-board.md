# 20. v21: server events board (2026-10-17)

**Status:** `Config.FEATURES.EventsBoard` (default `true`); `false` = no banner. Client only: **no remote, no server code, no save-format change**, no new mesh.

- **What it shows (`src/ui/EventsBoard`, pure):** one HUD banner `EventsBoard` in the `Banners` stack (hidden while a menu is open like the others), lines: `📅 Server events`; `🧪 <Mutation> week - <time> left` and the Saturday trait event (`🍀 Lucky Saturday x1.5 luck - <time> left`) from the replicated `WeeklyEvent` attribute (§18, `WeeklyEvents.decode`; needs `FEATURES.WeeklyEvents`, otherwise those lines are absent); the day/night or live admin modifier through `ModifierBadge.banner` (needs `FEATURES.CycleModifier`); and `Next: <event> in <time>` from the same attribute. Nothing running = banner hidden.
- **Clocks:** weekly times are unix (`os.time()`, like the schedule), the modifier uses the server clock (`ctx.serverNow()`), as their own badges do. Past events are dropped, so a stale attribute never shows an ended event.
- **Pc-watcher:** shot `v21-events-board` (`luau/events_board`) fails when the banner is missing, hidden or lists no event.
