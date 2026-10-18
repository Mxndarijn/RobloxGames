--!strict
--[[
	SafeCall (pure)

	The entry scripts' "this step may fail, the server keeps going" call: `SafeCall.new(log)` returns
	`safeCall(name, fn, ...)`, which runs `fn(...)` inside pcall. On success it returns true plus fn's results;
	on an error it logs "[Server] <name> failed: <error>" once through `log` and returns false plus the error.
	init.server passes `warn`; specs pass a recorder.
]]

export type Call = (name: string, fn: (...any) -> ...any, ...any) -> (boolean, ...any)

local SafeCall = {}

function SafeCall.new(log: (message: string) -> ()): Call
	return function(name: string, fn: (...any) -> ...any, ...: any): (boolean, ...any)
		local results = table.pack(pcall(fn, ...))
		if not results[1] then
			log(`[Server] {name} failed: {results[2]}`)
		end
		return table.unpack(results, 1, results.n)
	end
end

return SafeCall
