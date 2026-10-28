--!strict
--[[
	One simulated player: what they do between trips (claim, merge, buy,
	lock, rebirth) and the trips themselves, through the real Actions,
	Carry and StealService calls.

	A trip is two legs. Out: walk to the fountain or a victim's plot
	(profile.walk / 2 at the player's walk speed). Back: walk home carrying
	the slime (at Carry.walkSpeed, so carry slow, Speed Coil and Strong Arms
	count). The slime is grabbed when the out leg ends, so other bots can
	take it first. A stolen slime can be slapped back home on the way if its
	owner is online and defends.

	Every trip is counted (Stats.wild / Stats.steal) and every steal attempt is
	kept as a StealEvent, so the report can weigh stealing against farming.
]]

local Actions = require("../../../src/server/Actions")
local Carry = require("../../../src/server/Carry")
local CashPadService = require("../../../src/server/CashPadService")
local CashPads = require("../../../src/shared/CashPads")
local Config = require("../../../src/shared/Config")
local Consumables = require("../../../src/shared/Consumables")
local Economy = require("../../../src/shared/Economy")
local EggKind = require("../../../src/shared/EggKind")
local Eggs = require("./Eggs")
local Genome = require("../../../src/shared/Genome")
local GrabBlock = require("../../../src/shared/GrabBlock")
local Ledger = require("./Ledger")
local MergeGate = require("../../../src/shared/MergeGate")
local MergeRecipes = require("../../../src/shared/MergeRecipes")
local PlayerData = require("../../../src/shared/PlayerData")
local Profiles = require("./Profiles")
local Progression = require("../../../src/shared/Progression")
local Rng = require("../../../src/shared/Rng")
local Schedule = require("./Schedule")
local Shop = require("../../../src/shared/Shop")
local StealService = require("../../../src/server/StealService")
local TutorialProgress = require("../../../src/shared/TutorialProgress")
local Upgrades = require("../../../src/shared/Upgrades")
local VatState = require("../../../src/shared/VatState")
local World = require("../../../src/server/World")

type World = World.World
type Session = World.Session
type Slime = Genome.Slime

export type Task = {
	kind: "wild" | "steal",
	phase: "out" | "back",
	at: number,
	target: string,
	victim: number?,
	slapAt: number?,
	startedAt: number,
	slime: Slime, -- the slime this trip goes for
	income: number, -- cash/s it adds to this player's plot
	sell: number, -- what it sells for at this player
	victimLoss: number, -- steal: cash/s the victim loses when it works
	victimSell: number, -- steal: what it sells for at the victim
	victimIncome: number, -- steal: the victim's plot income before
	price: number, -- wild: asking price, charged on grab
	paid: number,
	flip: boolean?, -- wild: bought to be sold at once (profile.flip)
}

-- All trips of one kind: tries, successes and what they cost and brought.
export type Agg = {
	tries: number,
	ok: number,
	secs: number, -- time spent on all tries
	okSecs: number, -- time spent on the ones that worked
	gainIncome: number, -- cash/s added by the ones that worked
	gainSell: number, -- sell value added by the ones that worked
	paid: number, -- cash paid for wild slimes (lost ones included)
}

-- One steal attempt, for the steal EV tables.
export type StealEvent = {
	t: number, -- unix seconds the attempt ended
	played: number, -- the thief's played seconds so far
	thief: string, -- profile
	victim: string, -- profile
	outcome: string, -- stolen | slapped | lost | dropped | gone
	tier: number,
	secs: number,
	income: number, -- cash/s the thief gains if it works
	loss: number, -- cash/s the victim loses if it works
	sell: number,
	thiefIncome: number, -- thief's cash/s before
	victimIncome: number,
}

-- One rebirth level of a bot: online seconds, plot income samples and the flips done at that level.
export type LevelStats = {
	secs: number,
	incomeSum: number, -- plot cash/s sampled every 30 s
	samples: number,
	flips: number, -- sold flips
	flipTries: number,
	flipSecs: number, -- trip seconds of all flip tries
	revenue: number,
	paid: number,
	padSales: number, -- slimes sold only to open the flip pad
}

export type Stats = {
	trips: number,
	stealTries: number,
	steals: number,
	slapped: number, -- own steals slapped back
	stolenFrom: number,
	slaps: number, -- thieves this player slapped off
	offlineCash: number,
	blockedJoins: number,
	targeted: number, -- steal attempts against this player's slimes, slapped ones included
	stolenIncome: number, -- cash/s of the slimes lost to thieves
	stolenSell: number, -- sell value of the slimes lost to thieves
	lockBuys: number,
	lockSpent: number,
	lockSeconds: number, -- lock time bought
	lockedSeconds: number, -- online seconds the base was locked (join lock included)
	unlockedSeconds: number,
	friendSeconds: number, -- online seconds with a friend bonus
	eggsHatched: number,
	wild: Agg,
	steal: Agg,
	flip: Agg, -- gainSell = revenue of the sold flips
	levels: { [string]: LevelStats }, -- by rebirth level
}

export type Bot = {
	id: number,
	profile: Profiles.Profile,
	rng: Rng.Rng,
	schedule: { Schedule.Session },
	next: number, -- index of the next session in `schedule`
	online: boolean,
	stopAt: number,
	data: PlayerData.Data,
	task: Task?,
	nextActAt: number,
	stats: Stats,
	events: { StealEvent },
	codes: boolean, -- redeems every active code on its first join
	codesDone: boolean,
	rebirthLog: { { level: number, income: number, cash: number } }, -- income per second and cash at each rebirth, before it
}

local Bot = {}

local CTX: Actions.Context = {
	distanceBetween = function()
		return 0
	end,
	positionOf = function()
		return nil
	end,
}

local function agg(): Agg
	return { tries = 0, ok = 0, secs = 0, okSecs = 0, gainIncome = 0, gainSell = 0, paid = 0 }
end

function Bot.new(
	id: number,
	profile: Profiles.Profile,
	rng: Rng.Rng,
	schedule: { Schedule.Session },
	codes: boolean?
): Bot
	return {
		id = id,
		profile = profile,
		rng = rng,
		schedule = schedule,
		next = 1,
		online = false,
		stopAt = 0,
		data = PlayerData.new(),
		task = nil,
		nextActAt = 0,
		stats = {
			trips = 0,
			stealTries = 0,
			steals = 0,
			slapped = 0,
			stolenFrom = 0,
			slaps = 0,
			offlineCash = 0,
			blockedJoins = 0,
			targeted = 0,
			stolenIncome = 0,
			stolenSell = 0,
			lockBuys = 0,
			lockSpent = 0,
			lockSeconds = 0,
			lockedSeconds = 0,
			unlockedSeconds = 0,
			friendSeconds = 0,
			eggsHatched = 0,
			wild = agg(),
			steal = agg(),
			flip = agg(),
			levels = {},
		},
		events = {},
		codes = codes == true,
		codesDone = false,
		rebirthLog = {},
	}
end

local function act(world: World, bot: Bot, t: number, action: string, ...: any): boolean
	local session = world.sessions[bot.id]
	if not session then
		return false
	end
	session.limiter = {} -- a bot never spams; the rate limits are not what this measures
	local res = Actions.handle(world, bot.id, action, table.pack(...), t, CTX)
	return res.ok
end

local function levelStats(bot: Bot): LevelStats
	local key = tostring(bot.data.rebirths)
	local l = bot.stats.levels[key]
	if not l then
		l = {
			secs = 0,
			incomeSum = 0,
			samples = 0,
			flips = 0,
			flipTries = 0,
			flipSecs = 0,
			revenue = 0,
			paid = 0,
			padSales = 0,
		}
		bot.stats.levels[key] = l
	end
	return l
end

local eggWorth: { [string]: number } = {}

-- What a slime is worth to this bot in base cash/s. An unhatched egg shows no income: a bot that takes eggs
-- counts what its kind is expected to hatch into, less what the incubation costs against an hour of play.
local function worth(bot: Bot, slime: Slime): number
	local kind = EggKind.of(slime)
	if not kind then
		return Genome.baseIncome(slime)
	end
	if not bot.profile.eggs then
		return 0
	end
	local cached = eggWorth[kind.id]
	if not cached then
		cached = Eggs.expectedIncome(kind) * math.max(0, 1 - kind.hatchSeconds / 3600)
		eggWorth[kind.id] = cached
	end
	return cached
end

--[[
	What a smart bot works toward for its next rebirth (Progression.payment): the slimes it keeps, the
	species it still hunts, and three slime ids to put in the vat when a required hybrid's recipe
	(MergeRecipes) is complete on its pads.
]]
local function rebirthNeeds(bot: Bot): ({ [string]: boolean }, { [string]: boolean }, { string }?)
	local keep, missing = {}, {}
	if not bot.profile.smart then
		return keep, missing, nil
	end
	local picked = Progression.payment(bot.data)
	for _, slime in picked do
		keep[slime.id] = true
	end
	local recipeIds: { string }? = nil
	for i, species in Progression.requiredSpecies(bot.data.rebirths) do
		if not picked[i] then
			local recipe = MergeRecipes.recipeFor(species)
			if not recipe then
				missing[species] = true
			else
				local ids = {}
				for _, input in recipe.inputs do
					local found = nil
					for _, s in bot.data.slimes do
						if not keep[s.id] and not s.egg and s.species == input and s.tier == recipe.tier - 1 then
							found = s
							break
						end
					end
					if found then
						keep[found.id] = true
						table.insert(ids, found.id)
					else
						missing[input] = true
					end
				end
				if #ids == 3 and not recipeIds then
					recipeIds = ids
				end
			end
		end
	end
	return keep, missing, recipeIds
end

-- The pad slime this bot would give up first, and its value. Kept slimes, eggs (unsellable), the favourite and vat
-- slimes stay.
local function weakest(world: World, bot: Bot, keep: { [string]: boolean }): (Slime?, number)
	local busy = World.busySet(world)
	-- While the tutorial asks for a merge, a player keeps their Commons to brew them (only Commons merge at first).
	local keepCommons = TutorialProgress.currentId(bot.data) == "Merge"
	local worst, worstValue = nil, math.huge
	for _, s in bot.data.slimes do
		if
			not keep[s.id]
			and not (keepCommons and s.tier == 1)
			and not busy[s.id]
			and not s.egg
			and s.id ~= bot.data.favoriteId
			and not VatState.contains(bot.data, s.id)
		then
			local v = worth(bot, s)
			if v < worstValue then
				worst, worstValue = s, v
			end
		end
	end
	return worst, worstValue
end

-- Every active code, once, in a fixed order (what a player does who reads the codes list).
local function redeemCodes(world: World, bot: Bot, t: number)
	local ids = {}
	for code in Config.CODES do
		table.insert(ids, code)
	end
	table.sort(ids)
	for _, code in ids do
		act(world, bot, t, "Redeem", code)
	end
end

-- Luck Potion: bought when it costs a small share of the cash, drunk as soon as it fits.
local POTION = "LuckPotion"
local function drinkPotions(world: World, bot: Bot, t: number)
	local ratio = bot.profile.consumables
	if not ratio or Consumables.potionFull(world.potionUntil, t) then
		return
	end
	local data = bot.data
	local price = Consumables.price(data, POTION)
	if Consumables.held(data, POTION) < 1 and price and price * ratio < data.cash then
		act(world, bot, t, "BuyConsumable", POTION)
	end
	if Consumables.held(data, POTION) >= 1 then
		act(world, bot, t, "UseConsumable", POTION)
	end
end

-- Three slimes of the highest tier that has three free ones, the weakest first. Never top tier (merging three
-- Secrets only makes one Secret, so a player never does), busy, eggs or the favourite.
local function findTriple(data: PlayerData.Data, busy: { [string]: boolean }): { string }?
	local byTier: { [number]: { Slime } } = {}
	for _, s in data.slimes do
		-- Only rarities the rank may merge, and never three of the top tiers (only a recipe merges those).
		local mergeable = MergeGate.allows(s.tier, data.rebirths) and s.tier < Config.MERGE_MAX_TIER
		if mergeable and not (busy[s.id] or s.egg or s.id == data.favoriteId) then
			byTier[s.tier] = byTier[s.tier] or {}
			table.insert(byTier[s.tier], s)
		end
	end
	for tier = Config.MAX_TIER, 1, -1 do
		local list = byTier[tier]
		if list and #list >= 3 then
			table.sort(list, function(x, y)
				local ix, iy = Genome.baseIncome(x), Genome.baseIncome(y)
				if ix ~= iy then
					return ix < iy
				end
				return x.id < y.id
			end)
			return { list[1].id, list[2].id, list[3].id }
		end
	end
	return nil
end

-- The plot vat (MergeVat): collects a brew whose timer has run out, and clears inputs left waiting (a refused
-- start). Returns whether the vat is free for a new brew.
local function tendVat(world: World, bot: Bot, t: number): boolean
	local data = bot.data
	if VatState.isBrewing(data) then
		if not (VatState.isReady(data, t) and act(world, bot, t, "VatCollect")) then
			return false
		end
	end
	for _, id in VatState.ids(data) do
		act(world, bot, t, "VatRemove", id)
	end
	return #VatState.ids(data) == 0
end

-- Puts three slimes in the (empty) vat and starts the brew; takes them back out when any step is refused.
local function brew(world: World, bot: Bot, t: number, ids: { string }): boolean
	for _, id in ids do
		if not act(world, bot, t, "VatAdd", id) then
			tendVat(world, bot, t)
			return false
		end
	end
	if act(world, bot, t, "VatStart") then
		return true
	end
	tendVat(world, bot, t)
	return false
end

-- Between trips: everything that needs no walk.
-- FEATURES.CashPads: at home between trips the bot walks over every pad with cash waiting on it.
local function collectPads(world: World, bot: Bot, session: Session, t: number)
	if not CashPads.enabled() then
		return
	end
	local nags = {}
	for pad = 1, bot.data.padsUnlocked do
		if CashPads.pile(bot.data, pad) >= 1 then
			CashPadService.touch(world, nags, bot.id, session.plotIndex, pad, t)
		end
	end
end

local function chores(world: World, bot: Bot, session: Session, t: number, keep: { [string]: boolean })
	local data = bot.data
	collectPads(world, bot, session, t)
	act(world, bot, t, "Daily")
	for i = 1, 3 do
		act(world, bot, t, "ClaimQuest", i)
	end
	for _, s in table.clone(data.slimes) do
		if s.egg and act(world, bot, t, "HatchEgg", s.id) then
			bot.stats.eggsHatched += 1
		end
	end
	if not StealService.isLocked(session, t) and bot.rng:float() < bot.profile.lock then
		local cash, until0 = data.cash, session.lockUntil
		if act(world, bot, t, "Lock") then
			bot.stats.lockBuys += 1
			bot.stats.lockSpent += cash - data.cash
			bot.stats.lockSeconds += session.lockUntil - math.max(until0, t)
		end
	end
	local busy = World.busySet(world)
	for id in keep do
		busy[id] = true
	end
	if tendVat(world, bot, t) then
		local ids = findTriple(data, busy)
		if ids then
			brew(world, bot, t, ids)
		end
	end
	local padCost = Economy.padCost(data.padsUnlocked)
	if padCost and padCost * bot.profile.padRatio < data.cash then
		act(world, bot, t, "BuyPad")
	end
	for _, u in Upgrades.view(data) do
		if u.price and u.price * bot.profile.upgradeRatio < data.cash then
			act(world, bot, t, "BuyUpgrade", u.id)
		end
	end
	if not data.speedCoil and Config.SPEED_COIL_PRICE * bot.profile.upgradeRatio < data.cash then
		act(world, bot, t, "BuySpeedCoil")
	end
	drinkPotions(world, bot, t)
end

-- A Mystery Egg this bot's rank can't grab or steal yet (EggKind.grabBlock).
local function eggLocked(bot: Bot, slime: Slime): boolean
	local kind = EggKind.of(slime)
	return kind ~= nil and EggKind.grabBlock(bot.data.rebirths, kind) ~= nil
end

-- Best wild slime this bot can afford, by value (Mystery Eggs are free); a missing rebirth species wins outright.
local function pickWild(world: World, bot: Bot, missing: { [string]: boolean }): (string?, number)
	local options = {}
	local best, bestScore, bestValue = nil, -1, 0
	for id, wild in world.wild do
		if
			not wild.boss
			and wild.price <= bot.data.cash
			and not world.carriedBy[id]
			and not eggLocked(bot, wild.slime)
			and GrabBlock.rebirthsFor(wild.slime) <= bot.data.rebirths
		then
			local v = worth(bot, wild.slime)
			local score = v + (if missing[wild.slime.species] and not wild.slime.egg then 1e300 else 0)
			table.insert(options, id)
			if score > bestScore then
				best, bestScore, bestValue = id, score, v
			end
		end
	end
	if #options > 0 and bot.rng:float() < bot.profile.mistake then
		table.sort(options) -- table order is not stable across runs; ids are
		local id = bot.rng:pick(options)
		return id, worth(bot, world.wild[id].slime)
	end
	return best, bestValue
end

-- Best unlocked slime on another online plot, by value (a brewing vat's inputs can't be stolen).
local function pickSteal(world: World, bot: Bot, t: number): (string?, number?, number)
	local best, victim, bestValue = nil, nil, -1
	for userId, other in world.sessions do
		if userId ~= bot.id and not StealService.isLocked(other, t) then
			for _, s in other.data.slimes do
				if
					not World.isBusy(world, s.id)
					and not VatState.isLocked(other.data, s.id)
					and not eggLocked(bot, s)
				then
					local v = worth(bot, s)
					if v > bestValue then
						best, victim, bestValue = s.id, userId, v
					end
				end
			end
		end
	end
	return best, victim, bestValue
end

-- Pads that hold nothing.
local function freePads(data: PlayerData.Data): number
	local n = data.padsUnlocked
	for _, s in data.slimes do
		if s.pad then
			n -= 1
		end
	end
	return n
end

-- Wild slime with the best sell-minus-price profit this bot can pay for. Eggs can't be sold, so they are never a flip.
local function pickFlip(world: World, bot: Bot): (string?, number)
	local best, bestProfit = nil, 0
	local ids = {}
	for id in world.wild do
		table.insert(ids, id)
	end
	table.sort(ids) -- table order is not stable across runs; ids are
	for _, id in ids do
		local wild = world.wild[id]
		local sell = Economy.sellPrice(wild.slime)
		if sell and not wild.boss and wild.price <= bot.data.cash and not world.carriedBy[id] then
			local profit = sell - wild.price
			if profit > bestProfit then
				best, bestProfit = id, profit
			end
		end
	end
	return best, bestProfit
end

local function legSeconds(bot: Bot, speed: number): number
	return bot.profile.walk / 2 * Config.BASE_WALK_SPEED / math.max(speed, 1)
end

-- Cash/s a slime adds to `data`'s plot, and what it sells for there. An egg counts what it is expected to hatch
-- into and sells for nothing (eggs can't be sold).
local function valueFor(bot: Bot, data: PlayerData.Data, slime: Slime): (number, number)
	local kind = EggKind.of(slime)
	if kind then
		return Eggs.expectedIncome(kind) * Economy.rebirthMultiplier(data.rebirths), 0
	end
	return PlayerData.slimeIncome(data, slime), Economy.sellPrice(slime) or 0
end

local function newTask(
	bot: Bot,
	kind: "wild" | "steal",
	t: number,
	at: number,
	target: string,
	slime: Slime,
	price: number,
	victimBot: Bot?
): Task
	local income, sell = valueFor(bot, bot.data, slime)
	local victimLoss, victimSell, victimIncome = 0, 0, 0
	if victimBot then
		victimLoss, victimSell = valueFor(victimBot, victimBot.data, slime)
		victimIncome = PlayerData.incomePerSecond(victimBot.data)
	end
	return {
		kind = kind,
		phase = "out",
		at = at,
		target = target,
		victim = if victimBot then victimBot.id else nil,
		slapAt = nil,
		startedAt = t,
		slime = slime,
		income = income,
		sell = sell,
		victimLoss = victimLoss,
		victimSell = victimSell,
		victimIncome = victimIncome,
		price = price,
		paid = 0,
	}
end

-- Plans the next trip, or waits a little when nothing is worth the walk.
local function plan(
	world: World,
	bot: Bot,
	t: number,
	keep: { [string]: boolean },
	missing: { [string]: boolean },
	floor: number,
	bots: { [number]: Bot }
)
	local wildId, wildValue = pickWild(world, bot, missing)
	local out = legSeconds(bot, Shop.walkSpeed(bot.data))
	-- A flipper keeps one pad empty to deposit on: normal catches only use a pad beyond that one.
	local mode = bot.profile.flip
	local hasPad = if mode then freePads(bot.data) > 1 else PlayerData.freePad(bot.data) ~= nil
	local takesWild = wildId ~= nil
		and (hasPad or wildValue > floor or missing[world.wild[wildId].slime.species] == true)
	if mode == "always" or (mode == "full" and not hasPad) then
		-- full: every pad but the flip pad is taken, so flip instead of upgrading; always: flip instead of filling pads.
		local flipId = pickFlip(world, bot)
		if flipId and not (takesWild and missing[world.wild[wildId :: string].slime.species]) then
			if not PlayerData.freePad(bot.data) then
				local worst = weakest(world, bot, keep)
				if worst and act(world, bot, t, "Sell", worst.id) then
					levelStats(bot).padSales += 1
				end
			end
			if PlayerData.freePad(bot.data) then
				local wild = world.wild[flipId]
				local task = newTask(bot, "wild", t, t + out, flipId, wild.slime, wild.price, nil)
				task.flip = true
				bot.task = task
				levelStats(bot).flipTries += 1
				return
			end
		end
	end
	if bot.rng:float() < bot.profile.steal then
		local id, victim, v = pickSteal(world, bot, t)
		if id and victim and v > wildValue and (hasPad or v > floor) then
			local victimBot = bots[victim]
			local _, slime = World.ownerOf(world, id)
			if slime then
				bot.stats.stealTries += 1
				victimBot.stats.targeted += 1
				bot.task = newTask(bot, "steal", t, t + out, id, slime, 0, victimBot)
				return
			end
		end
	end
	if wildId and takesWild then
		local wild = world.wild[wildId]
		-- The game refuses a grab with a full plot, so a player sells first.
		if not PlayerData.freePad(bot.data) then
			local worst, worstValue = weakest(world, bot, keep)
			if worst and (worstValue < wildValue or missing[wild.slime.species] == true) then
				act(world, bot, t, "Sell", worst.id)
			end
		end
		bot.task = newTask(bot, "wild", t, t + out, wildId, wild.slime, wild.price, nil)
		return
	end
	bot.nextActAt = t + bot.profile.think + 5
end

-- Makes room for the slime being carried home: sells the weakest pad slime when it is worth less.
local function makeRoom(world: World, bot: Bot, t: number, carried: Slime, keep: { [string]: boolean }): boolean
	if PlayerData.freePad(bot.data) then
		return true
	end
	local worst, worstValue = weakest(world, bot, keep)
	local _, missing = rebirthNeeds(bot)
	if worst and (worstValue < worth(bot, carried) or (carried.species ~= nil and missing[carried.species])) then
		return act(world, bot, t, "Sell", worst.id)
	end
	return false
end

local function finishTrip(bot: Bot, t: number, outcome: string, bots: { [number]: Bot }, played: number)
	local task = bot.task :: Task
	local secs = t - task.startedAt
	local totals = if task.kind == "steal" then bot.stats.steal elseif task.flip then bot.stats.flip else bot.stats.wild
	if task.flip then
		levelStats(bot).flipSecs += secs
	end
	totals.tries += 1
	totals.secs += secs
	totals.paid += task.paid
	local worked = outcome == "stolen" or outcome == "caught"
	if worked then
		totals.ok += 1
		totals.okSecs += secs
		totals.gainIncome += task.income
		totals.gainSell += task.sell
	end
	if task.kind == "steal" then
		local victim = task.victim and bots[task.victim]
		table.insert(bot.events, {
			t = t,
			played = played,
			thief = bot.profile.name,
			victim = if victim then victim.profile.name else "?",
			outcome = outcome,
			tier = task.slime.tier,
			secs = secs,
			income = task.income,
			loss = task.victimLoss,
			sell = task.sell,
			thiefIncome = PlayerData.incomePerSecond(bot.data),
			victimIncome = task.victimIncome,
		})
		if worked and victim then
			victim.stats.stolenFrom += 1
			victim.stats.stolenIncome += task.victimLoss
			victim.stats.stolenSell += task.victimSell
		end
	end
	bot.task = nil
	bot.stats.trips += 1
	bot.nextActAt = t + bot.profile.think
	local afk = bot.profile.afk
	if afk and bot.rng:float() < afk then
		bot.nextActAt = t + (bot.profile.afkSeconds or 300)
	end
end

local function stepTask(world: World, bot: Bot, session: Session, t: number, bots: { [number]: Bot }, played: number)
	local task = bot.task :: Task
	if t < task.at and not (task.slapAt and t >= task.slapAt) then
		return
	end
	if task.phase == "out" then
		local wild = world.wild[task.target]
		local price = if wild then wild.price else 0
		local ok = Carry.grab(world, bot.id, task.target, 0, t)
		if not ok then
			finishTrip(bot, t, "lost", bots, played)
			return
		end
		task.paid = price
		task.phase = "back"
		task.at = t + legSeconds(bot, Carry.walkSpeed(session))
		local victim = task.victim and bots[task.victim]
		if victim and victim.online and victim.rng:float() < victim.profile.defend then
			task.slapAt = t + (task.at - t) * (0.2 + 0.6 * victim.rng:float())
		end
		return
	end
	local carry = session.carry
	if not carry then
		finishTrip(bot, t, "gone", bots, played) -- the owner left and the slime went home
		return
	end
	if task.slapAt and t >= task.slapAt then
		StealService.escape(world, session, t, "slap")
		bot.stats.slapped += 1
		local victim = task.victim and bots[task.victim]
		if victim then
			victim.stats.slaps += 1
		end
		finishTrip(bot, t, "slapped", bots, played)
		return
	end
	local keep = rebirthNeeds(bot)
	if makeRoom(world, bot, t, carry.slime, keep) and Carry.deposit(world, bot.id, t) then
		if task.kind == "steal" then
			bot.stats.steals += 1
		end
		if task.flip then
			local before = bot.data.cash
			if act(world, bot, t, "Sell", carry.slime.id) then
				local level = levelStats(bot)
				level.flips += 1
				level.revenue += bot.data.cash - before
				level.paid += task.paid
				bot.stats.flip.gainSell += bot.data.cash - before
			end
		end
		finishTrip(bot, t, if task.kind == "steal" then "stolen" else "caught", bots, played)
		return
	end
	Carry.release(world, bot.id, t, nil, "drop")
	finishTrip(bot, t, "dropped", bots, played)
end

-- One tick for an online bot. `played` is the bot's played seconds so far (for the event log).
function Bot.step(world: World, bot: Bot, t: number, bots: { [number]: Bot }, played: number?)
	local session = world.sessions[bot.id]
	if not session then
		return
	end
	local stats = bot.stats
	if StealService.isLocked(session, t) then
		stats.lockedSeconds += 1
	else
		stats.unlockedSeconds += 1
	end
	if (bot.data.friendBonus or 0) > 0 then
		stats.friendSeconds += 1
	end
	local level = levelStats(bot)
	level.secs += 1
	if math.floor(t) % 30 == 0 then
		level.incomeSum += PlayerData.incomePerSecond(bot.data)
		level.samples += 1
	end
	session.home = bot.task == nil -- standing at home between trips: Mystery Eggs incubate faster
	if bot.codes and not bot.codesDone then
		bot.codesDone = true
		redeemCodes(world, bot, t)
	end
	if bot.task then
		stepTask(world, bot, session, t, bots, played or 0)
		return
	end
	if t < bot.nextActAt then
		return
	end
	local vatFree = tendVat(world, bot, t)
	local keep, missing, recipeIds = rebirthNeeds(bot)
	if vatFree and recipeIds and brew(world, bot, t, recipeIds) then
		keep, missing = rebirthNeeds(bot)
	end
	chores(world, bot, session, t, keep)
	local cashBefore, incomeBefore, level = bot.data.cash, PlayerData.incomePerSecond(bot.data), bot.data.rebirths
	if bot.profile.rebirth ~= false and act(world, bot, t, "Rebirth") then
		Ledger.note(bot.data, "spent", "rebirth", Economy.rebirthCost(level))
		table.insert(bot.rebirthLog, { level = level + 1, income = incomeBefore, cash = cashBefore })
		keep, missing = rebirthNeeds(bot)
	end
	local _, floor = weakest(world, bot, keep)
	plan(world, bot, t, keep, missing, floor, bots)
end

return Bot
