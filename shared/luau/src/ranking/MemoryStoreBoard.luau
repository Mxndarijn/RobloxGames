--!strict
--[[
	MemoryStoreBoard: Roblox adapter giving PeriodBoard its store over MemoryStoreService sorted maps. Server runtime
	only; Studio, tests and cloud scripts use PeriodBoard.memoryStore() and never load this module.

		local store = MemoryStoreBoard.new()
		PeriodBoard.post(store, "Obby_981204_1a2b3c4d", userId, entry, { expiration = 5400, wait = task.wait })

	`update` is SortedMap:UpdateAsync (the transform returns the new value and sort key, or nil to keep the old one),
	`range` is GetRangeAsync ascending (lowest sort key first). Calls yield and may throw; PeriodBoard wraps them.
	At most MAX_OPEN maps stay open; the oldest is dropped first (a period board is only read while it is current).
]]

local PeriodBoard = if script then require(script.Parent.PeriodBoard) else require("./PeriodBoard")

local MemoryStoreBoard = {}

MemoryStoreBoard.MAX_OPEN = 4

function MemoryStoreBoard.new(service: any?): PeriodBoard.Store
	local memoryStore = service or (game :: any):GetService("MemoryStoreService")
	local open: { [string]: any } = {}
	local order: { string } = {}
	local function mapOf(name: string): any
		local map = open[name]
		if not map then
			map = memoryStore:GetSortedMap(name)
			open[name] = map
			table.insert(order, name)
			if #order > MemoryStoreBoard.MAX_OPEN then
				open[table.remove(order, 1) :: string] = nil
			end
		end
		return map
	end
	return {
		update = function(map: string, key: string, transform: PeriodBoard.Transform, expiration: number): any?
			return mapOf(map):UpdateAsync(key, transform, expiration)
		end,
		range = function(map: string, count: number): { PeriodBoard.Item }
			return mapOf(map):GetRangeAsync((Enum :: any).SortDirection.Ascending, count)
		end,
	}
end

return table.freeze(MemoryStoreBoard)
