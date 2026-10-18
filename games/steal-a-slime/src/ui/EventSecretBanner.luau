--!strict
--[[
	EventSecretBanner

	HUD banner text for this week's featured event Secret (State.featuredSecret, CONTRACT.md §34):
	"✨ Featured Secret this week: Kitsune (ends in 3d 4h)". nil while absent, malformed or over.
	Pure (tests/ui/EventSecretBanner.spec.luau).
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type View = { id: string, name: string, endsAt: number }

local EventSecretBanner = {}

function EventSecretBanner.banner(view: View?, now: number): string?
	if type(view) ~= "table" or type(view.name) ~= "string" or view.name == "" then
		return nil
	end
	if type(view.endsAt) ~= "number" or view.endsAt ~= view.endsAt then
		return nil
	end
	local remaining = Format.remainingSeconds(view.endsAt, now)
	if remaining <= 0 then
		return nil
	end
	return `✨ Featured Secret this week: {view.name} (ends in {Format.formatTimeLeft(remaining)})`
end

return table.freeze(EventSecretBanner)
