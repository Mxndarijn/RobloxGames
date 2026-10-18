--!strict
--[[
	EggReveal

	HUD banner text for a fresh Mystery Egg hatch (State.egg.hatched):
	"🥚 Hatched! Epic Blorp". nil when there is no hatch or it is older
	than `seconds`. Pure
	(tests/ui/EggReveal.spec.luau).
]]

export type View = { hatched: { slime: any, at: number }? }

local EggReveal = {}

-- `nameOf` is Genome.displayName.
function EggReveal.banner(view: View?, now: number, seconds: number, nameOf: (any) -> string): string?
	if view == nil or view.hatched == nil then
		return nil
	end
	local hatched = view.hatched
	if now - hatched.at > seconds then
		return nil
	end
	return `🥚 Hatched! {nameOf(hatched.slime)}`
end

return table.freeze(EggReveal)
