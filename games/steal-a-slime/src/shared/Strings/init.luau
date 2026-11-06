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

local Strings = {}

-- Area modules, in catalog order, with the key prefix each one owns.
Strings.AREAS = table.freeze({
	{ name = "Common", prefix = "common.", defs = Common },
	{ name = "Hud", prefix = "hud.", defs = Hud },
	{ name = "Onboarding", prefix = "onboarding.", defs = Onboarding },
	{ name = "Shop", prefix = "shop.", defs = Shop },
	{ name = "Collection", prefix = "collection.", defs = Collection },
	{ name = "Menus", prefix = "menus.", defs = Menus },
	{ name = "World", prefix = "world.", defs = World },
	{ name = "Data", prefix = "data.", defs = Data },
})

-- One key part from a data id: anything that is not a letter, digit or underscore becomes "_", and an id
-- that starts with a digit gets an "n" in front (Localize keys start with a letter).
function Strings.keyPart(id: any): string
	local part = string.gsub(tostring(id), "[^%w_]", "_")
	if not string.match(part, "^%a") then
		part = "n" .. part
	end
	return part
end

-- The key of a data field: "data.<kind>.<id>.<field>" (field defaults to "name").
function Strings.dataKey(kind: string, id: any, field: string?): string
	return `data.{kind}.{Strings.keyPart(id)}.{field or "name"}`
end

local groups = {}
for _, area in Strings.AREAS do
	table.insert(groups, area.defs)
end

Strings.catalog = Localize.catalog(groups)

return table.freeze(Strings)
