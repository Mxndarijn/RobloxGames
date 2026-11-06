--!strict
--[[
	Player-facing English for the data area (keys start with "data."). Localize.catalog checks it.

	Built from the game data when it loads, so Config (and the few shared modules below) stay the one place this
	English is written. Every key is DataKey.dataKey(kind, id, field) = "data.<kind>.<id>.<field>"; the client
	reads them with Text.data(kind, id, field, english). The id is the row's `id`, else its `name` (or `title`
	/ `key` where that is the row's id), else the map key; the field is the source field's name.

	Kinds:
	  rarity                 Config.RARITIES, id = name: name
	  upgrade                Config.UPGRADES: name, text
	  rebirthTier            Config.REBIRTH_TIERS, id = title: title
	  goal                   Config.GOALS: title.one / title.other (count keys, {count} = the target)
	  dailyQuest             Config.DAILY_QUESTS.pool: title.one / title.other (count keys, {count} = the target);
	                         boost.reward: a boost reward on the quest card ({mult}, {minutes})
	  plotSkin               Config.PLOT_SKINS: name
	  plotBase               Config.PLOT_BASES: name
	  petSeat                Config.PET_SEATS: name
	  carryTrail             Config.EXCLUSIVE_SHOP.trails (CARRY_TRAILS): name
	  batSkin                Config.EXCLUSIVE_SHOP.batSkins: name
	  lockStyle              Config.EXCLUSIVE_SHOP.lockStyles: name
	  slimeHat               Config.EXCLUSIVE_SHOP.hats: name
	  season                 Config.EXCLUSIVE_SHOP.seasons, id = map key: name
	  pvpTool                Config.PVP_TOOLS: name
	  shine                  Config.SHINES: name (the id is the shown word: "Gold", "Diamond", "Rainbow")
	  consumable             Config.CONSUMABLES: name, text
	  eggKind                Config.MYSTERY_EGG.KINDS: name (shown inside "{kind} Mystery Egg", common.egg_name)
	  weather                Config.WEATHER, id = map key: displayName
	  modifier               Config.MODIFIERS, id = name: label
	  weeklyTrait            Config.WEEKLY.TRAITS: label
	  adminEvent             Config.ADMIN_EVENTS: label (the event banner every player sees)
	  badge                  Config.BADGES, id = key: name
	  bossBadge              Config.BOSS_BADGES, id = key: name, description
	  shops                  Shops.SHOPS, id = shop id: name
	  shopItem               every Shops item row, id = item id: name, text
	  playerSettings         PlayerSettings.TABS: tab key: label; entry id: name, hint, labels_<i> (choice
	                         buttons, in order); hidden.name (PlayerSettings.HIDDEN_NAME)
	  fountainTier           FountainTiers.FAMILIES: name; classic.name (FountainTiers.CLASSIC_NAME)
	  fountainLook           FountainTiers.LOOKS, id = tier: name
	  leaderboards           Leaderboards.BOARDS, id = stat: title

	Not here, by design: slime species and boss names (SlimeRoster, proper nouns: Text.slime passes them as
	they are), boss badge descriptions keep the boss name inside the sentence; ids, mesh names, analytics
	names; admin-only text (AdminCommands). Exclusive passes, products and subscriptions have no English in
	Config (their shop names live in the shop UI). Daily rewards have no English in Config either.
]]

local DataKey = if script then require(script.Parent.DataKey) else require("./DataKey")
local Config = if script then require(script.Parent.Parent.Config) else require("../Config")
local Shops = if script then require(script.Parent.Parent.Shops) else require("../Shops")
local PlayerSettings = if script then require(script.Parent.Parent.PlayerSettings) else require("../PlayerSettings")
local FountainTiers = if script then require(script.Parent.Parent.FountainTiers) else require("../FountainTiers")
local Leaderboards = if script then require(script.Parent.Parent.Leaderboards) else require("../Leaderboards")

local key = DataKey.dataKey

local defs: { [string]: any } = {}

-- Adds one entry. The same key from two rows must carry the same English.
local function add(k: string, def: any)
	local source = if type(def) == "table" then def.source else def
	local old = defs[k]
	if old ~= nil then
		local oldSource = if type(old) == "table" then old.source else old
		assert(oldSource == source, `Strings.Data: {k} has two sources ("{oldSource}", "{source}")`)
		return
	end
	defs[k] = def
