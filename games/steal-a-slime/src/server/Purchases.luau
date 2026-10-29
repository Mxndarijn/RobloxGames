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
	  * fanfare / lockStyle / hat / plotSkin / plotBase (Fanfare_, LockStyle_, Hat_, Skin_, Base_<id>): joins
	    `data.ownedStyles[kind]` (worn with EquipStyle; a plot skin with EquipPlotSkin, a plot base with
	    EquipPlotBase). pack (a bundle): each of its `items`.
	  * lockBreak: opens the locked base aimed with AimLockBreak for the buyer (LockBreak.open), else one
	    `data.lockBreakCredits` (spent with UseCredit "lockBreak").
	  * gift (Gift_<item>): gives the cosmetic `item` to the player aimed with AimGift and writes their save now
	    (`ctx.save`). A target who left, already owns it or whose save failed leaves the buyer a `data.giftCredits`
	    entry instead (sent later with SendGift). The item is never lost: with no room for a credit the grant is
	    refused and Roblox asks again later.
	`useCredit` spends a saved credit (Request UseCredit), `applyPasses` sets the runtime Game Pass effects
	(`data.pass*`), `applySubscriptions` / `stepDaily` the Slime Club and its daily credits, `claimPerk` the VIP's
	daily server potion, and `view` builds State.exclusiveShop. Receipts, saving and the
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
local Growth = if Shared then require(Shared.Growth) else require("../shared/Growth")
local Perks = if Shared then require(Shared.Perks) else require("../shared/Perks")
local PetSeats = if Shared then require(Shared.PetSeats) else require("../shared/PetSeats")
local PlotBases = if Shared then require(Shared.PlotBases) else require("../shared/PlotBases")
local PlotSkins = if Shared then require(Shared.PlotSkins) else require("../shared/PlotSkins")
local Seasons = if Shared then require(Shared.Seasons) else require("../shared/Seasons")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")
local VatState = if Shared then require(Shared.VatState) else require("../shared/VatState")
local BossEvent = if script then require(script.Parent.BossEvent) else require("./BossEvent")
local LockBreak = if script then require(script.Parent.LockBreak) else require("./LockBreak")
local Spawner = if script then require(script.Parent.Spawner) else require("./Spawner")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

-- `features`: Config.FEATURES overrides by flag name (tests), like Actions.Context. `save`: writes another player's
-- session data now (the session-locked Persistence save; yields), true = written; nil = can't (a gift becomes a credit).
export type Context = {
	features: { [string]: boolean }?,
	requestWeather: ((id: string) -> boolean)?, -- the Weather service (Weather Totem); nil = no weather here
	save: ((userId: number, data: any) -> boolean)?,
}

local Purchases = {}

local SHOP = Config.EXCLUSIVE_SHOP

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

local function addCredit(data: PlayerData.Data, kind: "brew" | "hatch" | "rain" | "boss" | "totem" | "snack")
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

-- The Exclusive style kinds kept in data.ownedStyles / data.wornStyles, with their Config catalogue.
local STYLE_KINDS: { [string]: { list: { any }?, noun: string } } = {
	fanfare = { list = SHOP.fanfares, noun = "fanfare" },
	lockStyle = { list = SHOP.lockStyles, noun = "lock" },
	hat = { list = SHOP.hats, noun = "" },
	plotSkin = { list = nil, noun = "base skin" },
	plotBase = { list = nil, noun = "base" },
}

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
	elseif STYLE_KINDS[grant.kind] then
		local owned = data.ownedStyles
		local list = owned[grant.kind]
		if not list then
			list = {}
			owned[grant.kind] = list
		end
		return list, grant.style
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
	local def = Purchases.product(itemKey)
	local kind = def and def.grant.kind
	if kind and STYLE_KINDS[kind] and data.wornStyles[kind] == id then
		data.wornStyles[kind] = nil
	end
	if kind == "plotSkin" and data.plotSkin == id then
		data.plotSkin = Config.PLOT_SKIN_DEFAULT
	end
	if kind == "plotBase" and data.plotBase == id then
		data.plotBase = Config.PLOT_BASE_DEFAULT
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
	elseif grant and grant.kind == "plotSkin" then
		local skin = PlotSkins.get(grant.style)
		return `the {if skin then skin.name else grant.style} base skin`
	elseif grant and grant.kind == "plotBase" then
		local base = PlotBases.get(grant.style)
		return `the {if base then base.name else grant.style} base`
	elseif grant and STYLE_KINDS[grant.kind] then
		local style = STYLE_KINDS[grant.kind]
		local d = findDef(style.list or {}, grant.style)
		local name = if d then d.name else grant.style
		return if style.noun == "" then `the {name}` else `the {name} {style.noun}`
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

