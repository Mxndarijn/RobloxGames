--!strict
--[[
	Strings: every player-facing English string in Steal a Slime, by key (shared/luau Localize).

	One module per area; each key starts with its module's prefix ("hud.", "shop.", ...), so two areas never
	collide. Data names and descriptions (rarities, upgrades, skins, ...) are built from Config in Data, under
	"data.<kind>.<id>.<field>" (Strings.dataKey), so Config stays the one place their English is written.
	The client turns keys into the player's language with ui/Text; server-made world text goes through
	server/WorldText. scripts/gen-locale.luau writes the catalog to locale/Strings.csv, the LocalizationTable
	shipped under LocalizationService (tests/Locale.spec fails when it is stale).

	What stays untranslated, by design: player names, slime species and boss names (proper nouns), the game's
	name, redeem codes, and numbers (shared NumberFormat: "$1.25K", "4m 05s").
]]

local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Localize = if Lib then require(Lib.locale.Localize) else require("../../../../shared/luau/src/locale/Localize")

local Common = if script then require(script.Common) else require("@self/Common")
local Hud = if script then require(script.Hud) else require("@self/Hud")
local Onboarding = if script then require(script.Onboarding) else require("@self/Onboarding")
local Shop = if script then require(script.Shop) else require("@self/Shop")
local Collection = if script then require(script.Collection) else require("@self/Collection")
local Menus = if script then require(script.Menus) else require("@self/Menus")
local World = if script then require(script.World) else require("@self/World")
local Data = if script then require(script.Data) else require("@self/Data")
local DataKey = if script then require(script.DataKey) else require("@self/DataKey")

local Strings = {}

-- Area modules, in catalog order, with the key prefix each one owns.
Strings.AREAS = table.freeze({
	{ name = "Common", prefix = "common.", defs = Common :: any },
	{ name = "Hud", prefix = "hud.", defs = Hud :: any },
	{ name = "Onboarding", prefix = "onboarding.", defs = Onboarding :: any },
	{ name = "Shop", prefix = "shop.", defs = Shop :: any },
	{ name = "Collection", prefix = "collection.", defs = Collection :: any },
	{ name = "Menus", prefix = "menus.", defs = Menus :: any },
	{ name = "World", prefix = "world.", defs = World :: any },
	{ name = "Data", prefix = "data.", defs = Data :: any },
})

-- Data keys (DataKey): Strings.keyPart(id) and Strings.dataKey(kind, id, field) = "data.<kind>.<id>.<field>".
Strings.keyPart = DataKey.keyPart
Strings.dataKey = DataKey.dataKey

local groups: { any } = {}
for _, area in Strings.AREAS do
	table.insert(groups, area.defs)
end

Strings.catalog = Localize.catalog(groups)

return table.freeze(Strings)
