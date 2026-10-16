--!strict
--[[
	Actions (pure)

	The `Request` RemoteFunction dispatcher (CONTRACT.md §3). Validates every
	argument against Remotes.ACTIONS with Shared.Validate, rate-limits per
	action (Validate.ACTIONS; Sync is free but coalesced by Snapshot), calls
	the system and returns a RequestResult. Never errors.

	`ctx` gives the adapter's world queries:
	  distanceBetween(userIdA, userIdB) -> number (math.huge if unknown)
	  positionOf(userId) -> any? (opaque, stored on dropped wild slimes)
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Appraise = if Shared then require(Shared.Appraise) else require("../shared/Appraise")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Codes = if Shared then require(Shared.Codes) else require("../shared/Codes")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Perks = if Shared then require(Shared.Perks) else require("../shared/Perks")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Progression = if Shared then require(Shared.Progression) else require("../shared/Progression")
local Remotes = if Shared then require(Shared.Remotes) else require("../shared/Remotes")
local Rng = if Shared then require(Shared.Rng) else require("../shared/Rng")
local Shop = if Shared then require(Shared.Shop) else require("../shared/Shop")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")
local Upgrades = if Shared then require(Shared.Upgrades) else require("../shared/Upgrades")
local Validate = if Shared then require(Shared.Validate) else require("../shared/Validate")
local Carry = if script then require(script.Parent.Carry) else require("./Carry")
local MysteryEgg = if script then require(script.Parent.MysteryEgg) else require("./MysteryEgg")
local MergeVat = if script then require(script.Parent.MergeVat) else require("./MergeVat")
local Rebirth = if script then require(script.Parent.Rebirth) else require("./Rebirth")
local StealService = if script then require(script.Parent.StealService) else require("./StealService")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session
type Result = Types.RequestResult

export type Context = {
	distanceBetween: (a: number, b: number) -> number,
	positionOf: (userId: number) -> any?,
	rng: Rng.Rng?, -- Appraise rolls; nil = seeded from the clock and the player
}

local Actions = {}

local function fail(message: string): Result
	return { ok = false, message = message }
end

local OK: Result = table.freeze({ ok = true })

local function result(ok: boolean, message: string?): Result
	if ok then
		return OK
	end
	return fail(message or "failed")
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
		elseif kind == "number" then
			if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
				return nil, "bad argument"
			end
			out[i] = value
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
	World.notify(world, session.userId, `Sold for ${Economy.formatNumber(value :: number)}`, "good", "Cash")
	return OK
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
	World.notify(world, session.userId, `Daily reward: ${Economy.formatNumber(value :: number)}`, "good", "Cash")
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
	World.notify(world, session.userId, `Code redeemed: {what}!`, "good", "Cash")
	return OK
end

local function buyLockUpgrade(world: World, session: Session): Result
	local ok, value = Shop.buyLockUpgrade(session.data)
	if not ok then
		return fail(value :: string)
	end
	local level = session.data.lockLevel
	World.notify(world, session.userId, `Longer locks level {level}! Locks last longer now.`, "good", "Cash")
	return OK
end

local function buySpeedCoil(world: World, session: Session): Result
	local ok, value = Shop.buySpeedCoil(session.data)
	if not ok then
		return fail(value :: string)
	end
	World.notify(world, session.userId, "Speed Coil bought! You run faster now.", "good", "Cash")
	return OK
end

local function buyUpgrade(world: World, session: Session, id: string): Result
	local ok, value = Upgrades.buy(session.data, id)
	if not ok then
		return fail(value :: string)
	end
	local def = Perks.upgradeDef(id)
	local level = session.data.upgrades[id]
	World.notify(world, session.userId, `{def and def.name or id} level {level}!`, "good", "Cash")
	return OK
end

local function appraise(world: World, session: Session, id: string, kind: string, now: number, ctx: Context): Result
	if not Config.FEATURES.Appraise then
		return fail("appraise is off")
	end
	if World.isBusy(world, id) then
		return fail("slime is busy")
	end
	local rng = ctx.rng or Rng.new(math.floor(now * 1000) + session.userId)
	local ok, value = Appraise.reroll(session.data, id, kind, rng)
	if not ok then
		return fail(value :: string)
	end
	local appraisal = value :: Types.Appraisal
	World.notify(world, session.userId, `Appraised for ${Economy.formatNumber(appraisal.cost)}`, "good", "Cash")
	return { ok = true, appraisal = appraisal }
end

local function dispatch(
	world: World,
	session: Session,
	action: string,
	args: { any },
	now: number,
	ctx: Context
): Result
	if action == "Sync" then
		return OK
	elseif action == "Merge" then
		return result(MergeVat.merge(world, session, args[1], args[2]))
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
	elseif action == "BuyPad" then
		return buyPad(world, session)
	elseif action == "Daily" then
		return daily(world, session, now)
	elseif action == "Redeem" then
		return redeem(world, session, args[1], now)
	elseif action == "BuyLockUpgrade" then
		return buyLockUpgrade(world, session)
	elseif action == "BuySpeedCoil" then
		return buySpeedCoil(world, session)
	elseif action == "BuyUpgrade" then
		return buyUpgrade(world, session, args[1])
	elseif action == "Appraise" then
		return appraise(world, session, args[1], args[2], now, ctx)
	elseif action == "BuyEgg" then
		return result(MysteryEgg.buy(world, session, now))
	elseif action == "Slap" then
		local target = args[1]
		return result(StealService.slap(world, session, target, ctx.distanceBetween(session.userId, target), now))
	elseif action == "Drop" then
		if not session.carry then
			return fail("not carrying")
		end
		Carry.release(world, session.userId, now, ctx.positionOf(session.userId), "drop")
		return OK
	end
	return fail("unknown action")
end

function Actions.handle(world: World, userId: number, action: any, raw: { any }, now: number, ctx: Context): Result
	if type(action) ~= "string" or Remotes.ACTIONS[action] == nil then
		return fail("unknown action")
	end
	local session = World.session(world, userId)
	if not session then
		return fail("still loading")
	end
	local args, reason = Actions.parseArgs(action, raw)
	if not args then
		return fail(reason or "bad argument")
	end
	if action ~= "Sync" and not Validate.allow(session.limiter, action, now) then
		return fail("too fast")
	end
	local ok, res = pcall(dispatch, world, session, action, args, now, ctx)
	if not ok then
		return fail("server error")
	end
	-- Sync re-sends (still coalesced to STATE_MIN_INTERVAL); successful actions changed state.
	if res.ok then
		World.markDirty(session)
	end
	return res
end

return Actions
