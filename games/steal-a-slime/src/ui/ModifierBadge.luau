--!strict
--[[
	ModifierBadge

	HUD badge text for the active server modifier (State.modifier,
	FEATURES.CycleModifier): "Luck Surge x2 luck - 3:20 left". nil for "None",
	when the feature is off or when the modifier has run out. Pure
	(tests/ui/ModifierBadge.spec.luau).
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type View = { name: string, label: string, luck: number, endsAt: number?, icon: string? }

local ModifierBadge = {}

local function mult(n: number): string
	return string.format("x%g", n)
end

function ModifierBadge.banner(view: View?, now: number, enabled: boolean): string?
	if not enabled or view == nil or view.name == "None" then
		return nil
	end
	local parts = {}
	if view.luck ~= 1 then
		table.insert(parts, `{mult(view.luck)} luck`)
	end
	local text = if view.icon then `{view.icon} {view.label}` else view.label
	if #parts > 0 then
		text ..= ` {table.concat(parts, ", ")}`
	end
	if view.endsAt then
		local left = Format.remainingSeconds(view.endsAt, now)
		if left <= 0 then
			return nil
		end
		text ..= ` - {Format.formatDuration(left)} left`
	end
	return text
end

return table.freeze(ModifierBadge)
