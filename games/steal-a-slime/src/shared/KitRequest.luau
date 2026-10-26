--!strict
--[[
	KitRequest (pure)

	The `RequestKits` action (CONTRACT.md §3): the client asks for the species meshes a SlimeDex or rebirth preview
	is about to show, instead of every client getting every kit at join. The argument is up to MAX species ids
	joined by "," (`"gummy,mochi"`); `parse` turns it into kit names (`slime_<id>`, SlimeLooks.KITS) and refuses
	anything else, `encode` builds it on the client.
]]

local SlimeLooks = if script then require(script.Parent.SlimeLooks) else require("./SlimeLooks")

local KitRequest = {}

KitRequest.MAX = 16 -- species per request: more than one SlimeDex screen of live previews (SlimePreview.MAX_LIVE)
KitRequest.MAX_ID_LENGTH = 32
-- MAX ids of MAX_ID_LENGTH and the commas between them.
KitRequest.MAX_LENGTH = KitRequest.MAX * (KitRequest.MAX_ID_LENGTH + 1)

local KIT_SET: { [string]: boolean } = {}
for _, kit in SlimeLooks.KITS do
	KIT_SET[kit] = true
end
table.freeze(KIT_SET)

-- The kit a species wears ("slime_<id>"), or nil when the species has no kit of its own.
function KitRequest.kitOf(speciesId: string): string?
	local kit = `slime_{speciesId}`
	return if KIT_SET[kit] then kit else nil
end

-- Kit names for a client request string, in order and without repeats, or nil when it is malformed: not a string,
-- too long, empty, more than MAX ids, or an id with no kit.
function KitRequest.parse(raw: any): { string }?
	if type(raw) ~= "string" or #raw == 0 or #raw > KitRequest.MAX_LENGTH then
		return nil
	end
	local parts = string.split(raw, ",")
	if #parts > KitRequest.MAX then
		return nil
	end
	local out: { string } = {}
	local seen: { [string]: boolean } = {}
	for _, id in parts do
		if #id == 0 or #id > KitRequest.MAX_ID_LENGTH then
			return nil
		end
		local kit = KitRequest.kitOf(id)
		if kit == nil then
			return nil
		end
		if not seen[kit] then
			seen[kit] = true
			table.insert(out, kit)
		end
	end
	return out
end

-- The request strings for `speciesIds` (species without a kit are dropped), at most MAX ids each.
function KitRequest.encode(speciesIds: { string }): { string }
	local out: { string } = {}
	local batch: { string } = {}
	for _, id in speciesIds do
		if #id <= KitRequest.MAX_ID_LENGTH and KitRequest.kitOf(id) then
			table.insert(batch, id)
			if #batch == KitRequest.MAX then
				table.insert(out, table.concat(batch, ","))
				batch = {}
			end
		end
	end
	if #batch > 0 then
		table.insert(out, table.concat(batch, ","))
	end
	return out
end

return table.freeze(KitRequest)
