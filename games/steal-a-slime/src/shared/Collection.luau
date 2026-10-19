--!strict
--[[
	Collection

	SlimeDex milestone rewards (Config.DEX_MILESTONES, CONTRACT.md §36.3): one ladder, species found (of
	SpeciesDex.TOTAL). Each milestone pays cash
	(x rebirthMultiplier) and a permanent income bonus (Perks.dexBonus). Paid automatically by `check`;
	data.speciesRewards counts the milestones paid. `view` is State.dexRewards.
	Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local SpeciesDex = if script then require(script.Parent.SpeciesDex) else require("./SpeciesDex")

type Data = PlayerData.Data

export type Ladder = string -- always "species"
export type Paid = { ladder: Ladder, count: number, reward: number, bonus: number }
export type View = { ladder: Ladder, count: number, reward: number, bonus: number, claimed: boolean }

local Collection = {}

local LADDER: Ladder = "species"
Collection.LADDERS = table.freeze({ LADDER })

-- Milestones already paid.
function Collection.paid(data: Data): number
	return math.clamp(math.floor(tonumber(data.speciesRewards) or 0), 0, #Config.DEX_MILESTONES.species)
end

-- The count the ladder measures: species found.
function Collection.progress(data: Data): number
	return SpeciesDex.count(data)
end

-- Pays every reached, unpaid milestone. Returns what was paid.
function Collection.check(data: Data): { Paid }
	local out: { Paid } = {}
	local milestones = Config.DEX_MILESTONES.species
	local have = Collection.progress(data)
	local done = Collection.paid(data)
	while done < #milestones and have >= milestones[done + 1].count do
		done += 1
		local milestone = milestones[done]
		local reward = math.floor(milestone.reward * Economy.rebirthMultiplier(data.rebirths))
		data.speciesRewards = done
		PlayerData.earn(data, reward)
		local paid: Paid = { ladder = LADDER, count = milestone.count, reward = reward, bonus = milestone.bonus }
		table.insert(out, paid)
	end
	return out
end

function Collection.view(data: Data): { View }
	local out: { View } = {}
	local done = Collection.paid(data)
	for i, milestone in Config.DEX_MILESTONES.species do
		local row: View = {
			ladder = LADDER,
			count = milestone.count,
			reward = math.floor(milestone.reward * Economy.rebirthMultiplier(data.rebirths)),
			bonus = milestone.bonus,
			claimed = i <= done,
		}
		table.insert(out, row)
	end
	return out
end

return table.freeze(Collection)
