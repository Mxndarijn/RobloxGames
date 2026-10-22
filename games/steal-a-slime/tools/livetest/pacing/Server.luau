--!strict
--[[
	One simulated server for one seed: a population of bots joins and leaves
	on their schedules over `days` days, on the real World / GameLoop /
	Sessions. Offline income is paid by Sessions.join from the lastOnline the
	save writes on leave. Time with nobody online is skipped. The wall clock
	the game reads (weekly events, the featured Secret) is the simulated one.

	Returns one Record per bot: snapshots at played-hour checkpoints and at
	the end of each calendar day, a time series every `seriesEvery` played
	seconds, when each milestone landed, the cash ledger and the steal events.
]]

local Bot = require("./Bot")
local Config = require("../../../src/shared/Config")
local Friends = require("../../../src/server/Friends")
local GameLoop = require("../../../src/server/GameLoop")
local Ledger = require("./Ledger")
local PlayerData = require("../../../src/shared/PlayerData")
local Profiles = require("./Profiles")
local Rng = require("../../../src/shared/Rng")
local Schedule = require("./Schedule")
local Sessions = require("../../../src/server/Sessions")
local Spawner = require("../../../src/server/Spawner")
local TutorialProgress = require("../../../src/shared/TutorialProgress")
local World = require("../../../src/server/World")

export type Snap = {
	rebirths: number,
	income: number,
	cash: number,
	earned: number,
	pads: number,
	dex: number,
	played: number, -- seconds played so far
	days: number, -- calendar days since the first join
}

-- One point of a bot's time series.
export type Point = {
	played: number,
	days: number,
	cash: number,
	income: number,
	rebirths: number,
	earned: number,
	pads: number,
	dex: number,
	slimes: number,
	by: { [string]: number }, -- cumulative earnings by source (Ledger)
}

export type Record = {
	seed: number,
	id: number,
	profile: string,
	joinDay: number,
	planned: number, -- seconds the schedule had in it
	hours: { [number]: Snap }, -- by index into Options.checkpoints
	days: { [number]: Snap }, -- d x 24 h after the first join (1-based)
	tutorialAt: Snap?,
	rebirthAt: { [number]: Snap }, -- by rebirth level
	milestones: { [string]: Snap }, -- first Rare / Epic / ..., pads, SlimeDex counts, first steal / lock / egg
	rebirthLog: { { level: number, income: number, cash: number } },
	series: { Point },
	earnedBy: { [string]: number },
	spentBy: { [string]: number },
	events: { Bot.StealEvent },
	final: Snap,
	stats: Bot.Stats,
}

export type Late = { profile: string, day: number, count: number }

export type Options = {
	seed: number,
	days: number,
	mix: { [string]: number }, -- profile name -> bots
	stagger: number, -- bots show up on a random day in [0, stagger)
	checkpoints: { number }, -- played hours
	plots: number,
	late: { Late }?, -- bots of a profile that all join on one day, reported as "late-<profile>"
	codes: boolean?, -- every bot redeems all active codes on its first join
	friends: number?, -- friend groups of this size (0 / nil = nobody has friends here)
	party: boolean?, -- friends share one schedule (they are online together)
	seriesEvery: number?, -- played seconds between time series points (default 300)
	startLevel: number?, -- every bot starts at this rebirth level with `startCash` (flip probes)
	startCash: number?,
}

local Server = {}

local DAY = 86400
Server.T0 = 1_699_833_600 -- a Monday 00:00 UTC, so the Weekend x2 lands on days 5-6 and Lucky Saturday on day 5

local function snap(bot: Bot.Bot, played: number, firstJoin: number?, t: number): Snap
	local data = bot.data
	return {
		rebirths = data.rebirths,
		income = PlayerData.incomePerSecond(data),
		cash = data.cash,
		earned = data.totalEarned,
		pads = data.padsUnlocked,
		dex = PlayerData.dexCount(data),
		played = played,
		days = if firstJoin then (t - firstJoin) / DAY else 0,
	}
end

local function copy(map: { [string]: number }): { [string]: number }
	return table.clone(map)
end

