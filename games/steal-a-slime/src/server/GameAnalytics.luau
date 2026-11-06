--!strict
--[[
	GameAnalytics (pure over an injected tracker)

	Steal a Slime's analytics catalog and the glue between World.track calls and the shared Analytics tracker
	(shared/luau analytics). Systems queue `{ type = "Analytics", track }` events; the Outbox hands each to `play`
	with the player. Names here are what the Creator Dashboard shows: keep them stable between versions, or the
	before / after comparison breaks.

	- Onboarding funnel: "Joined", then the tutorial steps (TutorialProgress.STEPS), then "Done". Only players who
	  have not finished the tutorial are in it, so returning players do not show up as drop-offs at step 1.
	- "Shop" funnel: Opened -> Tried -> Bought, one session per shop visit.
	- Economy: one currency, "Cash". The transaction is the source or sink ("Income", "Sale", "Upgrade", ...);
	  the sku is what it was for.
	- Progression: "Rebirth", level = rebirth count.
	- Custom events: the list in CATALOG.events.
	- Why players leave: "SessionMinutes" on leave carries the rank, how full the server was on average and whether
	  this was the player's first visit; "LeftAfterRobbed" marks a leave soon after being robbed; "FirstTime" marks
	  the first sale, steal, rebirth, ... per player (value = minutes played until then).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local TutorialProgress = if Shared then require(Shared.TutorialProgress) else require("../shared/TutorialProgress")
local World = if script then require(script.Parent.World) else require("./World")

local GameAnalytics = {}

local onboarding = { "Joined" }
for _, step in TutorialProgress.STEPS do
	table.insert(onboarding, step)
end
table.insert(onboarding, "Done")

GameAnalytics.CURRENCY = "Cash"

GameAnalytics.CATALOG = table.freeze({
	onboarding = table.freeze(onboarding),
	funnels = table.freeze({ Shop = table.freeze({ "Opened", "Tried", "Bought" }) }),
	events = table.freeze({
		"SlimeCaught", -- a wild slime brought home (field: tier, paid / free)
		"SlimeSold", -- (field: tier)
		"StealStarted", -- picked up someone else's slime (field: tier)
		"StealDone", -- delivered it home (field: tier)
		"StealFailed", -- lost it on the way (field: reason)
		"StealBlocked", -- refused at the start (field: reason)
		"Merged", -- a brew collected (field: tier of the result)
		"RecipeFound", -- first time a recipe is brewed (field: recipe)
		"SpeciesFound", -- new Dex species; value = species owned (field: tier)
		"EggHatched", -- (field: tier)
		"BossHits", -- per player online when a boss fight ends; value = their hits (fields: outcome, joined)
		"BossWon", -- the carrier who brought the boss home (field: species)
		"ObbyStarted", -- stepped into the Obby portal (field: first try on this course, or a retry after a clear)
		"ObbyFinished", -- value = run seconds (field: boost earned or not)
		"ObbyNewBest", -- a new best on the course board; value = rank, 0 = past #100 (field: Top 3 / 10 / 100 / Deeper)
		"ObbyFell", -- fell off a section (field: section)
		"TutorialSkipped", -- (field: the step it was on)
		"ShopDenied", -- a shop buy refused (field: shop, reason)
		"RobuxPurchase", -- a Developer Product granted; value = Robux (field: product)
		"GamePassBought", -- (field: pass)
		"QuestClaimed",
		"DailyClaimed", -- value = streak day
		"CodeRedeemed",
		"SessionMinutes", -- on leave; value = minutes played (fields: rank, average server size, first visit or not)
		"RebirthHours", -- on rebirth; value = total hours played so far (field: the rebirth number)
		"SlimeLost", -- the owner's side of StealDone: one of my slimes was stolen (field: tier)
		"LeftAfterRobbed", -- left within ROBBED_LEAVE_SECONDS of a SlimeLost; value = minutes since (field: losses this session)
		"FirstTime", -- once per player (Constants.FIRST_TIMES); value = minutes played until then (field: which)
		"RobuxPrompt", -- a Robux purchase prompt closed (fields: item, bought yes / no)
		"BrokeTopUp", -- no slimes and too little cash: cash raised to BROKE_TOPUP_CASH; value = cash given (field: top-ups this session)
	}),
	currencies = table.freeze({ GameAnalytics.CURRENCY }),
	progressions = table.freeze({ "Rebirth" }),
})

-- "Tier - Rare" for a rarity index (unknown tiers keep their number).
function GameAnalytics.tierField(tier: number?): string
	local rarity = if tier then Config.RARITIES[tier] else nil
	return `Tier - {if rarity then rarity.name else tostring(tier)}`
end

-- The rank title for a rebirth count (Config.REBIRTH_TIERS), for custom fields.
function GameAnalytics.rankField(rebirths: number): string
	local title = "None"
	for _, rank in Config.REBIRTH_TIERS do
		if rebirths >= rank.rebirths then
			title = rank.title
		end
	end
	return `Rank - {title}`
end

-- A leave this soon after losing a slime counts as "LeftAfterRobbed".
GameAnalytics.ROBBED_LEAVE_SECONDS = 300

-- "Server - 2-3" for the average number of players in the server (the player included) while they played.
-- The servers hold Config.PLOT_COUNT players.
function GameAnalytics.serverField(average: number): string
	local bracket = if average < 1.5
		then "Alone"
		elseif average < 3.5 then "2-3"
		elseif average < 5.5 then "4-5"
		else "6+"
	return `Server - {bracket}`
end

-- "Lost - 2-3" for how many slimes a player lost to thieves this session.
local function lossesField(n: number): string
	return `Lost - {if n <= 1 then "1" elseif n <= 3 then "2-3" else "4+"}`
end

-- Queues the "FirstTime" event the first time this player does `id` (one of Constants.FIRST_TIMES), ever.
-- Remembered in the save (`data.firsts`), so it fires once per player, not per session.
function GameAnalytics.firstTime(world: World.World, session: World.Session, id: string)
	local data = session.data
	local firsts = data.firsts or {}
	if firsts[id] or not table.find(Constants.FIRST_TIMES, id) then
		return
	end
	firsts[id] = true
	data.firsts = firsts
	World.markDirty(session)
	World.track(world, session.userId, {
		op = "event",
		name = "FirstTime",
		value = math.floor((data.stats.playSeconds or 0) / 6) / 10,
		fields = { `First - {id}` },
	})
end

-- Economy transaction name per Request action that moves cash. Actions not listed (Admin, ...) are not tracked.
GameAnalytics.TRANSACTIONS = table.freeze({
	Sell = "Sale",
	Daily = "Daily",
	ClaimQuest = "Quest",
	Redeem = "Code",
	BuyPad = "Pad",
	BuySpeedCoil = "SpeedCoil",
	BuyUpgrade = "Upgrade",
	BuyConsumable = "Consumable",
	BuyPvpItem = "PvpItem",
	ShopBuy = "Shop",
	Rebirth = "Rebirth",
	VatStart = "Brew",
	HatchEgg = "Hatch",
	UseCredit = "Credit",
})

-- Which argument names the bought item (the economy sku). Slime ids are never a sku (too many values).
local SKU_ARG: { [string]: number } = { BuyUpgrade = 1, BuyConsumable = 1, BuyPvpItem = 1, ShopBuy = 2 }

-- A custom event per successful action.
local ACTION_EVENTS: { [string]: string } =
	{ Daily = "DailyClaimed", ClaimQuest = "QuestClaimed", Redeem = "CodeRedeemed" }

-- After a Request action ran: logs its cash change (one economy event, sink or source) and its custom event.
function GameAnalytics.afterAction(
	world: World.World,
	session: World.Session,
	action: string,
	args: { any },
	cashBefore: number,
	ok: boolean
)
	if not ok then
		return
	end
	local transaction = GameAnalytics.TRANSACTIONS[action]
	if transaction then
		local delta = session.data.cash - cashBefore
		local index = SKU_ARG[action]
		local sku = if index and type(args[index]) == "string" then args[index] else nil
		if delta > 0 then
			World.trackCash(world, session, "source", transaction, delta, sku)
		elseif delta < 0 then
			World.trackCash(world, session, "spend", transaction, -delta, sku)
		end
	end
	local event = ACTION_EVENTS[action]
	if event then
		World.track(world, session.userId, { op = "event", name = event })
	end
end

-- A boss fight ended (`outcome` "Won" | "Lost - fight" | "Lost - haul"): one BossHits per player online, 0 for
-- those who stayed out, so the dashboard shows how many players join a fight and how much they hit.
function GameAnalytics.bossOver(world: World.World, contributions: { [number]: number }, outcome: string)
	for userId in world.sessions do
		local hits = contributions[userId] or 0
		World.track(world, userId, {
			op = "event",
			name = "BossHits",
			value = hits,
			fields = { `Outcome - {outcome}`, if hits > 0 then "Joined - yes" else "Joined - no" },
		})
		local session = World.session(world, userId)
		if hits > 0 and session then
			GameAnalytics.firstTime(world, session, "Boss")
		end
	end
end

-- The tracker calls GameAnalytics makes (shared/luau Analytics.Tracker, or a fake in specs).
export type Tracker = {
	onboarding: (self: any, key: any, step: string, fields: { string }?) -> (boolean, string?),
	startFunnel: (self: any, key: any, funnel: string, fields: { string }?) -> (boolean, string?),
	funnelStep: (self: any, key: any, funnel: string, step: string, fields: { string }?) -> (boolean, string?),
	event: (self: any, key: any, name: string, value: number?, fields: { string }?) -> (boolean, string?),
	count: (self: any, key: any, name: string, amount: number?, fields: { string }?) -> (boolean, string?),
	source: (self: any, key: any, ...any) -> (boolean, string?),
	spend: (self: any, key: any, ...any) -> (boolean, string?),
	progression: (self: any, key: any, ...any) -> (boolean, string?),
	update: (self: any, now: number?) -> (),
	forget: (self: any, key: any) -> (),
}

export type State = {
	tracker: Tracker,
	now: () -> number, -- the clock join / leave are given (os.clock in a live server)
	inOnboarding: { [any]: boolean },
	joinedAt: { [any]: number },
	firstVisit: { [any]: boolean }, -- no play time saved at join
	-- Players in the server over time: `area` adds up players x seconds since the server started, so a
	-- player's average server size is (area at leave - area at join) / their seconds played.
	online: number,
	area: number,
	areaAt: number,
	areaAtJoin: { [any]: number },
	robbedAt: { [any]: number }, -- when the player last lost a slime (SlimeLost), this session
	losses: { [any]: number }, -- slimes lost this session
}

function GameAnalytics.new(tracker: Tracker, now: (() -> number)?): State
	return {
		tracker = tracker,
		now = now or os.clock,
		inOnboarding = {},
		joinedAt = {},
		firstVisit = {},
		online = 0,
		area = 0,
		areaAt = 0,
		areaAtJoin = {},
		robbedAt = {},
		losses = {},
	}
end

-- Adds the players x seconds since the last join or leave.
local function advance(state: State, now: number)
	if state.online > 0 then
		state.area += state.online * math.max(0, now - state.areaAt)
	end
	state.areaAt = now
end

-- A player's session started. `data` is their loaded PlayerData.
function GameAnalytics.join(state: State, key: any, data: PlayerData.Data, now: number)
	advance(state, now)
	state.online += 1
	state.areaAtJoin[key] = state.area
	state.joinedAt[key] = now
	state.firstVisit[key] = data.stats.playSeconds < 5
	if data.tutorialStep ~= 0 then
		state.inOnboarding[key] = true
		if data.tutorialStep == 1 then
			state.tracker:onboarding(key, "Joined")
		end
	end
end

-- Sends one queued World.track call. Returns the tracker's (ok, reason).
function GameAnalytics.play(state: State, key: any, track: World.Track): (boolean, string?)
	local tracker, op = state.tracker, track.op
	if op == "onboarding" then
		if not state.inOnboarding[key] then
			return false, "NotOnboarding"
		end
		return tracker:onboarding(key, track.name, track.fields)
	elseif op == "startFunnel" then
		return tracker:startFunnel(key, track.name, track.fields)
	elseif op == "funnelStep" then
		return tracker:funnelStep(key, track.name, track.step or "", track.fields)
	elseif op == "event" then
		if track.name == "SlimeLost" then
			state.robbedAt[key] = state.now()
			state.losses[key] = (state.losses[key] or 0) + 1
		end
		return tracker:event(key, track.name, track.value, track.fields)
	elseif op == "count" then
		return tracker:count(key, track.name, track.value, track.fields)
	elseif op == "source" then
		local amount, balance = track.value or 0, track.balance or 0
		return tracker:source(
			key,
			GameAnalytics.CURRENCY,
			amount,
			balance,
			track.name,
			track.sku,
			track.fields,
			track.batch
		)
	elseif op == "spend" then
		local amount, balance = track.value or 0, track.balance or 0
		return tracker:spend(
			key,
			GameAnalytics.CURRENCY,
			amount,
			balance,
			track.name,
			track.sku,
			track.fields,
			track.batch
		)
	elseif op == "progression" then
		return tracker:progression(
			key,
			track.name,
			track.status or "Complete",
			track.value or 0,
			track.step,
			track.fields
		)
	end
	return false, "UnknownOp"
end

-- A player's session ended: logs the minutes played (and a leave right after a robbery), then sends their
-- pending batches.
function GameAnalytics.leave(state: State, key: any, data: { rebirths: number }?, now: number)
	local joinedAt = state.joinedAt[key]
	if joinedAt then
		advance(state, now)
		local seconds = now - joinedAt
		local minutes = math.floor(seconds / 6) / 10
		if minutes > 0 then
			local average = (state.area - (state.areaAtJoin[key] or state.area)) / seconds
			state.tracker:event(key, "SessionMinutes", minutes, {
				GameAnalytics.rankField(if data then data.rebirths else 0),
				GameAnalytics.serverField(average),
				if state.firstVisit[key] then "Visit - First" else "Visit - Later",
			})
		end
		local robbedAt = state.robbedAt[key]
		if robbedAt and now - robbedAt <= GameAnalytics.ROBBED_LEAVE_SECONDS then
			state.tracker:event(
				key,
				"LeftAfterRobbed",
				math.floor((now - robbedAt) / 6) / 10,
				{ lossesField(state.losses[key] or 1) }
			)
		end
		state.online = math.max(0, state.online - 1)
	end
	state.tracker:forget(key)
	state.inOnboarding[key] = nil
	state.joinedAt[key] = nil
	state.firstVisit[key] = nil
	state.areaAtJoin[key] = nil
	state.robbedAt[key] = nil
	state.losses[key] = nil
end

return GameAnalytics
