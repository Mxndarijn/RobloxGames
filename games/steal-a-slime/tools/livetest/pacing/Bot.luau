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
]]

local Actions = require("../../../src/server/Actions")
local Carry = require("../../../src/server/Carry")
local Config = require("../../../src/shared/Config")
local Economy = require("../../../src/shared/Economy")
local Genome = require("../../../src/shared/Genome")
local Merge = require("../../../src/shared/Merge")
local MergeRecipes = require("../../../src/shared/MergeRecipes")
local PlayerData = require("../../../src/shared/PlayerData")
local Profiles = require("./Profiles")
local Progression = require("../../../src/shared/Progression")
local Rng = require("../../../src/shared/Rng")
local Schedule = require("./Schedule")
local Shop = require("../../../src/shared/Shop")
local StealService = require("../../../src/server/StealService")
local Upgrades = require("../../../src/shared/Upgrades")
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

function Bot.new(id: number, profile: Profiles.Profile, rng: Rng.Rng, schedule: { Schedule.Session }): Bot
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
		},
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

local function value(slime: Slime): number
	return Genome.baseIncome(slime)
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

-- The pad slime this bot would give up first, and its value. Kept slimes, eggs (unsellable) and the favourite stay.
local function weakest(world: World, bot: Bot, keep: { [string]: boolean }): (Slime?, number)
	local busy = World.busySet(world)
	local worst, worstValue = nil, math.huge
	for _, s in bot.data.slimes do
		if not keep[s.id] and not busy[s.id] and not s.egg and s.id ~= bot.data.favoriteId then
			local v = value(s)
			if v < worstValue then
				worst, worstValue = s, v
			end
		end
	end
	return worst, worstValue
end

-- Between trips: everything that needs no walk.
local function chores(world: World, bot: Bot, session: Session, t: number, keep: { [string]: boolean })
	local data = bot.data
	act(world, bot, t, "Daily")
	for i = 1, 3 do
		act(world, bot, t, "ClaimQuest", i)
	end
	for _, s in table.clone(data.slimes) do
		if s.egg then
			act(world, bot, t, "HatchEgg", s.id)
		end
	end
	if not StealService.isLocked(session, t) and bot.rng:float() < bot.profile.lock then
		act(world, bot, t, "Lock")
	end
	local busy = World.busySet(world)
	for id in keep do
		busy[id] = true
	end
	for _ = 1, 4 do
		local a, b = Merge.findPair(data.slimes, busy, data.favoriteId)
		if not (a and b and act(world, bot, t, "Merge", a, b)) then
			break
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
end

-- Best wild slime this bot can afford, by value; a missing rebirth species wins outright.
local function pickWild(world: World, bot: Bot, missing: { [string]: boolean }): (string?, number)
	local options = {}
	local best, bestScore, bestValue = nil, -1, 0
	for id, wild in world.wild do
		if not wild.boss and wild.price <= bot.data.cash and not world.carriedBy[id] then
			local v = value(wild.slime)
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
		return id, value(world.wild[id].slime)
	end
	return best, bestValue
end

-- Best unlocked slime on another online plot, by value.
local function pickSteal(world: World, bot: Bot, t: number): (string?, number?, number)
	local best, victim, bestValue = nil, nil, -1
	for userId, other in world.sessions do
		if userId ~= bot.id and not StealService.isLocked(other, t) then
			for _, s in other.data.slimes do
				if not World.isBusy(world, s.id) then
					local v = value(s)
					if v > bestValue then
						best, victim, bestValue = s.id, userId, v
					end
				end
			end
		end
	end
	return best, victim, bestValue
end

local function legSeconds(bot: Bot, speed: number): number
	return bot.profile.walk / 2 * Config.BASE_WALK_SPEED / math.max(speed, 1)
end

-- Plans the next trip, or waits a little when nothing is worth the walk.
local function plan(world: World, bot: Bot, t: number, missing: { [string]: boolean }, floor: number)
	local wildId, wildValue = pickWild(world, bot, missing)
	local hasPad = PlayerData.freePad(bot.data) ~= nil
	local out = legSeconds(bot, Shop.walkSpeed(bot.data))
	if bot.rng:float() < bot.profile.steal then
		local id, victim, v = pickSteal(world, bot, t)
		if id and v > wildValue and (hasPad or v > floor) then
			bot.stats.stealTries += 1
			bot.task = { kind = "steal", phase = "out", at = t + out, target = id, victim = victim }
			return
		end
	end
	if wildId and (hasPad or wildValue > floor or missing[world.wild[wildId].slime.species]) then
		bot.task = { kind = "wild", phase = "out", at = t + out, target = wildId }
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
	if worst and worstValue < value(carried) then
		return act(world, bot, t, "Sell", worst.id)
	end
	return false
end

local function finishTrip(bot: Bot, t: number)
	bot.task = nil
	bot.stats.trips += 1
	bot.nextActAt = t + bot.profile.think
end

local function stepTask(world: World, bot: Bot, session: Session, t: number, bots: { [number]: Bot })
	local task = bot.task :: Task
	if t < task.at and not (task.slapAt and t >= task.slapAt) then
		return
	end
	if task.phase == "out" then
		local ok = Carry.grab(world, bot.id, task.target, 0, t)
		if not ok then
			finishTrip(bot, t)
			return
		end
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
		finishTrip(bot, t) -- the owner left and the slime went home
		return
	end
	if task.slapAt and t >= task.slapAt then
		StealService.escape(world, session, t, "slap")
		bot.stats.slapped += 1
		local victim = task.victim and bots[task.victim]
		if victim then
			victim.stats.slaps += 1
		end
		finishTrip(bot, t)
		return
	end
	local keep = rebirthNeeds(bot)
	if makeRoom(world, bot, t, carry.slime, keep) and Carry.deposit(world, bot.id, t) then
		if task.kind == "steal" then
			bot.stats.steals += 1
			local victim = task.victim and bots[task.victim]
			if victim then
				victim.stats.stolenFrom += 1
			end
		end
	else
		Carry.release(world, bot.id, t, nil, "drop")
	end
	finishTrip(bot, t)
end

-- One tick for an online bot.
function Bot.step(world: World, bot: Bot, t: number, bots: { [number]: Bot })
	local session = world.sessions[bot.id]
	if not session then
		return
	end
	if bot.task then
		stepTask(world, bot, session, t, bots)
		return
	end
	if t < bot.nextActAt then
		return
	end
	local keep, missing, recipeIds = rebirthNeeds(bot)
	if recipeIds and act(world, bot, t, "Merge3", recipeIds[1], recipeIds[2], recipeIds[3]) then
		keep, missing = rebirthNeeds(bot)
	end
	chores(world, bot, session, t, keep)
	if act(world, bot, t, "Rebirth") then
		keep, missing = rebirthNeeds(bot)
	end
	local _, floor = weakest(world, bot, keep)
	plan(world, bot, t, missing, floor)
end

return Bot
