--!strict
--[[
	One simulated server for one seed: a population of bots joins and leaves
	on their schedules over `days` days, on the real World / GameLoop /
	Sessions. Offline income is paid by Sessions.join from the lastOnline the
	save writes on leave. Time with nobody online is skipped.

	Returns one Record per bot: snapshots at played-hour checkpoints and at
	the end of each calendar day, when each milestone landed, and counters.
]]

local Bot = require("./Bot")
local GameLoop = require("../../../src/server/GameLoop")
local PlayerData = require("../../../src/shared/PlayerData")
local Profiles = require("./Profiles")
local Rng = require("../../../src/shared/Rng")
local Schedule = require("./Schedule")
local Sessions = require("../../../src/server/Sessions")
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

export type Record = {
	profile: string,
	planned: number, -- seconds the schedule had in it
	hours: { [number]: Snap }, -- by index into Options.checkpoints
	days: { [number]: Snap }, -- d x 24 h after the first join (1-based)
	tutorialAt: Snap?,
	rebirthAt: { [number]: Snap }, -- by rebirth level
	final: Snap,
	stats: Bot.Stats,
}

export type Options = {
	seed: number,
	days: number,
	mix: { [string]: number }, -- profile name -> bots
	stagger: number, -- bots show up on a random day in [0, stagger)
	checkpoints: { number }, -- played hours
	plots: number,
}

local Server = {}

local DAY = 86400
Server.T0 = 1_699_833_600 -- a Monday 00:00 UTC, so the Weekend x2 lands on days 5-6

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

function Server.run(options: Options): { Record }
	local T0 = Server.T0
	local rng = Rng.new(options.seed)
	local world = World.new({ now = T0, seed = options.seed, plotCount = options.plots })

	local bots: { Bot.Bot } = {}
	local byId: { [number]: Bot.Bot } = {}
	for _, name in Profiles.names() do
		local profile = assert(Profiles.get(name))
		for _ = 1, options.mix[name] or 0 do
			local id = #bots + 1
			local botRng = Rng.new(options.seed * 1000 + id)
			local startDay = rng:int(0, math.max(options.stagger, 1) - 1)
			local bot = Bot.new(id, profile, botRng, Schedule.build(profile, botRng, T0, options.days, startDay))
			table.insert(bots, bot)
			byId[id] = bot
		end
	end

	local played: { [number]: number } = {}
	local firstJoin: { [number]: number } = {}
	local records: { [number]: Record } = {}
	for _, bot in bots do
		played[bot.id] = 0
		records[bot.id] = {
			profile = bot.profile.name,
			planned = Schedule.total(bot.schedule),
			hours = {},
			days = {},
			tutorialAt = nil,
			rebirthAt = {},
			final = snap(bot, 0, nil, T0),
			stats = bot.stats,
		}
	end

	local tEnd = T0 + options.days * DAY
	local t = T0
	while t < tEnd do
		-- Leaves, then joins.
		local anyOnline = false
		for _, bot in bots do
			if bot.online and t >= bot.stopAt then
				Sessions.leave(world, bot.id, t)
				bot.data.lastOnline = t -- what SaveData.serialize writes on the leave save
				bot.online = false
				bot.task = nil
				bot.next += 1
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
				else
					bot.stats.blockedJoins += 1
					s.start = t + 60 -- server full: try again in a minute
				end
			end
			anyOnline = anyOnline or bot.online
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
					Bot.step(world, bot, t, byId)
					local rec = records[id]
					local before = played[id]
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
		table.insert(out, rec)
	end
	return out
end

return Server
