--!strict
--[[
	ItemIcons

	The one item icon registry: item id -> icon spec, for every item the UI
	shows (shop rows, upgrades, gear, boosts, the Mystery Egg, code rewards,
	goal rewards, badges, plot skins, mutations, ...). Pure (no Roblox APIs),
	built from Config by ItemIcons.build(Config); rendering lives in
	ItemIconView.

	A spec resolves in this order (`source`):
	  1. "model": the item has a real 3D model in the repo: a slime with a
	     mutation finish (SlimePreview) or a kit mesh (MeshAssets name).
	     ItemIconView renders it in a ViewportFrame, lazily, under a global
	     live cap, and falls back to 2 / 3 when it cannot.
	  2. "image": an uploaded picture. Paste the asset id into ItemIcons.IMAGES
	     below (ITEM-ICONS-NEEDED.md lists what to make for each id).
	  3. "drawn": a UI-drawn scene of layered frames (ItemIconArt), for the ids
	     in ItemIcons.DRAWN_GROUPS without an image. Static: no viewport, no cap.
	  4. "placeholder": a rounded gradient tile in the item's colour with a
	     bold glyph and a stroke. Every spec has `color` + `glyph`, so the
	     tile is always there (also as the backdrop of 1 / 2).
]]

export type Spec = {
	id: string,
	name: string,
	group: string, -- "shop" | "gear" | "upgrade" | "boost" | "code" | "goal" | "badge" | "mutation" | "skin" | "misc" | "hud"
	color: { number }, -- tile colour, 0..255 RGB
	glyph: string, -- allowlisted (tests/ui/Glyphs.spec): ASCII, a proven BMP symbol or an emoji
	model: { kind: "slime" | "mesh", mutation: string?, mesh: string? }?,
	image: number?, -- uploaded asset id, from IMAGES
	source: "model" | "image" | "drawn" | "placeholder",
	brief: string, -- what Archer renders for the 512x512 icon (ITEM-ICONS-NEEDED.md)
}

local ItemIcons = {}

