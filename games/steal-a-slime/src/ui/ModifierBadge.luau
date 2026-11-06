--!strict
--[[
	ModifierBadge

	HUD badge text for the active server modifier (State.modifier,
	FEATURES.CycleModifier): "Luck Surge x2 luck - 3:20 left". nil for "None",
	when the feature is off or when the modifier has run out. Pure
	(tests/ui/ModifierBadge.spec.luau).
]]

local Format = if script then require(script.Parent.Format) else require("./Format")
local Text = if script then require(script.Parent.Text) else require("./Text")

export type View = { name: string, label: string, luck: number, endsAt: number?, icon: string? }

local ModifierBadge = {}

local function mult(n: number): string
	return string.format("x%g", n)
end

-- The modifier's name in the player's language: a Config MODIFIERS label, or an admin event's label
-- (State.modifier.name "Admin_<id>"). `label` may be a Localize message from the server.
function ModifierBadge.label(view: View): string
	local english = Text.text(view.label :: any)
	if type(view.name) ~= "string" then
		return english
	end
	local adminId = string.match(view.name, "^Admin_(.+)$")
	if adminId then
		return Text.data("adminEvent", adminId, "label", english)
	end
	return Text.data("modifier", view.name, "label", english)
end

function ModifierBadge.banner(view: View?, now: number, enabled: boolean): string?
	if not enabled or view == nil or view.name == "None" then
		return nil
	end
	local name = ModifierBadge.label(view)
	local left: string? = nil
	if view.endsAt then
		local seconds = Format.remainingSeconds(view.endsAt, now)
		if seconds <= 0 then
			return nil
		end
		left = Format.formatDuration(seconds)
	end
	local text
	if view.luck ~= 1 then
		text = if left
			then Text.t("hud.modifier.luck_left", { name = name, luck = mult(view.luck), time = left })
			else Text.t("hud.modifier.luck", { name = name, luck = mult(view.luck) })
	else
		text = if left then Text.t("hud.modifier.left", { name = name, time = left }) else name
	end
	return if view.icon then `{view.icon} {text}` else text
end

return table.freeze(ModifierBadge)
