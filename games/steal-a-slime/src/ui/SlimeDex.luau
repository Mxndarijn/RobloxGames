--!strict
--[[
	SlimeDex

	Rows of the SlimeDex panel (Panels/Dex). Pure (tests/ui/SlimeDex.spec).

	Every discovered Genome.dexKey gets a row with an image: an uploaded
	picture from IMAGES when there is one, else a placeholder swatch in the
	mutation (or rarity) colour. Undiscovered entries are not listed one by
	one (dexTotal is 720 keys, mostly locked: too many rows on a phone);
	each tier gets one silhouette row instead (dark fill, "?", no names).
	Panels/Dex renders a ViewportFrame per row: the real in-world slime
	model (Visuals.ModelFactory, from SlimeDex.genome) when the client has
	it, else the SlimePreview blob from `color` and `mutation`. Uploaded
	thumbnails still win: see v28-NEEDS-UPLOAD.md for the files to make.
]]

local Format = if script then require(script.Parent.Format) else require("./Format")
local Progress = if script then require(script.Parent.Progress) else require("./Progress")

export type Row = {
	key: string, -- the dexKey, or "locked:<tier>"
	tier: number,
	locked: boolean,
	title: string,
	detail: string,
	image: string?, -- rbxassetid://..., nil = placeholder swatch
	color: { number }, -- swatch / silhouette fill (RGB 0..255)
	mutation: string?, -- save id of a discovered row ("None", "Lava", ...); nil when locked
	skin: { id: string, unlocked: boolean, equipped: boolean }?, -- plot skin card (FEATURES.PlotSkins), not a slime row
}

local SlimeDex = {}

-- Uploaded pictures: a dexKey ("3:Glow:Spots:Happy") or a whole tier +
-- mutation ("3:Glow") -> image asset id. Empty until art is uploaded.
SlimeDex.IMAGES = table.freeze({} :: { [string]: string })

SlimeDex.SILHOUETTE = table.freeze({ 24, 26, 36 })

-- Placeholder swatch per mutation save id ("Lava" displays as Syrup); "None"
-- uses the rarity colour.
SlimeDex.MUTATION_COLORS = table.freeze({
	Glow = table.freeze({ 255, 245, 150 }),
	Lava = table.freeze({ 255, 110, 40 }),
	Wet = table.freeze({ 70, 150, 255 }),
	Frozen = table.freeze({ 190, 235, 255 }),
	Galaxy = table.freeze({ 130, 90, 220 }),
	Gold = table.freeze({ 255, 205, 70 }),
	Rainbow = table.freeze({ 255, 120, 200 }),
	Crystal = table.freeze({ 150, 235, 255 }),
	Eclipse = table.freeze({ 30, 20, 50 }),
	-- Combos (Config.COMBOS)
	Solar = table.freeze({ 255, 170, 90 }),
	Nebula = table.freeze({ 190, 80, 160 }),
	Aurora = table.freeze({ 120, 255, 190 }),
	Royal = table.freeze({ 255, 225, 120 }),
	Sleet = table.freeze({ 120, 190, 235 }),
	Comet = table.freeze({ 150, 170, 255 }),
})

function SlimeDex.image(key: string, images: { [string]: string }?): string?
	local map = images or SlimeDex.IMAGES
	local tierMutation = string.match(key, "^(%d+:[^:]+)")
	return map[key] or (if tierMutation then map[tierMutation] else nil)
end

-- A display genome for a dex row (Genome.Slime shape, for
-- Visuals.ModelFactory.build): the dexKey's tier, mutation, pattern and eyes
-- on a size-1 body in the row colour, smiling. Locked rows get the tier's
-- plain look (the panel paints it as a silhouette). nil for a bad key.
function SlimeDex.genome(row: Row): { [string]: any }?
	local tier, mutation, pattern, eyes = string.match(row.key, "^(%d+):([^:]+):([^:]+):([^:]+)$")
	if row.locked then
		tier = string.match(row.key, "^locked:(%d+)$")
		mutation, pattern, eyes = "None", "Plain", "Round"
	end
	local t = tonumber(tier)
	if t == nil then
		return nil
	end
	return {
		id = `Dex_{row.key}`,
		name = "",
		tier = t,
		color = { row.color[1], row.color[2], row.color[3] },
		size = 1,
		pattern = pattern,
		eyes = eyes,
		mouth = "Smile",
		mutation = mutation,
	}
end

