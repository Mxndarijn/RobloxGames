--!strict
--[[
	RevengePlots (pure, FEATURES.Revenge)

	Wire format of the victim-only Player attribute Constants.REVENGE_PLOTS_ATTRIBUTE:
	plot indexes of the thieves in the player's revenge window, "3,5". Written by
	WorldView.setRevengePlots, read by VisualsClient/RevengeFx.
]]

local RevengePlots = {}

function RevengePlots.format(plots: { number }): string?
	if #plots == 0 then
		return nil
	end
	local parts = {}
	for _, index in plots do
		table.insert(parts, tostring(math.floor(index)))
	end
	return table.concat(parts, ",")
end

-- Unique positive integer indexes in the order given; anything malformed is skipped.
function RevengePlots.parse(value: any): { number }
	local out = {}
	if type(value) ~= "string" then
		return out
	end
	local seen = {}
	for token in string.gmatch(value, "[^,]+") do
		local n = tonumber(token)
		if n and n >= 1 and n == math.floor(n) and not seen[n] then
			seen[n] = true
			table.insert(out, n)
		end
	end
	return out
end

return RevengePlots
