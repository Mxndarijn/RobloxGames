# 48. Notice cards: steal moments on screen

**Status:** always on (no flag). Server-authoritative; no new remote, **no save-format change**, nothing saved.

Most Notify messages only play their sound (UI-STYLEGUIDE "No toasts"). A few moments get a card in the top banner stack instead, drawn by `ui/StealCards` in the steal-card style.

- **Owner steal cards (client only):** from `State.slimes[].stolenBy`. "Ann is stealing your slime!" while a thief carries one; "Ann has stolen one of your slimes" for `StealCardsLogic.STOLEN_SECONDS` once a carried slime is gone from the plot. At most `StealCardsLogic.MAX_CARDS` cards, then a "+N more" chip.
- **State `notices: { Notice }`** (`shared/NoticeCards`): the live notices for this player, `{ id, at, name?, opensAt? }`. The server adds them with `World.notice` and sends those younger than `NoticeCards.SECONDS[id]`; the client shows each `id`+`at` once for that long.
  - `Bonked`: you were bonked while carrying a stolen slime (`StealService.escape`, reason `slap`).
  - `SlimeHome`: a slime being stolen from you went home (`StealService.escape`, any reason); `name` = the carrier.
  - `BaseLocked`: you walked into a locked base (`SlimeGuard.intruded`); `opensAt` = that owner's `lockUntil`, shown as a countdown.
- **State `plotFull: boolean`:** you carry a slime in your own HomeZone and no pad is free (`ServerLoop`). The carry card shows "Your plot is full" / "Sell or merge a slime" with the Gold ring until that changes.