-- Discovered rows of each tier (sorted by key), then that tier's silhouette
-- row while some of it is still undiscovered. `config` supplies RARITIES and
-- MUTATIONS (save id -> displayName for the titles).
function SlimeDex.rows(dex: any, total: any, config: any, images: { [string]: string }?): { Row }
	local tierNames: { string } = {}
	for i, rarity in config.RARITIES do
		tierNames[i] = rarity.name
	end
	local mutationNames: { [string]: string } = {}
	for _, m in config.MUTATIONS or {} do
		mutationNames[m.name] = m.displayName or m.name
	end
	for _, c in config.COMBOS or {} do
		mutationNames[c.name] = c.displayName or c.name
	end
	for _, list in { config.WEATHER_MUTATIONS or {}, config.WEATHER_COMBOS or {} } do
		for _, m in list do
			mutationNames[m.name] = m.displayName or m.name
		end
	end
	local progress = Progress.dex(dex, total, tierNames)
	local byTier: { [number]: { string } } = {}
	for _, key in (if type(dex) == "table" then dex else {}) :: { any } do
		local tier = tonumber(string.match(tostring(key), "^(%d+):"))
		if tier then
			byTier[tier] = byTier[tier] or {}
			table.insert(byTier[tier], tostring(key))
		end
	end
	local out: { Row } = {}
	for tier, name in tierNames do
		local keys = byTier[tier] or {}
		table.sort(keys)
		local rarityColor = config.RARITIES[tier].color
		for _, key in keys do
			local mutation = string.match(key, "^%d+:([^:]+)")
			table.insert(out, {
				key = key,
				tier = tier,
				locked = false,
				title = Format.dexLabel(key, tierNames, mutationNames),
				detail = "Discovered",
				image = SlimeDex.image(key, images),
				color = (SlimeDex.MUTATION_COLORS :: any)[mutation or ""] or rarityColor,
				mutation = mutation,
			})
		end
		local t = progress.byTier[tier]
		local left = if t.total then t.total - t.count else 0
		if left > 0 then
			table.insert(out, {
				key = `locked:{tier}`,
				tier = tier,
				locked = true,
				title = `??? · {name}`,
				detail = `{left} more to discover`,
				image = nil,
				color = SlimeDex.SILHOUETTE,
			})
		end
	end
	return out
end

-- Plot skin cards (FEATURES.PlotSkins, CONTRACT.md §15) shown above the slime rows: one per
-- State.plotSkins entry, locked / unlocked with the SlimeDex set progress. Empty without the field.
function SlimeDex.skinRows(plotSkins: any, config: any): { Row }
	local out: { Row } = {}
	if type(plotSkins) ~= "table" then
		return out
	end
	local floors: { [string]: { number } } = {}
	for _, def in config.PLOT_SKINS or {} do
		floors[def.id] = if def.floor then def.floor.color else { 214, 176, 124 } -- classic: ranch_plaza
	end
	for _, skin in plotSkins :: { any } do
		if type(skin) == "table" and type(skin.id) == "string" then
			local set = if skin.setName then `{skin.setName} set` else "Default look"
			local unlocked, equipped = skin.unlocked == true, skin.equipped == true
			local detail = if equipped
				then `Equipped · {set}`
				elseif unlocked then `Unlocked · {set}`
				else `{set}: {skin.owned}/{skin.needed} to unlock`
			table.insert(out, {
				key = `skin:{skin.id}`,
				tier = skin.tier or 0,
				locked = not unlocked,
				title = `Plot skin · {skin.name}`,
				detail = detail,
				image = nil,
				color = floors[skin.id] or SlimeDex.SILHOUETTE,
				mutation = nil,
				skin = { id = skin.id, unlocked = unlocked, equipped = equipped },
			})
		end
	end
	return out
end

-- Panel header above the list (Panels/Dex, design px): percent + count
-- (40), the bar (to 64), the per-rarity grid (7 rarities, three per row =
-- three 18 px rows, to 128), then the rewards line (36) when there is one.
SlimeDex.HEADER = table.freeze({ count = 40, bar = 64, tiers = 128, rewards = 36, gap = 4 })
-- The list keeps at least one 72 px row (Panels/Dex) + scroll padding.
SlimeDex.MIN_LIST = 72 + 12

export type Header = { bar: boolean, tiers: boolean, rewards: boolean, rewardsY: number, listTop: number }

-- What fits above the list in a `bodyH` tall panel body: the tier grid goes
-- first, then the rewards line, then the bar, until the list is MIN_LIST
-- tall (short landscape phones). The list height is never negative.
function SlimeDex.header(bodyH: number, hasRewards: boolean): Header
	local h = SlimeDex.HEADER
	local options = {
		{ bar = true, tiers = true, rewards = hasRewards },
		{ bar = true, tiers = false, rewards = hasRewards },
		{ bar = true, tiers = false, rewards = false },
		{ bar = false, tiers = false, rewards = false },
	}
	local out: Header
	for _, o in options do
		local top = if o.tiers then h.tiers elseif o.bar then h.bar else h.count
		out = {
			bar = o.bar,
			tiers = o.tiers,
			rewards = o.rewards,
			rewardsY = top,
			listTop = top + h.gap + (if o.rewards then h.rewards else 0),
		}
		if bodyH - out.listTop >= SlimeDex.MIN_LIST then
			break
		end
	end
	return out
end

return table.freeze(SlimeDex)
