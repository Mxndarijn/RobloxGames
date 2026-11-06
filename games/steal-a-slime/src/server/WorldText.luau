--!strict
--[[
	WorldText: translated text on instances the server makes (ProximityPrompt ActionText / ObjectText, TextLabels
	in world BillboardGuis and SurfaceGuis). Every client shows its own language: the server writes the English
	and keeps the message in an attribute (shared/luau locale/LocalizedTree); ui/init.client watches the tag and
	writes the player's language.

	  WorldText.set(prompt, "ActionText", "world.lock_base")
	  WorldText.set(prompt, "ObjectText", "world.base_owner", { name = player.DisplayName })
	  WorldText.setMessage(label, "Text", Localize.msg("world.cost", { price = "$1.2K" }))

	Message args can be messages themselves (a translated item name inside a sentence).
]]

local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Localize = if Lib then require(Lib.locale.Localize) else require("../../../../shared/luau/src/locale/Localize")
local LocalizedTree = if Lib
	then require(Lib.locale.LocalizedTree)
	else require("../../../../shared/luau/src/locale/LocalizedTree")
local Strings = if Shared then require(Shared.Strings) else require("../shared/Strings")

-- JSON and tags from the engine; under Lune, @lune/serde and the instance's own AddTag.
local encodeJson: (any) -> string
local tag: (any, string) -> ()
if script then
	local HttpService = game:GetService("HttpService")
	local CollectionService = game:GetService("CollectionService")
	encodeJson = function(value: any): string
		return HttpService:JSONEncode(value)
	end
	tag = function(inst: any, name: string)
		CollectionService:AddTag(inst, name)
	end
else
	local serde = (require :: any)("@lune/serde")
	encodeJson = function(value: any): string
		return serde.encode("json", value)
	end
	tag = function(inst: any, name: string)
		inst:AddTag(name)
	end
end

local WorldText = {}

local deps: LocalizedTree.ServerDeps = {
	english = function(message: any): string
		return Localize.english(Strings.catalog, message)
	end,
	encode = encodeJson,
	addTag = tag,
}

function WorldText.setMessage(inst: Instance, property: string, message: Localize.Message)
	LocalizedTree.set(inst, property, message, deps)
end

function WorldText.set(inst: Instance, property: string, key: string, args: Localize.Args?)
	LocalizedTree.set(inst, property, Localize.msg(key, args), deps)
end

-- The English for a message (server logs, a fallback where no instance carries it).
function WorldText.english(message: Localize.Text): string
	return Localize.english(Strings.catalog, message)
end

return table.freeze(WorldText)
