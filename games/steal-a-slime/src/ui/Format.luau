--!strict
--[[
	Format

	Pure text / time helpers for the UI. No Roblox APIs, so it
	loads unchanged in the client and under Lune (tests/ui/Format.spec.luau).
]]

local Format = {}

local NumberFormat = if script
	then require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("NumberFormat") :: any)
	else require("../shared/NumberFormat")

local function trimZero(text: string): string
	return (string.gsub(text, "%.0$", ""))
end

-- 950 -> "950", 1250 -> "1.25K", 15300000 -> "15.3M". Non-finite values -> "0".
Format.shortNumber = NumberFormat.short
Format.formatCash = NumberFormat.cash

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

-- A long countdown: "1d 4h" from a day, "5h 12m" from an hour, then formatDuration ("m:ss").
function Format.formatTimeLeft(seconds: number): string
	local total = math.ceil(seconds)
	if total >= 86400 then
		return string.format("%dd %dh", total // 86400, (total % 86400) // 3600)
	elseif total >= 3600 then
		return string.format("%dh %dm", total // 3600, (total % 3600) // 60)
	end
	return Format.formatDuration(total)
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

-- SlimeDex key "tier:mutation:pattern:eyes" -> "Rare · Glow · Spots · Happy".
-- `tierNames[tier]` supplies rarity names; unknown tiers show "Tier N".
-- `mutationNames` maps mutation save ids to display names ("Lava" -> "Syrup").
function Format.dexLabel(key: string, tierNames: { string }, mutationNames: { [string]: string }?): string
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
	local shown = if mutationNames and mutationNames[mutation] then mutationNames[mutation] else mutation
	return `{tierName} · {shown} · {parts[3]} · {parts[4]}`
end

-- "12 / 720 (2%)"
function Format.dexCount(count: number, total: number): string
	local pct = if total > 0 then math.floor(count / total * 100) else 0
	return `{count} / {total} ({pct}%)`
end

return table.freeze(Format)
