--!strict
--[[
	Carry (pure)

	Picking slimes up (the ProximityPrompt on each slime's Body calls `grab`),
	carrying one at a time, depositing on your own plot (`deposit`, called
	when the carrier enters their HomeZone) and dropping.

	* Wild slime: free or costs its price, charged on grab. Dropped -> it
	  lands where the carrier stood and its lifetime restarts.
	* Pad slime of another player: StealService.steal. Dropped -> escapes home.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local FountainTiers = if Shared then require(Shared.FountainTiers) else require("../shared/FountainTiers")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local SlimeRoster = if Shared then require(Shared.SlimeRoster) else require("../shared/SlimeRoster")
local Perks = if Shared then require(Shared.Perks) else require("../shared/Perks")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Shop = if Shared then require(Shared.Shop) else require("../shared/Shop")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local Revenge = if script then require(script.Parent.Revenge) else require("./Revenge")
local StealAlert = if Shared then require(Shared.StealAlert) else require("../shared/StealAlert")
local StealService = if script then require(script.Parent.StealService) else require("./StealService")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local Carry = {}

-- Prompt ActionText for a slime as seen by a non-owner.
function Carry.actionText(price: number?): string
	if price == nil then
		return "Steal"
	end
	if price <= 0 then
		return "Grab"
	end
	return `Buy ${Economy.formatNumber(price)}`
end

-- Hold needed on a slime prompt: only a free grab of a wild slime is instant
-- (costs nothing, takes nothing from anyone); buying or stealing needs a hold.
function Carry.holdDuration(price: number?): number
	if price ~= nil and price <= 0 then
		return 0
	end
	return Config.HOLD_CONFIRM_SECONDS
end

-- FEATURES.FountainTiers: failure text when a player of `rebirths` can't catch this wild slime because its
-- family is not open to their rank yet, else nil. `enabled` (tests) overrides the flag.
function Carry.familyBlock(rebirths: number, slime: Genome.Slime, enabled: boolean?): string?
	if not (if enabled == nil then Config.FEATURES.FountainTiers else enabled) then
		return nil
	end
	local species = slime.species
	local entry = if species then SlimeRoster.get(species) else nil
	return if entry then FountainTiers.catchBlock(rebirths, entry.family) else nil
end

function Carry.grabWild(
	world: World,
	session: Session,
	slimeId: string,
	distance: number,
	now: number
): (boolean, string?)
	local wild = world.wild[slimeId]
	if not wild then
		return false, "slime is gone"
	end
	if session.carry then
		return false, "already carrying a slime"
	end
	if world.carriedBy[slimeId] then
		return false, "someone is already carrying it"
	end
	if distance ~= distance or distance > Config.STEAL_REACH then
		return false, "too far away"
	end
	-- Checked before the price is charged, so a refused grab costs nothing.
	local block = Carry.familyBlock(session.data.rebirths, wild.slime)
	if block then
		return false, block
	end
	if wild.price > 0 and not PlayerData.spend(session.data, wild.price) then
		return false, `need ${Economy.formatNumber(wild.price)}`
	end
	wild.price = 0 -- paid for: dropping it doesn't charge the next grabber
	session.carry = {
		slimeId = slimeId,
		kind = "wild",
		ownerUserId = nil,
		timer = Steal.newCarry("wild", wild.slime.tier, now),
		slime = wild.slime,
	}
	world.carriedBy[slimeId] = session.userId
	World.markDirty(session)
	World.tutorial(world, session, "Grab")
	return true, nil
end

-- ProximityPrompt entry point: wild slimes are grabbed, pad slimes stolen.
function Carry.grab(world: World, userId: number, slimeId: string, distance: number, now: number): (boolean, string?)
	local session = World.session(world, userId)
	if not session then
		return false, "still loading"
	end
	if world.wild[slimeId] then
		return Carry.grabWild(world, session, slimeId, distance, now)
	end
	return StealService.steal(world, session, slimeId, distance, now)
end

--[[
	The carrier reached their own HomeZone. Wild slimes go on a free pad;
	stolen ones move to the thief with Steal.complete (and, given `now`, open the
	victim's Revenge window). A full plot keeps the
	slime in your arms (and the escape timer keeps running).
]]
function Carry.deposit(world: World, userId: number, now: number?): (boolean, string?)
	local session = World.session(world, userId)
	local carry = session and session.carry
	if not session or not carry then
		return false, "not carrying"
	end
	local name = Genome.displayName(carry.slime)
	if carry.kind == "wild" then
		if not PlayerData.freePad(session.data) then
			return false, "plot full"
		end
		local wasBoss = world.wild[carry.slimeId] and world.wild[carry.slimeId].boss
		world.wild[carry.slimeId] = nil
		world.carriedBy[carry.slimeId] = nil
		session.carry = nil
		if wasBoss then
			World.notify(world, nil, `{session.name} caught the Boss Slime!`, "info", nil)
		end
		local slime = carry.slime
		slime.pad = nil
		-- Lucky Charm (Perks.luckChance): one rarity higher on the way home.
		if slime.tier < Config.MAX_TIER and world.rng:float() < Perks.luckChance(session.data) then
			local old = Genome.rarity(slime.tier).name
			slime.tier += 1
			World.notify(
				world,
				userId,
				`Lucky! Your {old} slime became {Genome.rarity(slime.tier).name}!`,
				"good",
				"Cash"
			)
			name = Genome.displayName(slime)
		end
		PlayerData.addSlime(session.data, slime)
		session.data.stats.caught += 1
		World.markDirty(session)
		World.notify(world, userId, `{name} joined your plot!`, "good", "Deposit")
		World.effect(world, "Collect", { userId = userId })
		World.tutorial(world, session, "Deposit")
		return true, nil
	end

	local owner = if carry.ownerUserId then World.session(world, carry.ownerUserId) else nil
	if not owner then
		session.carry = nil
		world.carriedBy[carry.slimeId] = nil
		World.markDirty(session)
		return false, "slime is gone"
	end
	local ok, result = Steal.complete(owner.data, session.data, carry.slimeId)
	if not ok then
		return false, result :: string
	end
	session.carry = nil
	world.carriedBy[carry.slimeId] = nil
	World.markDirty(session)
	World.markDirty(owner)
	if Config.FEATURES.StealAlerts then
		StealAlert.record(owner.data.stealLog, session.name, name, os.time())
	end
	World.notify(world, userId, `You stole a {name}!`, "good", "Stolen")
	World.notify(world, owner.userId, `{session.name} stole your {name}!`, "bad", "Stolen")
	if now then
		Revenge.mark(world, owner.userId, userId, now) -- FEATURES.Revenge: the victim's window opens
	end
	World.effect(world, "Collect", { userId = userId })
	World.tutorial(world, session, "Deposit")
	return true, nil
end

--[[
	Ends any carry. Wild -> lands at `position` (opaque, adapter-defined) with
	a fresh lifetime; stolen -> escapes home. `reason` is passed to
	StealService.escape ("drop", "left", ...).
]]
function Carry.release(world: World, userId: number, now: number, position: any?, reason: string): boolean
	local session = World.session(world, userId)
	local carry = session and session.carry
	if not session or not carry then
		return false
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
		-- A dropped Boss Slime keeps the boss lifetime (DespawnTelegraph warns before either).
		wild.expiresAt = now + (if wild.boss then Config.BOSS_LIFETIME else Config.WILD_LIFETIME)
	end
	World.markDirty(session)
	return true
end

-- Ends carries of a slime that no longer exists (sold, merged, wiped).
function Carry.cancelMissing(world: World)
	for slimeId, carrierId in world.carriedBy do
		local carrier = World.session(world, carrierId)
		local carry = carrier and carrier.carry
		local exists = world.wild[slimeId] ~= nil or World.ownerOf(world, slimeId) ~= nil
		if not exists or not carry or carry.slimeId ~= slimeId then
			world.carriedBy[slimeId] = nil
			if carrier and carry and carry.slimeId == slimeId then
				carrier.carry = nil
				World.markDirty(carrier)
			end
		end
	end
end

-- Value of the Player attribute `Carrying` (CONTRACT.md §5.2): the carried slime id, or nil.
function Carry.carryingId(world: World, userId: number): string?
	local session = World.session(world, userId)
	local carry = session and session.carry
	return carry and carry.slimeId
end

-- WalkSpeed while carrying: the carry slowdown applies to the player's own base speed,
-- so the Speed Coil helps while carrying too (CONTRACT.md §8.10).
-- Strong Arms (Perks.carrySlowFactor) shrinks the slowdown.
function Carry.walkSpeed(session: Session, now: number): number
	local carry = session.carry
	local base = Shop.walkSpeed(session.data)
	if not carry then
		return base
	end
	return base * (1 - Steal.carrySlow(carry.timer, now) * Perks.carrySlowFactor(session.data))
end

-- The WalkSpeed the server enforces right now (Player attribute TargetWalkSpeed).
function Carry.targetWalkSpeed(session: Session, now: number): number
	if session.carry then
		return Carry.walkSpeed(session, now)
	end
	return Shop.walkSpeed(session.data)
end

return Carry
