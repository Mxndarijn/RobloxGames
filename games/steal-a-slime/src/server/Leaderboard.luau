--!strict
--[[
	Leaderboard (pure)

	* leaderstats: IntValues Cash, Rebirths, Steals (`stats`).
	* Global boards (Leaderboards.BOARDS): one OrderedDataStore each, key "u_<UserId>", or "h_<UserId>" for a player
	  who turned "Show me on leaderboards" off (`prefixFor`): a hidden key reads back as PlayerSettings.HIDDEN_NAME
	  with userId 0, so no client can look that player up, also while they are offline. `storeValue` is what a
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
local PlayerSettings = if Shared then require(Shared.PlayerSettings) else require("../shared/PlayerSettings")
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

Leaderboard.PREFIX = OrderedBoard.DEFAULT_PREFIX
Leaderboard.HIDDEN_PREFIX = "h_"

-- The key prefix a player's board values go under: HIDDEN_PREFIX when they turned "Show me on leaderboards" off.
function Leaderboard.prefixFor(data: any): string
	local settings = if type(data) == "table" then data.settings else nil
	return if PlayerSettings.clean(settings).showOnBoards then Leaderboard.PREFIX else Leaderboard.HIDDEN_PREFIX
end

-- What a board write does for a player whose last write this session went under `lastPrefix` (nil: none yet):
-- set the key under `prefix`, and remove the key under the other prefix the first time and whenever it changed.
function Leaderboard.boardWrites(lastPrefix: string?, prefix: string, userId: number): { set: string, remove: string? }
	local other = if prefix == Leaderboard.HIDDEN_PREFIX then Leaderboard.PREFIX else Leaderboard.HIDDEN_PREFIX
	return {
		set = OrderedBoard.key(userId, prefix),
		remove = if lastPrefix ~= prefix then OrderedBoard.key(userId, other) else nil,
	}
end

-- One ranked row of a board read: the real userId stays on the server; `hidden` rows go out without it.
export type Row = { userId: number, value: number, hidden: boolean }
type Session = { userId: number, data: any? }

--[[
	A sorted page (or joined pages) -> rows, best first, under either prefix. Junk items are skipped; a player found
	under both prefixes (a move between them that has not removed the old key yet) is listed once, at the higher
	value, and hidden if either key is.
]]
function Leaderboard.rows(items: { any }): { Row }
	local parsed: { Row } = {}
	local hiddenIds: { [number]: boolean } = {}
	for _, item in items do
		if type(item) == "table" then
			local value = tonumber(item.value)
			local shown = OrderedBoard.userIdFromKey(item.key, Leaderboard.PREFIX)
			local hidden = OrderedBoard.userIdFromKey(item.key, Leaderboard.HIDDEN_PREFIX)
			local userId = shown or hidden
			if userId and value and value == value then
				table.insert(parsed, { userId = userId, value = value, hidden = hidden ~= nil })
				if hidden then
					hiddenIds[userId] = true
				end
			end
		end
	end
	local out: { Row } = {}
	local seen: { [number]: boolean } = {}
	for _, row in parsed do
		if not seen[row.userId] then
			seen[row.userId] = true
			row.hidden = hiddenIds[row.userId] == true
			table.insert(out, row)
		end
	end
	return out
end

-- Rows with this server's players over them, so a settings change shows before their next board write: an online
-- player is hidden exactly when their current settings say so.
function Leaderboard.overlay(rows: { Row }, sessions: { [number]: Session }?): { Row }
	if not sessions then
		return rows
	end
	local out: { Row } = {}
	for _, row in rows do
		local session = sessions[row.userId]
		local hidden = row.hidden
		if session and session.data then
			hidden = Leaderboard.prefixFor(session.data) == Leaderboard.HIDDEN_PREFIX
		end
		table.insert(out, { userId = row.userId, value = row.value, hidden = hidden })
	end
	return out
end

--[[
	`page` is GetSortedAsync(false, n):GetCurrentPage(): { { key, value } }.
	`nameOf(userId)` returns a display name (the adapter caches lookups); it is never asked for a hidden player.
	`sessions` (this server's players by userId) applies `overlay`.
]]
function Leaderboard.fromPage(
	page: { any },
	nameOf: (userId: number) -> string,
	stat: Types.LeaderboardStat,
	sessions: { [number]: Session }?
): Types.Leaderboard
	local entries: { Types.LeaderboardEntry } = {}
	for _, row in Leaderboard.overlay(Leaderboard.rows(page), sessions) do
		if #entries >= Config.LEADERBOARD_SIZE then
			break
		end
		if row.hidden then
			table.insert(
				entries,
				{ rank = #entries + 1, userId = 0, name = PlayerSettings.HIDDEN_NAME, value = row.value, hidden = true }
			)
		else
			table.insert(
				entries,
				{ rank = #entries + 1, userId = row.userId, name = nameOf(row.userId), value = row.value }
			)
		end
	end
	return { stat = stat, entries = entries }
end

-- A GetSortedAsync-shaped page of `stat` built from live sessions (memory mode), each under its own prefix.
function Leaderboard.pageFromSessions(
	sessions: { [number]: { userId: number, data: PlayerData.Data } },
	stat: Types.LeaderboardStat,
	week: number
): { any }
	local items = {}
	for _, session in sessions do
		table.insert(items, {
			key = OrderedBoard.key(session.userId, Leaderboard.prefixFor(session.data)),
			value = Leaderboard.storeValue(stat, session.data, week),
		})
	end
	return OrderedBoard.pageFrom(items)
end

-- The rank of each wanted userId in `items` (joined pages, best first), under either prefix; absent when not found.
function Leaderboard.ranks(items: { any }, wanted: { [number]: boolean }): { [number]: number }
	local out: { [number]: number } = {}
	for rank, row in Leaderboard.rows(items) do
		if wanted[row.userId] then
			out[row.userId] = rank
		end
	end
	return out
end

-- Each session's rank on one board from the scanned pages (`items`, joined in order): its rank when found; -n when it
-- was not found and the scan stopped after n entries before the end of the board (deeper than #n); absent when the
-- whole board was read without it (nothing written for that player yet).
function Leaderboard.sessionRanks(
	items: { any },
	sessions: { [number]: { userId: number } },
	finished: boolean
): { [number]: number }
	local wanted: { [number]: boolean } = {}
	for _, session in sessions do
		wanted[session.userId] = true
	end
	local ranks = Leaderboard.ranks(items, wanted)
	if not finished then
		for userId in wanted do
			if ranks[userId] == nil then
				ranks[userId] = -#items
			end
		end
	end
	return ranks
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
