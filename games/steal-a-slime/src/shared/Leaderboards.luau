--!strict
--[[
	Leaderboards (pure)

	The five global boards of the Hall of Fame plaza: which stat each ranks, its OrderedDataStore, its world board
	Model, title, header colour and number format. Server (Leaderboard, Persistence, LeaderboardView), the world
	props and the UI all read this one list.

	Weekly Top Earners ranks cash earned since Monday 00:00 UTC (WeeklyEvents.weekIndex). The save keeps
	`weekly = { week, base }`: `base` is totalEarned when the player was first seen in `week`, so the weekly value
	is totalEarned - base. `rollWeek` starts a new week; each week writes to its own store, so the board starts
	empty every Monday without a reset job.
]]

local Constants = if script then require(script.Parent.Constants) else require("./Constants")
local NumberFormat = if script then require(script.Parent.NumberFormat) else require("./NumberFormat")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local Types = if script then require(script.Parent.Types) else require("./Types")

export type Stat = Types.LeaderboardStat
export type Board = {
	stat: Stat,
	title: string,
	store: string, -- OrderedDataStore name (the weekly board adds "_<week>", `storeName`)
	weekly: boolean,
	model: string, -- the world board Model under workspace.Map
	cash: boolean, -- values are cash ("$1.5K"), else plain counts ("1.5K")
	accent: { number }, -- header strip colour (RGB); white title text on it stays >= 4.5:1
	podium: boolean, -- the top 3 stand on the Hall of Fame podium
}

local function board(def: Board): Board
	return table.freeze(def)
end

local Leaderboards = {}

-- Order on the plaza ring, left to right as you walk in (WorldLayout.HALL_OF_FAME boards use this order).
Leaderboards.BOARDS = table.freeze({
	board({
		stat = "Dex",
		title = "Top SlimeDex",
		store = Constants.DEX_STORE,
		weekly = false,
		model = Constants.TOP_DEX_BOARD,
		cash = false,
		accent = table.freeze({ 34, 92, 168 }),
		podium = false,
	}),
	board({
		stat = "WeeklyEarned",
		title = "Weekly Top Earners",
		store = Constants.WEEKLY_EARNED_STORE,
		weekly = true,
		model = Constants.WEEKLY_EARNERS_BOARD,
		cash = true,
		accent = table.freeze({ 24, 112, 66 }),
		podium = false,
	}),
	board({
		stat = "TotalEarned",
		title = "Top Earners",
		store = Constants.LEADERBOARD_STORE,
		weekly = false,
		model = Constants.LEADERBOARD_BOARD,
		cash = true,
		accent = table.freeze({ 150, 96, 0 }),
		podium = true,
	}),
	board({
		stat = "Steals",
		title = "Top Steals",
		store = Constants.STEALS_STORE,
		weekly = false,
		model = Constants.TOP_STEALS_BOARD,
		cash = false,
		accent = table.freeze({ 176, 40, 40 }),
		podium = false,
	}),
	board({
		stat = "Merges",
		title = "Top Merges",
		store = Constants.MERGES_STORE,
		weekly = false,
		model = Constants.TOP_MERGES_BOARD,
		cash = false,
		accent = table.freeze({ 104, 62, 168 }),
		podium = false,
	}),
}) :: { Board }

local byStat: { [string]: Board } = {}
local byModel: { [string]: Board } = {}
for _, def in Leaderboards.BOARDS do
	byStat[def.stat] = def
	byModel[def.model] = def
end

function Leaderboards.get(stat: any): Board?
	return if type(stat) == "string" then byStat[stat] else nil
end

-- The board a world Model shows, by the Model's name.
function Leaderboards.forModel(name: any): Board?
	return if type(name) == "string" then byModel[name] else nil
end

-- The board whose top 3 stand on the podium.
function Leaderboards.podium(): Board
	for _, def in Leaderboards.BOARDS do
		if def.podium then
			return def
		end
	end
	error("Leaderboards: no podium board")
end

-- The OrderedDataStore name of `def` in week `week`.
function Leaderboards.storeName(def: Board, week: number): string
	return if def.weekly then `{def.store}_{math.floor(week)}` else def.store
end

-- Starts week `week` for `data` when its saved week is another one: the weekly count restarts from 0.
function Leaderboards.rollWeek(data: PlayerData.Data, week: number)
	local weekly = data.weekly
	if weekly.week ~= week then
		data.weekly = { week = week, base = data.totalEarned }
	end
end

-- Cash earned in week `week` (0 when the save has not been seen in that week yet).
function Leaderboards.weeklyEarned(data: PlayerData.Data, week: number): number
	local weekly = data.weekly
	if weekly.week ~= week then
		return 0
	end
	return math.max(0, data.totalEarned - weekly.base)
end

-- The raw value `data` scores on the board of `stat` in week `week`.
function Leaderboards.value(stat: Stat, data: PlayerData.Data, week: number): number
	if stat == "TotalEarned" then
		return data.totalEarned
	elseif stat == "WeeklyEarned" then
		return Leaderboards.weeklyEarned(data, week)
	elseif stat == "Steals" then
		return data.totalStolen
	elseif stat == "Dex" then
		return PlayerData.dexCount(data)
	elseif stat == "Merges" then
		return data.stats.merges
	end
	return 0
end

-- My rank as text (State.boardRanks): "#48"; "#1000+" when it is deeper than the entries read (-1000); nil when
-- I'm not ranked yet.
function Leaderboards.rankText(rank: any): string?
	if type(rank) ~= "number" or rank ~= rank or rank == 0 then
		return nil
	end
	return if rank > 0 then `#{math.floor(rank)}` else `#{math.floor(-rank)}+`
end

-- A board value as shown on the board: "$1.5K" for cash boards, "1.5K" for counts.
function Leaderboards.format(stat: any, value: number): string
	local def = Leaderboards.get(stat)
	return if def and def.cash then NumberFormat.cash(value) else NumberFormat.short(value)
end

return table.freeze(Leaderboards)
