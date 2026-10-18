--!strict
--[[
	Collection

	SlimeDex milestone rewards (Config.DEX_MILESTONES, CONTRACT.md §35.3): two ladders, species found (of
	SpeciesDex.TOTAL) and core mutation stamps (of SpeciesDex.STAMP_TOTAL). Each milestone pays cash
	(x rebirthMultiplier) and a permanent income bonus (Perks.dexBonus). Paid automatically by `check`;
	data.speciesRewards / data.stampRewards count the milestones paid. `view` is State.dexRewards.
	Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local SpeciesDex = if script then require(script.Parent.SpeciesDex) else require("./SpeciesDex")

type Data = PlayerData.Data

export type Ladder = string -- "species" | "stamps"
export type Paid = { ladder: Ladder, count: number, reward: number, bonus: number }
export type View = { ladder: Ladder, count: number, reward: number, bonus: number, claimed: boolean }

local Collection = {}

local LADDERS: { Ladder } = { "species", "stamps" }
Collection.LADDERS = table.freeze(LADDERS)

local function list(ladder: Ladder): { Config.DexMilestone }
	return if ladder == "species" then Config.DEX_MILESTONES.species else Config.DEX_MILESTONES.stamps
end

-- Milestones of `ladder` already paid.
function Collection.paid(data: Data, ladder: Ladder): number
	local paid = if ladder == "species" then data.speciesRewards else data.stampRewards
	return math.clamp(math.floor(tonumber(paid) or 0), 0, #list(ladder))
end

-- The count a ladder measures: species found or core stamps.
function Collection.progress(data: Data, ladder: Ladder): number
	return if ladder == "species" then SpeciesDex.count(data) else SpeciesDex.stampCount(data)
end

-- Pays every reached, unpaid milestone (species ladder first). Returns what was paid.
function Collection.check(data: Data): { Paid }
	local out: { Paid } = {}
	for _, ladder in LADDERS do
		local milestones = list(ladder)
		local have = Collection.progress(data, ladder)
		local done = Collection.paid(data, ladder)
		while done < #milestones and have >= milestones[done + 1].count do
			done += 1
			local milestone = milestones[done]
			local reward = math.floor(milestone.reward * Economy.rebirthMultiplier(data.rebirths))
			if ladder == "species" then
				data.speciesRewards = done
			else
				data.stampRewards = done
			end
			PlayerData.earn(data, reward)
			local paid: Paid = { ladder = ladder, count = milestone.count, reward = reward, bonus = milestone.bonus }
			table.insert(out, paid)
		end
	end
	return out
end

function Collection.view(data: Data): { View }
	local out: { View } = {}
	for _, ladder in LADDERS do
		local done = Collection.paid(data, ladder)
		for i, milestone in list(ladder) do
			local row: View = {
				ladder = ladder,
				count = milestone.count,
				reward = math.floor(milestone.reward * Economy.rebirthMultiplier(data.rebirths)),
				bonus = milestone.bonus,
				claimed = i <= done,
			}
			table.insert(out, row)
		end
	end
	return out
end

return table.freeze(Collection)
