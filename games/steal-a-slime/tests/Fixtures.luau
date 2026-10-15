--!strict
-- Test helpers: hand-built slimes and profiles.

local Config = require("../src/shared/Config")
local Genome = require("../src/shared/Genome")
local PlayerData = require("../src/shared/PlayerData")

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
		mutation = "None",
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

return Fixtures
