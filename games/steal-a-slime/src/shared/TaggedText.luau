--!strict
--[[
	TaggedText: a translated text property on an Instance built by shared builder code (Props, ObbyParts, ...),
	on the server or on a client. It writes the English and keeps the message in the LocalizedTree attribute
	(`L10n_<Property>`, JSON) with the `Localized` tag; the client's watcher (ui/init.client) writes the player's
	language into every tagged instance, wherever it was made. No Roblox API at load time.

	  TaggedText.set(label, "Text", "world.sign.guide")
	  TaggedText.setMessage(label, "Text", Localize.msg("world.board.title", { stat = "..." }))
	  TaggedText.english(message) -> string

	Server code uses server/WorldText, which is this plus a few message helpers.
]]

local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local Localize = if Lib then require(Lib.locale.Localize) else require("../../../../shared/luau/src/locale/Localize")
local LocalizedTree = if Lib
	then require(Lib.locale.LocalizedTree)
	else require("../../../../shared/luau/src/locale/LocalizedTree")
local Strings = if script then require(script.Parent.Strings) else require("./Strings")

-- JSON and tags from the engine (looked up on first use, so `english` needs no services); under Lune,
-- @lune/serde and the instance's own AddTag.
local encodeJson: (any) -> string
local tag: (any, string) -> ()
if script then
	encodeJson = function(value: any): string
		return (game:GetService("HttpService") :: any):JSONEncode(value)
	end
	tag = function(inst: any, name: string)
		(game:GetService("CollectionService") :: any):AddTag(inst, name)
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

local TaggedText = {}

local deps: LocalizedTree.ServerDeps = {
	english = function(message: any): string
		return Localize.english(Strings.catalog, message)
	end,
	encode = encodeJson,
	addTag = tag,
}

function TaggedText.setMessage(inst: Instance, property: string, message: Localize.Text)
	LocalizedTree.set(inst, property, message, deps)
end

function TaggedText.set(inst: Instance, property: string, key: string, args: Localize.Args?)
	LocalizedTree.set(inst, property, Localize.msg(key, args), deps)
end

-- The message of `key` when the catalog has it with `english` as its source, else `english` itself (a data table's
-- text that a test or a new row may change before the catalog does).
function TaggedText.known(key: string, english: string): Localize.Text
	local entry = Strings.catalog.byKey[key]
	return if entry and entry.source == english then Localize.msg(key) else english
end

-- The English for a message (or a plain string as it is).
function TaggedText.english(message: Localize.Text): string
	return Localize.english(Strings.catalog, message)
end

return table.freeze(TaggedText)
