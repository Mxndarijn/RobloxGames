--!strict
--[[
	Actions (pure)

	The `Request` RemoteFunction dispatcher (CONTRACT.md §3). Validates every
	argument against Remotes.ACTIONS with Shared.Validate, rate-limits per
	action (Validate.ACTIONS; Sync at most once per Config.STATE_MIN_INTERVAL,
	the State coalescing window), calls the system and returns a RequestResult
	plus `ran` (true once the call got past every guard and was dispatched; the
	adapter only refreshes the world view then). Never errors.

	`ctx` (Context) gives the adapter's world queries, the PvP engine access (PvpService.Context fields) and
	`features`, the per-call Config.FEATURES overrides tests pass.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local AudioSettings = if Shared then require(Shared.AudioSettings) else require("../shared/AudioSettings")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Codes = if Shared then require(Shared.Codes) else require("../shared/Codes")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local HotbarOrder = if Shared then require(Shared.HotbarOrder) else require("../shared/HotbarOrder")
local Merge = if Shared then require(Shared.Merge) else require("../shared/Merge")
local Perks = if Shared then require(Shared.Perks) else require("../shared/Perks")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local PlotSkins = if Shared then require(Shared.PlotSkins) else require("../shared/PlotSkins")
local Progression = if Shared then require(Shared.Progression) else require("../shared/Progression")
local Remotes = if Shared then require(Shared.Remotes) else require("../shared/Remotes")
local Quests = if Shared then require(Shared.Quests) else require("../shared/Quests")
local Rng = if Shared then require(Shared.Rng) else require("../shared/Rng")
local Shop = if Shared then require(Shared.Shop) else require("../shared/Shop")
local Shops = if Shared then require(Shared.Shops) else require("../shared/Shops")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")
local Upgrades = if Shared then require(Shared.Upgrades) else require("../shared/Upgrades")
local Validate = if Shared then require(Shared.Validate) else require("../shared/Validate")
local Carry = if script then require(script.Parent.Carry) else require("./Carry")
local PlotPadGuard = if script then require(script.Parent.PlotPadGuard) else require("./PlotPadGuard")
local ShopGuard = if script then require(script.Parent.ShopGuard) else require("./ShopGuard")
local ConsumableShop = if script then require(script.Parent.ConsumableShop) else require("./ConsumableShop")
local MergeVat = if script then require(script.Parent.MergeVat) else require("./MergeVat")
local MysteryEgg = if script then require(script.Parent.MysteryEgg) else require("./MysteryEgg")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local Rebirth = if script then require(script.Parent.Rebirth) else require("./Rebirth")
local StealService = if script then require(script.Parent.StealService) else require("./StealService")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session
type Result = Types.RequestResult

export type Context = {
	distanceBetween: (a: number, b: number) -> number, -- math.huge if unknown
	positionOf: (userId: number) -> any?, -- opaque, stored on dropped wild slimes; also PvP's positionOf
	rng: Rng.Rng?, -- consumable rolls; nil = seeded from the clock and the player
	-- Config.FEATURES overrides by flag name (tests); a flag not listed reads Config.FEATURES.
	features: { [string]: boolean }?,
	-- PvP engine access, the fields of PvpService.Context (nil = can't)
	onOwnPlot: ((session: Session, userId: number) -> boolean)?,
	pointOnOwnPlot: ((session: Session, point: any) -> boolean)?,
	launch: ((userId: number, push: any, landing: any?) -> boolean)?,
	areFriends: ((a: number, b: number, now: number) -> boolean)?,
	pose: ((userId: number) -> (any?, any?))?,
	toVector3: ((position: any) -> any)?,
	slimePosition: ((slimeId: string) -> any?)?,
	groundBelow: ((point: any) -> any?)?,
	funBubble: ((
		userId: number,
		seconds: number,
		lift: number,
		onPop: (byUserId: number, now: number) -> boolean
	) -> boolean)?,
	-- What the adapter measured for `shopId`: the character's distance to the stand's Counter and whether it is
	-- alive (distance nil = no character or no stand). nil = no world: shop range is never satisfied, strict never applies.
	shopAccess: ((userId: number, shopId: string) -> ShopGuard.Access)?,
	-- What the adapter measured for the owner's plot prompt `kind` ("Lock" | "BuyPad" | "Merge"): the character's distance to the
	-- part that prompt sits on and whether it is alive. nil = no world: Actions.handlePlotPad skips the range check.
	plotPadAccess: ((userId: number, kind: string) -> PlotPadGuard.Access)?,
	strictBypass: boolean?, -- set by handlePlotPad on its private copy of the context: the pad range check replaced the shop gate
	-- ShopEvent to one player (CONTRACT.md §27.4); the adapter adds serverTime. nil = fire nothing.
	shopEvent: ((userId: number, payload: { [string]: any }) -> ())?,
	requestWeather: ((id: string) -> boolean)?, -- Weather Totem: makes `id` the next weather (nil = no Weather service)
	-- Drop tube (CONTRACT.md §5.3): moves the player's character to plot `plotIndex`'s splash pool; false = no
	-- character or no plot. nil = no world: the drop is refused.
	dropDown: ((userId: number, plotIndex: number) -> boolean)?,
}

local Actions = {}

local function fail(message: string): Result
	return { ok = false, message = message }
end

local OK: Result = table.freeze({ ok = true })

-- Config.FEATURES.<name> for this call: ctx.features overrides it (tests).
local function feature(ctx: Context, name: string): boolean
	local override = if ctx.features then ctx.features[name] else nil
	if override ~= nil then
		return override
	end
	return (Config.FEATURES :: any)[name] == true
end
Actions.feature = feature

local function result(ok: boolean, message: string?): Result
	if ok then
		return OK
	end
	return fail(message or "failed")
end

-- A Roblox Vector3 with finite, sane components (no NaN / inf / absurd magnitudes).
local MAX_COORD = 100000
local function finiteVector(value: any): boolean
	if typeof(value) ~= "Vector3" then
		return false
	end
	for _, c in { value.X, value.Y, value.Z } do
		if c ~= c or math.abs(c) > MAX_COORD then -- NaN fails c ~= c; inf fails the bound
			return false
		end
	end
	return true
end

--[[
	Checks the raw remote args against the action's spec. Returns the
	cleaned args or (nil, reason).
]]
function Actions.parseArgs(action: string, raw: { any }): ({ any }?, string?)
	local def = Remotes.ACTIONS[action]
	if not def then
		return nil, "unknown action"
	end
	local out: { any } = {}
	for i, kind in def.args do
		local value = raw[i]
		if kind == "string" or kind == "string?" then
			if value == nil and kind == "string?" then
				out[i] = nil
			else
				local id = Validate.slimeId(value)
				if not id then
					return nil, "bad argument"
				end
				out[i] = id
			end
		elseif kind == "code" then
			-- Free text: only bounded here; Codes.normalize words the result.
			if type(value) ~= "string" or #value > 64 then
				return nil, "bad argument"
			end
			out[i] = value
		elseif kind == "hotbar" then
			-- Only bounded here; HotbarOrder.parse checks the keys.
			if type(value) ~= "string" or #value > HotbarOrder.MAX_LENGTH then
				return nil, "bad argument"
			end
			out[i] = value
		elseif kind == "boolean" or kind == "boolean?" then
			if value == nil and kind == "boolean?" then
				out[i] = nil
			elseif type(value) ~= "boolean" then
				return nil, "bad argument"
			else
				out[i] = value
			end
		elseif kind == "number" or kind == "number?" then
			if value == nil and kind == "number?" then
				out[i] = nil
			else
				if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
					return nil, "bad argument"
				end
				out[i] = value
			end
		elseif kind == "vector3?" then
			if value ~= nil then
				if not finiteVector(value) then
					return nil, "bad argument"
				end
				out[i] = value
			end
		else
			return nil, "bad argument"
		end
	end
	return out, nil
end

local function sell(world: World, session: Session, id: string): Result
	if World.isBusy(world, id) then
		return fail("slime is busy")
	end
	local ok, value = PlayerData.sell(session.data, id)
	if not ok then
		return fail(value :: string)
	end
	World.notify(world, session.userId, `Sold for ${Economy.formatNumber(value :: number)}`, "good", "Cash", "Cash")
	return OK
end

local function moveSlime(world: World, session: Session, id: string, pad: number, ctx: Context): Result
	if not feature(ctx, "MoveSlime") then
		return fail("moving slimes is off")
	end
	local other = PlayerData.slimeOnPad(session.data, pad)
	if World.isBusy(world, id) or (other ~= nil and World.isBusy(world, other.id)) then
		return fail("slime is busy")
	end
	return result(PlayerData.moveSlime(session.data, id, pad))
end

local function buyPad(world: World, session: Session): Result
	local ok, reason = PlayerData.buyPad(session.data)
	if ok then
		World.notify(world, session.userId, "New pad unlocked!", "good", "Cash")
		World.tutorial(world, session, "BuyPad")
	end
	return result(ok, reason)
end

local function daily(world: World, session: Session, now: number): Result
	local ok, value = Progression.claimDaily(session.data, now)
	if not ok then
		return fail(value :: string)
	end
	World.notify(
		world,
		session.userId,
		`Daily reward: ${Economy.formatNumber(value :: number)}`,
		"good",
		"Cash",
		"Daily"
	)
	return OK
end

local function claimQuest(world: World, session: Session, index: any, now: number): Result
	if type(index) ~= "number" or index % 1 ~= 0 then
		return fail("no such quest")
	end
	local ok, value = Quests.claim(session.data, index, now, session.userId)
	if not ok then
		return fail(value)
	end
	World.notify(world, session.userId, `Quest complete! {value}`, "good", "Goal")
	return OK
end

local function redeem(world: World, session: Session, text: string, now: number): Result
	local ok, status, reward = Codes.redeem(session.data, text, now)
	if not ok or not reward then
		return fail(Codes.MESSAGES[status] or "That code doesn't work")
	end
	local what = if reward.kind == "boost"
		then `{reward.mult}x income for {reward.minutes} min`
		else `${Economy.formatNumber(reward.amount or 0)}`
	World.notify(world, session.userId, `Code redeemed: {what}!`, "good", "Cash", "Gift")
	return OK
end

local function buySpeedCoil(world: World, session: Session): Result
	local ok, value = Shop.buySpeedCoil(session.data)
	if not ok then
		return fail(value :: string)
	end
	World.notify(world, session.userId, "Speed Coil bought! You run faster now.", "good", "Cash", "SpeedCoil")
	return OK
end

local function buyUpgrade(world: World, session: Session, id: string): Result
	local ok, value = Upgrades.buy(session.data, id)
	if not ok then
		return fail(value :: string)
	end
	local def = Perks.upgradeDef(id)
	local level = session.data.upgrades[id]
	World.notify(world, session.userId, `{def and def.name or id} level {level}!`, "good", "Cash", `Upgrade_{id}`)
	return OK
end

local function merge3(world: World, session: Session, args: { any }, ctx: Context): Result
	if not feature(ctx, "MergeVat3") then
		return fail("the 3-slime vat is off")
	end
	return result(MergeVat.merge3(world, session, { args[1], args[2], args[3] }))
end

local function autoMerge(world: World, session: Session, mask: number, ctx: Context): Result
	if not feature(ctx, "MergeVat3") then
		return fail("the 3-slime vat is off")
	end
	return result(MergeVat.autoMerge(world, session, mask))
end

local function equipPlotSkin(world: World, session: Session, id: string, ctx: Context): Result
	if not feature(ctx, "PlotSkins") then
		return fail("plot skins are off")
	end
	local ok, reason = PlotSkins.equip(session.data, id)
	if not ok then
		return fail(reason or "failed")
	end
	local skin = PlotSkins.get(id)
	World.notify(world, session.userId, `Plot skin: {skin and skin.name or id}`, "good", nil, `PlotSkin_{id}`)
	return OK
end

local function setAudioSettings(session: Session, music: number, sfx: number, muted: boolean, ctx: Context): Result
	if not feature(ctx, "Audio") then
		return fail("audio settings are off")
	end
	session.data.settings = AudioSettings.clean({ musicVolume = music, sfxVolume = sfx, muted = muted })
	return OK
end

local function buyConsumable(
	world: World,
	session: Session,
	id: string,
	slimeId: string?,
	now: number,
	ctx: Context
): Result
	local ok, reason = ConsumableShop.buy(world, session, id, slimeId, now, { requestWeather = ctx.requestWeather })
	return result(ok, reason)
end

local function useConsumable(
	world: World,
	session: Session,
	id: string,
	slimeId: string?,
	now: number,
	ctx: Context
): Result
	local rng = ctx.rng or Rng.new(math.floor(now * 1000) + session.userId)
	local ok, reason =
		ConsumableShop.use(world, session, id, slimeId, now, { rng = rng, requestWeather = ctx.requestWeather })
	return result(ok, reason)
end

---------------------------------------------------------------------------
-- World shops (FEATURES.WorldShops, CONTRACT.md §27): validation lives in ShopGuard, the purchases are the
-- existing handlers (dispatch), nothing is priced or charged here.
---------------------------------------------------------------------------

local function worldShopsOn(ctx: Context): boolean
	return feature(ctx, "WorldShops")
end

local function strictOn(ctx: Context): boolean
	return worldShopsOn(ctx) and feature(ctx, "WorldShopsStrict")
end

local function accessOf(ctx: Context, userId: number, shopId: string): ShopGuard.Access?
	return if ctx.shopAccess then ctx.shopAccess(userId, shopId) else nil
end

local function shopEvent(ctx: Context, userId: number, payload: { [string]: any })
	if ctx.shopEvent and worldShopsOn(ctx) then
		ctx.shopEvent(userId, payload)
	end
end

local function denied(ctx: Context, userId: number, shopId: any, itemId: any, code: string, text: string?): Result
	local message = text or ShopGuard.MESSAGES[code] or code
	shopEvent(ctx, userId, {
		kind = "Denied",
		shopId = if type(shopId) == "string" then shopId else nil,
		itemId = if type(itemId) == "string" then itemId else nil,
		code = code,
		message = message,
	})
	return { ok = false, message = message, code = code }
end

-- Closes the player's open shop and tells them (range / death / leave from the adapter's tick, or CloseShop).
function Actions.closeShop(session: Session, reason: string, ctx: Context)
	local shopId = session.openShop
	if shopId == nil then
		return
	end
	session.openShop = nil
	shopEvent(ctx, session.userId, { kind = "Close", shopId = shopId, reason = reason })
end

-- Throttled by the caller: closes the open shop when it left range, died or the flag went off.
function Actions.shopTick(session: Session, ctx: Context)
	local shopId = session.openShop
	if shopId == nil then
		return
	end
	local reason = ShopGuard.closeReason(shopId, worldShopsOn(ctx), accessOf(ctx, session.userId, shopId))
	if reason then
		Actions.closeShop(session, reason, ctx)
	end
end

local function openShop(session: Session, shopId: string, ctx: Context): Result
	local code = ShopGuard.check({
		worldShops = worldShopsOn(ctx),
		strict = false,
		shopId = shopId,
		openShop = session.openShop,
		access = accessOf(ctx, session.userId, shopId),
	})
	if code then
		return denied(ctx, session.userId, shopId, nil, code)
	end
	session.openShop = shopId
	shopEvent(ctx, session.userId, { kind = "Open", shopId = shopId })
	return OK
end

-- The shop prompt (WorldProps) opens the shop on the server, so it works without any client code and does not
-- spend the OpenShop rate limit the client's own OpenShop call uses. Returns the same Result as OpenShop.
function Actions.openFromPrompt(world: World, userId: number, shopId: string, ctx: Context): Result
	local session = World.session(world, userId)
	if not session then
		return fail("still loading")
	end
	return openShop(session, shopId, ctx)
end

local function closeShopAction(session: Session, ctx: Context): Result
	if worldShopsOn(ctx) then
		Actions.closeShop(session, "closed", ctx)
	end
	return OK
end

-- Level after a purchase, for ShopEvent Purchased (leveled upgrades only).
local function levelOf(session: Session, itemId: string): number?
	local level = session.data.upgrades[itemId]
	return if Perks.upgradeDef(itemId) then level or 0 else nil
end

local dispatch: (World, Session, string, { any }, number, Context) -> Result

local function shopBuy(
	world: World,
	session: Session,
	shopId: string,
	itemId: string,
	arg: string?,
	now: number,
	ctx: Context
): Result
	local userId = session.userId
	local code = ShopGuard.check({
		worldShops = worldShopsOn(ctx),
		strict = strictOn(ctx),
		shopId = shopId,
		itemId = itemId,
		openShop = session.openShop,
		access = accessOf(ctx, userId, shopId),
	})
	if code then
		return denied(ctx, userId, shopId, itemId, code)
	end
	local row = Shops.find(shopId, itemId) :: Shops.Item
	local features = Config.FEATURES :: any
	if row.flag ~= nil and features[row.flag] ~= true then
		return denied(ctx, userId, shopId, itemId, "Unavailable", "not available right now")
	end
	-- The delegated action keeps its own rate limit (Validate.ACTIONS), so ShopBuy never loosens it.
	if not Validate.allow(session.limiter, row.action, now) then
		return denied(ctx, userId, shopId, itemId, "Busy")
	end
	local args: { any } = {}
	if row.argIsItem then
		args = { itemId, arg }
	end
	local cashBefore = session.data.cash
	local res = dispatch(world, session, row.action, args, now, ctx)
	if not res.ok then
		return denied(ctx, userId, shopId, itemId, ShopGuard.classify(res.message), res.message)
	end
	shopEvent(ctx, userId, {
		kind = "Purchased",
		shopId = shopId,
		itemId = itemId,
		price = math.max(0, cashBefore - session.data.cash),
		level = levelOf(session, itemId),
	})
	return res
end

-- Strict mode (FEATURES.WorldShopsStrict): the old buy actions need the matching shop open and in range.
-- Only applies where the adapter measures ranges (ctx.shopAccess).
local function strictGate(session: Session, action: string, ctx: Context): Result?
	if ctx.strictBypass or not (ctx.shopAccess and strictOn(ctx)) then
		return nil
	end
	-- Locks are not sold in a shop: the HUD Lock button works while standing at the owner's own lock pad
	-- (same check as the pad prompt).
	if action == "Lock" then
		local code = if ctx.plotPadAccess then PlotPadGuard.check(ctx.plotPadAccess(session.userId, "Lock")) else nil
		return if code then fail(PlotPadGuard.MESSAGES[code]) else nil
	end
	local shopId = Shops.shopOfAction(action)
	if not shopId then
		return nil
	end
	local code = ShopGuard.check({
		worldShops = true,
		strict = true,
		shopId = shopId,
		itemId = nil,
		openShop = session.openShop,
		access = accessOf(ctx, session.userId, shopId),
	})
	if code == nil and session.openShop ~= shopId then
		code = "NotOpen"
	end
	if code == "NotOpen" then
		local name = (Shops.shop(shopId) :: Shops.Shop).name
		return denied(ctx, session.userId, shopId, nil, code, `open the {string.gsub(name, " Shop$", "")} Shop first`)
	end
	if code then
		return denied(ctx, session.userId, shopId, nil, code)
	end
	return nil
end

dispatch = function(world: World, session: Session, action: string, args: { any }, now: number, ctx: Context): Result
	if action == "Sync" then
		return OK
	elseif action == "OpenShop" then
		return openShop(session, args[1], ctx)
	elseif action == "CloseShop" then
		return closeShopAction(session, ctx)
	elseif action == "ShopBuy" then
		return shopBuy(world, session, args[1], args[2], args[3], now, ctx)
	end
	-- A pad is bought at the pad (its BuyPadPrompt, handlePlotPad): a Request("BuyPad") from anywhere else is refused
	-- wherever the adapter measures the range, strict mode or not.
	if action == "BuyPad" and not ctx.strictBypass and ctx.plotPadAccess then
		local code = PlotPadGuard.check(ctx.plotPadAccess(session.userId, "BuyPad"))
		if code then
			return fail(PlotPadGuard.MESSAGES[code])
		end
	end
	local blocked = strictGate(session, action, ctx)
	if blocked then
		return blocked
	end
	if action == "Merge" then
		return result(MergeVat.merge(world, session, args[1], args[2]))
	elseif action == "Merge3" then
		return merge3(world, session, args, ctx)
	elseif action == "AutoMerge" then
		return autoMerge(world, session, args[1], ctx)
	elseif action == "KeepSlime" then
		return result(MergeVat.setKeep(session, args[1], args[2]))
	elseif action == "Lock" then
		return result(StealService.buyLock(world, session, now))
	elseif action == "Rebirth" then
		return result(Rebirth.rebirth(world, session))
	elseif action == "Sell" then
		return sell(world, session, args[1])
	elseif action == "Favorite" then
		if not PlayerData.setFavorite(session.data, args[1]) then
			return fail("not your slime")
		end
		return OK
	elseif action == "MoveSlime" then
		return moveSlime(world, session, args[1], args[2], ctx)
	elseif action == "HatchEgg" then
		return result(MysteryEgg.hatch(world, session, args[1], now))
	elseif action == "BuyPad" then
		return buyPad(world, session)
	elseif action == "Daily" then
		return daily(world, session, now)
	elseif action == "ClaimQuest" then
		return claimQuest(world, session, args[1], now)
	elseif action == "Redeem" then
		return redeem(world, session, args[1], now)
	elseif action == "BuySpeedCoil" then
		return buySpeedCoil(world, session)
	elseif action == "BuyUpgrade" then
		return buyUpgrade(world, session, args[1])
	elseif action == "EquipPlotSkin" then
		return equipPlotSkin(world, session, args[1], ctx)
	elseif action == "SetAudioSettings" then
		return setAudioSettings(session, args[1], args[2], args[3], ctx)
	elseif action == "BuyConsumable" then
		return buyConsumable(world, session, args[1], args[2], now, ctx)
	elseif action == "UseConsumable" then
		return useConsumable(world, session, args[1], args[2], now, ctx)
	elseif action == "BuyPvpItem" then
		return result(PvpService.buy(world, session, args[1], feature(ctx, "PvP")))
	elseif action == "EquipPvpItem" then
		return result(PvpService.equip(session, args[1], feature(ctx, "PvP")))
	elseif action == "UsePvpItem" then
		return result(PvpService.use(world, session, args[1], args[2], args[3], now, feature(ctx, "PvP"), ctx, args[4]))
	elseif action == "SetHotbar" then
		return result(HotbarOrder.set(session.data, args[1]))
	elseif action == "Drop" then
		if not session.carry then
			return fail("not carrying")
		end
		Carry.release(world, session.userId, now, ctx.positionOf(session.userId), "drop")
		return OK
	end
	return fail("unknown action")
end

-- Sync can't push State faster than the coalescing window anyway, so a spammed Sync is refused before it costs a refresh.
local function allowSync(session: Session, now: number): boolean
	local last = session.limiter.Sync
	if last and now - last < Config.STATE_MIN_INTERVAL then
		return false
	end
	session.limiter.Sync = now
	return true
end

-- Returns (result, ran): `ran` is false when a guard refused the call before dispatch (unknown action, still loading,
-- bad argument, too fast), so the adapter can skip the world-wide view refresh for spam it never acted on.
function Actions.handle(
	world: World,
	userId: number,
	action: any,
	raw: { any },
	now: number,
	ctx: Context
): (Result, boolean)
	if type(action) ~= "string" or Remotes.ACTIONS[action] == nil then
		return fail("unknown action"), false
	end
	local session = World.session(world, userId)
	if not session then
		return fail("still loading"), false
	end
	local args, reason = Actions.parseArgs(action, raw)
	if not args then
		return fail(reason or "bad argument"), false
	end
	local allowed = if action == "Sync" then allowSync(session, now) else Validate.allow(session.limiter, action, now)
	if not allowed then
		return fail("too fast"), false
	end
	local ok, res = pcall(dispatch, world, session, action, args, now, ctx)
	if not ok then
		return fail("server error"), true
	end
	-- Sync re-sends (still coalesced to STATE_MIN_INTERVAL); successful actions changed state.
	if res.ok then
		World.markDirty(session)
	end
	return res, true
end

-- The owner-only plot prompts (LockPrompt, BuyPadPrompt, MergePrompt). The caller has already checked that the player owns the
-- plot; here the character must stand within PlotPadGuard.range() of THAT prompt's part. They never go through the world-shop
-- strict gate (the Item Shop stand is nowhere near the pad), but every other rule of the action still applies.
function Actions.handlePlotPad(
	world: World,
	userId: number,
	kind: string,
	args: { any },
	now: number,
	ctx: Context
): Result
	if PlotPadGuard.KINDS[kind] ~= true then
		return fail("unknown action")
	end
	if ctx.plotPadAccess then
		local code = PlotPadGuard.check(ctx.plotPadAccess(userId, kind))
		if code then
			return fail(PlotPadGuard.MESSAGES[code])
		end
	end
	local padCtx = table.clone(ctx)
	padCtx.strictBypass = true
	local res = Actions.handle(world, userId, kind, args, now, padCtx)
	return res
end

--[[
	A player triggered plot `plotIndex`'s owner-only prompt `kind` ("Lock" | "BuyPad" | "Merge"). Someone else's
	(or a free) plot answers with a toast naming the owner. Merge does nothing with FEATURES.MergeVat3 (the
	owner's client opens the merge menu); without it Merge picks the pair itself (Merge.findPair, the favourite
	kept out) and toasts when there is none. A refused action toasts its reason. Returns the result.
]]
-- The owner's HatchPrompt on a ready Mystery Egg: the HatchEgg action, with a toast when it is refused.
function Actions.triggerHatchPrompt(world: World, userId: number, slimeId: string, now: number, ctx: Context): Result
	local res = Actions.handle(world, userId, "HatchEgg", table.pack(slimeId), now, ctx)
	if not res.ok and res.message then
		World.notify(world, userId, res.message, "info", nil)
	end
	return res
end

function Actions.triggerPlotPrompt(
	world: World,
	userId: number,
	plotIndex: number,
	kind: string,
	now: number,
	ctx: Context
): Result
	local session = World.session(world, userId)
	if not session or session.plotIndex ~= plotIndex then
		local ownerId = world.plots[plotIndex]
		local owner = ownerId and world.sessions[ownerId]
		local text = if owner then `This is {owner.name}'s base` else "Nobody owns this plot"
		World.notify(world, userId, text, "info", nil)
		return fail(text)
	end
	if kind == "Merge" and feature(ctx, "MergeVat3") then
		return OK -- the owner's client opens the merge menu (CONTRACT.md §21.1)
	end
	local args = {}
	if kind == "Merge" then
		local a, b = Merge.findPair(session.data.slimes, World.busySet(world), session.data.favoriteId)
		if not a or not b then
			World.notify(world, userId, "Need two slimes of the same rarity", "info", nil)
			return fail("no pair")
		end
		args = { a, b }
	end
	local res = Actions.handlePlotPad(world, userId, kind, args, now, ctx)
	if not res.ok and res.message then
		World.notify(world, userId, res.message, "info", nil)
	end
	return res
end

-- A player took plot `plotIndex`'s drop tube (any upper jar's DropPrompt, CONTRACT.md §5.3). Anyone may, except a
-- player carrying a slime: they must walk out through the door.
function Actions.useDropTube(world: World, userId: number, plotIndex: number, ctx: Context): Result
	local session = World.session(world, userId)
	if not session then
		return fail("not loaded")
	end
	if session.plotIndex ~= plotIndex then
		-- owners only: a visitor walks the stair down (and a thief carries the slime out through the door)
		local text = "Only this base's owner can take its goo tube. Take the stairs down!"
		World.notify(world, userId, text, "bad", nil)
		return fail(text)
	end
	if Carry.carryingId(world, userId) then
		local text = "You can't take the goo tube while carrying a slime. Walk out through the door!"
		World.notify(world, userId, text, "bad", nil)
		return fail(text)
	end
	if not (ctx.dropDown and ctx.dropDown(userId, plotIndex)) then
		return fail("no drop")
	end
	return OK
end

return Actions
