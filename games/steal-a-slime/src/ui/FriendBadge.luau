--!strict
--[[
	FriendBadge

	HUD text for the friend income bonus (State.friends, FEATURES.FriendBonus):
	`label` is "+20%" for the status slot, `line` the same bonus as an
	income-breakdown line ("Friends +20% income"). nil with no friends or the
	feature off. Pure (tests/ui/FriendBadge.spec.luau).
]]

export type View = { count: number, bonus: number }

local FriendBadge = {}

local function percent(bonus: number): string
	return `+{math.floor(bonus * 100 + 0.5)}%`
end

local function active(view: any, enabled: boolean): boolean
	return enabled
		and type(view) == "table"
		and type(view.bonus) == "number"
		and view.bonus == view.bonus
		and view.bonus > 0
end

-- "+20%" alone (the bottom-right status slot); nil with no friends or the feature off.
function FriendBadge.label(view: View?, enabled: boolean): string?
	if not active(view, enabled) then
		return nil
	end
	return percent((view :: View).bonus)
end

function FriendBadge.line(view: View?, enabled: boolean): string?
	if not active(view, enabled) then
		return nil
	end
	return `Friends {percent((view :: View).bonus)} income`
end

return table.freeze(FriendBadge)
