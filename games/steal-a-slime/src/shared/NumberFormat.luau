--!strict
--[[
	NumberFormat

	The one cash / count abbreviation used by the HUD, shop, rebirth, toasts,
	billboards and leaderboards. Three significant digits, truncated (never
	rounded up past a suffix), trailing zeros trimmed:
	999 -> "999", 1250 -> "1.25K", 12500 -> "12.5K", 125000 -> "125K",
	1.25e9 -> "1.25B". Pure, no requires.
]]

local NumberFormat = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trim(text: string): string
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

-- Non-finite or non-number values -> "0".
function NumberFormat.short(value: number): string
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return "0"
	end
	local sign = if value < 0 then "-" else ""
	local n = math.abs(value)
	if n < 1000 then
		return sign .. tostring(math.floor(n))
	end
	local index = 1
	while n >= 1000 and index < #SUFFIXES do
		n /= 1000
		index += 1
	end
	local decimals = if n < 10 then 2 elseif n < 100 then 1 else 0
	local scale = 10 ^ decimals
	local text = string.format("%." .. decimals .. "f", math.floor(n * scale + 1e-6) / scale)
	return sign .. trim(text) .. SUFFIXES[index]
end

function NumberFormat.cash(value: number): string
	local text = NumberFormat.short(value)
	if string.sub(text, 1, 1) == "-" then
		return "-$" .. string.sub(text, 2)
	end
	return "$" .. text
end

return table.freeze(NumberFormat)
