--!strict
-- The catalog keys of data names and descriptions: "data.<kind>.<id>.<field>". Pure; Strings and Strings.Data
-- both use it (Strings re-exports keyPart and dataKey).

local DataKey = {}

-- One key part from a data id: anything that is not a letter, digit or underscore becomes "_", and an id
-- that starts with a digit gets an "n" in front (Localize keys start with a letter).
function DataKey.keyPart(id: any): string
	local part = string.gsub(tostring(id), "[^%w_]", "_")
	if not string.match(part, "^%a") then
		part = "n" .. part
	end
	return part
end

-- The key of a data field: "data.<kind>.<id>.<field>" (field defaults to "name").
function DataKey.dataKey(kind: string, id: any, field: string?): string
	return `data.{kind}.{DataKey.keyPart(id)}.{field or "name"}`
end

return table.freeze(DataKey)
