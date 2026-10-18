--!strict
--[[
	DataStoreBackend: Roblox adapter giving DataService its `update(key, transform)` over DataStore:UpdateAsync.
	Server runtime only; tests use DataService.memoryBackend() and never load this module.

		local backend = DataStoreBackend.new("PlayerData")
]]

export type Backend = {
	update: (key: string, transform: (old: any) -> any?) -> any,
}

local DataStoreBackend = {}

function DataStoreBackend.new(name: string, scope: string?): Backend
	local store = (game :: any):GetService("DataStoreService"):GetDataStore(name, scope)
	return {
		update = function(key: string, transform: (old: any) -> any?): any
			return store:UpdateAsync(key, transform)
		end,
	}
end

return table.freeze(DataStoreBackend)
