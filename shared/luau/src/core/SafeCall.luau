--!strict
--[[
	SafeCall (pure)

	The "this step may fail, the rest keeps going" call: `SafeCall.new(log, tag?)` returns
	`safeCall(name, fn, ...)`, which runs `fn(...)` inside pcall. On success it returns true plus fn's results;
	on an error it logs "<tag> <name> failed: <error>" once through `log` and returns false plus the error.
	`tag` defaults to "[Server]". Roblox code passes `warn`; specs pass a recorder.
]]

export type Call = (name: string, fn: (...any) -> ...any, ...any) -> (boolean, ...any)

local SafeCall = {}

function SafeCall.new(log: (message: string) -> (), tag: string?): Call
	local prefix = tag or "[Server]"
	return function(name: string, fn: (...any) -> ...any, ...: any): (boolean, ...any)
		local results = table.pack(pcall(fn, ...))
		if not results[1] then
			log(`{prefix} {name} failed: {results[2]}`)
		end
		return table.unpack(results, 1, results.n)
	end
end

return table.freeze(SafeCall)
