--!strict
--[[
	LockBreak (pure, contract/exclusive-shop.md §11)

	"Open locked door": a paid pass for one player through one locked base's LockBarrier. Owns `session.lockBreakAim`
	(the base the next LockBreak receipt opens, AimLockBreak) and `session.lockBreak` (the running pass: plot, the
	owner it was bought against, when it ends). Both are runtime only.

	  * Only the buyer passes, only that plot, only for Config.EXCLUSIVE_SHOP.lockBreak.seconds from the moment it
	    opened. A pass is never extended or stacked: a second one can't open while one runs.
	  * The lock itself is untouched: it stays up for everyone else and its timer runs as before.
	  * Refused for an open base, your own, a base in its breather lock (SlimeGuard.breather, after a steal) and a base
	    whose owner already lets the buyer in (PlotGuests).
	  * While the base is in a breather lock the pass does nothing (no stealing, the door is shut), and it ends early
	    when the plot changes owner. A buyer inside when it ends or pauses is let out like a former guest
	    (SlimeGuard.trackPlot marks the visit, SlimeGuard.formerGuests lets them through until they are out).
	  * Stealing inside still goes through every Steal / SlimeGuard check; the pass only answers "base is locked".
	No Roblox APIs.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local PlotGuests = if script then require(script.Parent.PlotGuests) else require("./PlotGuests")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local LockBreak = {}

local RULES = Config.EXCLUSIVE_SHOP.lockBreak

-- True while `owner`'s base is in the breather lock SlimeGuard gave it after a steal.
function LockBreak.inBreather(owner: Session, now: number): boolean
	local untilTime = owner.breatherUntil
	return untilTime ~= nil and owner.lockUntil == untilTime and Steal.isLocked(owner.lockUntil, now)
end

-- `session`'s running pass: nil when there is none, it ended, or its plot no longer belongs to the owner it was for.
function LockBreak.pass(world: World, session: Session, now: number): World.LockBreakPass?
	local pass = session.lockBreak
	if not pass or now >= pass.untilTime then
		return nil
	end
	if world.plots[pass.plot] ~= pass.ownerId or world.sessions[pass.ownerId] == nil then
		return nil
	end
	return pass
end

-- True when `userId`'s pass lets them through plot `plotIndex`'s locked door right now (and steal there).
function LockBreak.passes(world: World, userId: number, plotIndex: number, now: number): boolean
	local session = world.sessions[userId]
	local pass = if session then LockBreak.pass(world, session, now) else nil
	if not pass or pass.plot ~= plotIndex then
		return false
	end
	return not LockBreak.inBreather(world.sessions[pass.ownerId], now)
end

-- Who passes each plot's door on a lock break right now: result[plotIndex] = sorted user ids. Plots without are left out.
function LockBreak.holders(world: World, now: number): { [number]: { number } }
	local out: { [number]: { number } } = {}
	for userId, session in world.sessions do
		local pass = session.lockBreak
		if pass and LockBreak.passes(world, userId, pass.plot, now) then
			local list = out[pass.plot] or {}
			table.insert(list, userId)
			out[pass.plot] = list
		end
	end
	for _, list in out do
		table.sort(list)
	end
	return out
end

--[[
	Whether `buyer` may open plot `plotIndex`'s locked door now. Returns (ok, player-facing reason). `features`
	overrides Config.FEATURES (FriendsInBase) for tests.
]]
function LockBreak.canOpen(
	world: World,
	buyer: Session,
	plotIndex: number,
	now: number,
	features: PlotGuests.Features
): (boolean, string?)
	if type(plotIndex) ~= "number" or plotIndex % 1 ~= 0 or plotIndex < 1 or plotIndex > world.plotCount then
		return false, "that is not a base"
	end
	local ownerId = world.plots[plotIndex]
	local owner = if ownerId then world.sessions[ownerId] else nil
	if not owner then
		return false, "nobody owns that base"
	end
	if owner.userId == buyer.userId then
		return false, "that's your own base"
	end
	if not Steal.isLocked(owner.lockUntil, now) then
		return false, "that base isn't locked"
	end
	if LockBreak.inBreather(owner, now) then
		return false, "that base just lost a slime: its short lock can't be opened"
	end
	if PlotGuests.isGuest(owner, buyer.userId, features) then
		return false, "you can already walk in: they let their friends in"
	end
	if LockBreak.pass(world, buyer, now) then
		return false, "your lock break is still running"
	end
	return true, nil
end

-- AimLockBreak: remembers the locked base the next LockBreak receipt opens. Returns (ok, reason).
function LockBreak.aim(
	world: World,
	session: Session,
	plotIndex: number,
	now: number,
	features: PlotGuests.Features
): (boolean, string?)
	local ok, reason = LockBreak.canOpen(world, session, plotIndex, now, features)
	if not ok then
		return false, reason
	end
	session.lockBreakAim = { plot = plotIndex, ownerId = world.plots[plotIndex] :: number, at = now }
	return true, nil
end

-- The aimed plot when the aim is still fresh and the plot still has the owner it was aimed at; nil otherwise.
function LockBreak.aimed(world: World, session: Session, now: number): number?
	local aim = session.lockBreakAim
	if not aim or now - aim.at > RULES.aimSeconds or world.plots[aim.plot] ~= aim.ownerId then
		return nil
	end
	return aim.plot
end

-- Opens the pass for `session` on plot `plotIndex` (canOpen first) and tells both players. Returns (ok, reason).
function LockBreak.open(
	world: World,
	session: Session,
	plotIndex: number,
	now: number,
	features: PlotGuests.Features
): (boolean, string?)
	local ok, reason = LockBreak.canOpen(world, session, plotIndex, now, features)
	if not ok then
		return false, reason
	end
	local owner = world.sessions[world.plots[plotIndex] :: number]
	session.lockBreak = { plot = plotIndex, ownerId = owner.userId, untilTime = now + RULES.seconds }
	session.lockBreakAim = nil
	World.markDirty(session)
	World.markDirty(owner)
	World.notify(
		world,
		session.userId,
		`{owner.name}'s door is open for you for {RULES.seconds}s!`,
		"good",
		"Unlock",
		"Lock"
	)
	World.notify(world, owner.userId, `{session.name} broke into your base!`, "bad", "Alarm")
	return true, nil
end

-- Call every frame: forgets passes that ended (time up, or the plot changed owner) and pushes State for them.
function LockBreak.step(world: World, now: number)
	for _, session in world.sessions do
		local pass = session.lockBreak
		if pass and LockBreak.pass(world, session, now) == nil then
			session.lockBreak = nil
			World.markDirty(session)
			local owner = world.sessions[pass.ownerId]
			if owner then
				World.markDirty(owner)
			end
			World.notify(world, session.userId, "Your lock break ended", "info", nil)
		end
	end
end

return table.freeze(LockBreak)
