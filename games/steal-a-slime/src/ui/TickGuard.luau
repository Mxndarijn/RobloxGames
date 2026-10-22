--!strict
--[[
	TickGuard

	Runs a UI component's tick under pcall so one failing component cannot end the shared countdown loop.
	The error is logged once per component name (no spam at 10 Hz). No Roblox APIs, so it loads under Lune.
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

return TickGuard
