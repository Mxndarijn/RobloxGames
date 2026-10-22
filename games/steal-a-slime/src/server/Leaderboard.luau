--!strict
--[[
	Leaderboard (pure)

	* leaderstats: IntValues Cash, Rebirths, Steals (`stats`).
	* Global boards (Leaderboards.BOARDS): one OrderedDataStore each, key "u_<UserId>". `storeValue` is what a
	  save writes for a board, `fromPage` turns a GetSortedAsync page into the `Leaderboard` RemoteEvent payload
	  (Types.Leaderboard) and `pageFromSessions` builds the same page from this server's players (memory mode).
	* World boards: `boardRows` is the text the server writes into a board's Row_<k> labels (CONTRACT.md §5.3).
	Ranking itself is the shared OrderedBoard module.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Leaderboards = if Shared then require(Shared.Leaderboards) else require("../shared/Leaderboards")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")
local OrderedBoard = if Lib
	then require(Lib.ranking.OrderedBoard)
	else require("../../../../shared/luau/src/ranking/OrderedBoard")

local Leaderboard = {}

Leaderboard.STATS = table.freeze({ "Cash", "Rebirths", "Steals" })

-- OrderedDataStore values must be integers that fit in 2^53.
Leaderboard.MAX_VALUE = OrderedBoard.MAX_VALUE

function Leaderboard.stats(data: PlayerData.Data): { [string]: number }
	return {
		Cash = math.floor(data.cash),
		Rebirths = data.rebirths,
		Steals = data.totalStolen,
	}
end

-- What a save writes to the board of `stat` in week `week` (a valid OrderedDataStore integer).
function Leaderboard.storeValue(stat: Types.LeaderboardStat, data: PlayerData.Data, week: number): number
	return OrderedBoard.clamp(Leaderboards.value(stat, data, week))
end

-- A save writes the board value when the save went through, the session is not read-only and the value changed.
Leaderboard.shouldWrite = OrderedBoard.shouldWrite

-- "u_123" -> 123
Leaderboard.userIdFromKey = OrderedBoard.userIdFromKey

--[[
	`page` is GetSortedAsync(false, n):GetCurrentPage(): { { key, value } }.
	`nameOf(userId)` returns a display name (the adapter caches lookups).
]]
function Leaderboard.fromPage(
	page: { any },
	nameOf: (userId: number) -> string,
	stat: Types.LeaderboardStat
): Types.Leaderboard
	return { stat = stat, entries = OrderedBoard.entries(page, nameOf, { size = Config.LEADERBOARD_SIZE }) }
end

-- A GetSortedAsync-shaped page of `stat` built from live sessions (memory mode).
function Leaderboard.pageFromSessions(
	sessions: { [number]: { userId: number, data: PlayerData.Data } },
	stat: Types.LeaderboardStat,
	week: number
): { any }
	local items = {}
	for _, session in sessions do
		table.insert(items, {
			key = OrderedBoard.key(session.userId),
			value = Leaderboard.storeValue(stat, session.data, week),
		})
	end
	return OrderedBoard.pageFrom(items)
end

export type BoardRow = { rank: string, name: string, value: string }

Leaderboard.EMPTY_TEXT = "No entries yet"

-- Text for a world board's rows, best first; one placeholder row when empty.
function Leaderboard.boardRows(board: Types.Leaderboard?): { BoardRow }
	local rows: { BoardRow } = {}
	local entries: { Types.LeaderboardEntry } = if board then board.entries else {}
	local stat = if board then board.stat else nil
	for _, entry in entries do
		if #rows >= Config.LEADERBOARD_SIZE then
			break
		end
		table.insert(rows, {
			rank = `#{entry.rank}`,
			name = entry.name,
			value = Leaderboards.format(stat, entry.value),
		})
	end
	if #rows == 0 then
		table.insert(rows, { rank = "", name = Leaderboard.EMPTY_TEXT, value = "" })
	end
	return rows
end

return Leaderboard
