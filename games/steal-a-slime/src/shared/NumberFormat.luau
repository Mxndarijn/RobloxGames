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
	-- three digits at most: the float-error nudge must not carry 999.999999 over to 1000 of the same suffix.
	-- The last suffix has nothing above it, so it keeps every digit (5e36 -> "5000Dc").
	local digits = math.floor(n * scale + 1e-6)
	if index < #SUFFIXES then
		digits = math.min(digits, 999)
	end
	local text = string.format("%." .. decimals .. "f", digits / scale)
	return sign .. trim(text) .. SUFFIXES[index]
end

function NumberFormat.cash(value: number): string
	local text = NumberFormat.short(value)
	if string.sub(text, 1, 1) == "-" then
		return "-$" .. string.sub(text, 2)
	end
	return "$" .. text
end

-- Cash per second. Small fractional rates keep one decimal (truncated): 1.58 -> "$1.5/s", 1250 -> "$1.25K/s".
function NumberFormat.rate(value: number): string
	if type(value) == "number" and value > 0 and value < 100 and value ~= math.floor(value) then
		return "$" .. (string.gsub(string.format("%.1f", math.floor(value * 10) / 10), "%.0$", "")) .. "/s"
	end
	return NumberFormat.cash(value) .. "/s"
end

return table.freeze(NumberFormat)
