--!strict
--[[
	Steal

	Pure rules for base locks, stealing, carrying, wriggling free and slapping.

	* Lock: every plot is locked for JOIN_LOCK_SECONDS after joining. The plot's
	  lock button buys LOCK_SECONDS (+LOCK_SECONDS_PER_REBIRTH per rebirth) more,
	  stacking on top of any remaining lock. Neither one purchase nor the stack
	  goes past LOCK_MAX_REMAINING.
	* Steal: a slime on an unlocked plot can be grabbed by anyone else within
	  STEAL_REACH who isn't already carrying something.
	* Carry: carrying slows you by the rarity's carrySlow. There is no time
	  limit: a stolen slime stays in your arms until you reach home, drop it,
	  get slapped, die or leave.
	* Slap: hitting anyone carrying a slime within SLAP_REACH makes them
	  drop it; a stolen one bounces home.
	No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")

type Slime = Genome.Slime

export type CarryKind = "wild" | "stolen"
export type Carry = {
	kind: CarryKind,
	tier: number,
	startedAt: number,
}

export type StealContext = {
	thiefId: number,
	ownerId: number,
	now: number,
	lockUntil: number,
	thiefCarrying: boolean,
	slimeBusy: boolean, -- already being carried by someone
	distance: number,
}

export type SlapContext = {
	now: number,
	lastSlapAt: number,
	distance: number,
	slapperId: number,
	targetId: number,
	targetCarry: Carry?,
}

local Steal = {}

---------------------------------------------------------------------------
-- Lock
---------------------------------------------------------------------------

-- Seconds one bought lock adds: base + per rebirth, never more than LOCK_MAX_REMAINING.
function Steal.lockDuration(rebirths: number): number
	local r = math.max(0, math.floor(tonumber(rebirths) or 0))
	return math.min(Config.LOCK_SECONDS + r * Config.LOCK_SECONDS_PER_REBIRTH, Config.LOCK_MAX_REMAINING)
end

function Steal.joinLockUntil(now: number): number
	return now + Config.JOIN_LOCK_SECONDS
end

function Steal.isLocked(lockUntil: number, now: number): boolean
	return now < lockUntil
end

function Steal.lockRemaining(lockUntil: number, now: number): number
	return math.max(0, lockUntil - now)
end

--[[
	Buys / extends the plot lock. Charges Economy.lockCost(income).
	Returns (ok, newLockUntil, costOrReason).
]]
function Steal.buyLock(
	data: PlayerData.Data,
	lockUntil: number,
	now: number,
	incomePerSec: number
): (boolean, number, number | string)
	local remaining = Steal.lockRemaining(lockUntil, now)
	if remaining >= Config.LOCK_MAX_REMAINING - 1 then
		return false, lockUntil, "lock is already at max"
	end
	local cost = Economy.lockCost(incomePerSec)
	if not PlayerData.spend(data, cost) then
		return false, lockUntil, "not enough cash"
	end
	local newRemaining = math.min(remaining + Steal.lockDuration(data.rebirths), Config.LOCK_MAX_REMAINING)
	return true, now + newRemaining, cost
end

---------------------------------------------------------------------------
-- Stealing
---------------------------------------------------------------------------

function Steal.canSteal(ctx: StealContext): (boolean, string?)
	if ctx.thiefId == ctx.ownerId then
		return false, "that's your own slime"
	end
	if Steal.isLocked(ctx.lockUntil, ctx.now) then
		return false, "base is locked"
	end
	if ctx.thiefCarrying then
		return false, "already carrying a slime"
	end
	if ctx.slimeBusy then
		return false, "someone is already carrying it"
	end
	if ctx.distance ~= ctx.distance or ctx.distance > Config.STEAL_REACH then
		return false, "too far away"
	end
	return true, nil
end

function Steal.newCarry(kind: CarryKind, tier: number, now: number): Carry
	return {
		kind = kind,
		tier = tier,
		startedAt = now,
	}
end

function Steal.carrySlow(carry: Carry): number
	return math.min(Genome.rarity(carry.tier).carrySlow, Config.MAX_CARRY_SLOW)
end

function Steal.walkSpeed(carry: Carry?, baseSpeed: number?): number
	local base = baseSpeed or Config.BASE_WALK_SPEED
	if not carry then
		return base
	end
	return base * (1 - Steal.carrySlow(carry))
end

function Steal.canSlap(ctx: SlapContext): (boolean, string?)
	if ctx.slapperId == ctx.targetId then
		return false, "can't slap yourself"
	end
	if ctx.now - ctx.lastSlapAt < Config.SLAP_COOLDOWN then
		return false, "slap on cooldown"
	end
	if ctx.distance ~= ctx.distance or ctx.distance > Config.SLAP_REACH then
		return false, "too far away"
	end
	if not ctx.targetCarry then
		return false, "target isn't carrying a slime"
	end
	return true, nil
end

--[[
	The thief got home: move the slime from the victim's plot to a free pad
	on the thief's plot. Returns (ok, slimeOrReason). Fails without changing
	anything if the thief's plot is full.
]]
function Steal.complete(victim: PlayerData.Data, thief: PlayerData.Data, slimeId: string): (boolean, Slime | string)
	local slime = PlayerData.findSlime(victim, slimeId)
	if not slime then
		return false, "slime is gone"
	end
	if not PlayerData.freePad(thief) then
		return false, "plot full"
	end
	PlayerData.removeSlime(victim, slimeId)
	slime.pad = nil
	slime.keep = nil -- a kept mark belongs to the previous owner
	PlayerData.addSlime(thief, slime)
	thief.totalStolen += 1
	return true, slime
end

return Steal
