--!strict
--[[
	Format

	Pure text / time helpers for the UI. No Roblox APIs and no requires, so it
	loads unchanged in the client and under Lune (tests/ui/Format.spec.luau).
]]

local Format = {}

local SUFFIXES = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }

local function trimZero(text: string): string
	return (string.gsub(text, "%.0$", ""))
end

-- 950 -> "950", 1234 -> "1.2K", 15300000 -> "15.3M". Non-finite values -> "0".
function Format.shortNumber(value: number): string
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
	local text = if n < 100 then string.format("%.1f", math.floor(n * 10) / 10) else tostring(math.floor(n))
	return sign .. trimZero(text) .. SUFFIXES[index]
end

function Format.formatCash(value: number): string
	local text = Format.shortNumber(value)
	if string.sub(text, 1, 1) == "-" then
		return "-$" .. string.sub(text, 2)
	end
	return "$" .. text
end

-- Income per second. Small fractional rates keep one decimal: "$1.5/s".
function Format.formatRate(value: number): string
	if type(value) == "number" and value > 0 and value < 100 and value ~= math.floor(value) then
		return "$" .. trimZero(string.format("%.1f", math.floor(value * 10) / 10)) .. "/s"
	end
	return Format.formatCash(value) .. "/s"
end

-- 1.5 -> "x1.5", 2 -> "x2".
function Format.formatMultiplier(value: number): string
	return "x" .. trimZero(string.format("%.1f", value))
end

-- Seconds left until `untilTime` (server time) at server time `now`. Never < 0.
function Format.remainingSeconds(untilTime: number?, now: number): number
	if type(untilTime) ~= "number" or type(now) ~= "number" then
		return 0
	end
	return math.max(0, untilTime - now)
end

-- 65 -> "1:05", 3725 -> "1:02:05". Rounds partial seconds up so "0:00" means done.
function Format.formatDuration(seconds: number): string
	local total = math.max(0, math.ceil(seconds - 1e-9))
	local h = total // 3600
	local m = (total % 3600) // 60
	local s = total % 60
	if h > 0 then
		return string.format("%d:%02d:%02d", h, m, s)
	end
	return string.format("%d:%02d", m, s)
end

-- Client clock sync: offset = state.serverTime - os.clock() when a State arrives,
-- then serverNow(offset, os.clock()) ticks locally between snapshots.
function Format.clockOffset(serverTime: number, localClock: number): number
	return serverTime - localClock
end

function Format.serverNow(offset: number, localClock: number): number
	return localClock + offset
end

-- 0..1 progress of a countdown from `startedAt` to `endsAt`.
function Format.progress(startedAt: number, endsAt: number, now: number): number
	local span = endsAt - startedAt
	if span <= 0 then
		return 1
	end
	return math.clamp((now - startedAt) / span, 0, 1)
end

-- Slimedex key "tier:mutation:pattern:eyes" -> "Rare · Glow · Spots · Happy".
-- `tierNames[tier]` supplies rarity names; unknown tiers show "Tier N".
function Format.dexLabel(key: string, tierNames: { string }): string
	local parts = string.split(key, ":")
	if #parts ~= 4 then
		return key
	end
	local tier = tonumber(parts[1])
	local tierName = if tier and tierNames[tier] then tierNames[tier] else `Tier {parts[1]}`
	local mutation = parts[2]
	if mutation == "None" then
		return `{tierName} · {parts[3]} · {parts[4]}`
	end
	return `{tierName} · {mutation} · {parts[3]} · {parts[4]}`
end

-- "12 / 720 (2%)"
function Format.dexCount(count: number, total: number): string
	local pct = if total > 0 then math.floor(count / total * 100) else 0
	return `{count} / {total} ({pct}%)`
end

return table.freeze(Format)