end

-- Adds `row[field]` under (kind, id, field) when it is a non-empty string.
local function field(kind: string, id: any, row: any, name: string)
	local value = row[name]
	if type(value) == "string" and value ~= "" then
		add(key(kind, id, name), value)
	end
end

-- Every row of a list: `fields` of each, keyed by `idField` (default "id").
local function rows(kind: string, list: any, fields: { string }, idField: string?)
	for _, row in list do
		local id = row[idField or "id"]
		for _, name in fields do
			field(kind, id, row, name)
		end
	end
end

-- The two count forms of a "<n> ... <s>" title: ".one" drops "<s>", ".other" makes it "s"; "<n>" is {count}.
local function countTitle(kind: string, row: any)
	local base = key(kind, row.id, "title")
	local example = { count = if row.cash then "$10K" else "5" }
	local title = string.gsub(row.title, "<n>", "{count}")
	add(
		base .. ".one",
		{ source = (string.gsub(title, "<s>", "")), example = { count = if row.cash then "$1" else "1" } }
	)
	add(base .. ".other", { source = (string.gsub(title, "<s>", "s")), example = example })
end

-- Config ------------------------------------------------------------------------------------------------

rows("rarity", Config.RARITIES, { "name" }, "name")
rows("upgrade", Config.UPGRADES, { "name", "text" })
rows("rebirthTier", Config.REBIRTH_TIERS, { "title" }, "title")
for _, goal in Config.GOALS do
	countTitle("goal", goal)
end
for _, quest in Config.DAILY_QUESTS.pool do
	countTitle("dailyQuest", quest)
end
-- A boost reward on a daily quest card (Quests.view).
add("data.dailyQuest.boost.reward", { source = "{mult}x income for {minutes}m", example = { mult = 2, minutes = 5 } })
rows("plotSkin", Config.PLOT_SKINS, { "name" })
rows("plotBase", Config.PLOT_BASES, { "name" })
rows("petSeat", Config.PET_SEATS, { "name" })
rows("carryTrail", Config.EXCLUSIVE_SHOP.trails, { "name" })
rows("batSkin", Config.EXCLUSIVE_SHOP.batSkins, { "name" })
rows("lockStyle", Config.EXCLUSIVE_SHOP.lockStyles, { "name" })
rows("slimeHat", Config.EXCLUSIVE_SHOP.hats, { "name" })
for id, season in Config.EXCLUSIVE_SHOP.seasons do
	field("season", id, season, "name")
end
rows("pvpTool", Config.PVP_TOOLS, { "name" })
for _, shine in Config.SHINES do
	add(key("shine", shine.id, "name"), shine.id)
end
rows("consumable", Config.CONSUMABLES, { "name", "text" })
rows("eggKind", Config.MYSTERY_EGG.KINDS, { "name" })
for id, weather in Config.WEATHER do
	field("weather", id, weather, "displayName")
end
rows("modifier", Config.MODIFIERS, { "label" }, "name")
rows("weeklyTrait", Config.WEEKLY.TRAITS, { "label" })
rows("adminEvent", Config.ADMIN_EVENTS, { "label" })
rows("badge", Config.BADGES, { "name" }, "key")
rows("bossBadge", Config.BOSS_BADGES, { "name", "description" }, "key")

-- Other shared modules ------------------------------------------------------------------------------------

for id, shop in Shops.SHOPS do
	field("shops", id, shop, "name")
	rows("shopItem", shop.items, { "name", "text" })
end

for _, tab in PlayerSettings.TABS do
	field("playerSettings", tab.key, tab, "label")
	for _, entry in tab.entries do
		field("playerSettings", entry.id, entry, "name")
		field("playerSettings", entry.id, entry, "hint")
		for i, label in (entry :: any).labels or {} do
			add(key("playerSettings", entry.id, `labels_{i}`), label)
		end
	end
end
add(key("playerSettings", "hidden", "name"), PlayerSettings.HIDDEN_NAME)

rows("fountainTier", FountainTiers.FAMILIES, { "name" })
add(key("fountainTier", "classic", "name"), FountainTiers.CLASSIC_NAME)
for tier, look in FountainTiers.LOOKS do
	field("fountainLook", tier, look, "name")
end

rows("leaderboards", Leaderboards.BOARDS, { "title" }, "stat")

return defs
