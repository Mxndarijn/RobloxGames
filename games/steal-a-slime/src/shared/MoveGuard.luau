--!strict
--[[
	MoveGuard (pure, FEATURES.MoveGuardLog)

	Compares a player's root position between two samples and says whether the player could have walked there.
	Log-only: nothing here moves, kicks or releases anyone. No Roblox APIs, so Lune tests it.

	  * Horizontal: allowed = maxSpeed x dt x FACTOR + SLACK (maxSpeed = the speed the SERVER set, never the client's
	    WalkSpeed). Sloped ground only makes the horizontal part shorter, so it needs no extra room.
	  * Vertical, split: a jump or bounce going UP is bounded by MAX_UP_SPEED x dt + SLACK; a drop is bounded by
	    MAX_FALL_SPEED x dt + SLACK (free fall has no hard cap, 400 studs/s is two seconds of gravity at 196.2).
	    A 100 stud teleport in one 0.1 s tick is 1000 studs/s either way, so both bounds still catch it.
	  * allow(state, t, seconds): every server-initiated move opens a window. The next sample inside it only
	    moves the baseline (no violation), so a teleport, launch or respawn never counts.
	  * dt above MAX_DT (a server hitch, a stalled player step) re-baselines instead of judging a long gap.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Vec = { X: number, Y: number, Z: number }

export type State = {
	lastPos: Vec?,
	lastT: number,
	allowUntil: number,
	rebase: boolean, -- an allow() happened: the next sample only sets the baseline
	samples: number,
	violations: number,
	maxExcess: number, -- studs over the allowed displacement, worst so far
	unreported: number, -- violations since the last summary line
}

export type Result = { ok: boolean, excess: number, horizontal: number, vertical: number }

local MoveGuard = {}

function MoveGuard.newState(): State
	return {
		lastPos = nil,
		lastT = 0,
		allowUntil = -math.huge,
		rebase = false,
		samples = 0,
		violations = 0,
		maxExcess = 0,
		unreported = 0,
	}
end

-- Opens an allow-window of `seconds` from `t`; the next sample re-baselines.
function MoveGuard.allow(state: State, t: number, seconds: number)
	state.allowUntil = math.max(state.allowUntil, t + seconds)
	state.rebase = true
end

-- New character (respawn): forget the baseline and any window.
function MoveGuard.reset(state: State)
	state.lastPos = nil
	state.rebase = false
	state.allowUntil = -math.huge
end

local function finite(v: Vec): boolean
	return v.X == v.X
		and v.Y == v.Y
		and v.Z == v.Z
		and math.abs(v.X) ~= math.huge
		and math.abs(v.Y) ~= math.huge
		and math.abs(v.Z) ~= math.huge
end

local OK: Result = table.freeze({ ok = true, excess = 0, horizontal = 0, vertical = 0 })

-- One position sample at time `t`; `maxSpeed` = the fastest the server lets this player walk (studs/s).
function MoveGuard.sample(state: State, pos: Vec, t: number, maxSpeed: number): Result
	local cfg = Config.MOVE_GUARD
	if not finite(pos) then
		return OK
	end
	local last = state.lastPos
	local dt = t - state.lastT
	local baseline = last == nil or state.rebase or t < state.allowUntil or dt <= 0 or dt > cfg.MAX_DT
	state.lastPos, state.lastT, state.rebase = pos, t, false
	if baseline then
		return OK
	end
	state.samples += 1
	local last3 = last :: Vec
	local dx, dz, dy = pos.X - last3.X, pos.Z - last3.Z, pos.Y - last3.Y
	local horizontal = math.sqrt(dx * dx + dz * dz)
	local allowedH = maxSpeed * dt * cfg.FACTOR + cfg.SLACK
	local allowedV = (if dy >= 0 then cfg.MAX_UP_SPEED else cfg.MAX_FALL_SPEED) * dt + cfg.SLACK
	local excess = math.max(horizontal - allowedH, math.abs(dy) - allowedV, 0)
	if excess <= 0 then
		return OK
	end
	state.violations += 1
	state.unreported += 1
	state.maxExcess = math.max(state.maxExcess, excess)
	return { ok = false, excess = excess, horizontal = horizontal, vertical = dy }
end

-- Per-server bookkeeping: one State per user, reset when the character changes, rate-limited summary lines.
export type Book = {
	players: { [number]: State },
	characters: { [number]: any },
	pendingAllow: { [number]: number },
	lastLogAt: number,
}

function MoveGuard.newBook(): Book
	return { players = {}, characters = {}, pendingAllow = {}, lastLogAt = -math.huge }
end

-- Server-initiated move for `userId`; applied to the player's state at its next sample.
function MoveGuard.allowUser(book: Book, userId: number, seconds: number)
	book.pendingAllow[userId] = math.max(book.pendingAllow[userId] or 0, seconds)
end

function MoveGuard.forget(book: Book, userId: number)
	book.players[userId] = nil
	book.characters[userId] = nil
	book.pendingAllow[userId] = nil
end

-- One sample for a player. `character` identifies the current character (a new one resets the baseline).
function MoveGuard.step(book: Book, userId: number, character: any, pos: Vec, t: number, maxSpeed: number): Result
	local state = book.players[userId]
	if not state then
		state = MoveGuard.newState()
		book.players[userId] = state
	end
	if book.characters[userId] ~= character then
		book.characters[userId] = character
		MoveGuard.reset(state)
		MoveGuard.allow(state, t, Config.MOVE_GUARD.RESPAWN_ALLOW)
	end
	local pending = book.pendingAllow[userId]
	if pending then
		book.pendingAllow[userId] = nil
		MoveGuard.allow(state, t, pending)
	end
	return MoveGuard.sample(state, pos, t, maxSpeed)
end

-- A summary line at most every LOG_INTERVAL seconds, and only when something was flagged since the last one.
function MoveGuard.summary(book: Book, t: number): string?
	if t - book.lastLogAt < Config.MOVE_GUARD.LOG_INTERVAL then
		return nil
	end
	local parts = {}
	for userId, state in book.players do
		if state.unreported > 0 then
			table.insert(
				parts,
				`{userId}: +{state.unreported} (total {state.violations}/{state.samples}, worst +{math.floor(
					state.maxExcess
				)} studs)`
			)
			state.unreported = 0
		end
	end
	if #parts == 0 then
		return nil
	end
	book.lastLogAt = t
	table.sort(parts)
	return "MoveGuard (log only): " .. table.concat(parts, "; ")
end

return MoveGuard
