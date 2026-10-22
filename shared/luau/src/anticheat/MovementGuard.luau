--!strict
--[[
	MovementGuard (pure)

	Server-side movement check for characters the client physically owns. The server feeds one position per
	player at a steady rate (`step`); the guard compares it with the previous one and returns a flag:

	* "teleport": one jump much longer than the allowed speed covers, past `teleportStuds`.
	* "speed": flat speed over the limit for `overSeconds` in a row (one flag per fast stretch).
	* "fly": rising faster than any jump.

	The limit is `maxSpeed` (the speed the server set for the character) times `speedSlack`. Movement the server
	causes on purpose goes through `allow` (a window with a higher limit and no rise check) or `reset` (forget the
	last point, for a server teleport or a respawn) and is never flagged.

	Two tolerances keep honest players clear:
	* Lag: samples where the character did not move add up (to `maxStall` s) and the next real move may cover that
	  time too, so a replication freeze followed by a catch-up is not a teleport.
	* Downhill: every stud of height lost gives `dropCredit` studs of extra flat travel (capped, fading with
	  `creditHalfLife`), so a slide or a jump off a ledge is not a speed hack.

	No Roblox APIs: runs unchanged under Lune.
]]

export type Sample = { t: number, x: number, y: number, z: number }
export type Flag = "teleport" | "speed" | "fly"

export type Options = {
	speedSlack: number, -- x maxSpeed
	jumpSlack: number, -- studs a single sample may run over the limit (replication jitter)
	teleportStuds: number, -- one jump at least this long (after slack and credit) is a teleport
	overSeconds: number, -- too fast this long in a row is a speed hack
	maxRise: number, -- studs/s upward outside a window
	maxStall: number, -- seconds of standing still a catch-up move may use
	stillStuds: number, -- a sample that moved less than this counts as standing still
	dropCredit: number, -- extra flat studs per stud of height lost
	creditMax: number, -- studs of downhill credit at most
	creditHalfLife: number, -- seconds for unused credit to halve
}

export type Track = {
	options: Options,
	last: Sample?,
	stalled: number, -- seconds without movement since the last move (capped at maxStall)
	credit: number, -- downhill credit in studs
	allowUntil: number,
	allowSpeed: number,
	teleportAt: number,
	overSince: number?,
	reported: boolean,
}

local MovementGuard = {}

MovementGuard.DEFAULTS = table.freeze({
	speedSlack = 1.35,
	jumpSlack = 4,
	teleportStuds = 30,
	overSeconds = 0.6,
	maxRise = 80,
	maxStall = 1,
	stillStuds = 0.05,
	dropCredit = 2,
	creditMax = 40,
	creditHalfLife = 1,
} :: Options)

function MovementGuard.new(overrides: { [string]: number }?): Track
	local options = table.clone(MovementGuard.DEFAULTS) :: any
	for key, value in overrides or {} do
		if options[key] == nil or type(value) ~= "number" or value ~= value then
			error(`MovementGuard.new: bad option {tostring(key)}`, 2)
		end
		options[key] = value
	end
	return {
		options = table.freeze(options) :: Options,
		last = nil,
		stalled = 0,
		credit = 0,
		allowUntil = -math.huge,
		allowSpeed = 0,
		teleportAt = -math.huge,
		overSince = nil,
		reported = false,
	}
end

-- The server is about to move this character on purpose: for `seconds` the flat limit is at least `speed` and the
-- rise check is off. Overlapping windows keep the later end and the higher speed.
function MovementGuard.allow(track: Track, now: number, seconds: number, speed: number)
	local active = now < track.allowUntil
	track.allowSpeed = if active then math.max(track.allowSpeed, speed) else speed
	track.allowUntil = math.max(track.allowUntil, now + seconds)
end

-- The server teleported the character (or it respawned): the next sample starts fresh.
function MovementGuard.reset(track: Track)
	track.last = nil
	track.stalled = 0
	track.credit = 0
	track.overSince = nil
	track.reported = false
end

function MovementGuard.inWindow(track: Track, now: number): boolean
	return now < track.allowUntil
end

function MovementGuard.teleportedWithin(track: Track, now: number, seconds: number): boolean
	return now - track.teleportAt < seconds
end

-- Feeds one server-read position. `maxSpeed` is the flat speed the server allows right now (studs/s).
function MovementGuard.step(track: Track, s: Sample, maxSpeed: number): Flag?
	local o = track.options
	local last = track.last
	track.last = s
	if not last then
		return nil
	end
	local dt = s.t - last.t
	if dt <= 0 then
		return nil
	end
	track.credit *= 0.5 ^ (dt / o.creditHalfLife)
	local drop = last.y - s.y
	if drop > 0 then
		track.credit = math.min(o.creditMax, track.credit + drop * o.dropCredit)
	end

	local dx, dz = s.x - last.x, s.z - last.z
	local flat = math.sqrt(dx * dx + dz * dz)
	if flat < o.stillStuds and math.abs(drop) < o.stillStuds then
		track.stalled = math.min(o.maxStall, track.stalled + dt)
		track.overSince = nil
		track.reported = false
		return nil
	end
	local span = dt + track.stalled
	track.stalled = 0

	local inWindow = s.t < track.allowUntil
	local limit = maxSpeed * o.speedSlack
	if inWindow then
		limit = math.max(limit, track.allowSpeed)
	end
	local over = flat - limit * span
	local used = 0
	if over > 0 and track.credit > 0 then
		used = math.min(track.credit, over)
		track.credit -= used
		over -= used
	end

	if not inWindow and over > o.jumpSlack and flat - used > o.teleportStuds then
		track.teleportAt = s.t
		track.overSince = nil
		return "teleport"
	end

	if over > 0 then
		track.overSince = track.overSince or last.t
		if not track.reported and s.t - (track.overSince :: number) >= o.overSeconds - 1e-9 then
			track.reported = true
			return "speed"
		end
	else
		track.overSince = nil
		track.reported = false
	end

	if not inWindow and (s.y - last.y) / span > o.maxRise then
		return "fly"
	end
	return nil
end

return table.freeze(MovementGuard)