-- Milestone names and the check for each; a milestone is stamped the first time its check holds.
local TIER_MILESTONES = { [3] = "Rare", [4] = "Epic", [5] = "Legendary", [6] = "Mythic", [7] = "Secret" }

local function observe(rec: Record, bot: Bot.Bot, played: number, firstJoin: number, t: number)
	local data = bot.data
	local function mark(name: string)
		if not rec.milestones[name] then
			rec.milestones[name] = snap(bot, played, firstJoin, t)
		end
	end
	local top = 0
	for _, s in data.slimes do
		if not s.egg and s.tier > top then
			top = s.tier
		end
	end
	for tier, name in TIER_MILESTONES do
		if top >= tier then
			mark(name)
		end
	end
	for floor = 1, #Config.BASE_FLOORS do
		if data.padsUnlocked >= floor * Config.PADS_PER_FLOOR then
			mark(`pads{floor * Config.PADS_PER_FLOOR}`)
		end
	end
	local dex = PlayerData.dexCount(data)
	for _, m in Config.DEX_MILESTONES.species do
		if dex >= m.count then
			mark(`dex{m.count}`)
		end
	end
	if bot.stats.steals > 0 then
		mark("firstSteal")
	end
	if bot.stats.lockBuys > 0 then
		mark("firstLock")
	end
	if bot.stats.eggsHatched > 0 then
		mark("firstEgg")
	end
end

