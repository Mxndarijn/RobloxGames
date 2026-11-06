--!strict
--[[
	Quests

	Daily quests (Config.DAILY_QUESTS, CONTRACT.md §8.8): every player gets
	`count` quests per UTC day, rolled from the pool by a seed of (day, userId)
	so the same day always rolls the same quests. A slot remembers the stat
	value at the roll (`base`), so progress = gained since then and is driven by
	the same counters the Goals use. `sync` rolls when the UTC day changed (the
	reset at midnight); `claim` pays one finished slot once. Pure: no Roblox APIs.
]]

local Codes = if script then require(script.Parent.Codes) else require("./Codes")
local Config = if script then require(script.Parent.Config) else require("./Config")
local Economy = if script then require(script.Parent.Economy) else require("./Economy")
local Goals = if script then require(script.Parent.Goals) else require("./Goals")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Rng = if script then require(script.Parent.Rng) else require("./Rng")
local DataKey = if script then require(script.Parent.Strings.DataKey) else require("./Strings/DataKey")
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Localize = if Lib then require(Lib.locale.Localize) else require("../../../../shared/luau/src/locale/Localize")

type Data = PlayerData.Data

export type View = {
	id: string,
	title: Localize.Message, -- the quest's count key (data.dailyQuest.<id>.title.one / .other), {count} as shown
	icon: string, -- Config.GOALS id (ItemIcons.forGoal)
	progress: number,
	target: number,
	done: boolean,
	claimed: boolean,
	reward: Localize.Text, -- "+$500" (a string), or a boost message ("2x income for 5m")
	rewardKind: string, -- "cash" | "boost"
}

export type DayView = { day: number, resetsIn: number, quests: { View } }

local Quests = {}

local DAY = 86400

function Quests.day(now: number): number
	return math.floor(now / DAY)
end

local function find(id: string): Config.DailyQuest?
	for _, def in Config.DAILY_QUESTS.pool do
		if def.id == id then
			return def
		end
	end
	return nil
end

-- The slots for (day, userId): distinct pool entries, deterministic. `data` supplies the baselines.
function Quests.roll(data: Data, day: number, userId: number)
	local rng = Rng.new(day * 7919 + userId * 104729 + 17)
	local pool = table.clone(Config.DAILY_QUESTS.pool)
	local slots = {}
	for _ = 1, math.min(Config.DAILY_QUESTS.count, #pool) do
		local def = table.remove(pool, rng:int(1, #pool)) :: Config.DailyQuest
		table.insert(slots, {
			id = def.id,
			target = def.choices[rng:int(1, #def.choices)],
			base = Goals.stat(data, def.stat),
			claimed = false,
		})
	end
	data.quests = { day = day, slots = slots }
end

-- Rolls today's quests when the UTC day changed (or the slots were lost). Returns whether it rolled.
function Quests.sync(data: Data, now: number, userId: number): boolean
	local day = Quests.day(now)
	if data.quests.day == day and #data.quests.slots > 0 then
		return false
	end
	Quests.roll(data, day, userId)
	return true
end

local function progress(data: Data, slot: PlayerData.QuestSlot, def: Config.DailyQuest): number
	return math.clamp(Goals.stat(data, def.stat) - slot.base, 0, slot.target)
end

local function rewardText(def: Config.DailyQuest, rebirths: number): (string, number)
	local reward = def.reward
	if reward.kind == "boost" then
		return `{reward.mult}x income for {reward.minutes}m`, 0
	end
	local amount = math.floor((reward.amount or 0) * Economy.rebirthMultiplier(rebirths))
	return `+${Economy.formatNumber(amount)}`, amount
end

local function title(def: Config.DailyQuest, target: number): Localize.Message
	local n = Economy.formatNumber(target)
	local form = if target == 1 then ".one" else ".other"
	return Localize.msg(
		DataKey.dataKey("dailyQuest", def.id, "title") .. form,
		{ count = if def.cash then `${n}` else n }
	)
end

-- What the quest card shows as its reward: the cash text, or the boost as a message.
local function rewardView(def: Config.DailyQuest, rebirths: number): Localize.Text
	local reward = def.reward
	if reward.kind == "boost" then
		return Localize.msg("data.dailyQuest.boost.reward", { mult = reward.mult, minutes = reward.minutes })
	end
	return (rewardText(def, rebirths))
end

function Quests.view(data: Data, now: number): DayView
	local out: { View } = {}
	local day = Quests.day(now)
	if data.quests.day == day then -- a stale day shows nothing until `sync` re-rolls
		for _, slot in data.quests.slots do
			local def = find(slot.id)
			if def then
				local have = progress(data, slot, def)
				table.insert(out, {
					id = def.id,
					title = title(def, slot.target),
					icon = def.icon,
					progress = have,
					target = slot.target,
					done = have >= slot.target,
					claimed = slot.claimed,
					reward = rewardView(def, data.rebirths),
					rewardKind = def.reward.kind,
				})
			end
		end
	end
	return { day = day, resetsIn = (day + 1) * DAY - now, quests = out }
end

-- Claims slot `index` once it is finished. Returns (ok, rewardTextOrReason).
function Quests.claim(data: Data, index: number, now: number, userId: number): (boolean, string)
	Quests.sync(data, now, userId)
	local slot = data.quests.slots[index]
	local def = if slot then find(slot.id) else nil
	if not slot or not def then
		return false, "no such quest"
	end
	if slot.claimed then
		return false, "already claimed"
	end
	if progress(data, slot, def) < slot.target then
		return false, "not finished yet"
	end
	slot.claimed = true
	local text, amount = rewardText(def, data.rebirths)
	if def.reward.kind == "boost" then
		Codes.addBoost(data, def.reward.mult or 1, def.reward.minutes or 0, now)
	else
		PlayerData.earn(data, amount)
	end
	return true, text
end

return table.freeze(Quests)
