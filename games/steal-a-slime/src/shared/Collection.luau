--!strict
--[[
	Collection

	SlimeDex completion rewards (Config.DEX_MILESTONES, CONTRACT.md §8.8): at
	each discovered-count milestone the player gets cash (x rebirthMultiplier)
	and a permanent income bonus (Perks.dexBonus). Paid automatically by
	`check`; data.dexRewards counts the milestones paid. `view` is
	State.dexRewards. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")

type Data = PlayerData.Data

export type Paid = { count: number, reward: number, bonus: number }
export type View = { count: number, reward: number, bonus: number, claimed: boolean }

local Collection = {}

local function paidCount(data: Data): number
	return math.clamp(math.floor(tonumber(data.dexRewards) or 0), 0, #Config.DEX_MILESTONES)
end

-- Bit k-1 set when data.dex holds a tier-k entry (plot attribute DexTierMask).
function Collection.tierMask(data: Data): number
	local mask = 0
	for key in data.dex do
		local tier = tonumber(string.match(key, "^(%d+):"))
		if tier and tier >= 1 and tier <= Config.MAX_TIER then
			mask = bit32.bor(mask, bit32.lshift(1, tier - 1))
		end
	end
	return mask
end

-- Pays every reached, unpaid milestone. Returns what was paid.
function Collection.check(data: Data): { Paid }
	local paid = {}
	local count = PlayerData.dexCount(data)
	local done = paidCount(data)
	while done < #Config.DEX_MILESTONES and count >= Config.DEX_MILESTONES[done + 1].count do
		done += 1
		local milestone = Config.DEX_MILESTONES[done]
		local reward = math.floor(milestone.reward * Economy.rebirthMultiplier(data.rebirths))
		data.dexRewards = done
		PlayerData.earn(data, reward)
		table.insert(paid, { count = milestone.count, reward = reward, bonus = milestone.bonus })
	end
	return paid
end

function Collection.view(data: Data): { View }
	local out = {}
	local done = paidCount(data)
	for i, milestone in Config.DEX_MILESTONES do
		table.insert(out, {
			count = milestone.count,
			reward = math.floor(milestone.reward * Economy.rebirthMultiplier(data.rebirths)),
			bonus = milestone.bonus,
			claimed = i <= done,
		})
	end
	return out
end

return table.freeze(Collection)
