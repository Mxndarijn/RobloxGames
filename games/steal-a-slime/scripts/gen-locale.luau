--!strict
-- lune run scripts/gen-locale  (from games/steal-a-slime)
-- Writes locale/Strings.csv, the LocalizationTable shipped under LocalizationService, from the Strings
-- catalog (src/shared/Strings). Rerun after adding or changing a string; tests/Locale.spec fails when stale.
-- The same file is what Merijn uploads to the experience's cloud localization table (docs/translations.md).
local fs = require("@lune/fs")

local Localize = require("../../../shared/luau/src/locale/Localize")
local Strings = require("../src/shared/Strings")

local PATH = "locale/Strings.csv"

if not fs.isDir("locale") then
	fs.writeDir("locale")
end
fs.writeFile(PATH, Localize.csv(Strings.catalog, Strings.manual))
print(`wrote {PATH} ({#Strings.catalog.entries} strings)`)