-- EquipStyle: wears an owned fanfare / lockStyle / hat ("" takes that kind off). Returns (ok, reason).
function Purchases.equipStyle(session: Session, kind: string, id: string): (boolean, string?)
	if kind ~= "fanfare" and kind ~= "lockStyle" and kind ~= "hat" then
		return false, "unknown style"
	end
	local data = session.data
	local owned = data.ownedStyles[kind]
	if id ~= "" and not (owned and table.find(owned, id)) then
		return false, "you don't own that"
	end
	if id == "" then
		data.wornStyles[kind] = nil
	else
		data.wornStyles[kind] = id
	end
	World.markDirty(session)
	return true, nil
end

-- The worn style of `kind` ("fanfare", "lockStyle", "hat"), or nil.
function Purchases.wornStyle(data: PlayerData.Data, kind: string): string?
	return data.wornStyles[kind]
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

-- Server boosts (contract/exclusive-shop.md §14): Slime Rain now, the boss now, the Weather Totem. Each is refused
-- (and kept as a credit) while it can't happen: a rain or boss already on, the server's cooldown, no weather service.

-- Why a paid Slime Rain can't start now on this server; nil = it can.
function Purchases.rainRefusal(world: World, now: number): string?
	if world.raining or Spawner.rain(world, now) then
		return "a Slime Rain is already falling"
	end
	if world.boss ~= nil then
		return "not during a boss"
	end
	local last = world.paidRainAt
	if last and now - last < SHOP.serverBoosts.rainCooldown then
		return `the next paid rain is possible in {math.ceil((SHOP.serverBoosts.rainCooldown - (now - last)) / 60)} min`
	end
	return nil
end

-- Why the boss can't be summoned now on this server; nil = it can.
function Purchases.summonRefusal(world: World, now: number): string?
	if world.boss ~= nil then
		return "the boss is already here"
	end
	local warning = Config.BOSS.WARNING_SECONDS
	if world.nextBossAt - now <= warning then
		return "the boss is on its way already"
	end
	if BossEvent.rainBlocks(world, now, now + warning) then
		return "not during a Slime Rain"
	end
	local last = world.summonedAt
	if last and now - last < SHOP.serverBoosts.summonCooldown then
		return `the boss can be summoned again in {math.ceil((SHOP.serverBoosts.summonCooldown - (now - last)) / 60)} min`
	end
	return nil
end

local function startRain(world: World, session: Session, now: number): (boolean, string?)
	local refusal = Purchases.rainRefusal(world, now)
	if refusal then
		return false, refusal
	end
	world.paidRainAt = now
	Spawner.forceRain(world, now)
	World.notify(world, nil, `{session.name} started a Slime Rain for everyone!`, "good", "Rain")
	World.markAllDirty(world)
	return true, nil
end

local function summonBoss(world: World, session: Session, now: number): (boolean, string?)
	local refusal = Purchases.summonRefusal(world, now)
	if refusal then
		return false, refusal
	end
	world.summonedAt = now
	world.nextBossAt = now + Config.BOSS.WARNING_SECONDS
	World.notify(world, nil, `{session.name} summoned the boss! It arrives soon.`, "good", nil)
	World.markAllDirty(world)
	return true, nil
end

local function callWeather(world: World, session: Session, now: number, ctx: Context?): (boolean, string?)
	local request = ctx and ctx.requestWeather
	if not (request and Config.FEATURES.Weather == true) then
		return false, "no weather here"
	end
	local _, weather = Consumables.stock(Consumables.slotAt(now))
	local ok, called = pcall(request, weather)
	if not (ok and called) then
		return false, "the weather can't change that way right now"
	end
	World.notify(world, nil, `{session.name} used a Weather Totem: {weather} is next!`, "good", nil)
	World.markAllDirty(world)
	return true, nil
