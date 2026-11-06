--!strict
--[[
	WorldText: translated text on instances the server makes (ProximityPrompt ActionText / ObjectText, TextLabels
	in world BillboardGuis and SurfaceGuis). Every client shows its own language: the server writes the English
	and keeps the message in an attribute (shared/luau locale/LocalizedTree, through shared/TaggedText); ui/init.client
	watches the tag and writes the player's language.

	  WorldText.set(prompt, "ActionText", "world.prompt.lock_base")
	  WorldText.set(prompt, "ObjectText", "world.prompt.free_plot")
	  WorldText.setMessage(label, "Text", WorldText.msg("world.prompt.buy_price", { price = "$1.2K" }))

	Message args can be messages themselves (a translated item name inside a sentence).

	  WorldText.data("rarity", "Rare", "name", "Rare")   -- a data name's message, or the English when the catalog
	                                                      -- has no such key
	  WorldText.slime(slime)                              -- a slime's display name as a message (Genome.displayName)
]]

local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Localize = if Lib then require(Lib.locale.Localize) else require("../../../../shared/luau/src/locale/Localize")
local Strings = if Shared then require(Shared.Strings) else require("../shared/Strings")
local TaggedText = if Shared then require(Shared.TaggedText) else require("../shared/TaggedText")
local EggKind = if Shared then require(Shared.EggKind) else require("../shared/EggKind")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local PlayerSettings = if Shared then require(Shared.PlayerSettings) else require("../shared/PlayerSettings")

local WorldText = {}

WorldText.setMessage = TaggedText.setMessage
WorldText.set = TaggedText.set

-- A message value (Localize.msg).
WorldText.msg = Localize.msg

-- The message of data field "data.<kind>.<id>.<field>" (Strings.dataKey), or `english` when the catalog lacks it.
function WorldText.data(kind: string, id: any, field: string?, english: string): Localize.Text
	local key = Strings.dataKey(kind, id, field)
	return if Localize.has(Strings.catalog, key) then Localize.msg(key) else english
end

-- A player name as a world board shows it: PlayerSettings.HIDDEN_NAME (a player hidden from boards) as its message,
-- any other name as it is.
function WorldText.boardName(name: string): Localize.Text
	if name == PlayerSettings.HIDDEN_NAME then
		return WorldText.data("playerSettings", "hidden", "name", name)
	end
	return name
end

-- A slime's display name (Genome.displayName) as a message: the shine and rarity words translated, the species
-- name as it is; an egg shows its egg name.
function WorldText.slime(slime: any): Localize.Message
	local kind = EggKind.of(slime)
	if kind then
		return Localize.msg("common.egg_name", { kind = WorldText.data("eggKind", kind.id, "name", kind.name) })
	end
	local rarity = Genome.rarity(slime.tier).name
	local args: Localize.Args = {
		rarity = WorldText.data("rarity", rarity, "name", rarity),
		name = tostring(slime.name or ""),
	}
	local shine = Genome.shine(slime)
	if shine then
		args.shine = WorldText.data("shine", shine.id, "name", tostring(slime.shine))
		return Localize.msg("common.slime_shine", args)
	end
	return Localize.msg("common.slime", args)
end

-- The English for a message (server logs, a fallback where no instance carries it).
WorldText.english = TaggedText.english

return table.freeze(WorldText)
