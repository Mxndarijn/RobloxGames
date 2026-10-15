--!strict
--[[
	SlimeDex

	Rows of the SlimeDex panel (Panels/Dex). Pure (tests/ui/SlimeDex.spec).

	Every discovered Genome.dexKey gets a row with an image: an uploaded
	picture from IMAGES when there is one, else a placeholder swatch in the
	mutation (or rarity) colour. Undiscovered entries are not listed one by
	one (dexTotal is 720 keys, mostly locked: too many rows on a phone);
	each tier gets one silhouette row instead (dark fill, "?", no names).
	A ViewportFrame of the real slime model is the planned upgrade
	(UI-PLAN.md): models are built server-side, the client has none to
	render.
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
}

local SlimeDex = {}

-- Uploaded pictures: a dexKey ("3:Glow:Spots:Happy") or a whole tier +
-- mutation ("3:Glow") -> image asset id. Empty until art is uploaded.
SlimeDex.IMAGES = table.freeze({} :: { [string]: string })

SlimeDex.SILHOUETTE = table.freeze({ 24, 26, 36 })

-- Placeholder swatch per mutation; "None" uses the rarity colour.
SlimeDex.MUTATION_COLORS = table.freeze({
	Glow = table.freeze({ 255, 245, 150 }),
	Lava = table.freeze({ 255, 110, 40 }),
	Galaxy = table.freeze({ 130, 90, 220 }),
	Gold = table.freeze({ 255, 205, 70 }),
	Rainbow = table.freeze({ 255, 120, 200 }),
	Crystal = table.freeze({ 150, 235, 255 }),
	Eclipse = table.freeze({ 30, 20, 50 }),
})

function SlimeDex.image(key: string, images: { [string]: string }?): string?
	local map = images or SlimeDex.IMAGES
	local tierMutation = string.match(key, "^(%d+:[^:]+)")
	return map[key] or (if tierMutation then map[tierMutation] else nil)
end

-- Discovered rows of each tier (sorted by key), then that tier's silhouette
-- row while some of it is still undiscovered. `config` supplies RARITIES.
function SlimeDex.rows(dex: any, total: any, config: any, images: { [string]: string }?): { Row }
	local tierNames: { string } = {}
	for i, rarity in config.RARITIES do
		tierNames[i] = rarity.name
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
				title = Format.dexLabel(key, tierNames),
				detail = "Discovered",
				image = SlimeDex.image(key, images),
				color = (SlimeDex.MUTATION_COLORS :: any)[mutation or ""] or rarityColor,
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

return table.freeze(SlimeDex)
