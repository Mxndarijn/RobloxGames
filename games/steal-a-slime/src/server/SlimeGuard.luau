--!strict
--[[
	SlimeGuard (pure, FEATURES.SlimeGuard, CONTRACT.md §41)

	Anti-cheat for stealing. Owns `world.guard` (per player: the shared MovementGuard track, Suspicion points,
	where a stolen carry began, the other player's jar the character is in) and `world.stealLedger` (completed
	steals, for undo). The adapter (SlimeGuardView) feeds positions and does the Roblox side (kicks, log
	lines); everything decided here is plain data over World.

	When a steal looks wrong, the slime goes home (StealService.escape "guard"). In watch mode
	(SLIME_GUARD.ENFORCE = false) flags only add points and come back as Reports for the log; the lock rules
	(intruders reported, the breather lock) apply in both modes. The guard never moves a character.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local MovementGuard = if Lib
	then require(Lib.anticheat.MovementGuard)
	else require("../../../../shared/luau/src/anticheat/MovementGuard")
local Suspicion = if Lib
	then require(Lib.anticheat.Suspicion)
	else require("../../../../shared/luau/src/anticheat/Suspicion")
local PlotGuests = if script then require(script.Parent.PlotGuests) else require("./PlotGuests")
local PlotLockGuard = if script then require(script.Parent.PlotLockGuard) else require("./PlotLockGuard")
local StealService = if script then require(script.Parent.StealService) else require("./StealService")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

export type Mode = "off" | "watch" | "enforce"

-- One flag, for the adapter's log line and kick.
export type Report = {
	userId: number,
	kind: string,
	detail: string,
	points: number, -- the player's points after this flag
	level: Suspicion.Level,
	enforced: boolean, -- ENFORCE was on: the effects applied
}

local SlimeGuard = {}

local G = Config.SLIME_GUARD

function SlimeGuard.mode(world: World): Mode
	if world.guardMode then
		return world.guardMode
	end
	if not Config.FEATURES.SlimeGuard then
		return "off"
	end
	return if G.ENFORCE then "enforce" else "watch"
end

function SlimeGuard.entry(world: World, userId: number, now: number): World.GuardEntry
	local e = world.guard[userId]
	if not e then
		e = {
			track = MovementGuard.new(),
			suspicion = Suspicion.new(now),
			lastMax = 0,
			carry = nil,
			plot = nil,
			logMinute = -1,
			logCount = 0,
		}
		world.guard[userId] = e
	end
	return e
end

function SlimeGuard.forget(world: World, userId: number)
	world.guard[userId] = nil
end

-- The server moved the character itself (respawn, void rescue, drop tube, launch): start fresh.
function SlimeGuard.serverMoved(world: World, userId: number, now: number)
	local track = SlimeGuard.entry(world, userId, now).track
	MovementGuard.reset(track)
	MovementGuard.allow(track, now, G.SERVER_MOVE_SECONDS, math.huge)
end

-- A PvP / boss launch or PvP control is active this tick: fast movement and rising are the server's doing.
function SlimeGuard.launchWindow(world: World, userId: number, now: number)
	MovementGuard.allow(SlimeGuard.entry(world, userId, now).track, now, G.SAMPLE_SECONDS * 2, G.LAUNCH_SPEED)
end

function SlimeGuard.inWindow(world: World, userId: number, now: number): boolean
	local e = world.guard[userId]
	return e ~= nil and MovementGuard.inWindow(e.track, now)
end

-- True when this report should become a log line (at most LOG_PER_MINUTE per player).
function SlimeGuard.shouldLog(world: World, userId: number, now: number): boolean
	local e = SlimeGuard.entry(world, userId, now)
	local minute = math.floor(now / 60)
	if minute ~= e.logMinute then
		e.logMinute = minute
		e.logCount = 0
	end
	e.logCount += 1
	return e.logCount <= G.LOG_PER_MINUTE
end

--[[
	Undoes `thiefId`'s steals of the last UNDO_SECONDS: each slime the thief still has goes back to its victim when
	the victim is here, both saves are writable, the slime is not busy and the victim has a free pad.
	Returns (returned, kept).
]]
function SlimeGuard.undoRecent(world: World, thiefId: number, now: number): (number, number)
	local thief = World.session(world, thiefId)
	local returned, kept = 0, 0
	for _, record in world.stealLedger do
		if record.thiefId == thiefId and not record.undone and now - record.at <= G.UNDO_SECONDS then
			record.undone = true
			local victim = World.session(world, record.victimId)
			local held = if thief then PlayerData.findSlime(thief.data, record.slimeId) else nil
			if
				thief
				and victim
				and held
				and World.canSave(world, thiefId)
				and World.canSave(world, record.victimId)
				and not World.isBusy(world, record.slimeId)
				and PlayerData.freePad(victim.data) ~= nil
			then
				local slime = PlayerData.removeSlime(thief.data, record.slimeId) :: Genome.Slime
				slime.pad = nil
				PlayerData.addSlime(victim.data, slime)
				World.markDirty(thief)
				World.markDirty(victim)
				World.notify(
					world,
					victim.userId,
					`Your {Genome.displayName(slime)} was returned: {thief.name} was removed for cheating.`,
					"good",
					"Escape"
				)
				returned += 1
			else
				kept += 1
			end
		end
	end
	return returned, kept
end

-- Adds the points for one flag. With ENFORCE on, a stolen carry goes home and a kick undoes recent steals.
function SlimeGuard.report(world: World, session: Session, kind: string, detail: string, now: number): Report
	local e = SlimeGuard.entry(world, session.userId, now)
	local level = Suspicion.add(e.suspicion, G.POINTS[kind] or 1, now)
	local enforced = SlimeGuard.mode(world) == "enforce"
	if enforced then
		local carry = session.carry
		if carry and carry.kind == "stolen" then
			StealService.escape(world, session, now, "guard")
		end
		if level == "kick" then
			SlimeGuard.undoRecent(world, session.userId, now)
		end
	end
	local report: Report = {
		userId = session.userId,
		kind = kind,
		detail = detail,
		points = e.suspicion.points,
		level = level :: Suspicion.Level,
		enforced = enforced,
	}
	return report
end

--[[
	One server-read position for `session`'s character. `allowedSpeed` is Carry.targetWalkSpeed this tick; the
	check uses the higher of it and last tick's, so a Speed Coil put away mid-run is not a flag. Remembers where a
	stolen carry began (the last position before the grab). Returns a Report on a flag.
]]
function SlimeGuard.observe(
	world: World,
	session: Session,
	x: number,
	y: number,
	z: number,
	now: number,
	allowedSpeed: number
): Report?
	if SlimeGuard.mode(world) == "off" then
		return nil
	end
	local e = SlimeGuard.entry(world, session.userId, now)
	local maxSpeed = math.max(allowedSpeed, e.lastMax)
	e.lastMax = allowedSpeed
	local carry = session.carry
	if carry and carry.kind == "stolen" then
		if not e.carry or e.carry.slimeId ~= carry.slimeId then
			local from = e.track.last
			e.carry = {
				slimeId = carry.slimeId,
				x = if from then from.x else x,
				z = if from then from.z else z,
				maxSpeed = maxSpeed,
			}
		else
			e.carry.maxSpeed = math.max(e.carry.maxSpeed, maxSpeed)
		end
	else
		e.carry = nil
	end
	local last = e.track.last
	local flag = MovementGuard.step(e.track, { t = now, x = x, y = y, z = z }, maxSpeed)
	if not flag then
		return nil
	end
	local moved = if last then math.sqrt((x - last.x) ^ 2 + (z - last.z) ^ 2) else 0
	local rise = if last then y - last.y else 0
	local detail = `{flag}: {math.floor(moved + 0.5)} studs flat, {math.floor(rise + 0.5)} up in one sample at `
		.. `({math.floor(x)}, {math.floor(y)}, {math.floor(z)}), allowed {math.floor(maxSpeed + 0.5)} studs/s`
	return SlimeGuard.report(world, session, flag, detail, now)
end

-- (recentTeleport, stealsPaused) for Steal.canSteal; both false unless ENFORCE is on.
function SlimeGuard.stealBlock(
	world: World,
	userId: number,
	now: number
): { recentTeleport: boolean, stealsPaused: boolean }
	local e = world.guard[userId]
	if SlimeGuard.mode(world) ~= "enforce" or not e then
		return { recentTeleport = false, stealsPaused = false }
	end
	return {
		recentTeleport = MovementGuard.teleportedWithin(e.track, now, G.TELEPORT_COOLDOWN),
		stealsPaused = Suspicion.paused(e.suspicion, now),
	}
end

--[[
	The carrier of a stolen slime stands in their HomeZone at world (x, z). False (and a Report) when
	it got there faster than the straight line from where the carry began allows at DEPOSIT_SPEED_SLACK x the fastest
	carry speed seen: with ENFORCE on the slime has gone home and the deposit must not run. In watch mode the
	Report is returned but the deposit may go ahead.
]]
function SlimeGuard.depositCheck(world: World, session: Session, x: number, z: number, now: number): (boolean, Report?)
	local carry = session.carry
	if SlimeGuard.mode(world) == "off" or not carry or carry.kind ~= "stolen" then
		return true, nil
	end
	local e = world.guard[session.userId]
	local from = e and e.carry
	if not from or from.slimeId ~= carry.slimeId then
		return true, nil
	end
	local distance = math.sqrt((x - from.x) ^ 2 + (z - from.z) ^ 2)
	local need = distance / (math.max(from.maxSpeed, 1) * G.DEPOSIT_SPEED_SLACK)
	local took = now - carry.timer.startedAt
	if took >= need then
		return true, nil
	end
	local detail = `earlyDeposit: carried {string.format("%.1f", took)} s over {math.floor(distance + 0.5)} studs, `
		.. `needs {string.format("%.1f", need)} s`
	local report = SlimeGuard.report(world, session, "earlyDeposit", detail, now)
	return not report.enforced, report
end

-- A steal completed (Carry.deposit): record it for undo and give the victim a breather lock.
function SlimeGuard.recordSteal(world: World, thiefId: number, victim: Session, slime: Genome.Slime, now: number)
	if SlimeGuard.mode(world) == "off" then
		return
	end
	local kept = {}
	for _, record in world.stealLedger do
		if now - record.at <= G.UNDO_SECONDS then
			table.insert(kept, record)
		end
	end
	table.insert(kept, {
		thiefId = thiefId,
		victimId = victim.userId,
		slimeId = slime.id,
		name = Genome.displayName(slime),
		at = now,
		undone = false,
	})
	world.stealLedger = kept
	SlimeGuard.breather(world, victim, now)
end

-- The victim's base locks for at least BREATHER_SECONDS more; a longer lock is kept.
function SlimeGuard.breather(world: World, owner: Session, now: number)
	local untilTime = now + G.BREATHER_SECONDS
	if owner.lockUntil >= untilTime then
		return
	end
	if not StealService.isLocked(owner, now) then
		owner.lockStartedAt = now
	end
	owner.lockUntil = untilTime
	World.markDirty(owner)
	World.notify(world, owner.userId, `Your base is locked for {G.BREATHER_SECONDS}s`, "good", "Lock", "Lock")
end

-- Jar floors built on a plot (the tower the guard counts as "inside").
function SlimeGuard.floorsOf(owner: Session): number
	local pads = owner.data.padsUnlocked
	return if pads > 0 then Economy.floorsShown(pads) else 1
end

-- The other player's jar the character was in at the last tick (for PlotLockGuard.insideJar's hysteresis).
function SlimeGuard.currentPlot(world: World, userId: number): number?
	local e = world.guard[userId]
	return e and e.plot and e.plot.index
end

--[[
	`inside` is the index of another player's jar the character is in this tick (nil = none). Remembers when it
	went in; returns that index once per visit when the plot is locked and the character got in after the lock
	began (an intruder). Nobody is moved: a character inside a locked base just can't steal there.

	A guest (PlotGuests) is never an intruder, and neither is a former guest still inside from that visit: when
	the owner switches friends off (or they stop being friends) the friend stays where they are and may walk out
	through the stopper (`formerGuests`), but no longer steal.
]]
function SlimeGuard.trackPlot(world: World, session: Session, inside: number?, now: number): number?
	if SlimeGuard.mode(world) == "off" then
		return nil
	end
	local e = SlimeGuard.entry(world, session.userId, now)
	if inside == nil then
		e.plot = nil
		return nil
	end
	local was = e.plot
	local plot: World.PlotVisit = if was and was.index == inside then was else { index = inside, since = now }
	e.plot = plot
	local ownerId = world.plots[inside]
	local owner = if ownerId then World.session(world, ownerId) else nil
	if not owner or owner.userId == session.userId then
		return nil
	end
	if PlotGuests.isGuest(owner, session.userId) then
		plot.guest = true
		return nil
	end
	if plot.guest or plot.flagged or not StealService.isLocked(owner, now) then
		return nil
	end
	if not PlotLockGuard.intruder(plot.since, owner.lockStartedAt) then
		return nil
	end
	plot.flagged = true
	return inside
end

--[[
	Former guests still inside the base they were let into: result[i][userId] = true when that player was a guest of
	plot i on this visit, is no longer one, and is still in its jar. The stopper keeps letting them through until
	they are out, so nobody is shut in a base they were invited into.
]]
function SlimeGuard.formerGuests(world: World): { [number]: { [number]: boolean } }
	local out = {}
	for userId, e in world.guard do
		local plot = e.plot
		if plot and plot.guest then
			local ownerId = world.plots[plot.index]
			local owner = if ownerId then world.sessions[ownerId] else nil
			if owner and world.sessions[userId] and not PlotGuests.isGuest(owner, userId) then
				local set = out[plot.index] or {}
				set[userId] = true
				out[plot.index] = set
			end
		end
	end
	return out
end

--[[
	Who plot i's stopper lets through besides its owner: result[i] = the sorted user ids of its guests in the server
	(PlotGuests.list) and its former guests still inside (formerGuests). Plots nobody passes are left out.
]]
function SlimeGuard.stopperPasses(world: World, features: PlotGuests.Features): { [number]: { number } }
	local sets = SlimeGuard.formerGuests(world)
	for _, owner in world.sessions do
		for _, id in PlotGuests.list(world, owner, features) do
			local set = sets[owner.plotIndex] or {}
			set[id] = true
			sets[owner.plotIndex] = set
		end
	end
	local out = {}
	for index, set in sets do
		local ids = {}
		for id in set do
			table.insert(ids, id)
		end
		table.sort(ids)
		out[index] = ids
	end
	return out
end

--[[
	An intruder was found inside a locked base (trackPlot): a stolen carry goes home and the player is told. They
	stay where they are. `serverPut` = a server launch put them there: no points.
]]
function SlimeGuard.intruded(
	world: World,
	session: Session,
	plotIndex: number,
	now: number,
	serverPut: boolean
): Report?
	local carry = session.carry
	if carry and carry.kind == "stolen" then
		StealService.escape(world, session, now, "guard")
	end
	World.notify(world, session.userId, "That base is locked. You can't steal here until it opens.", "info", "Denied")
	local ownerId = world.plots[plotIndex]
	local owner = if ownerId then World.session(world, ownerId) else nil
	World.notice(world, session, { id = "BaseLocked", at = now, opensAt = if owner then owner.lockUntil else nil })
	if serverPut then
		return nil
	end
	return SlimeGuard.report(world, session, "lockedEntry", `lockedEntry: inside locked plot {plotIndex}`, now)
end

return SlimeGuard
