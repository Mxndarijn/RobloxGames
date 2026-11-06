--!strict
-- Shared by the translation specs: what a UI tree built under the pseudo-language (UiHarness.setLocale
-- "pseudo") still shows in plain English. Every catalog string comes out as "[Ácçéñtéd ...]", so a word left
-- outside brackets is a string that skipped ui/Text.
local Localize = require("../../../../shared/luau/src/locale/Localize")
local UiHarness = require("./UiHarness")

local LocaleCheck = {}

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
				if ok and type(value) == "string" and value ~= "" and Localize.untranslated(value) then
					table.insert(out, `{LocaleCheck.path(inst, root)}.{prop}: {value}`)
				end
			end
		end
	end
	table.sort(out)
	return out
end

return LocaleCheck
