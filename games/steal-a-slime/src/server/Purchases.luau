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
	  * trail / batSkin (Trail_<id>, BatSkin_<id>): the carry trail / Bat skin joins `data.ownedTrails` /
	    `data.ownedBatSkins` (worn with EquipTrail / EquipBatSkin).
	  * lockBreak: opens the locked base aimed with AimLockBreak for the buyer (LockBreak.open), else one
	    `data.lockBreakCredits` (spent with UseCredit "lockBreak").
	  * gift (Gift_<item>): gives the cosmetic `item` to the player aimed with AimGift and writes their save now
	    (`ctx.save`). A target who left, already owns it or whose save failed leaves the buyer a `data.giftCredits`
	    entry instead (sent later with SendGift). The item is never lost: with no room for a credit the grant is
	    refused and Roblox asks again later.
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
local LockBreak = if script then require(script.Parent.LockBreak) else require("./LockBreak")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

-- `features`: Config.FEATURES overrides by flag name (tests), like Actions.Context. `save`: writes another player's
-- session data now (the session-locked Persistence save; yields), true = written; nil = can't (a gift becomes a credit).
export type Context = {
	features: { [string]: boolean }?,
	save: ((userId: number, data: any) -> boolean)?,
}

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

local function hatchReady(world: World, session: Session, egg: Genome.Slime, now: number)
	local record = egg.egg :: EggKind.Egg
	record.hatchAt = now
	World.markDirty(session)
	local kind = EggKind.of(egg)
	local name = if kind then EggKind.displayName(kind) else "egg"
	World.notify(world, session.userId, `Your {name} is ready to hatch!`, "good", "EggReady", "MysteryEgg")
end

local function findDef(list: { any }, id: string): any?
	for _, def in list do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- The owned list a cosmetic product key adds to and the id it adds; nil for a key that is no cosmetic.
local function cosmetic(data: PlayerData.Data, itemKey: string): ({ string }?, string?)
	local def = Purchases.product(itemKey)
	local grant = def and def.grant
	if not grant then
		return nil, nil
	end
	if grant.kind == "seat" then
		return data.ownedSeats, grant.seat
	elseif grant.kind == "trail" then
		return data.ownedTrails, grant.trail
	elseif grant.kind == "batSkin" then
		return data.ownedBatSkins, grant.skin
	end
	return nil, nil
end

-- True when the product `itemKey` (Seat_* / Trail_* / BatSkin_*) also sells as a gift.
function Purchases.giftable(itemKey: string): boolean
	return type(itemKey) == "string" and SHOP.products["Gift_" .. itemKey] ~= nil
end

-- True when `data` already owns the cosmetic product `itemKey`.
function Purchases.owns(data: PlayerData.Data, itemKey: string): boolean
	local list, id = cosmetic(data, itemKey)
	return list ~= nil and id ~= nil and table.find(list, id) ~= nil
end

-- Adds the cosmetic product `itemKey` to `data`. Returns whether it was added (false: owned already or no cosmetic).
function Purchases.giveItem(data: PlayerData.Data, itemKey: string): boolean
	local def = Purchases.product(itemKey)
	if def and def.grant.kind == "seat" then
		return addSeat(data, def.grant.seat)
	end
	local list, id = cosmetic(data, itemKey)
	if not list or not id or table.find(list, id) then
		return false
	end
	table.insert(list, id)
	return true
end

-- Takes the cosmetic product `itemKey` back out of `data` (a gift whose save failed) and takes it off.
local function takeItem(data: PlayerData.Data, itemKey: string)
	local list, id = cosmetic(data, itemKey)
	local at = if list and id then table.find(list, id) else nil
	if list and at then
		table.remove(list, at)
	end
	if id and data.trail == id then
		data.trail = nil
	end
	if id and data.batSkin == id then
		data.batSkin = nil
	end
	if id and data.petSeat == id then
		data.petSeat = Config.PET_SEAT_DEFAULT
	end
end

