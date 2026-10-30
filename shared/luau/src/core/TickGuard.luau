--!strict
--[[
	TickGuard

	Runs a component's tick under pcall so one failing component cannot end a shared frame or countdown loop.
	The error is logged once per component name, so a loop at 10 Hz does not spam the output. Pure.
]]
local TickGuard = {}

function TickGuard.new(log: (...any) -> ()): (string, () -> ()) -> boolean
	local failed: { [string]: boolean } = {}
	return function(name: string, fn: () -> ()): boolean
		local ok, err = pcall(fn)
		if not ok and not failed[name] then
			failed[name] = true
			log("[UI] tick failed:", name, err)
		end
		return ok
	end
end

return table.freeze(TickGuard)
