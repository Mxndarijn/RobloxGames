--!strict
--[[
	Nav

	Left-bar entries and their badges (Rebirth, Goals, SlimeDex, Codes, Leaders; the Merge and world shop
	menus have no button, your slimes are managed at their pads with keys (SlimeKeys), see init.client panelByKey). Shown as a grid of rounded tiles, icon over label (B5). Pure (tests/ui/Nav.spec.luau); the
	buttons themselves are built in init.client.luau. Badges are short hints
	derived from the latest State ("!" = something to do there); the SlimeDex tile shows its completion as a
	slime jar instead (DexJarView).
]]

-- `item` = the ItemIcons registry id of the tile's picture (B5); `icon` = the plain glyph for text (hint bubbles).
export type Entry = { key: string, icon: string, label: string, item: string }

local Nav = {}

Nav.ENTRIES = table.freeze({
	table.freeze({ key = "Rebirth", icon = "♻️", label = "Rebirth", item = "Rebirth" }),
	table.freeze({ key = "Goals", icon = "🎯", label = "Goals", item = "Quest" }),
	table.freeze({ key = "Dex", icon = "📖", label = "SlimeDex", item = "Dex_50" }),
	table.freeze({ key = "Codes", icon = "🎁", label = "Codes", item = "Gift" }),
	table.freeze({ key = "Leaderboard", icon = "🏆", label = "Leaders", item = "Badge_Millionaire" }),
} :: { Entry })

local function num(value: any): number
	return if type(value) == "number" and value == value then value else 0
end

-- True when three slimes that aren't being stolen share a tier (a full merge vat load).
function Nav.canMerge(slimes: any): boolean
	if type(slimes) ~= "table" then
		return false
	end
	local seen: { [number]: number } = {}
	for _, view in slimes do
		if type(view) == "table" and view.stolenBy == nil and type(view.slime) == "table" then
			local tier = view.slime.tier
			seen[tier] = (seen[tier] or 0) + 1
			if seen[tier] >= 3 then
				return true
			end
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
	if state.canRebirth == true then
		out.Rebirth = "!"
	end
	return out
end

return table.freeze(Nav)
