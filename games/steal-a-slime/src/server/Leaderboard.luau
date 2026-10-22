--!strict
--[[
	Leaderboard (pure)

	* leaderstats: IntValues Cash, Rebirths, Steals (`stats`).
	* Global board: the OrderedDataStore Constants.LEADERBOARD_STORE ranks by
	  totalEarned. `fromPage` turns a GetSortedAsync page into the
	  `Leaderboard` RemoteEvent payload (Types.Leaderboard).
	* World board: `boardRows` is the text the server writes into the
	  LeaderboardBoard's Row_<k> labels (CONTRACT.md §5.3).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")

local Leaderboard = {}

Leaderboard.STATS = table.freeze({ "Cash", "Rebirths", "Steals" })

-- OrderedDataStore values must be integers that fit in 2^53.
Leaderboard.MAX_VALUE = 2 ^ 53 - 1

function Leaderboard.stats(data: PlayerData.Data): { [string]: number }
	return {
		Cash = math.floor(data.cash),
		Rebirths = data.rebirths,
		Steals = data.totalStolen,
	}
end

function Leaderboard.storeValue(data: PlayerData.Data): number
	return math.clamp(math.floor(data.totalEarned), 0, Leaderboard.MAX_VALUE)
end

-- Whether a save should also write the board: only a save that went through (a failed or lost-session one would
-- rank stale progress over the live session's), not a read-only session's, and only when the value moved.
function Leaderboard.shouldWrite(saved: boolean, readOnly: boolean, lastWritten: number?, value: number): boolean
	return saved and not readOnly and lastWritten ~= value
end

-- "u_123" -> 123
function Leaderboard.userIdFromKey(key: any): number?
	if type(key) ~= "string" then
		return nil
	end
	local digits = string.match(key, "^u_(%d+)$")
	return if digits then tonumber(digits) else nil
end

--[[
	`page` is GetSortedAsync(false, n):GetCurrentPage(): { { key, value } }.
	`nameOf(userId)` returns a display name (the adapter caches lookups).
]]
function Leaderboard.fromPage(page: { any }, nameOf: (userId: number) -> string): Types.Leaderboard
	local entries: { Types.LeaderboardEntry } = {}
	for _, item in page do
		local userId = if type(item) == "table" then Leaderboard.userIdFromKey(item.key) else nil
		local value = if type(item) == "table" then tonumber(item.value) else nil
		if userId and value and #entries < Config.LEADERBOARD_SIZE then
			table.insert(entries, {
				rank = #entries + 1,
				userId = userId,
				name = nameOf(userId),
				value = value,
			})
		end
	end
	return { stat = "TotalEarned", entries = entries }
end

-- A GetSortedAsync-shaped page built from live sessions (memory mode).
function Leaderboard.pageFromSessions(sessions: { [number]: { userId: number, data: PlayerData.Data } }): { any }
	local page = {}
	for _, session in sessions do
		table.insert(page, { key = `u_{session.userId}`, value = Leaderboard.storeValue(session.data) })
	end
	table.sort(page, function(x, y)
		if x.value ~= y.value then
			return x.value > y.value
		end
		return x.key < y.key
	end)
	return page
end

export type BoardRow = { rank: string, name: string, value: string }

Leaderboard.EMPTY_TEXT = "No entries yet"

-- Text for the world board's rows, best first; one placeholder row when empty.
function Leaderboard.boardRows(board: Types.Leaderboard?): { BoardRow }
	local rows: { BoardRow } = {}
	local entries: { Types.LeaderboardEntry } = if board then board.entries else {}
	for _, entry in entries do
		if #rows >= Config.LEADERBOARD_SIZE then
			break
		end
		table.insert(rows, {
			rank = `#{entry.rank}`,
			name = entry.name,
			value = `${Economy.formatNumber(entry.value)}`,
		})
	end
	if #rows == 0 then
		table.insert(rows, { rank = "", name = Leaderboard.EMPTY_TEXT, value = "" })
	end
	return rows
end

return Leaderboard
