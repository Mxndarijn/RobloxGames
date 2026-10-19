--!strict
--[[
	Retry (pure): run `attempt` once, then once more after each delay in `delays` while it returns nil. Bounded
	(1 + #delays calls), never a hot loop; `wait` is injected (task.wait on the server, a recorder in specs).
	Returns the first non-nil result, or nil once every attempt failed. A throwing attempt counts as a failure.
]]

local Retry = {}

function Retry.run<T>(attempt: () -> T?, delays: { number }, wait: (number) -> ()): T?
	for i = 1, #delays + 1 do
		if i > 1 then
			wait(delays[i - 1])
		end
		local ok, result = pcall(attempt)
		if ok and result ~= nil then
			return result
		end
	end
	return nil
end

return Retry
