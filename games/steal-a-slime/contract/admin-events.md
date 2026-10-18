# 12. v29 #10: live admin events (2026-10-16, Jolt)

**Status:** contract first. `Config.FEATURES.AdminEvents` (default on); `false` = nothing can be triggered. Server-only logic.

- **Who:** `AdminEvents.isAdmin(userId, creatorId)` (`src/shared/AdminEvents`): the place owner (when `game.CreatorType` is User) or a UserId in `Config.ADMIN_USER_IDS` (empty by default). There is no remote and no client code path; non-admins get no reply at all.
- **Trigger:** chat `"/event <luck|rain> [minutes]"` (`Player.Chatted`, minutes clamped to `ADMIN_EVENT_MIN/MAX_SECONDS`, default 10). `src/server/AdminEventsService`.
- **Cross-server:** `MessagingService` topic `Config.ADMIN_EVENT_TOPIC`, payload `{ v = 1, id, seconds, by, nonce }`. Every call is in a pcall; a failed send still starts the event on this server. Receivers rebuild the payload (`AdminEvents.validate`: known id, clamped seconds, `by` must itself be an admin), drop a repeated nonce, and share one cooldown (`ADMIN_EVENT_COOLDOWN`, 20 s) with local triggers.
- **Effects (existing systems):** `luck` sets `world.adminEvent`, which overrides the dawn / dusk `world.modifier` until it ends (`Spawner.stepModifier`; then the normal roll resumes); `rain` calls `Spawner.forceRain`. Needs `FEATURES.CycleModifier` for the multipliers.
- **State / UI:** `State.modifier.icon?` (emoji) is set while an admin event runs; the HUD modifier banner shows `"<icon> Luck Event x3 luck - 9:00 left"`. A server-wide toast announces it. No save-format change.
