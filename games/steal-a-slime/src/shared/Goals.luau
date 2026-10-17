--!strict
--[[
	Goals

	Quest chains with cash rewards (Config.GOALS, CONTRACT.md §8.8). Each goal
	has stage targets on one stat; `check` pays every newly reached stage
	(base reward x rebirthMultiplier) and records it in data.goals, so old
	saves get past stages retroactively. Paid automatically, no claim
	action. `view` is State.goals. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")

type Data = PlayerData.Data

export type Paid = { id: string, title: string, reward: number }

export type View = {
	id: string,
	title: string,
	stat: string,
	progress: number,
	stage: number,
	stages: number,
	target: number?,
	reward: number?,
	nextTitle: string?, -- the step after the current one (nil on the last step)
	done: boolean,
}

local Goals = {}

-- Current value of a goal stat.
function Goals.stat(data: Data, stat: string): number
	if stat == "stolen" then
		return data.totalStolen
	elseif stat == "earned" then
		return data.totalEarned
	elseif stat == "rebirths" then
		return data.rebirths
	elseif stat == "pads" then
		return data.padsUnlocked
	end
	local value = (data.stats :: any)[stat]
	return if type(value) == "number" then value else 0
end

function Goals.title(goal: Config.Goal, target: number): string
	local n = Economy.formatNumber(target)
	local title = string.gsub(goal.title, "<n>", if goal.cash then `${n}` else n)
	return (string.gsub(title, "<s>", if target == 1 then "" else "s"))
end

-- Stages of `goal` already paid (clamped).
function Goals.stage(data: Data, goal: Config.Goal): number
	local stage = data.goals[goal.id]
	if type(stage) ~= "number" then
		return 0
	end
	return math.clamp(math.floor(stage), 0, #goal.targets)
end

-- Pays every reached, unpaid stage. Returns what was paid (in order).
function Goals.check(data: Data): { Paid }
	local paid = {}
	for _, goal in Config.GOALS do
		local stage = Goals.stage(data, goal)
		local value = Goals.stat(data, goal.stat)
		while stage < #goal.targets and value >= goal.targets[stage + 1] do
			stage += 1
			local reward = math.floor(goal.rewards[stage] * Economy.rebirthMultiplier(data.rebirths))
			data.goals[goal.id] = stage
			PlayerData.earn(data, reward)
			table.insert(paid, { id = goal.id, title = Goals.title(goal, goal.targets[stage]), reward = reward })
		end
	end
	return paid
end

function Goals.view(data: Data): { View }
	local out = {}
	for _, goal in Config.GOALS do
		local stage = Goals.stage(data, goal)
		local done = stage >= #goal.targets
		local target = if done then nil else goal.targets[stage + 1]
		table.insert(out, {
			id = goal.id,
			title = Goals.title(goal, target or goal.targets[#goal.targets]),
			stat = goal.stat,
			progress = Goals.stat(data, goal.stat),
			stage = stage,
			stages = #goal.targets,
			target = target,
			reward = if done
				then nil
				else math.floor(goal.rewards[stage + 1] * Economy.rebirthMultiplier(data.rebirths)),
			nextTitle = if stage + 2 <= #goal.targets then Goals.title(goal, goal.targets[stage + 2]) else nil,
			done = done,
		})
	end
	return out
end

return table.freeze(Goals)