end

-- The owned slime a Growth Snack feeds: `slimeId` when it is a grown-up-able slime on a pad, else the least grown
-- one on a pad. Eggs and fully grown slimes never.
function Purchases.snackTarget(world: World, session: Session, slimeId: string?): Genome.Slime?
	if not Growth.enabled() then
		return nil -- slimes don't grow on this server: a snack is kept as a credit
	end
	local best: Genome.Slime? = nil
	for _, slime in session.data.slimes do
		local fits = slime.pad ~= nil
			and slime.egg == nil
			and (slime.growth or 0) < 1
			and not World.isBusy(world, slime.id)
		if fits and slime.id == slimeId then
			return slime
		end
		if fits and (best == nil or (slime.growth or 0) < ((best :: Genome.Slime).growth or 0)) then
			best = slime
		end
	end
	return best
end

local function feedSnack(world: World, session: Session, slimeId: string?): boolean
	local slime = Purchases.snackTarget(world, session, slimeId)
	if not slime then
		return false
	end
	Growth.advance(slime, SHOP.growthSnackSeconds)
	World.markDirty(session)
	World.notify(world, session.userId, `{Genome.displayName(slime)} ate a Growth Snack and grew!`, "good", "Gift")
	return true
end

-- AimSnack: remembers which slime the next GrowthSnack receipt feeds. Returns (ok, reason).
function Purchases.aimSnack(world: World, session: Session, slimeId: string): (boolean, string?)
	local slime = Purchases.snackTarget(world, session, slimeId)
	if not slime or slime.id ~= slimeId then
		return false, "that slime can't grow any more"
	end
	session.snackTarget = slimeId
	return true, nil
end