function Server.run(options: Options): { Record }
	local T0 = Server.T0
	local rng = Rng.new(options.seed)
	local world = World.new({ now = T0, seed = options.seed, plotCount = options.plots })
	Ledger.install()
	local clock = T0
	Spawner.unixTime = function()
		return clock
	end

	local bots: { Bot.Bot } = {}
	local byId: { [number]: Bot.Bot } = {}
	local joinDays: { [number]: number } = {}
	local function add(profile: Profiles.Profile, startDay: number)
		local id = #bots + 1
		local botRng = Rng.new(options.seed * 1000 + id)
		local bot =
			Bot.new(id, profile, botRng, Schedule.build(profile, botRng, T0, options.days, startDay), options.codes)
		if options.startLevel then
			bot.data.rebirths = options.startLevel
			bot.data.cash = options.startCash or 1e15
		end
		table.insert(bots, bot)
		byId[id] = bot
		joinDays[id] = startDay
	end
	for _, name in Profiles.names() do
		local profile = assert(Profiles.get(name))
		for _ = 1, options.mix[name] or 0 do
			add(profile, rng:int(0, math.max(options.stagger, 1) - 1))
		end
	end
	for _, late in options.late or {} do
		local profile = assert(Profiles.variant(late.profile, `late-{late.profile}`))
		for _ = 1, late.count do
			add(profile, late.day)
		end
	end

	-- Friends: bots are dealt into groups of `friends`; a group member is a friend of the others.
	local friends = options.friends or 0
	local cache: Friends.Cache? = nil
	if friends > 1 and #bots > 1 then
		local groups = math.max(1, math.ceil(#bots / friends))
		local function groupOf(id: number): number
			return (id - 1) % groups
		end
		cache = Friends.new(function(a, b)
			return groupOf(a) == groupOf(b)
		end)
		if options.party then
			local leaders: { [number]: Bot.Bot } = {}
			for _, bot in bots do
				local leader = leaders[groupOf(bot.id)]
				if not leader then
					leaders[groupOf(bot.id)] = bot
				else
					bot.schedule = {}
					for _, s in leader.schedule do
						table.insert(bot.schedule, { start = s.start, stop = s.stop })
					end
				end
			end
		end
	end

	local played: { [number]: number } = {}
	local firstJoin: { [number]: number } = {}
	local records: { [number]: Record } = {}
	for _, bot in bots do
		played[bot.id] = 0
		records[bot.id] = {
			seed = options.seed,
			id = bot.id,
			profile = bot.profile.name,
			joinDay = joinDays[bot.id],
			planned = Schedule.total(bot.schedule),
			hours = {},
			days = {},
			tutorialAt = nil,
			rebirthAt = {},
			milestones = {},
			rebirthLog = bot.rebirthLog,
			series = {},
			earnedBy = {},
			spentBy = {},
			events = bot.events,
			final = snap(bot, 0, nil, T0),
			stats = bot.stats,
		}
	end
	local every = options.seriesEvery or 300

	local tEnd = T0 + options.days * DAY
	local t = T0
	while t < tEnd do
		clock = t
		-- Leaves, then joins.
		local anyOnline = false
		local changed = false
		for _, bot in bots do
			if bot.online and t >= bot.stopAt then
				Sessions.leave(world, bot.id, t)
				bot.data.lastOnline = t -- what SaveData.serialize writes on the leave save
				bot.online = false
				bot.task = nil
				bot.next += 1
				changed = true
			end
			local s = bot.schedule[bot.next]
			while not bot.online and s and s.stop <= t do
				bot.next += 1
				s = bot.schedule[bot.next]
			end
			if not bot.online and s and s.start <= t then
				local before = bot.data.cash
				if Sessions.join(world, bot.id, `Bot{bot.id}`, bot.data, t) then
					bot.online = true
					bot.stopAt = s.stop
					bot.nextActAt = t
					bot.stats.offlineCash += math.max(0, bot.data.cash - before)
					firstJoin[bot.id] = firstJoin[bot.id] or t
					changed = true
				else
					bot.stats.blockedJoins += 1
					s.start = t + 60 -- server full: try again in a minute
				end
			end
			anyOnline = anyOnline or bot.online
		end
		if changed and cache then
			Friends.refresh(cache, world, t)
		end

		if not anyOnline then
			-- Nobody here: skip to the next join or the next day boundary.
			local nextAt = tEnd
			for _, bot in bots do
				local s = bot.schedule[bot.next]
				if s then
					nextAt = math.min(nextAt, s.start)
				end
			end
			for id, joined in firstJoin do
				nextAt = math.min(nextAt, joined + (#records[id].days + 1) * DAY)
			end
			if nextAt > t then
				t = nextAt
			else
				t += 1
			end
		else
			GameLoop.step(world, t)
			world.outbox = {}
			for _, bot in bots do
				if bot.online then
					local id = bot.id
					local rec = records[id]
					local before = played[id]
					Bot.step(world, bot, t, byId, before)
					played[id] = before + 1
					for i, hours in options.checkpoints do
						if before < hours * 3600 and played[id] >= hours * 3600 then
							rec.hours[i] = snap(bot, played[id], firstJoin[id], t)
						end
					end
					if not rec.tutorialAt and TutorialProgress.currentId(bot.data) == nil then
						rec.tutorialAt = snap(bot, played[id], firstJoin[id], t)
					end
					local level = bot.data.rebirths
					if level > 0 and not rec.rebirthAt[level] then
						rec.rebirthAt[level] = snap(bot, played[id], firstJoin[id], t)
					end
					if played[id] % 5 == 0 then
						observe(rec, bot, played[id], firstJoin[id], t)
					end
					if played[id] % every == 0 then
						local data = bot.data
						table.insert(rec.series, {
							played = played[id],
							days = (t - firstJoin[id]) / DAY,
							cash = data.cash,
							income = PlayerData.incomePerSecond(data),
							rebirths = data.rebirths,
							earned = data.totalEarned,
							pads = data.padsUnlocked,
							dex = PlayerData.dexCount(data),
							slimes = #data.slimes,
							by = copy(Ledger.book(data).earned),
						})
					end
				end
			end
			t += 1
		end

		for id, joined in firstJoin do
			local rec = records[id]
			local at = joined + (#rec.days + 1) * DAY
			if t >= at then
				rec.days[#rec.days + 1] = snap(byId[id], played[id], joined, at)
			end
		end
	end

	local out = {}
	for _, bot in bots do
		local rec = records[bot.id]
		rec.final = snap(bot, played[bot.id], firstJoin[bot.id], tEnd)
		rec.earnedBy = copy(Ledger.book(bot.data).earned)
		rec.spentBy = copy(Ledger.book(bot.data).spent)
		table.insert(out, rec)
	end
	return out
end

return Server
