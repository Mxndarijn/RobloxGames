--!strict
--[[
	OrderedBoard: top-N rankings kept in OrderedDataStores, as pure functions.

		local value = OrderedBoard.clamp(data.totalEarned)
		if OrderedBoard.shouldWrite(saved, readOnly, lastWritten, value) then store:SetAsync(key, value) end
		local entries = OrderedBoard.entries(page, nameOf, { size = 10 }) -- page = GetSortedAsync(false, 10):GetCurrentPage()
		local page = OrderedBoard.pageFrom({ { key = "u_1", value = 5 }, ... }) -- the same shape from in-memory records
		local ranks = OrderedBoard.ranks(items, { [userId] = true }) -- userId -> rank, for the players in `items`

	Keys are "<prefix><userId>" (prefix "u_" unless `options.prefix` says otherwise). OrderedDataStore values must be
	integers in 0 .. 2^53 - 1, so `clamp` floors, caps and turns NaN into 0. `periodKey` names one store per time
	period (a weekly board is a new store every week, so it starts empty without any reset job).
]]

export type PageItem = { key: string, value: number }
export type Entry = { rank: number, userId: number, name: string, value: number }
export type Options = { size: number?, prefix: string? }

local OrderedBoard = {}

OrderedBoard.MAX_VALUE = 2 ^ 53 - 1
OrderedBoard.DEFAULT_SIZE = 10
OrderedBoard.DEFAULT_PREFIX = "u_"

-- A number as an OrderedDataStore value: an integer in 0 .. MAX_VALUE (NaN and non-numbers -> 0).
function OrderedBoard.clamp(value: any): number
	if type(value) ~= "number" or value ~= value then
		return 0
	end
	return math.clamp(math.floor(value), 0, OrderedBoard.MAX_VALUE)
end

-- True when a save went through, the profile may write, and the value changed since the last write.
function OrderedBoard.shouldWrite(saved: boolean, readOnly: boolean, lastWritten: number?, value: number): boolean
	return saved and not readOnly and lastWritten ~= value
end

-- "u_123" -> 123 (nil for any other shape).
function OrderedBoard.userIdFromKey(key: any, prefix: string?): number?
	local p = prefix or OrderedBoard.DEFAULT_PREFIX
	if type(key) ~= "string" or string.sub(key, 1, #p) ~= p then
		return nil
	end
	local digits = string.match(string.sub(key, #p + 1), "^(%d+)$")
	return if digits then tonumber(digits) else nil
end

function OrderedBoard.key(userId: number, prefix: string?): string
	return `{prefix or OrderedBoard.DEFAULT_PREFIX}{userId}`
end

-- A sorted page -> ranked entries, best first. Junk items (bad keys, non-numbers) are skipped; at most `size`.
function OrderedBoard.entries(page: { any }, nameOf: (userId: number) -> string, options: Options?): { Entry }
	local size = (options and options.size) or OrderedBoard.DEFAULT_SIZE
	local prefix = options and options.prefix
	local out: { Entry } = {}
	for _, item in page do
		if #out >= size then
			break
		end
		local userId = if type(item) == "table" then OrderedBoard.userIdFromKey(item.key, prefix) else nil
		local value = if type(item) == "table" then tonumber(item.value) else nil
		if userId and value and value == value then
			table.insert(out, { rank = #out + 1, userId = userId, name = nameOf(userId), value = value })
		end
	end
	return out
end

-- The rank of each wanted user id in `items` (the pages of GetSortedAsync(false, ...) in order, joined): the same
-- numbering as `entries` (junk items are skipped, not counted). Ids not in `items` are absent from the result.
function OrderedBoard.ranks(items: { any }, wanted: { [number]: boolean }, prefix: string?): { [number]: number }
	local out: { [number]: number } = {}
	local rank = 0
	for _, item in items do
		local userId = if type(item) == "table" then OrderedBoard.userIdFromKey(item.key, prefix) else nil
		local value = if type(item) == "table" then tonumber(item.value) else nil
		if userId and value and value == value then
			rank += 1
			if wanted[userId] and out[userId] == nil then
				out[userId] = rank
			end
		end
	end
	return out
end

-- True when every wanted id has a rank in `ranks`.
function OrderedBoard.allFound(ranks: { [number]: number }, wanted: { [number]: boolean }): boolean
	for userId in wanted do
		if ranks[userId] == nil then
			return false
		end
	end
	return true
end

-- In-memory records -> a page shaped like GetSortedAsync(false, n):GetCurrentPage(): highest value first, ties by
-- key, so the order is the same on every call. Values are clamped like a store write.
function OrderedBoard.pageFrom(items: { PageItem }): { PageItem }
	local page: { PageItem } = {}
	for _, item in items do
		table.insert(page, { key = item.key, value = OrderedBoard.clamp(item.value) })
	end
	table.sort(page, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.key < b.key
	end)
	return page
end

-- The store name for one period: "<base>_<period>" (for example a week number).
function OrderedBoard.periodKey(base: string, period: number): string
	return `{base}_{math.floor(period)}`
end

return table.freeze(OrderedBoard)