-- True when the daily streak is broken and a KeepStreak would save it: a streak of 2+ days whose last claim was
-- before yesterday, today not claimed yet.
function Purchases.streakKeepable(data: PlayerData.Data, now: number): boolean
	local today = Purchases.day(now)
	return data.daily.streak >= 2 and data.daily.lastDay < today - 1
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
	elseif kind == "slimeRain" or kind == "summonBoss" or kind == "weatherTotem" then
		local credit: "rain" | "boss" | "totem" = if kind == "slimeRain"
			then "rain"
			elseif kind == "summonBoss" then "boss"
			else "totem"
		local ok = if kind == "slimeRain"
			then startRain(world, session, now)
			elseif kind == "summonBoss" then summonBoss(world, session, now)
			else callWeather(world, session, now, ctx)
		if not ok then
			addCredit(data, credit)
			World.notify(
				world,
				userId,
				"Not possible right now: saved as a credit. Use it in the Exclusive shop.",
				"info",
				nil
			)
		end
	elseif kind == "boost" then
		Codes.addBoost(data, grant.mult, grant.seconds / 60, now)
		World.notify(world, userId, `{grant.mult}x income for {math.floor(grant.seconds / 60)} min!`, "good", "Gift")
	elseif kind == "keepStreak" then
		if Purchases.streakKeepable(data, now) then
			data.daily.lastDay = Purchases.day(now) - 1
			World.notify(
				world,
				userId,
				`Your {data.daily.streak} day streak is safe! Claim today's reward.`,
				"good",
				"Daily"
			)
		else
			World.notify(world, userId, "Your streak is safe.", "good", "Daily")
		end
	elseif kind == "growthSnack" then
		local target = session.snackTarget
		session.snackTarget = nil
		if not feedSnack(world, session, target) then
			addCredit(data, "snack")
			World.notify(world, userId, "No slime can grow right now: saved as a snack credit.", "info", nil)
		end
	elseif kind == "trail" or kind == "batSkin" or STYLE_KINDS[kind] then
		Purchases.giveItem(data, productKey)
		local where = if kind == "plotSkin" or kind == "plotBase"
			then "Pick it in Skins."
			else "Wear it in the Exclusive shop."
		World.notify(world, userId, `{Purchases.itemName(productKey)} is yours! {where}`, "good", "Gift")
	elseif kind == "pack" then
		for _, item in grant.items do
			Purchases.giveItem(data, item)
		end
		World.notify(world, userId, "Bundle unlocked! Everything in it is yours.", "good", "Gift")
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
	elseif kind == "rain" or kind == "boss" or kind == "totem" then
		local credits = data.credits :: any
		if credits[kind] < 1 then
			return false, "no credit of that"
		end
		local ok, reason
		if kind == "rain" then
			ok, reason = startRain(world, session, now)
		elseif kind == "boss" then
			ok, reason = summonBoss(world, session, now)
		else
			ok, reason = callWeather(world, session, now, ctx)
		end
		if not ok then
			return false, reason
		end
		credits[kind] -= 1
		return true, nil
	elseif kind == "snack" then
		if data.credits.snack < 1 then
			return false, "no snack credits"
		end
		if not feedSnack(world, session, slimeId) then
			return false, "no slime can grow right now"
		end
		data.credits.snack -= 1
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
	Sets the runtime Game Pass effects from `passes` (pass key -> owned), field by field (Config.ExclusivePass):
	incomeMult (every owned one multiplies) into Perks.bonusMultiplier, offlineRate as the offline rate, brewFactor
	into Perks.brewFactor, warmAway, luckBonus into Perks.luckChance; radar and vip are read from `session.passes`.
	When the offline rate goes up after this join's payout was made (pass checks finish after the join), the
	difference is paid now. Returns that top-up (0 when none).
]]
function Purchases.applyPasses(session: Session, passes: { [string]: boolean }): number
	local data = session.data
	local owned: { [string]: boolean } = {}
	local income, brew, luck = 1, 1, 0
	local offline: number? = nil
	local warm, auto = false, false
	for key, def in SHOP.passes do
		owned[key] = passes[key] == true
		if owned[key] then
			income *= def.incomeMult or 1
			if def.offlineRate then
				offline = math.max(offline or 0, def.offlineRate)
			end
			brew *= def.brewFactor or 1
			warm = warm or def.warmAway == true
			auto = auto or def.autoCollect == true
			luck += def.luckBonus or 0
		end
	end
	session.passes = owned
	data.passIncomeMult = if income ~= 1 then income else nil
	data.passOfflineRate = offline
	data.passBrewFactor = if brew ~= 1 then brew else nil
	data.passWarmNest = if warm then true else nil
	data.passAutoCollect = if auto then true else nil
	data.passLuckBonus = if luck > 0 then luck else nil
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

-- True when `session` owns the Game Pass `key` (checked on join, never saved).
function Purchases.hasPass(session: Session, key: string): boolean
	return session.passes ~= nil and session.passes[key] == true
end

-- True when `session` owns a pass with the effect `field` (a Config.ExclusivePass field, e.g. "radar", "vip").
function Purchases.hasEffect(session: Session, field: string): boolean
	for key, def in SHOP.passes do
		if (def :: any)[field] and Purchases.hasPass(session, key) then
			return true
		end
	end
	return false
end

-- True while `session` is subscribed to `key` (Config.EXCLUSIVE_SHOP.subscriptions; checked on join, never saved).
function Purchases.subscribed(session: Session, key: string): boolean
	return session.subscriptions ~= nil and session.subscriptions[key] == true
end

-- The tag `session` wears (Constants.MEMBER_ATTRIBUTE): "vip", "club" or nil. VIP wins when both.
function Purchases.member(session: Session): string?
	if Purchases.hasEffect(session, "vip") then
		return "vip"
	elseif Purchases.subscribed(session, "SlimeClub") then
		return "club"
	end
	return nil
end

-- The UTC day number of `now`: daily perks reset at 00:00 UTC, the same on every server.
function Purchases.day(now: number): number
	return math.floor(now / 86400)
end

local function perkDays(data: PlayerData.Data): PlayerData.PerkDays
	local days = data.perkDays or {}
	data.perkDays = days
	return days
end

