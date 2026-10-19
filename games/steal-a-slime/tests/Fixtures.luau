--!strict
-- Test helpers: hand-built slimes and profiles.

local Config = require("../src/shared/Config")
local Genome = require("../src/shared/Genome")
local PlayerData = require("../src/shared/PlayerData")
local SpeciesDex = require("../src/shared/SpeciesDex")

local Fixtures = {}

function Fixtures.slime(id: string, tier: number?, overrides: { [string]: any }?): Genome.Slime
	local s: Genome.Slime = {
		id = id,
		name = "Blorp",
		tier = tier or 1,
		color = { 200, 50, 100 },
		size = 1,
		pattern = "Plain",
		eyes = "Round",
		mouth = "Smile",
		pad = nil,
	}
	if overrides then
		for k, v in overrides do
			(s :: any)[k] = v
		end
	end
	return s
end

-- Fresh profile with the given slimes placed on pads 1..n.
function Fixtures.data(slimes: { Genome.Slime }?, cash: number?): PlayerData.Data
	local data = PlayerData.new()
	data.padsUnlocked = Config.PADS_MAX
	for _, s in slimes or {} do
		PlayerData.addSlime(data, s)
	end
	if cash then
		data.cash = cash
	end
	return data
end

-- Roll function that returns the given values in order (then repeats the last).
function Fixtures.rolls(values: { number }): () -> number
	local i = 0
	return function()
		i = math.min(i + 1, #values)
		return values[i]
	end
end

-- Recipe and featured-week sources for SpeciesDex.view: `recipes` maps hybrid id -> { inputs, hint }, `weeks`
-- event id -> unix week start. Missing = no recipe / not scheduled.
function Fixtures.dexSources(
	recipes: { [string]: SpeciesDex.Recipe }?,
	weeks: { [string]: number }?
): SpeciesDex.Sources
	return {
		recipeFor = function(id: string): SpeciesDex.Recipe?
			return if recipes then recipes[id] else nil
		end,
		featuredWeek = function(id: string, _now: number): number?
			return if weeks then weeks[id] else nil
		end,
	}
end

-- A State.dex (SpeciesDex.view) for a player who found `found` (species ids).
function Fixtures.dex(found: { string }?, sources: SpeciesDex.Sources?, now: number?): SpeciesDex.View
	local data = { found = {} }
	for _, id in found or {} do
		data.found[id] = true
	end
	return SpeciesDex.view(data, now or 0, sources or Fixtures.dexSources())
end

return Fixtures
