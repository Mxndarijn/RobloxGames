--!strict
--[[
	WeekendBadge

	HUD chip text for the x2 Weekend (State.weekend): "💰 x2 Weekend - 1d 4h left". nil while
	the window is off, malformed or over. Pure (tests/ui/WeekendBadge.spec.luau).
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type View = { active: boolean, multiplier: number, endsAt: number? }

local WeekendBadge = {}

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
		text ..= ` - {Format.formatTimeLeft(remaining)} left`
	end
	return text
end

return table.freeze(WeekendBadge)
