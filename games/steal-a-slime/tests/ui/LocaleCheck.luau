--!strict
-- Shared by the translation specs: what a UI tree built under the pseudo-language (UiHarness.setLocale
-- "pseudo") still shows in plain English. Every catalog string comes out as "[Ácçéñtéd ...]", so a word left
-- outside brackets is a string that skipped ui/Text.
local Localize = require("../../../../shared/luau/src/locale/Localize")
local SlimeRoster = require("../../src/shared/SlimeRoster")
local UiHarness = require("./UiHarness")

local LocaleCheck = {}

-- Names that stay as they are in every language (Strings header): slime species and boss names, the test
-- player's name and the game's name. Longest first, so "Mecha Goo" goes before "Goo".
local NAMES: { string } = { "Tester", "Steal a Slime" }
for _, entry in SlimeRoster.ROSTER do
	table.insert(NAMES, entry.name)
end
table.sort(NAMES, function(a, b)
	return #a > #b
end)
LocaleCheck.NAMES = table.freeze(NAMES)

-- `text` with the proper nouns taken out.
function LocaleCheck.withoutNames(text: string): string
	for _, name in NAMES do
		local at = string.find(text, name, 1, true)
		while at do
			text = string.sub(text, 1, at - 1) .. string.sub(text, at + #name)
			at = string.find(text, name, 1, true)
		end
	end
	return text
end

local TEXT_PROPS = { "Text", "PlaceholderText" }

-- The path of `inst` from `root` ("Root/Card/Title").
function LocaleCheck.path(inst: any, root: any): string
	local parts = {}
	local node = inst
	while node and node ~= root do
		table.insert(parts, 1, node.Name)
		node = node.Parent
	end
	return table.concat(parts, "/")
end

-- "path: text" for every visible-text property under `root` that is not in the pseudo-language.
function LocaleCheck.untranslated(root: any): { string }
	local out = {}
	for _, inst in UiHarness.descendants(root) do
		if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
			for _, prop in TEXT_PROPS do
				local ok, value = pcall(function()
					return inst[prop]
				end)
				if
					ok
					and type(value) == "string"
					and value ~= ""
					and Localize.untranslated(LocaleCheck.withoutNames(value))
				then
					table.insert(out, `{LocaleCheck.path(inst, root)}.{prop}: {value}`)
				end
			end
		end
	end
	table.sort(out)
	return out
end

return LocaleCheck
