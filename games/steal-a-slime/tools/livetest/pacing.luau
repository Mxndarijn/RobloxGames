--!strict
--[[
	Pacing estimate (pure modules, no Roblox): one greedy player alone on a
	server, played second by second on the real World / GameLoop / Actions.

	  lune run tools/livetest/pacing [hours] [seed] [walkSeconds]

	Every WALK seconds the player brings home the best wild slime they can
	afford (one trip = WALK seconds), sells the weakest pad slime when the plot
	is full and the new one is better, merges any pair, buys a pad when it
	costs under a third of their cash, an upgrade under a fifth, and rebirths as
	soon as they can. No steals, no rain luck beyond the schedule, no offline
	time. Prints when each tutorial step, rebirth and rank lands.
]]

local process = require("@lune/process")

local Actions = require("../../src/server/Actions")
local Carry = require("../../src/server/Carry")
local Config = require("../../src/shared/Config")
local Economy = require("../../src/shared/Economy")
local GameLoop = require("../../src/server/GameLoop")
local Genome = require("../../src/shared/Genome")
local Merge = require("../../src/shared/Merge")
local Perks = require("../../src/shared/Perks")
local PlayerData = require("../../src/shared/PlayerData")
local Sessions = require("../../src/server/Sessions")
local TutorialProgress = require("../../src/shared/TutorialProgress")
local Upgrades = require("../../src/shared/Upgrades")
local World = require("../../src/server/World")

local HOURS = tonumber(process.args[1]) or 6
local SEED = tonumber(process.args[2]) or 1
local WALK = tonumber(process.args[3]) or 20 -- seconds per volcano -> plot round trip
local T0 = 1_700_000_000
local ID = 1

local world = World.new({ now = T0, seed = SEED })
local session = assert(Sessions.join(world, ID, "Pacer", PlayerData.new(), T0))
local data = session.data
local ctx = {
	distanceBetween = function()
		return 0
	end,
	positionOf = function()
		return nil
	end,
}

local function fmt(seconds: number): string
	return string.format("%dh%02dm", seconds // 3600, (seconds % 3600) // 60)
end
local events = {}
local function log(t: number, text: string)
	table.insert(events, `{fmt(t - T0)}  {text}`)
end
local function act(t: number, action: string, ...: any)
	session.limiter = {}
	return Actions.handle(world, ID, action, table.pack(...), t, ctx)
end

local lastStep = TutorialProgress.currentId(data)
local lastTrip = T0
local rebirthAt = T0
for t = T0, T0 + HOURS * 3600 do
	GameLoop.step(world, t)
	world.outbox = {}
	if t - lastTrip >= WALK then
		lastTrip = t
		-- Best affordable wild slime by income.
		local best, bestIncome = nil, -1
		for id, wild in world.wild do
			if wild.price <= data.cash and not world.carriedBy[id] then
				local income = Genome.baseIncome(wild.slime)
				if income > bestIncome then
					best, bestIncome = id, income
				end
			end
		end
		if best then
			if not PlayerData.freePad(data) then
				local weakest, weakIncome = nil, math.huge
				for _, s in data.slimes do
					local income = Genome.baseIncome(s)
					if income < weakIncome and s.id ~= data.favoriteId then
						weakest, weakIncome = s, income
					end
				end
				if weakest and weakIncome < bestIncome then
					act(t, "Sell", weakest.id)
				end
			end
			if PlayerData.freePad(data) and Carry.grab(world, ID, best, 0, t) then
				Carry.deposit(world, ID)
			end
		end
		if session.lockUntil < t then
			act(t, "Lock")
		end
		local a, b = Merge.findPair(data.slimes, World.busySet(world), data.favoriteId)
		if a and b then
			act(t, "Merge", a, b)
		end
		local padCost = Economy.padCost(data.padsUnlocked)
		if padCost and padCost * 3 < data.cash then
			act(t, "BuyPad")
		end
		for _, u in Upgrades.view(data) do
			if u.price and u.price * 5 < data.cash then
				act(t, "BuyUpgrade", u.id)
			end
		end
		if not data.speedCoil and Config.SPEED_COIL_PRICE * 5 < data.cash then
			act(t, "BuySpeedCoil")
		end
		if act(t, "Rebirth").ok then
			log(
				t,
				`rebirth {data.rebirths} ({Perks.title(data.rebirths)}), {fmt(t - rebirthAt)} after the last; next costs ${Economy.formatNumber(
					Economy.rebirthCost(data.rebirths)
				)}`
			)
			rebirthAt = t
		end
	end
	local step = TutorialProgress.currentId(data)
	if step ~= lastStep then
		log(t, `tutorial: {lastStep} done -> {step or "finished"}`)
		lastStep = step
	end
end

print(`pacing: seed {SEED}, {HOURS} h, one trip per {WALK} s, no steals / offline`)
for _, line in events do
	print(`  {line}`)
end
print(
	`  end: rebirths {data.rebirths}, income ${Economy.formatNumber(PlayerData.incomePerSecond(data))}/s, cash ${Economy.formatNumber(
		data.cash
	)}, pads {data.padsUnlocked}, dex {PlayerData.dexCount(data)}, goal stages paid {(function()
		local n = 0
		for _, s in data.goals do
			n += s
		end
		return n
	end)()}`
)
