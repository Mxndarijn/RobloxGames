--!strict
-- Player-facing English shared by many areas (keys start with "common."). Localize.catalog checks it.
return {
	["common.slime"] = { source = "{rarity} {name}", example = { rarity = "Rare", name = "Bubbles" } },
	["common.slime_shine"] = {
		source = "{shine} {rarity} {name}",
		example = { shine = "Gold", rarity = "Rare", name = "Bubbles" },
	},
	["common.egg_name"] = { source = "{kind} Mystery Egg", example = { kind = "Lava" } },
}
