# §41 Slime Guard (`FEATURES.SlimeGuard`)

Anti-cheat for stealing. The goal is narrow: a cheater never keeps someone else's slime, and an honest player never loses one to a cheater. When a steal looks wrong, the slime goes home, the same as when a thief is hit. Tunables are in `Config.SLIME_GUARD`; movement thresholds are the defaults of the shared `Lib.anticheat.MovementGuard`.

Owner: Phoenix (`src/server`, `src/shared`). No new remote, State field or attribute.

## 41.1 Modes

- `FEATURES.SlimeGuard = false`: none of this section runs.
- `Config.SLIME_GUARD.ENFORCE = false` (watch mode): every check runs, flags are logged on the server (`[SlimeGuard]` lines) and add suspicion points, but steals are not bounced, refused, paused or undone and nobody is kicked.
- `ENFORCE = true`: the effects below apply.
- §41.5 (locked-base intruders) and §41.6 (breather lock) are lock rules and apply in both modes; only their points follow the mode.

## 41.2 Movement check

- The server reads every character's `HumanoidRootPart` position every `SAMPLE_SECONDS` and feeds it to `MovementGuard.step` with `Carry.targetWalkSpeed` (the higher of this tick's and the last tick's) as the allowed flat speed.
- Flags: `teleport` (one long jump), `speed` (over the limit for 0.6 s in a row), `fly` (rising faster than a jump). Lag freezes and downhill runs (slides, ledges) are tolerated by the guard itself.
- Server-caused movement is never flagged: while `PvpLaunch.guardActive` is true (a PvP or boss launch, PvP control) the limit is `LAUNCH_SPEED`; a respawn, a void rescue, the doorway set-down and an intruder sent home reset the guard and skip `SERVER_MOVE_SECONDS`.

## 41.3 Steal gate, carry watch, deposit check

- `Steal.canSteal` refuses (enforce only) within `TELEPORT_COOLDOWN` s of a teleport flag (reason "too far away", the same as a normal miss) and while the player's steals are paused ("stealing is paused for a moment").
- Any flag while carrying a stolen slime ends the carry: `StealService.escape(..., "guard")`, the slime goes home (enforce only).
- The guard records where a stolen carry started. A deposit that arrives faster than the straight line home allows at `DEPOSIT_SPEED_SLACK` x the fastest carry speed seen is refused, the slime goes home and the player gets `earlyDeposit` points (enforce only for the refusal).

## 41.4 Points, pause, kick and undo

- Points per flag: `SLIME_GUARD.POINTS`. They drain at 1 per minute (`Suspicion` defaults).
- 3 points: stealing paused for 60 s. 8 points: the player is kicked and every steal they completed in the last `UNDO_SECONDS` is undone (enforce only).
- Undo: each completed steal is written to `world.stealLedger` (thief, victim, a copy of the slime, time). Undoing removes the slime from the thief and gives it back to the victim when the victim is in the server, both saves are writable and the victim has a free pad. Otherwise the entry is logged and the slime stays where it is.
- No automatic bans.

## 41.5 Locked-base intruders

- The server tracks when each character entered each other player's jar (inside jar f's glass on a built floor, with hysteresis so the doorway does not flicker).
- A non-owner inside a locked plot who entered **after** the lock started (`session.lockStartedAt`) is an intruder: any stolen slime they carry goes home, they are set down on their own plot's spawn (`WorldView.plotSpawn`) and told "That base is locked. You were sent home." They get `lockedEntry` points unless a server launch put them there.
- A non-owner who was already inside when the lock started stays trapped inside until it ends (the LockBarrier blocks both ways, see `CONTRACT.md` §2), as before.

## 41.6 Breather lock

- When a slime is stolen from a plot (deposit completes), the victim's plot is locked for at least `BREATHER_SECONDS` more. An existing longer lock is kept; a new lock sets `lockStartedAt`.
