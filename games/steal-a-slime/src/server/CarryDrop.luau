--!strict
--[[
	CarryDrop (pure)

	Ending a carry without a deposit, and the rule that a hit makes the carrier drop whatever they hold.

	* release: ends any carry. Wild -> lands at `position`; a wild egg smashes there; the hauled boss lies on the
	  spot; stolen -> escapes home.
	* knockLoose: the carrier was hit (Bat, PvP item). Same as release, with the "you got bonked" toasts.
	* slap: a Bat hit on a carrier (reach SLAP_REACH, the slap cooldown), then knockLoose.

	Carry.release is this module's release; PvpService.hitCarrier calls knockLoose (Carry itself can't be required
	from the PvP modules: Carry requires PvpFun).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local BossFight = if Shared then require(Shared.BossFight) else require("../shared/BossFight")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Fountain = if Shared then require(Shared.Fountain) else require("../shared/Fountain")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local ParadeLane = if Shared then require(Shared.ParadeLane) else require("../shared/ParadeLane")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local StealService = if script then require(script.Parent.StealService) else require("./StealService")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local CarryDrop = {}

-- World x / z of an adapter-defined drop position, when it has them (a Vector3 does; test stand-ins may not).
local function spotOf(position: any?): (number?, number?)
	if position == nil or type(position) == "string" then
		return nil, nil
	end
	local x, z = position.X, position.Z
	if type(x) == "number" and type(z) == "number" then
		return x, z
	end
	return nil, nil
end

--[[
	Ends any carry. Wild -> lands at `position` (opaque, adapter-defined; a
	Vector3 in the server). A position with numeric X / Z walks back to the
	parade lane (FEATURES.Parade); any other rests there with a fresh
	lifetime. A wild Mystery Egg smashes instead: it lies there for
	MYSTERY_EGG.SMASH_SECONDS (contract/mystery-egg.md 40.7), then goes.
	Stolen -> escapes home. `reason` is passed to
	StealService.escape ("drop", "left", "slap", ...).
]]
function CarryDrop.release(world: World, userId: number, now: number, position: any?, reason: string): boolean
	local session = World.session(world, userId)
	local carry = session and session.carry
	if not session or not carry then
		return false
	end
	if reason == "drop" or reason == "slap" then
		session.lastDropAt = now -- no pickups for Config.DROP_PICKUP_COOLDOWN (Carry.grab)
	end
	if carry.kind == "stolen" then
		StealService.escape(world, session, now, reason)
		return true
	end
	session.carry = nil
	world.carriedBy[carry.slimeId] = nil
	local wild = world.wild[carry.slimeId]
	if wild then
		wild.position = position
		if wild.boss then
			-- The hauled boss lies on the spot; the haul deadline (expiresAt) stays.
			if world.boss then
				BossFight.drop(world.boss.fight)
			end
			World.markAllDirty(world)
		elseif wild.slime.egg then
			wild.smashedAt = now
			wild.returning = nil
			wild.choreo = nil
			wild.expiresAt = now + Config.MYSTERY_EGG.SMASH_SECONDS
		else
			local lifetime = Fountain.wildLifetime(wild.slime)
			local x, z = spotOf(position)
			local plan = if ParadeLane.enabled()
					and x
					and z
				then ParadeLane.returnPlan(x, z, ParadeLane.wildLateral(wild.radius), lifetime, now)
				else nil
			if plan then
				wild.returning = plan
				wild.spawnedAt, wild.expiresAt = ParadeLane.rejoin(plan.s, lifetime, plan.arriveAt)
			else
				wild.expiresAt = now + lifetime
			end
		end
	end
	World.markDirty(session)
	return true
end

--[[
	`victim` was hit while carrying: whatever they hold drops. A stolen slime bounces home (StealService.escape
	"slap": its own toasts and the SlapHitAt FX); a wild slime or the boss lands at `position` (the victim's spot,
	nil = its landing) and the victim is told. Returns the dropped slime's id, nil when they carried nothing.
]]
function CarryDrop.knockLoose(world: World, victim: Session, now: number, position: any?): string?
	local carry = victim.carry
	if not carry then
		return nil
	end
	CarryDrop.release(world, victim.userId, now, position, "slap")
	if carry.kind ~= "stolen" then
		local name = if carry.boss then "boss" else Genome.displayName(carry.slime)
		local text = if carry.kind == "wild" and carry.slime.egg
			then `You got bonked! The {name} smashed.`
			else `You got bonked! You dropped the {name}.`
		World.notify(world, victim.userId, text, "bad", "Slap", "Slap")
	end
	return carry.slimeId
end

--[[
	A Bat slap by `slapper` on `targetUserId` (Steal.canSlap: reach, the slap cooldown, the target carries a slime):
	the target drops it (knockLoose at `position`). Returns (ok, reason).
]]
function CarryDrop.slap(
	world: World,
	slapper: Session,
	targetUserId: number,
	distance: number,
	now: number,
	position: any?
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
	if not ok or not target or not carry then
		return false, reason or "no such player"
	end
	slapper.lastSlapAt = now
	CarryDrop.knockLoose(world, target, now, position)
	World.notify(world, slapper.userId, `You bonked {target.name} with your bat!`, "good", "Slap", "Slap")
	if carry.kind == "stolen" then
		World.tutorial(world, slapper, "Steal")
	end
	return true, nil
end

return CarryDrop
