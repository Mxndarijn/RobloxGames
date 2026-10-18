--!strict
--[[
	NumberFormat: pure number and time text.

	short: three significant digits, truncated (never rounded up past a suffix), trailing zeros trimmed:
	  999 -> "999", 1250 -> "1.25K", 12500 -> "12.5K", 125000 -> "125K", 3.4e6 -> "3.4M", 1.25e9 -> "1.25B".
	cash:  short with a currency prefix ("$" unless given): "$1.25K", "-$40".
	duration: the two largest units: 42 -> "42s", 245 -> "4m 05s", 3900 -> "1h 05m", 93600 -> "1d 02h".
	clock: 65 -> "1:05", 3725 -> "1:02:05".
	Partial seconds round up in duration and clock, so "0s" / "0:00" means done.
]]

local NumberFormat = {}

local SUFFIXES = table.freeze({ "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" })

local function finite(value: any): boolean
	return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function trim(text: string): string
	if string.find(text, ".", 1, true) then
		text = string.gsub(text, "0+$", "")
		text = string.gsub(text, "%.$", "")
	end
	return text
end

-- Non-finite or non-number values give "0".
function NumberFormat.short(value: number): string
	if not finite(value) then
		return "0"
	end
	local sign = if value < 0 then "-" else ""
	local n = math.abs(value)
	if n < 1000 then
		local whole = math.floor(n)
		return (if whole == 0 then "" else sign) .. tostring(whole)
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

-- short with a prefix in front of the digits; the minus sign goes before the prefix.
function NumberFormat.cash(value: number, prefix: string?): string
	local mark = prefix or "$"
	local text = NumberFormat.short(value)
	if string.sub(text, 1, 1) == "-" then
		return "-" .. mark .. string.sub(text, 2)
	end
	return mark .. text
end

local function wholeSeconds(seconds: number): number
	if not finite(seconds) then
		return 0
	end
	return math.max(0, math.ceil(seconds - 1e-9))
end

-- Compact duration with the two largest non-trivial units; the second unit is zero-padded.
function NumberFormat.duration(seconds: number): string
	local total = wholeSeconds(seconds)
	local d = total // 86400
	local h = (total % 86400) // 3600
	local m = (total % 3600) // 60
	local s = total % 60
	if d > 0 then
		return string.format("%dd %02dh", d, h)
	elseif h > 0 then
		return string.format("%dh %02dm", h, m)
	elseif m > 0 then
		return string.format("%dm %02ds", m, s)
	end
	return string.format("%ds", s)
end

-- Clock-style countdown: "m:ss", or "h:mm:ss" from one hour.
function NumberFormat.clock(seconds: number): string
	local total = wholeSeconds(seconds)
	local h = total // 3600
	local m = (total % 3600) // 60
	local s = total % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- Seconds left until `untilTime` at time `now`. Never below 0; non-numbers give 0.
function NumberFormat.remaining(untilTime: number?, now: number): number
	if not finite(untilTime) or not finite(now) then
		return 0
	end
	return math.max(0, (untilTime :: number) - now)
end

-- 0..1 progress of a countdown from `startedAt` to `endsAt` at time `now`. An empty span counts as done.
function NumberFormat.progress(startedAt: number, endsAt: number, now: number): number
	local span = endsAt - startedAt
	if span <= 0 then
		return 1
	end
	return math.clamp((now - startedAt) / span, 0, 1)
end

return table.freeze(NumberFormat)
