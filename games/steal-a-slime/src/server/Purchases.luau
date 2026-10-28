--!strict
--[[
	Purchases (pure, contract/exclusive-shop.md §3)

	What a Robux purchase gives, by its Config.EXCLUSIVE_SHOP.products key and `grant.kind`:
	  * seat: the Exclusive pet seat joins `data.ownedSeats`.
	  * bundle (StarterBundle): its seats, plus its income boost into the capped code boost (Codes.addBoost);
	    `data.starterBundle` marks it claimed.
	  * finishBrew: a running brew ends now (VatState.finishNow; the roll was fixed at Start), else one brew credit.
	  * hatchNow (HatchNow_<eggKind>): the player's incubating egg of that kind closest to ready on a pad is ready now
	    (`hatchAt = now`; the hatch roll was fixed when it started), else one hatch credit.
	  * doubleOffline: pays the last welcome-back payout (`data.offlineDouble.cash`) once more; nothing to pay grants 0.
	  * serverPotion: extends the server-wide Luck Potion (Consumables.extendPotion) and tells everyone who gave it.
	`useCredit` spends a saved credit (Request UseCredit), `applyPasses` sets the runtime Game Pass factors
	(`data.passIncomeMult`, `data.passOfflineRate`) and `view` builds State.exclusiveShop. Receipts, saving and the
	MarketplaceService callbacks live in PurchaseService. Never errors; no Roblox APIs.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Codes = if Shared then require(Shared.Codes) else require("../shared/Codes")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Consumables = if Shared then require(Shared.Consumables) else require("../shared/Consumables")
local EggKind = if Shared then require(Shared.EggKind) else require("../shared/EggKind")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local ExclusiveRotation = if Shared then require(Shared.ExclusiveRotation) else require("../shared/ExclusiveRotation")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local PetSeats = if Shared then require(Shared.PetSeats) else require("../shared/PetSeats")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")
local VatState = if Shared then require(Shared.VatState) else require("../shared/VatState")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

-- `features`: Config.FEATURES overrides by flag name (tests), like Actions.Context.
export type Context = { features: { [string]: boolean }? }

local Purchases = {}

local SHOP = Config.EXCLUSIVE_SHOP

local function enabled(ctx: Context?): boolean
	local override = if ctx and ctx.features then ctx.features.ExclusiveShop else nil
	if override ~= nil then
		return override
	end
	return Config.FEATURES.ExclusiveShop == true
end
Purchases.enabled = enabled

-- The catalogue entry of a product key, or nil.
function Purchases.product(productKey: string): { [string]: any }?
	return SHOP.products[productKey]
end

-- The product key whose Roblox productId is `productId` (never matches 0 = not created yet).
function Purchases.keyForProductId(productId: number): string?
	if type(productId) ~= "number" or productId == 0 then
		return nil
	end
	for key, def in SHOP.products do
		if def.productId == productId then
			return key
		end
	end
	return nil
end

-- The pass key whose Roblox passId is `passId` (never matches 0).
function Purchases.keyForPassId(passId: number): string?
	if type(passId) ~= "number" or passId == 0 then
		return nil
	end
	for key, def in SHOP.passes do
		if def.passId == passId then
			return key
		end
	end
	return nil
end

local function addSeat(data: PlayerData.Data, seatId: string): boolean
	local seat = PetSeats.get(seatId)
	if not seat or seat.unlock.kind ~= "exclusive" or table.find(data.ownedSeats, seat.id) then
		return false
	end
	table.insert(data.ownedSeats, seat.id)
	return true
end

local function addCredit(data: PlayerData.Data, kind: "brew" | "hatch")
	data.credits[kind] = math.min(data.credits[kind] + 1, SHOP.creditMax)
end

-- The player's incubating, not yet ready pad egg (of `kindId` when given) closest to ready, skipping eggs being
-- carried off.
function Purchases.nextEgg(world: World, session: Session, now: number, kindId: string?): Genome.Slime?
	local best: Genome.Slime? = nil
	for _, slime in session.data.slimes do
		local egg = slime.egg
		local hatchAt = egg and egg.hatchAt
		if
			egg
			and hatchAt
			and hatchAt > now
			and slime.pad ~= nil
			and (kindId == nil or egg.kind == kindId)
			and not World.isBusy(world, slime.id)
		then
			if best == nil or hatchAt < ((best.egg :: EggKind.Egg).hatchAt :: number) then
				best = slime
			end
		end
	end
	return best
end

local function incubating(world: World, session: Session, slimeId: string?, now: number, kindId: string?): Genome.Slime?
	if slimeId == nil then
		return nil
	end
	for _, slime in session.data.slimes do
		if slime.id == slimeId then
			local egg = slime.egg
			local hatchAt = egg and egg.hatchAt
			if
				egg
				and hatchAt
				and hatchAt > now
				and slime.pad ~= nil
				and (kindId == nil or egg.kind == kindId)
				and not World.isBusy(world, slime.id)
			then
				return slime
			end
			return nil
		end
	end
	return nil
end

-- AimHatch: remembers which incubating pad egg the next HatchNow receipt is for. Returns (ok, reason).
function Purchases.aimHatch(world: World, session: Session, slimeId: string, now: number): (boolean, string?)
	if incubating(world, session, slimeId, now, nil) == nil then
		return false, "that is not an incubating egg on your pads"
	end
	session.hatchTarget = slimeId
	return true, nil
end

local function seatName(seatId: string): string
	local seat = PetSeats.get(seatId)
	return if seat then seat.name else seatId
end

local function hatchReady(world: World, session: Session, egg: Genome.Slime, now: number)
	local record = egg.egg :: EggKind.Egg
	record.hatchAt = now
	World.markDirty(session)
	local kind = EggKind.of(egg)
	local name = if kind then EggKind.displayName(kind) else "egg"
	World.notify(world, session.userId, `Your {name} is ready to hatch!`, "good", "EggReady", "MysteryEgg")
end

--[[
	Applies one purchase of `productKey` to `session`. Returns (ok, reason): false only for an unknown product or the
	shop being off, and then nothing changed. A purchase with nothing to apply right now (a seat already owned, no
	brew running) still succeeds: it gives what the rules say (a credit, nothing) so the receipt can be closed.
]]
function Purchases.grant(
	world: World,
	session: Session,
	productKey: string,
	now: number,
	ctx: Context?
): (boolean, string?)
	if not enabled(ctx) then
		return false, "the Exclusive Shop is off"
	end
	local def = Purchases.product(productKey)
	if not def then
		return false, "unknown product"
	end
	local data = session.data
	local grant = def.grant
	local userId = session.userId
	local kind = grant.kind
	if kind == "seat" then
		addSeat(data, grant.seat)
		World.notify(world, userId, `{seatName(grant.seat)} is yours! Pick it in Skins.`, "good", "Gift")
	elseif kind == "bundle" then
		for _, seatId in grant.seats do
			addSeat(data, seatId)
		end
		Codes.addBoost(data, grant.boostMult, grant.boostSeconds / 60, now)
		data.starterBundle = true
		World.notify(
			world,
			userId,
			`Starter Bundle: {grant.boostMult}x income for {math.floor(grant.boostSeconds / 60)} min!`,
			"good",
			"Gift"
		)
	elseif kind == "finishBrew" then
		if VatState.isBrewing(data) and not VatState.isReady(data, now) then
			VatState.finishNow(data, now)
			World.notify(world, userId, "Your brew is done! Collect it at the vat.", "good", "Merge")
		else
			addCredit(data, "brew")
			World.notify(world, userId, "No brew running: saved as a brew credit.", "info", nil)
		end
	elseif kind == "hatchNow" then
		local kindId = string.match(productKey, "^HatchNow_(.+)$")
		-- The aimed egg when it still fits the paid kind, else that kind's egg closest to ready.
		local egg = incubating(world, session, session.hatchTarget, now, kindId)
			or Purchases.nextEgg(world, session, now, kindId)
		session.hatchTarget = nil
		if egg then
			hatchReady(world, session, egg, now)
		else
			addCredit(data, "hatch")
			World.notify(world, userId, "No egg to hatch: saved as a hatch credit.", "info", nil)
		end
	elseif kind == "doubleOffline" then
		local record = data.offlineDouble
		if record and not record.used then
			record.used = true
			PlayerData.earn(data, record.cash)
			World.notify(
				world,
				userId,
				`Doubled! +${Economy.formatNumber(record.cash)} from your time away.`,
				"good",
				"Cash"
			)
		end
	elseif kind == "serverPotion" then
		world.potionUntil = Consumables.extendPotion(world.potionUntil, now)
		World.notify(world, nil, `{session.name} gave the server a Luck Potion!`, "good", nil)
		World.markAllDirty(world)
	else
		return false, "unknown product"
	end
	World.markDirty(session)
	return true, nil
end

--[[
	Spends one saved credit (Request UseCredit): "brew" ends the running brew now; "hatch" makes the owned incubating
	pad egg `slimeId` (nil = the one closest to ready) ready now. Returns (ok, player-facing reason).
]]
function Purchases.useCredit(
	world: World,
	session: Session,
	kind: string,
	slimeId: string?,
	now: number
): (boolean, string?)
	local data = session.data
	if kind == "brew" then
		if data.credits.brew < 1 then
			return false, "no brew credits"
		end
		if not VatState.isBrewing(data) or VatState.isReady(data, now) then
			return false, "no brew to finish"
		end
		VatState.finishNow(data, now)
		data.credits.brew -= 1
		World.notify(world, session.userId, "Your brew is done! Collect it at the vat.", "good", "Merge")
		return true, nil
	elseif kind == "hatch" then
		if data.credits.hatch < 1 then
			return false, "no hatch credits"
		end
		local egg: Genome.Slime? = nil
		if slimeId then
			local slime = PlayerData.findSlime(data, slimeId)
			local hatchAt = slime and slime.egg and slime.egg.hatchAt
			if slime and hatchAt and hatchAt > now and slime.pad ~= nil and not World.isBusy(world, slime.id) then
				egg = slime
			end
		else
			egg = Purchases.nextEgg(world, session, now, nil)
		end
		if not egg then
			return false, "no egg to hatch"
		end
		hatchReady(world, session, egg, now)
		data.credits.hatch -= 1
		return true, nil
	end
	return false, "unknown credit"
end

--[[
	Sets the runtime Game Pass factors from `passes` (pass key -> owned): Income2x into Perks.bonusMultiplier,
	Offline2x as the offline rate. When the offline rate goes up after this join's payout was made (pass checks
	finish after the join), the difference is paid now. Returns that top-up (0 when none).
]]
function Purchases.applyPasses(session: Session, passes: { [string]: boolean }): number
	local data = session.data
	local owned: { [string]: boolean } = {}
	for key in SHOP.passes do
		owned[key] = passes[key] == true
	end
	session.passes = owned
	data.passIncomeMult = if owned.Income2x then SHOP.passes.Income2x.incomeMult else nil
	data.passOfflineRate = if owned.Offline2x then SHOP.passes.Offline2x.offlineRate else nil
	World.markDirty(session)
	local paidRate, paid = session.offlineRate, session.offlinePaid or 0
	local rate = math.max(data.passOfflineRate or 0, Config.OFFLINE_RATE)
	if not paidRate or rate <= paidRate or paid <= 0 then
		return 0
	end
	local extra = math.floor(paid * rate / paidRate) - paid
	session.offlineRate, session.offlinePaid = rate, paid + math.max(extra, 0)
	if extra <= 0 then
		return 0
	end
	PlayerData.earn(data, extra)
	local record, welcome = data.offlineDouble, session.welcome
	if record and not record.used then
		record.cash += extra -- this join's payout (Income.applyOffline records every one that paid)
	end
	if welcome then
		welcome.cash += extra
	end
	return extra
end

-- State.exclusiveShop for this session (the caller decides whether the flag is on).
function Purchases.view(session: Session, now: number): Types.ExclusiveShopView
	local data = session.data
	local owned: { [string]: boolean } = {}
	for _, id in data.ownedSeats do
		owned[id] = true
	end
	local passes: { [string]: boolean } = {}
	for key in SHOP.passes do
		passes[key] = session.passes ~= nil and session.passes[key] == true
	end
	local record = data.offlineDouble
	return {
		owned = owned,
		passes = passes,
		starterClaimed = data.starterBundle == true,
		credits = { brew = data.credits.brew, hatch = data.credits.hatch },
		offlineDouble = if record then { cash = record.cash, available = not record.used } else nil,
		paidRandomAllowed = session.paidRandomAllowed == true,
		featured = ExclusiveRotation.featured(ExclusiveRotation.week(now)),
	}
end

return table.freeze(Purchases)
