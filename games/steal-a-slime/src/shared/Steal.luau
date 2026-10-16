--!strict
--[[
	Steal

	Pure rules for base locks, stealing, carrying, wriggling free and slapping.

	* Lock: every plot is locked for JOIN_LOCK_SECONDS after joining. The lock
	  button buys LOCK_SECONDS (+LOCK_SECONDS_PER_REBIRTH per rebirth) more,
	  stacking on top of any remaining lock but never past LOCK_MAX_REMAINING.
	* Steal: a slime on an unlocked plot can be grabbed by anyone else within
	  STEAL_REACH who isn't already carrying something.
	* Carry: carrying slows you by the rarity's carrySlow. A stolen slime adds
	  up to STOLEN_EXTRA_SLOW as its escape timer runs down, and each second has
	  a growing chance (up to WRIGGLE_MAX_CHANCE) to wriggle free. At escapeAt it
	  escapes for sure and bounces home.
	* Slap: hitting a carrier of a stolen slime within SLAP_REACH makes them
	  drop it, and it bounces home.
	No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local Perks = if script then require(script.Parent.Perks) else require("./Perks")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")

type Slime = Genome.Slime

export type CarryKind = "wild" | "stolen"
export type Carry = {
	kind: CarryKind,
	tier: number,
	startedAt: number,
	escapeAt: number?, -- only for stolen slimes
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

-- Seconds one lock purchase adds: base + per rebirth + per Shop lock upgrade level.
-- Seconds one bought lock adds: base + per rebirth + lock upgrade + rank bonus (Perks.lockBonus).
function Steal.lockDuration(rebirths: number, lockLevel: number?): number
	local r = math.max(0, math.floor(tonumber(rebirths) or 0))
	local l = math.clamp(math.floor(tonumber(lockLevel) or 0), 0, Config.LOCK_UPGRADE_MAX)
	return Config.LOCK_SECONDS
		+ r * Config.LOCK_SECONDS_PER_REBIRTH
		+ l * Config.LOCK_UPGRADE_SECONDS
		+ Perks.lockBonus(r)
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
	incomePerSec: number,
	costMult: number? -- FEATURES.Revenge: x2 while inside a victim's window
): (boolean, number, number | string)
	local remaining = Steal.lockRemaining(lockUntil, now)
	if remaining >= Config.LOCK_MAX_REMAINING - 1 then
		return false, lockUntil, "lock is already at max"
	end
	local cost = Economy.lockCost(incomePerSec) * (costMult or 1)
	if not PlayerData.spend(data, cost) then
		return false, lockUntil, "not enough cash"
	end
	local newRemaining =
		math.min(remaining + Steal.lockDuration(data.rebirths, data.lockLevel), Config.LOCK_MAX_REMAINING)
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

function Steal.escapeTime(tier: number): number
	return Genome.rarity(tier).escapeTime
end

function Steal.newCarry(kind: CarryKind, tier: number, now: number): Carry
	return {
		kind = kind,
		tier = tier,
		startedAt = now,
		escapeAt = if kind == "stolen" then now + Steal.escapeTime(tier) else nil,
	}
end

-- 0 at pickup, 1 when the escape timer runs out (always 0 for wild slimes).
function Steal.heldFraction(carry: Carry, now: number): number
	local escapeAt = carry.escapeAt
	if not escapeAt then
		return 0
	end
	local total = escapeAt - carry.startedAt
	if total <= 0 then
		return 1
	end
	return math.clamp((now - carry.startedAt) / total, 0, 1)
end

function Steal.carrySlow(carry: Carry, now: number): number
	local slow = Genome.rarity(carry.tier).carrySlow
	if carry.kind == "stolen" then
		slow += Config.STOLEN_EXTRA_SLOW * Steal.heldFraction(carry, now)
	end
	return math.min(slow, Config.MAX_CARRY_SLOW)
end

function Steal.walkSpeed(carry: Carry?, now: number, baseSpeed: number?): number
	local base = baseSpeed or Config.BASE_WALK_SPEED
	if not carry then
		return base
	end
	return base * (1 - Steal.carrySlow(carry, now))
end

-- Per-second chance a stolen slime wriggles free right now.
function Steal.wriggleChance(carry: Carry, now: number): number
	if carry.kind ~= "stolen" then
		return 0
	end
	local p = Steal.heldFraction(carry, now)
	return Config.WRIGGLE_MAX_CHANCE * p * p
end

-- Call once per second with a fresh roll in [0, 1).
function Steal.shouldEscape(carry: Carry, now: number, roll: number): boolean
	if carry.kind ~= "stolen" then
		return false
	end
	if carry.escapeAt and now >= carry.escapeAt then
		return true
	end
	return roll < Steal.wriggleChance(carry, now)
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
	if not ctx.targetCarry or ctx.targetCarry.kind ~= "stolen" then
		return false, "target isn't carrying a stolen slime"
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
	PlayerData.addSlime(thief, slime)
	thief.totalStolen += 1
	return true, slime
end

return Steal
