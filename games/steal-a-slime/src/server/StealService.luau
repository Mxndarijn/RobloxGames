--!strict
--[[
	StealService (pure)

	Plot locks, stealing a pad slime, the escape-home timer, slapping and lock
	expiry. Rules come from Shared.Steal; this module applies them to the
	World and queues toasts.

	* steal: the thief starts carrying a slime that stays in the victim's data
	  (it just stops paying) until Carry.deposit moves it with Steal.complete.
	* escape: the carry ends and the slime bounces back to its pad for
	  World.ESCAPE_BOUNCE_SECONDS (model State "Escaping"; still busy).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local EggKind = if Shared then require(Shared.EggKind) else require("../shared/EggKind")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local TutorialProgress = if Shared then require(Shared.TutorialProgress) else require("../shared/TutorialProgress")
local Revenge = if script then require(script.Parent.Revenge) else require("./Revenge")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local StealService = {}

function StealService.isLocked(session: Session, now: number): boolean
	return Steal.isLocked(session.lockUntil, now)
end

function StealService.buyLock(world: World, session: Session, now: number): (boolean, string?)
	local ok, lockUntil, result = Steal.buyLock(
		session.data,
		session.lockUntil,
		now,
		World.incomeOf(world, session),
		Revenge.lockMultiplier(world, session.userId, now)
	)
	if not ok then
		return false, result :: string
	end
	if not Steal.isLocked(session.lockUntil, now) then
		session.lockStartedAt = now -- a new lock; extending keeps the start
	end
	session.lockUntil = lockUntil
	session.locked = true
	session.data.stats.locks += 1
	World.markDirty(session)
	World.notify(world, session.userId, `Base locked for {math.floor(lockUntil - now + 0.5)}s`, "good", "Lock", "Lock")
	World.tutorial(world, session, "Lock")
	return true, nil
end

--[[
	The thief grabs a slime from someone else's pad. `distance` is the
	server-measured distance from the thief to the slime.
]]
function StealService.steal(
	world: World,
	thief: Session,
	slimeId: string,
	distance: number,
	now: number
): (boolean, string?)
	local owner, slime = World.ownerOf(world, slimeId)
	if not owner or not slime then
		return false, "slime is gone"
	end
	local ok, reason = Steal.canSteal({
		thiefId = thief.userId,
		ownerId = owner.userId,
		now = now,
		lockUntil = owner.lockUntil,
		thiefCarrying = thief.carry ~= nil,
		slimeBusy = World.isBusy(world, slimeId),
		distance = distance,
	})
	if not ok then
		return false, reason
	end
	thief.carry = {
		slimeId = slimeId,
		kind = "stolen",
		ownerUserId = owner.userId,
		timer = Steal.newCarry("stolen", EggKind.shownTier(slime), now),
		slime = slime,
	}
	world.carriedBy[slimeId] = thief.userId
	World.markDirty(thief)
	World.markDirty(owner)
	World.notify(world, owner.userId, `{thief.name} is stealing your {Genome.displayName(slime)}!`, "bad", "Alarm")
	World.notify(world, thief.userId, "Run home before it wriggles free!", "info", "Grab")
	World.effect(world, "Steal", { slimeId = slimeId, userId = thief.userId })
	World.tutorial(world, thief, "Steal")
	return true, nil
end

--[[
	Ends a stolen carry: the slime bounces home. `reason` is "wriggle" |
	"timeout" | "slap" | "drop" | "left". Returns the slime id or nil.
]]
function StealService.escape(world: World, carrier: Session, now: number, reason: string): string?
	local carry = carrier.carry
	if not carry or carry.kind ~= "stolen" then
		return nil
	end
	carrier.carry = nil
	world.carriedBy[carry.slimeId] = nil
	World.markDirty(carrier)

	local owner = if carry.ownerUserId then World.session(world, carry.ownerUserId) else nil
	local _, stillOwned = World.ownerOf(world, carry.slimeId)
	if not owner or not stillOwned then
		return nil -- owner left or the slime was wiped: nothing to bounce home
	end
	world.escaping[carry.slimeId] = now + World.ESCAPE_BOUNCE_SECONDS
	World.markDirty(owner)
	World.emit(world, {
		type = "Escaped",
		slimeId = carry.slimeId,
		ownerUserId = owner.userId,
		carrierUserId = carrier.userId,
		reason = reason,
	})
	local name = Genome.displayName(carry.slime)
	if reason == "slap" then
		World.notify(world, carrier.userId, `You got bonked! The {name} bounced home.`, "bad", "Slap", "Slap")
	elseif reason ~= "left" then
		World.notify(world, carrier.userId, `The {name} wriggled free!`, "bad", "Escape")
	end
	World.notify(world, owner.userId, `Your {name} escaped back to you!`, "good", "Escape")
	return carry.slimeId
end

function StealService.slap(
	world: World,
	slapper: Session,
	targetUserId: number,
	distance: number,
	now: number
): (boolean, string?)
	local target = World.session(world, targetUserId)
	local carry = target and target.carry
	local ok, reason = Steal.canSlap({
		now = now,
		lastSlapAt = slapper.lastSlapAt,
		distance = distance,
		slapperId = slapper.userId,
		targetId = targetUserId,
		targetCarry = carry and carry.timer,
	})
	if not ok or not target then
		return false, reason or "no such player"
	end
	slapper.lastSlapAt = now
	StealService.escape(world, target, now, "slap")
	World.notify(world, slapper.userId, `You bonked {target.name} with your bat!`, "good", "Slap", "Slap")
	World.tutorial(world, slapper, "Steal")
	return true, nil
end

-- Call once per second with the world's rng: wriggles and timeouts.
function StealService.tickEscapes(world: World, now: number)
	for _, session in world.sessions do
		local carry = session.carry
		if carry and carry.kind == "stolen" then
			if Steal.shouldEscape(carry.timer, now, world.rng:float()) then
				local timedOut = carry.timer.escapeAt ~= nil and now >= carry.timer.escapeAt
				StealService.escape(world, session, now, if timedOut then "timeout" else "wriggle")
			else
				World.markDirty(session) -- walkSpeed ramps up while held
			end
		end
	end
end

-- True when some other player has a slime on a pad (a possible Steal target).
local function hasStealTarget(world: World, session: Session): boolean
	for userId, other in world.sessions do
		if userId ~= session.userId then
			for _, slime in other.data.slimes do
				if slime.pad ~= nil then
					return true
				end
			end
		end
	end
	return false
end

-- Call once per second: a player on the tutorial's Steal step with nobody to steal from
-- (solo server, or empty plots) gets the step skipped after TUTORIAL_STEAL_SKIP_SECONDS.
function StealService.tickTutorial(world: World, now: number)
	for _, session in world.sessions do
		if TutorialProgress.currentId(session.data) ~= "Steal" or hasStealTarget(world, session) then
			session.stealWaitSince = nil
		elseif not session.stealWaitSince then
			session.stealWaitSince = now
		elseif now - session.stealWaitSince >= Config.TUTORIAL_STEAL_SKIP_SECONDS then
			session.stealWaitSince = nil
			World.notify(world, session.userId, "Nobody to steal from here, so Steal is skipped.", "good", nil)
			World.tutorial(world, session, "Steal")
		end
	end
end

-- Call every frame: finishes escape bounces and pushes State on lock expiry.
function StealService.step(world: World, now: number)
	Revenge.prune(world, now)
	for id, untilTime in world.escaping do
		if now >= untilTime then
			world.escaping[id] = nil
			local owner = World.ownerOf(world, id)
			World.markDirty(owner)
		end
	end
	for _, session in world.sessions do
		local locked = StealService.isLocked(session, now)
		if locked ~= session.locked then
			session.locked = locked
			World.markDirty(session)
			if not locked then
				World.notify(world, session.userId, "Your base is unlocked!", "bad", "Unlock", "Lock")
			end
		end
	end
end

return StealService