local function seatName(seatId: string): string
	local seat = PetSeats.get(seatId)
	return if seat then seat.name else seatId
end

-- The player-facing name of a cosmetic product key.
function Purchases.itemName(itemKey: string): string
	local def = Purchases.product(itemKey)
	local grant = def and def.grant
	if grant and grant.kind == "seat" then
		return seatName(grant.seat)
	elseif grant and grant.kind == "trail" then
		local trail = findDef(SHOP.trails, grant.trail)
		return if trail then `the {trail.name} trail` else grant.trail
	elseif grant and grant.kind == "batSkin" then
		local skin = findDef(SHOP.batSkins, grant.skin)
		local name = if skin then skin.name else grant.skin
		return if string.find(name, "Bat", 1, true) then `the {name}` else `the {name} Bat`
	end
	return itemKey
end

-- Why `from` can't gift `itemKey` to `targetId` now; nil = they can.
local function giftRefusal(world: World, from: Session, itemKey: string, targetId: number): string?
	if not Purchases.giftable(itemKey) then
		return "that can't be gifted"
	end
	if targetId == from.userId then
		return "you can't gift yourself"
	end
	local target = world.sessions[targetId]
	if not target then
		return "that player isn't in this server"
	end
	if Purchases.owns(target.data, itemKey) then
		return "they already have it"
	end
	return nil
end

--[[
	Gives `itemKey` to `target` and writes their save now through `ctx.save`. A save that fails (or no `save`) takes
	the item back. Returns whether the target has it saved; on success tells both players.
]]
local function deliver(world: World, from: Session, target: Session, itemKey: string, ctx: Context?): boolean
	if not Purchases.giveItem(target.data, itemKey) then
		return false
	end
	local save = ctx and ctx.save
	local saved = false
	if save then
		local ok, written = pcall(save, target.userId, target.data)
		saved = ok and written == true
	end
	if not saved then
		takeItem(target.data, itemKey)
		return false
	end
	local name = Purchases.itemName(itemKey)
	World.markDirty(target)
	World.notify(world, target.userId, `{from.name} gave you {name}!`, "good", "Gift")
	World.notify(world, from.userId, `You gave {target.name} {name}!`, "good", "Gift")
	return true
end

-- AimGift: remembers who the next Gift_<itemKey> receipt is for. Returns (ok, reason).
function Purchases.aimGift(
	world: World,
	session: Session,
	itemKey: string,
	targetId: number,
	now: number
): (boolean, string?)
	local refusal = giftRefusal(world, session, itemKey, targetId)
	if refusal then
		return false, refusal
	end
	session.giftAim = { item = itemKey, targetId = targetId, at = now }
	return true, nil
end

-- SendGift: spends one unsent gift of `itemKey` on `targetId` (their save is written first). Returns (ok, reason).
function Purchases.sendGift(
	world: World,
	session: Session,
	itemKey: string,
	targetId: number,
	ctx: Context?
): (boolean, string?)
	local at = table.find(session.data.giftCredits, itemKey)
	if not at then
		return false, "you have no unsent gift of that"
	end
	local refusal = giftRefusal(world, session, itemKey, targetId)
	if refusal then
		return false, refusal
	end
	if not deliver(world, session, world.sessions[targetId], itemKey, ctx) then
		return false, "the gift couldn't be delivered, try again"
	end
	local still = table.find(session.data.giftCredits, itemKey) -- the save yielded: find it again
	if still then
		table.remove(session.data.giftCredits, still)
	end
	World.markDirty(session)
	return true, nil
end

-- EquipTrail / EquipBatSkin: wears an owned carry trail / Bat skin; "" takes it off. Returns (ok, reason).
function Purchases.equipTrail(session: Session, trailId: string): (boolean, string?)
	local data = session.data
	if trailId ~= "" and not table.find(data.ownedTrails, trailId) then
		return false, "you don't own that trail"
	end
	data.trail = if trailId == "" then nil else trailId
	World.markDirty(session)
	return true, nil
end

