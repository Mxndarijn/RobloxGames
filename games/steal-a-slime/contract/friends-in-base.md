# §42 Friends in your base (`FEATURES.FriendsInBase`)

An owner can let their Roblox friends into their base while it is locked. A let-in friend (a **guest**) walks through the cork stopper and may steal there, exactly as if the base were open. Everyone else is still blocked (§41.5). The switch is free, saved, and starts off.

Owners: Phoenix (`src/server`, `src/shared`), Jolt (`src/ui`).

## 42.1 Rule

- A player is a guest of plot `i` when `FEATURES.FriendsInBase` is on, the owner's `data.allowFriends` is `true`, and the player is in the owner's `session.friendIds` (Roblox friends in this server, filled by `Friends.refresh` on every join and leave from the cached `Player:IsFriendsWith`). The owner is never their own guest. `server/PlotGuests` holds the rule.
- A guest passes the lock in `Steal.canSteal` (`thiefIsGuest`); every other steal rule still applies (saves, vat, paused steals, distance).
- A guest is never a locked-base intruder (`SlimeGuard.trackPlot`). Nobody is ever teleported for a lock.
- When a guest stops being one (switch off, unfriended) while inside the jar, they stay where they are and are not an intruder. They can no longer steal there, and the stopper keeps letting them through until they have left the jar (`SlimeGuard.formerGuests`). Once out, they are blocked like anyone.
- The breather lock after a steal (§41.6) does not stop guests: it is a lock like any other.

## 42.2 Request and prompt

| Action | Args | Effect |
|---|---|---|
| `"ToggleFriends"` | none | Flips `data.allowFriends`. Toasts the owner; on switching on, toasts each friend in the server "<name> lets you into their base". Refused with `"unknown action"` when the feature is off. Rate limit 0.5 s. |

- `FriendsPrompt` (`Constants.FRIENDS_PROMPT_NAME`) is an owner-only plot prompt on the `LockButton`, next to `LockPrompt`, with the plot prompt rules of §8.5 (`ShowOnlyToUserId`, range check through `PlotPadGuard`, kind `"ToggleFriends"`). Keys `Constants.FRIENDS_PROMPT_KEYS` (G, gamepad ButtonY; F is the pad hatch key). Instant. `ActionText` "Allow friends" / "Block friends", `ObjectText` "Friends: blocked" / "Friends can enter".
- `LockPrompt` and `FriendsPrompt` use `ProximityPromptStyle.Custom`: `src/ui/SlimeKeyCard` draws one card over the button, titled with the lock status from the `LockPrompt` ObjectText ("LOCKED 1:42" / "OPEN", without the "<name>'s base: " part), the `FriendsPrompt` ObjectText under it, one row per prompt (lock first).

## 42.3 Attributes

- `Plot_<i>.FriendsAllowed: true?` (`Constants.PLOT_FRIENDS_ALLOWED_ATTRIBUTE`): set while the owner's switch is on. `src/ui/FriendsLockIcon` shows the friend icon (`ItemIcons` `Boost_Friend`) as a sticker on the outer face of the shut stopper (`LockBarrier.Stopper`) while the plot is also `Locked`, and as a badge over the `LockButton` while the switch is on. Nothing shows with the switch off.
- `Plot_<i>.Guests: string?` (`Constants.PLOT_GUESTS_ATTRIBUTE`): `",<id>,<id>,"` of the players plot `i`'s stopper lets through besides the owner (`SlimeGuard.stopperPasses`), nil for none. `PlotDecor` shows the shut door half see-through (`OWNER_DOOR_TRANSPARENCY`) to those viewers, as it does to the owner.
- `GrabPrompt.GuestsOnly: string?` (`Constants.PROMPT_GUESTS_ATTRIBUTE`): on the Steal prompts of a locked base that has guests in the server, `",<id>,<id>,"`. Such a prompt is `Enabled` on the server, and `src/ui/PromptHide` keeps it disabled on every client whose UserId is not in the list. The server writes `GuestsOnly` before `Enabled`, so a client applies the list first. `Carry.grab` still refuses a non-guest.

## 42.4 Stopper collisions

`PlotLock_<i>` (the stopper's parts) and `PlotOwner_<j>` (player `j`'s character; every player owns one plot) are set non-colliding while plot `j`'s owner passes plot `i`'s stopper (a guest, or a former guest still inside), and colliding again when that ends (`WorldView`, from `SlimeGuard.stopperPasses`). No new collision groups.

## 42.5 Save

`allowFriends: true?` in the save; missing or anything but `true` loads as off. No version bump.
