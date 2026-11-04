# 24. Welcome back + daily reward card

**Status:** always on (no flag). Server-authoritative; no new remote, **no save-format change**, nothing saved.

- **Report (`src/shared/WelcomeBack.report`):** at join, `Income.applyOffline` builds `session.welcome = { away, cash, grown, onPads? }` (`onPads`: with `FEATURES.CashPads` the cash waits on the cash pads, contract/cash-pads.md) when the player was away at least `Config.WELCOME_BACK_MIN_SECONDS` (4 h): `cash` is the offline income just paid (or put on the pads), `grown` the number of pad slimes whose growth rose from offline time (`Growth.applyOffline`). Missing / future `lastOnline` gives nil.
- **State:** `welcomeBack: { away, cash, grown, onPads? }?`, present for the whole session.
- **One card (client):** the `Welcome` menu card shows the join report and the daily reward together (`ui/WelcomeBack.view`). Two modes:
  - `join` (opened once per join for the report): title "Welcome back", a cash row (the away time and where the cash went), the daily row (7 days of the 30-day streak from `State.daily.track`, §54), and a growth row when slimes grew.
  - `daily` (a daily claim becomes ready without a report, or Goals "Open"): title "Daily reward", only the daily row.
  - The main button claims the daily reward with the existing `Request("Daily")` while `State.daily.available`; otherwise it only closes the card ("Got it"). The away cash is never claimed here: it was paid (or put on the cash pads) at join. After a claim the button reads "Claimed" and the card closes 1.5 s later, unless another menu took its place.
  - "Double it" (`ExclusiveShopView.doubleQuickBuy`) and "Keep my streak" (`ExclusiveShopView.streakQuickBuy`) show as secondary buttons when offered.
- **Ordering (`ui/PopupQueue`):** the early tutorial steps hold the card back, and it never replaces a menu or the bag the player has open: it waits until they close it. The join report opens it in `join` mode and takes any pending daily edge with it, so closing the card without claiming does not reopen it. A later daily availability edge opens it in `daily` mode, unless Settings `dailyPopup` is off (then the reward waits in Goals). The join card shows regardless of that setting.