function Purchases.equipBatSkin(session: Session, skinId: string): (boolean, string?)
	local data = session.data
	if skinId ~= "" and not table.find(data.ownedBatSkins, skinId) then
		return false, "you don't own that Bat skin"
	end
	data.batSkin = if skinId == "" then nil else skinId
	World.markDirty(session)
	return true, nil
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
	elseif kind == "trail" or kind == "batSkin" then
		Purchases.giveItem(data, productKey)
		World.notify(world, userId, `{Purchases.itemName(productKey)} is yours! Wear it in Style.`, "good", "Gift")
	elseif kind == "lockBreak" then
		local plot = LockBreak.aimed(world, session, now)
		if not (plot and LockBreak.open(world, session, plot, now, if ctx then ctx.features else nil)) then
			if data.lockBreakCredits >= SHOP.creditMax then
				return false, "too many lock break credits"
			end
			session.lockBreakAim = nil
			data.lockBreakCredits += 1
			World.notify(world, userId, "That door can't be opened now: saved as a lock break credit.", "info", nil)
		end
	elseif kind == "gift" then
		local item = grant.item
		local aim = session.giftAim
		local target = if aim
				and aim.item == item
				and now - aim.at <= SHOP.gift.aimSeconds
				and giftRefusal(world, session, item, aim.targetId) == nil
			then world.sessions[aim.targetId]
			else nil
		if not (target and deliver(world, session, target, item, ctx)) then
			if #data.giftCredits >= SHOP.gift.creditMax then
				return false, "too many unsent gifts"
			end
			table.insert(data.giftCredits, item)
			World.notify(world, userId, `Saved {Purchases.itemName(item)} as a gift to send later.`, "info", "Gift")
		end
		session.giftAim = nil
	else
		return false, "unknown product"
	end
	World.markDirty(session)
	return true, nil
end

--[[
	Spends one saved credit (Request UseCredit): "brew" ends the running brew now; "hatch" makes the owned incubating
	pad egg `target` (a slime id; nil = the one closest to ready) ready now; "lockBreak" opens plot `target`'s locked
	door for the player (a plot index, number or numeric string; LockBreak.open). Returns (ok, player-facing reason).
]]
function Purchases.useCredit(
	world: World,
	session: Session,
	kind: string,
	target: (string | number)?,
	now: number,
	ctx: Context?
): (boolean, string?)
	local data = session.data
	local slimeId = if type(target) == "string" then target else nil
	if kind == "lockBreak" then
		if data.lockBreakCredits < 1 then
			return false, "no lock break credits"
		end
		local plot = tonumber(target)
		if not plot then
			return false, "pick a locked base"
		end
		local ok, reason = LockBreak.open(world, session, plot, now, if ctx then ctx.features else nil)
		if not ok then
			return false, reason
		end
		data.lockBreakCredits -= 1
		return true, nil
	elseif kind == "brew" then
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

-- The carry trail and Bat skin `session` wears now: both nil while the shop is off.
function Purchases.worn(session: Session, ctx: Context?): (string?, string?)
	if not enabled(ctx) then
		return nil, nil
	end
	return session.data.trail, session.data.batSkin
end

local function set(ids: { string }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, id in ids do
		out[id] = true
	end
	return out
end

-- State.exclusiveShop for this session (the caller decides whether the flag is on). `world` also checks that a lock
-- break's plot still has its owner (nil: by its end time only).
function Purchases.view(session: Session, now: number, world: World?): Types.ExclusiveShopView
	local data = session.data
	local pass = if world then LockBreak.pass(world, session, now) else session.lockBreak
	if pass and now >= pass.untilTime then
		pass = nil
	end
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
		trails = set(data.ownedTrails),
		trail = data.trail,
		batSkins = set(data.ownedBatSkins),
		batSkin = data.batSkin,
		lockBreak = if pass then { plot = pass.plot, untilTime = pass.untilTime } else nil,
		lockBreakCredits = data.lockBreakCredits,
		giftCredits = table.clone(data.giftCredits),
	}
end

return table.freeze(Purchases)