-- Uploaded 512x512 icons by item id (rbxassetid number of the IMAGE asset, not the Decal), rendered by
-- shared/modeling-kit/tools/icons (ids in shared/modeling-kit/icons_uploaded.json). An image wins over
-- the drawn scene and the placeholder tile, never over a working 3D model (it is that model's fallback).
ItemIcons.IMAGES = {
	Appraise = 83435847821482,
	Badge_Dex100 = 126553682019734,
	Badge_Dex25 = 103035902991477,
	Badge_Dex50 = 132537225738577,
	Badge_FirstLegendary = 92898240575380,
	Badge_FirstRebirth = 71546390489545,
	Badge_FirstSecret = 140702355269432,
	Badge_FirstSlime = 120070367416197,
	Badge_FirstSteal = 78925771107042,
	Badge_Millionaire = 127519969347286,
	Badge_Rebirth5 = 118825716133448,
	Boost_Blessed = 102114473664766,
	Boost_Code = 116865449672644,
	Boost_Friend = 134160547679550,
	Boost_Weekend = 130491704533609,
	Cash = 87921251358162,
	Code_LAUNCH = 71722668257014,
	Code_SLIMEBOOST = 96448805080296,
	Code_WELCOME = 132772869844350,
	Consumable_LuckPotion = 130655218939229,
	Consumable_MutationSpray = 132258473401570,
	Consumable_WeatherTotem = 128919354425403,
	Daily = 136919499537484,
	Dex_10 = 121377018671664,
	Dex_100 = 104036768146434,
	Dex_200 = 124460827254481,
	Dex_25 = 103082196233051,
	Dex_400 = 119341987106293,
	Dex_50 = 98335037376213,
	Dex_720 = 86513854908521,
	Event_luck = 110897664124431,
	Event_mutation = 77556138887188,
	Event_rain = 85475866363499,
	Gift = 100988775125780,
	Goal_Catch = 72111768355754,
	Goal_Earn = 95884409898940,
	Goal_Lock = 127760359460961,
	Goal_Merge = 113657744087680,
	Goal_Pads = 99255351965390,
	Goal_Rebirth = 123035773985810,
	Goal_Steal = 94010775081099,
	Lock = 80470044151843,
	LockUpgrade = 127943211946057,
	MysteryEgg = 140462029142577,
	Perk_income = 94766482619711,
	Perk_luck = 80060700315838,
	Perk_mutation = 89742124559371,
	PlotSkin_candy = 75125399713715,
	PlotSkin_classic = 75405645541984,
	PlotSkin_crystal = 91231773101915,
	PlotSkin_mushroom = 110584867448733,
	Pvp_Bat = 107609481658581, -- default melee Bat (Tool 'Bat'); not a Config.PVP_TOOLS item, wired as its own tool
	Pvp_FunBalloon = 139662990313432,
	Pvp_FunBouncePad = 127452735645388,
	Pvp_FunBubbles = 88858283106113,
	Pvp_FunConfetti = 122616884845171,
	Pvp_FunDanceBomb = 137723785708403,
	Pvp_FunFireworks = 116322150278697,
	Pvp_FunHatLauncher = 114143203132186,
	Pvp_FunSqueaky = 72993429128584,
	Pvp_GooBlaster1 = 102597813981315,
	Pvp_GooBlaster2 = 77287889149557,
	Pvp_GooBlaster3 = 118148004083191,
	Pvp_GooTrap1 = 120019511635968,
	Pvp_GooTrap2 = 77139319310400,
	Pvp_GooTrap3 = 109811195391239,
	Pvp_KnockGlove1 = 97320008087030,
	Pvp_KnockGlove2 = 135576606024136,
	Pvp_KnockGlove3 = 117188261441907,
	Pvp_KnockGlove4 = 124623182677388,
	Pvp_KnockGlove5 = 70956878049152,
	Quest = 134202290579149,
	Rebirth = 111386939880268,
	Slap = 126349026044270,
	SpeedCoil = 122726751933466,
	Upgrade_CarrySpeed = 78961904430736,
	Upgrade_Income = 78599900293497,
	Upgrade_Luck = 138463958912705,
	Upgrade_OfflineCap = 119754785018464,
	Upgrade_RainMagnet = 117424238725252,
} :: { [string]: number }

-- Groups whose items are UI-drawn (ItemIconArt recipe per id). Kit-mesh plot skins stay "model"
-- (live mesh) and show their drawn diorama while the mesh is missing.
ItemIcons.DRAWN_GROUPS = table.freeze({
	shop = true,
	upgrade = true,
	boost = true,
	misc = true,
	code = true,
	goal = true,
	badge = true,
	skin = true,
})

-- Drawn groups without uploaded pictures yet: the same UI-drawn recipes (ItemIconArt), no IMAGES entry required.
-- The world shop's consumables live here until Archer renders them; all 19 PvP tools (Pvp_*) already have uploaded
-- pictures in IMAGES (PNGs in shared/modeling-kit/out/icons).
ItemIcons.DRAWN_ONLY_GROUPS = table.freeze({
	gear = true,
})

-- Items an artist must still render: in a DRAWN group but with no recipe worth shipping. Empty now.
-- The H1 HUD icons (group "hud", not drawn) keep their tile + glyph until Archer renders them.
ItemIcons.FOR_ARCHER = table.freeze({ "Income", "FriendBoost" } :: { string })

-- Kit meshes that exist in MeshAssets (shared/MeshAssets NAMES) and may back a "mesh" model.
ItemIcons.MESHES = table.freeze({
	PlotSkin_mushroom = "plot_skin_mushroom",
	PlotSkin_candy = "plot_skin_candy",
	PlotSkin_crystal = "plot_skin_crystal",
})

-- Tint of the slime shown for a mutation (the mutation's own look).
ItemIcons.MUTATION_TINTS = table.freeze({
	Glow = { 255, 240, 120 },
	Lava = { 255, 120, 50 },
	Galaxy = { 110, 80, 200 },
	Rainbow = { 255, 130, 200 },
	Gold = { 255, 200, 40 },
	Crystal = { 160, 230, 255 },
	Eclipse = { 40, 36, 70 },
	Wet = { 80, 170, 255 },
	Frozen = { 190, 235, 255 },
	Solar = { 255, 170, 60 },
	Nebula = { 170, 90, 210 },
	Aurora = { 90, 230, 190 },
	Royal = { 255, 215, 90 },
	Sleet = { 140, 200, 235 },
	Comet = { 120, 190, 255 },
})

local function freeze(spec: any): Spec
	return table.freeze(spec)
end

-- Items defined by hand: id, name, group, colour, glyph, brief.
type Hand = { id: string, name: string, group: string, color: { number }, glyph: string, brief: string }

local HAND: { Hand } = {
	{
		id = "Lock",
		name = "Lock base",
		group = "shop",
		color = { 90, 140, 230 },
		glyph = "🔒",
		brief = "Chunky brass padlock, closed, shackle up, blue enamel face plate; 3/4 view from front-left, soft shadow underneath. Defence gear.",
	},
	{
		id = "LockUpgrade",
		name = "Longer locks",
		group = "shop",
		color = { 70, 180, 200 },
		glyph = "⏱️",
		brief = "The brass padlock with a small stopwatch hung on its shackle and a little green up-arrow; 3/4 view, teal accents.",
	},
	{
		id = "SpeedCoil",
		name = "Speed Coil",
		group = "shop",
		color = { 255, 200, 50 },
		glyph = "⚡",
		brief = "A chunky metal spring coil standing upright, yellow-gold with a glowing white-yellow lightning bolt through the middle; slight top-down 3/4 view.",
	},
	{
		id = "MysteryEgg",
		name = "Mystery Egg",
		group = "shop",
		color = { 200, 120, 230 },
		glyph = "🥚",
		brief = "A big egg, cream shell with purple spots and a bold white question mark, tiny sparkles; front view, slightly tilted, soft glow behind.",
	},
	{
		id = "Slap",
		name = "Slap",
		group = "shop",
		color = { 255, 130, 80 },
		glyph = "👋",
		brief = "A cartoon open hand mid-slap (white glove, orange motion lines), side angle. PvP gear.",
	},
	{
		id = "Upgrade_Income",
		name = "Slime Snacks",
		group = "upgrade",
		color = { 235, 160, 70 },
		glyph = "🍪",
		brief = "A round cookie shaped like a slime with green goo drip, two chocolate-chip eyes; front view.",
	},
	{
		id = "Upgrade_CarrySpeed",
		name = "Strong Arms",
		group = "upgrade",
		color = { 230, 110, 90 },
		glyph = "💪",
		brief = "A flexed green slime arm with a bulging bicep and a gold wristband; side view.",
	},
	{
		id = "Upgrade_OfflineCap",
		name = "Night Shift",
		group = "upgrade",
		color = { 90, 90, 190 },
		glyph = "🌙",
		brief = "A yellow crescent moon with a sleeping slime curled in it and 3 small stars; night-blue accent.",
	},
	{
		id = "Upgrade_Luck",
		name = "Lucky Charm",
		group = "upgrade",
		color = { 90, 200, 100 },
		glyph = "🍀",
		brief = "A four-leaf clover with a gold coin at its centre and a glossy highlight; top-down view.",
	},
	{
		id = "Upgrade_RainMagnet",
		name = "Rain Magnet",
		group = "upgrade",
		color = { 90, 150, 230 },
		glyph = "🧲",
		brief = "A red-and-silver horseshoe magnet pulling three blue raindrops and a snowflake toward it; front view.",
	},
	{
		id = "Boost_Code",
		name = "Income boost",
		group = "boost",
		color = { 255, 190, 40 },
		glyph = "⚡",
		brief = "A glass potion bottle with glowing yellow liquid, lightning bolt on the label and a cork; 3/4 view.",
	},
	{
		id = "Boost_Blessed",
		name = "Blessed",
		group = "boost",
		color = { 170, 130, 255 },
		glyph = "✨",
		brief = "A glowing purple-white halo ring with sparkles around a small slime silhouette; front view.",
	},
	{
		id = "Boost_Weekend",
		name = "Weekend x2",
		group = "boost",
		color = { 255, 120, 90 },
		glyph = "x2",
		brief = "A big bold gold 'x2' on a party-confetti burst with a tiny calendar corner; front view.",
	},
	{
		id = "Boost_Friend",
		name = "Friend bonus",
		group = "boost",
		color = { 255, 140, 190 },
		glyph = "+10%",
		brief = "Two slimes high-fiving with a pink heart between them; front view.",
	},
	{
		id = "Perk_income",
		name = "Pet income perk",
		group = "boost",
		color = { 240, 190, 60 },
		glyph = "💰",
		brief = "A small cash bag with a gold coin popping out, a tiny slime ear on the bag; 3/4 view.",
	},
	{
		id = "Perk_luck",
		name = "Pet luck perk",
		group = "boost",
		color = { 90, 200, 100 },
		glyph = "🍀",
		brief = "A green clover leaf with a ladybug on it, front view.",
	},
	{
		id = "Perk_mutation",
		name = "Pet mutation perk",
		group = "boost",
		color = { 190, 100, 220 },
		glyph = "🧬",
		brief = "A purple-green DNA double helix twisting upward with a few bubbles; front view.",
	},
	{
		id = "Event_luck",
		name = "Luck Event",
		group = "boost",
		color = { 90, 200, 100 },
		glyph = "🍀",
		brief = "A shiny clover on a rainbow arc with a pot of gold coins at the foot; front view.",
	},
	{
		id = "Event_mutation",
		name = "Mutation Event",
		group = "boost",
		color = { 190, 100, 220 },
		glyph = "🧬",
		brief = "A bubbling flask with a glowing rainbow-green slime inside and DNA sparks; 3/4 view.",
	},
	{
		id = "Event_rain",
		name = "Slime Rain",
		group = "boost",
		color = { 80, 170, 255 },
		glyph = "🌧",
		brief = "A blue storm cloud raining green slime droplets; front view.",
	},
	{
		id = "Appraise",
		name = "Appraise",
		group = "misc",
		color = { 120, 190, 220 },
		glyph = "🔍",
		brief = "A big magnifying glass with a gold frame over a sparkling slime; 3/4 view.",
	},
	{
		id = "Daily",
		name = "Daily reward",
		group = "misc",
		color = { 255, 190, 70 },
		glyph = "📅",
		brief = "A tear-off calendar page with a gold star stamp and a small wrapped gift; front view.",
	},
	{
		id = "Rebirth",
		name = "Rebirth",
		group = "misc",
		color = { 120, 220, 170 },
		glyph = "♻️",
		brief = "A slime shaped like a green circular arrow with golden sparkles; front view.",
	},
	{
		id = "Cash",
		name = "Cash",
		group = "misc",
		color = { 255, 200, 60 },
		glyph = "💰",
		brief = "A pile of chunky gold coins with a $ stamp on the top coin; 3/4 view.",
	},
	{
		id = "Income",
		name = "Income per second",
		group = "hud",
		color = { 110, 210, 100 },
		glyph = "📈",
		brief = "A green up-arrow rising out of a small stack of gold coins; front view.",
	},
	{
		id = "FriendBoost",
		name = "Friend boost",
		group = "hud",
		color = { 90, 200, 120 },
		glyph = "👥",
		brief = "Two smiling slimes (green and pink) side by side with a small gold plus sign; front view.",
	},
	{
		id = "Gift",
		name = "Gift",
		group = "misc",
		color = { 190, 90, 200 },
		glyph = "🎁",
		brief = "A purple gift box with a gold ribbon bow, lid slightly open with sparkles; 3/4 view.",
	},
	{
		id = "Quest",
		name = "Quest",
		group = "misc",
		color = { 230, 120, 80 },
		glyph = "🎯",
		brief = "A bullseye target with a gold arrow stuck in the centre; 3/4 view.",
	},
}

local GOAL_GLYPHS: { [string]: { glyph: string, color: { number }, what: string } } = {
	Catch = { glyph = "🥅", color = { 90, 190, 120 }, what = "a butterfly-style net holding a green slime" },
	Merge = { glyph = "🌀", color = { 150, 110, 230 }, what = "two slimes swirling into one purple slime" },
	Steal = { glyph = "💨", color = { 235, 90, 90 }, what = "a masked slime sprinting with a sack of loot" },
	Lock = { glyph = "🔒", color = { 90, 140, 230 }, what = "the blue padlock with a gold star" },
	Pads = { glyph = "🟩", color = { 100, 190, 110 }, what = "a stone pad with a green glow and a slime on it" },
	Earn = { glyph = "💰", color = { 255, 200, 60 }, what = "a tall stack of gold coins" },
	Rebirth = { glyph = "♻️", color = { 120, 220, 170 }, what = "the green rebirth arrow with sparkles" },
}
local GOAL_DEFAULT = { glyph = "🎯", color = { 230, 120, 80 }, what = "a bullseye with an arrow" }

local BADGE_COLOR = { 255, 200, 60 }
local CONSUMABLE_COLORS: { [string]: { number } } =
	{ MutationSpray = { 190, 120, 230 }, LuckPotion = { 70, 190, 90 }, WeatherTotem = { 150, 155, 170 } }
local PVP_COLORS: { [string]: { number } } =
	{ Knockback = { 230, 120, 80 }, Trap = { 110, 200, 120 }, Blaster = { 90, 160, 240 }, Fun = { 255, 200, 60 } }
local PVP_GLYPHS: { [string]: string } = { Knockback = "🥊", Trap = "🟢", Blaster = "🔫", Fun = "🎉" }

local function finish(partial: { [string]: any }): Spec
	local model = partial.model
	local image = ItemIcons.IMAGES[partial.id]
	partial.image = image
	local drawn = (ItemIcons.DRAWN_GROUPS[partial.group] or ItemIcons.DRAWN_ONLY_GROUPS[partial.group])
		and not table.find(ItemIcons.FOR_ARCHER, partial.id)
	partial.source = if model then "model" elseif image then "image" elseif drawn then "drawn" else "placeholder"
	return freeze(partial)
end

-- The registry for `config` (shared Config). `order` is the stable id list.
function ItemIcons.build(config: any)
	local byId: { [string]: Spec } = {}
	local order: { string } = {}

	local function add(partial: { [string]: any })
		assert(byId[partial.id] == nil, `duplicate item icon {partial.id}`)
		local spec = finish(partial)
		byId[spec.id] = spec
		table.insert(order, spec.id)
	end

	for _, h in HAND do
		add({
			id = h.id,
			name = h.name,
			group = h.group,
			color = h.color,
			glyph = h.glyph,
			brief = h.brief,
		})
	end

	for _, u in config.UPGRADES do
		assert(byId[`Upgrade_{u.id}`], `UPGRADES {u.id} has no item icon`)
	end

	-- World shop rows (Shared.Shops): consumables and PvP tools, UI-drawn like the other shop items.
	for _, c in config.CONSUMABLES do
		add({
			id = `Consumable_{c.id}`,
			name = c.name,
			group = "gear",
			color = CONSUMABLE_COLORS[c.id] or { 120, 180, 220 },
			glyph = c.icon,
			brief = `{c.name}: {c.text}`,
		})
	end
	for _, t in config.PVP_TOOLS do
		add({
			id = `Pvp_{t.id}`,
			name = t.name,
			group = "gear",
			color = PVP_COLORS[t.line] or { 150, 150, 170 },
			glyph = PVP_GLYPHS[t.line] or "🎯",
			brief = `{t.name} ({t.line} tier {t.tier}), a PvP item.`,
		})
	end

	for _, mutations in { config.MUTATIONS, config.WEATHER_MUTATIONS, config.COMBOS, config.WEATHER_COMBOS } do
		for _, m in mutations do
			local tint = ItemIcons.MUTATION_TINTS[m.name]
			add({
				id = `Mutation_{m.name}`,
				name = m.displayName,
				group = "mutation",
				color = tint or { 160, 160, 160 },
				glyph = "🧬",
				model = { kind = "slime", mutation = m.name },
				brief = `{m.displayName} slime (has a 3D slime preview)`,
			})
		end
	end

	for id, def in config.CODES do
		local boost = def.reward.kind == "boost"
		add({
			id = `Code_{id}`,
			name = `Code {id}`,
			group = "code",
			color = if boost then { 255, 190, 40 } else { 255, 200, 60 },
			glyph = if boost then "⚡" else "💰",
			brief = if boost
				then "The income-boost potion (same art as Boost_Code), labelled with the code's multiplier."
				else "The cash coin pile (same art as Cash).",
		})
	end

	for _, g in config.GOALS do
		local style = GOAL_GLYPHS[g.id] or GOAL_DEFAULT
		add({
			id = `Goal_{g.id}`,
			name = g.id,
			group = "goal",
			color = style.color,
			glyph = style.glyph,
			brief = `Goal '{g.id}': {style.what}; front view.`,
		})
	end

	for i, m in config.DEX_MILESTONES do
		add({
			id = `Dex_{m.count}`,
			name = `Dex {m.count}`,
			group = "goal",
			color = { 255, 200 - math.min(i, 7) * 12, 80 },
			glyph = "🏆",
			brief = `Gold trophy with a slime on top and the number {m.count} on the base; front view.`,
		})
	end

	for _, b in config.BADGES do
		add({
			id = `Badge_{b.key}`,
			name = b.name,
			group = "badge",
			color = BADGE_COLOR,
			glyph = "⭐",
			brief = `Round gold medal for '{b.name}' with a ribbon and a small emblem; front view.`,
		})
	end

	for _, s in config.PLOT_SKINS do
		local mesh = ItemIcons.MESHES[`PlotSkin_{s.id}`]
		add({
			id = `PlotSkin_{s.id}`,
			name = s.name,
			group = "skin",
			color = if s.fence then s.fence else { 200, 200, 200 },
			glyph = "🏡",
			model = if mesh then { kind = "mesh", mesh = mesh } else nil,
			brief = `Mini diorama of the '{s.name}' plot (floor, fence and decor); 3/4 view from above.`,
		})
	end

	return {
		byId = byId,
		order = order,
		get = function(id: string): Spec?
			return byId[id]
		end,
		-- Always a spec: unknown ids get a neutral "?" tile.
		resolve = function(id: any): Spec
			local spec = if type(id) == "string" then byId[id] else nil
			return spec or ItemIcons.UNKNOWN
		end,
	}
end

-- The registry of a panel ctx: ctx.itemIcons, built from ctx.Config on first use.
function ItemIcons.of(ctx: any)
	if ctx.itemIcons == nil then
		ctx.itemIcons = ItemIcons.build(ctx.Config)
	end
	return ctx.itemIcons
end

ItemIcons.UNKNOWN = freeze({
	id = "Unknown",
	name = "Item",
	group = "misc",
	color = { 120, 125, 150 },
	glyph = "?",
	source = "placeholder",
	brief = "Unknown item",
})

-- Items still lacking art: no model and no uploaded image.
function ItemIcons.needsArt(registry: any): { Spec }
	local out = {}
	for _, id in registry.order do
		local spec: Spec = registry.byId[id]
		if spec.source == "placeholder" then
			table.insert(out, spec)
		end
	end
	return out
end

-- Toast text -> item id (Notify carries no item id): first matching rule wins.
local TOAST_RULES: { { pattern: string, id: string } } = {
	{ pattern = "^Speed Coil bought", id = "SpeedCoil" },
	{ pattern = "^Longer locks", id = "LockUpgrade" },
	{ pattern = "^Your egg hatched", id = "MysteryEgg" },
	{ pattern = "^Code redeemed", id = "Gift" },
	{ pattern = "^Daily reward", id = "Daily" },
	{ pattern = "^Appraised for", id = "Appraise" },
	{ pattern = "^Base locked", id = "Lock" },
	{ pattern = "^Your base is unlocked", id = "Lock" },
	{ pattern = "slapped", id = "Slap" },
	{ pattern = "^Rebirth %d", id = "Rebirth" },
	{ pattern = "income boost ended", id = "Boost_Code" },
	{ pattern = "Blessed", id = "Boost_Blessed" },
	{ pattern = "^Sold for", id = "Cash" },
	{ pattern = "^Plot skin:", id = "PlotSkin_classic" },
	{ pattern = "^Slime Rain", id = "Event_rain" },
	{ pattern = "^SLIME RAIN", id = "Event_rain" },
	{ pattern = "^Badge unlocked", id = "Badge_FirstSlime" },
}

-- Upgrade level-ups read "<Upgrade name> level N!": match by the upgrade's name.
function ItemIcons.forToast(text: any, config: any?): string?
	if type(text) ~= "string" then
		return nil
	end
	for _, rule in TOAST_RULES do
		if string.find(text, rule.pattern) then
			return rule.id
		end
	end
	if config then
		for _, u in config.UPGRADES do
			if string.find(text, u.name, 1, true) == 1 then
				return `Upgrade_{u.id}`
			end
		end
	end
	return nil
end

-- Local (client-derived) goal ids that reuse another item's art.
local GOAL_ALIASES: { [string]: string } = {
	FillPads = "Goal_Pads",
	AllPads = "Goal_Pads",
	BestTier = "Goal_Catch",
	Dex = "Dex_10",
}

-- Registry id for a Goals panel row: server goal ids (Catch, Merge, ...) and the local ones (FillPads, Daily, ...).
function ItemIcons.forGoal(registry: any, goalId: any): string
	if type(goalId) ~= "string" then
		return "Quest"
	end
	for _, candidate in { `Goal_{goalId}`, GOAL_ALIASES[goalId] or "", goalId } do
		if registry.byId[candidate] then
			return candidate
		end
	end
	return "Quest"
end

-- The registry id of a Config.BADGES key.
function ItemIcons.badge(key: string): string
	return `Badge_{key}`
end

-- The shop UI's icon id for a Shops item (CONTRACT.md §27): upgrades, consumables and PvP tools live under a
-- prefix in the registry (their bare ids clash with item ids / are not unique), everything else is its own id.
-- Look the picture up with `ItemIcons.IMAGES[ItemIcons.shopIconId(item)]` or
-- `registry.resolve(ItemIcons.shopIconId(item))`. Same mapping as WorldShopLogic.iconId.
ItemIcons.SHOP_ICON_PREFIX = table.freeze({
	BuyUpgrade = "Upgrade_",
	BuyConsumable = "Consumable_",
	BuyPvpItem = "Pvp_",
} :: { [string]: string })

function ItemIcons.shopIconId(item: { id: string, action: string? }): string
	local prefix = if item.action then ItemIcons.SHOP_ICON_PREFIX[item.action] else nil
	return (prefix or "") .. item.id
end

return table.freeze(ItemIcons)
