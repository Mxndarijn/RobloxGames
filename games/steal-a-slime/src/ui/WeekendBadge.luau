--!strict
--[[
	WeekendBadge

	HUD chip text for the x2 Weekend (State.weekend): "💰 x2 Weekend - 1d 4h left". nil while
	the window is off, malformed or over. Pure (tests/ui/WeekendBadge.spec.luau).
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type View = { active: boolean, multiplier: number, endsAt: number? }

local WeekendBadge = {}

-- Up to two days left: "1d 4h", "5h 12m", then "m:ss" in the last hour.
local function left(seconds: number): string
	local total = math.ceil(seconds)
	if total >= 86400 then
		return string.format("%dd %dh", total // 86400, (total % 86400) // 3600)
	elseif total >= 3600 then
		return string.format("%dh %dm", total // 3600, (total % 3600) // 60)
	end
	return Format.formatDuration(total)
end

function WeekendBadge.banner(view: View?, now: number): string?
	if type(view) ~= "table" or view.active ~= true then
		return nil
	end
	if type(view.multiplier) ~= "number" or view.multiplier ~= view.multiplier or view.multiplier <= 1 then
		return nil
	end
	local text = string.format("💰 x%g Weekend", view.multiplier)
	if type(view.endsAt) == "number" then
		local remaining = Format.remainingSeconds(view.endsAt, now)
		if remaining <= 0 then
			return nil
		end
		text ..= ` - {left(remaining)} left`
	end
	return text
end

return table.freeze(WeekendBadge)