--[[
	Once per UTC day while subscribed to the Slime Club, its daily skip credits (subscriptions.SlimeClub.daily) join
	`data.credits` (capped at creditMax) and the player is told. Cheap enough to call every second.
]]
function Purchases.stepDaily(world: World, session: Session, now: number)
	if not Purchases.subscribed(session, "SlimeClub") then
		return
	end
	local today = Purchases.day(now)
	local days = perkDays(session.data)
	if days.club == today then
		return
	end
	days.club = today
	local daily = SHOP.subscriptions.SlimeClub.daily
	local credits = session.data.credits
	credits.brew = math.min(credits.brew + daily.brew, SHOP.creditMax)
	credits.hatch = math.min(credits.hatch + daily.hatch, SHOP.creditMax)
	World.markDirty(session)
	World.notify(world, session.userId, "Slime Club: a free Finish now and Hatch now for today!", "good", "Gift")
end

-- Sets the runtime subscriptions from `subs` (subscription key -> active), then gives today's Club credits.
function Purchases.applySubscriptions(world: World, session: Session, subs: { [string]: boolean }, now: number)
	local active: { [string]: boolean } = {}
	for key in SHOP.subscriptions do
		active[key] = subs[key] == true
	end
	session.subscriptions = active
	World.markDirty(session)
	Purchases.stepDaily(world, session, now)
end

-- True while a VIP's free server Luck Potion of today is still unused.
function Purchases.vipPotionReady(session: Session, now: number): boolean
	if not Purchases.hasEffect(session, "vip") then
		return false
	end
	local days = session.data.perkDays
	return not (days and days.vipPotion == Purchases.day(now))
end

--[[
	ClaimPerk: "vipPotion" gives the server a Luck Potion, once per UTC day, for a VIP. Refused where paid random items
	are restricted (the potion changes the fountain odds). Returns (ok, player-facing reason).
]]
function Purchases.claimPerk(world: World, session: Session, perk: string, now: number): (boolean, string?)
	if perk ~= "vipPotion" then
		return false, "unknown perk"
	end
	if not Purchases.hasEffect(session, "vip") then
		return false, "that is a VIP perk"
	end
	if session.paidRandomAllowed ~= true then
		return false, "not available in your region"
	end
	if not Purchases.vipPotionReady(session, now) then
		return false, "you gave today's potion already: back tomorrow"
	end
	perkDays(session.data).vipPotion = Purchases.day(now)
	world.potionUntil = Consumables.extendPotion(world.potionUntil, now)
	World.notify(world, nil, `VIP {session.name} gave the server a Luck Potion!`, "good", nil)
	World.markAllDirty(world)
	return true, nil
end

-- The carry trail and Bat skin `session` wears now.
function Purchases.worn(session: Session): (string?, string?)
	return session.data.trail, session.data.batSkin
end

local function set(ids: { string }): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, id in ids do
		out[id] = true
	end
	return out
end

-- State.exclusiveShop for this session. `world` also checks that a lock
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
	local styles: { [string]: { [string]: boolean } } = {}
	for kind in STYLE_KINDS do
		styles[kind] = set(data.ownedStyles[kind] or {})
	end
	local seasons: { [string]: boolean } = {}
	for id in (SHOP :: any).seasons :: { [string]: any } do
		seasons[id] = Seasons.active(id, now)
	end
	local subscriptions: { [string]: boolean } = {}
	for key in SHOP.subscriptions do
		subscriptions[key] = session.subscriptions ~= nil and session.subscriptions[key] == true
	end
	local record = data.offlineDouble
	return {
		owned = owned,
		passes = passes,
		starterClaimed = data.starterBundle == true,
		credits = table.clone(data.credits),
		serverBoosts = {
			rain = if world then Purchases.rainRefusal(world, now) == nil else false,
			boss = if world then Purchases.summonRefusal(world, now) == nil else false,
		},
		streakKeepable = Purchases.streakKeepable(data, now),
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
		styles = styles,
		worn = table.clone(data.wornStyles),
		seasons = seasons,
		subscriptions = subscriptions,
		vipPotion = Purchases.vipPotionReady(session, now),
		luck = { base = Perks.baseLuckChance(data), bonus = SHOP.passes.LuckyCharmPlus.luckBonus or 0 },
		radar = if session.radar then table.clone(session.radar) else {},
	}
end

return table.freeze(Purchases)
