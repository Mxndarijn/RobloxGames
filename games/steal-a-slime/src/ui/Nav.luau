--!strict
--[[
	Nav

	Left-bar entries and their badges. Pure (tests/ui/Nav.spec.luau); the
	buttons themselves are built in init.client.luau. Badges are short hints
	derived from the latest State ("!" = something to do there).
]]

export type Entry = { key: string, icon: string, label: string }

local Nav = {}

Nav.ENTRIES = table.freeze({
	table.freeze({ key = "Plot", icon = "🏠", label = "Plot" }),
	table.freeze({ key = "Merge", icon = "🧪", label = "Merge" }),
	table.freeze({ key = "Shop", icon = "🛒", label = "Shop" }),
	table.freeze({ key = "Rebirth", icon = "♻️", label = "Rebirth" }),
	table.freeze({ key = "Goals", icon = "🎯", label = "Goals" }),
	table.freeze({ key = "Dex", icon = "📖", label = "SlimeDex" }),
	table.freeze({ key = "Leaders", icon = "🏆", label = "Top" }),
} :: { Entry })

local function num(value: any): number
	return if type(value) == "number" and value == value then value else 0
end

-- True when two slimes that aren't being stolen share a tier.
function Nav.canMerge(slimes: any): boolean
	if type(slimes) ~= "table" then
		return false
	end
	local seen: { [number]: boolean } = {}
	for _, view in slimes do
		if type(view) == "table" and view.stolenBy == nil and type(view.slime) == "table" then
			local tier = view.slime.tier
			if seen[tier] then
				return true
			end
			seen[tier] = true
		end
	end
	return false
end

-- True when some shop upgrade (not the plain Lock row) is affordable now:
-- State.shop entries, or v13 State.upgrades that are unlocked.
function Nav.shopAffordable(state: any): boolean
	if type(state) ~= "table" then
		return false
	end
	local cash = num(state.cash)
	local function affordable(entry: any): boolean
		return type(entry) == "table"
			and entry.unlocked ~= false
			and type(entry.price) == "number"
			and cash >= entry.price
	end
	for _, list in { state.shop, state.upgrades } do
		if type(list) == "table" then
			for _, entry in list do
				if affordable(entry) then
					return true
				end
			end
		end
	end
	return false
end

-- key -> badge text (nil = no badge).
function Nav.badges(state: any): { [string]: string }
	local out: { [string]: string } = {}
	if type(state) ~= "table" then
		return out
	end
	if type(state.slimes) == "table" then
		for _, view in state.slimes do
			if type(view) == "table" and view.stolenBy ~= nil then
				out.Plot = "!"
				break
			end
		end
	end
	if Nav.canMerge(state.slimes) then
		out.Merge = "!"
	end
	if Nav.shopAffordable(state) then
		out.Shop = "$"
	end
	if state.canRebirth == true then
		out.Rebirth = "!"
	end
	local total = num(state.dexTotal)
	if total > 0 and type(state.dex) == "table" then
		out.Dex = `{math.floor(#state.dex / total * 100)}%`
	end
	return out
end

return table.freeze(Nav)
