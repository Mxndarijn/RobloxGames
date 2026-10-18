# 24. v20: welcome-back card (2026-10-17)

**Status:** always on (no flag). Server-authoritative; no remote, **no save-format change**, nothing saved.

- **Report (`src/shared/WelcomeBack.report`):** at join, `Income.applyOffline` builds `session.welcome = { away, cash, grown }` when the player was away at least `Config.WELCOME_BACK_MIN_SECONDS` (4 h): `cash` is the offline income just paid, `grown` the number of pad slimes whose growth rose from offline time (`Growth.applyOffline`). Missing / future `lastOnline` gives nil.
- **State:** `welcomeBack: { away, cash, grown }?`, present for the whole session. The client shows it once per join (an edge in `PopupQueue`), as the content-sized `Welcome` menu card with the daily streak / reward and the next goal read from `State.daily` / `State.goals`. Collect only closes the card: the cash was paid at join.
- **Ordering (`ui/PopupQueue`):** the tutorial blocks it like the Daily popup; Welcome opens before Daily, and Daily waits until the Welcome card is closed (no overlap).
