--!strict
--[[
	ReceiptLedger (pure)

	The rules for Roblox Developer Product receipts kept in a player's save: a capped list of processed purchase
	ids (newest last) and the decision for one receipt. A receipt is answered "Granted" only once its grant and
	its id are both saved; anything else is "NotProcessedYet", so Roblox asks again later.

	  * `clean(raw, cap)`: a list of unique non-empty strings, at most `cap` (the newest kept), from untrusted data.
	  * `seen(list, id)` / `record(list, id, cap)`: lookup and append (dropping the oldest past `cap`).
	  * `process(request)`: the whole decision. A new id runs `grant`, is recorded and marked pending until `save`
	    succeeds. An id already in the list but still pending is saved again before it counts as granted, so a
	    grant that only lives in memory is never confirmed to Roblox.

	`pending` is runtime state the adapter owns (never saved). No Roblox APIs.
]]

export type Decision = "Granted" | "NotProcessedYet"

export type Request = {
	list: { string }, -- the saved receipt list (mutated: the new id is appended)
	id: string, -- the receipt's PurchaseId
	cap: number, -- most ids kept
	pending: { [string]: boolean }, -- ids granted in memory whose save has not succeeded yet (mutated)
	grant: () -> (boolean, string?), -- applies the purchase; false = nothing changed, ask again later
	save: () -> boolean, -- writes the save now (may yield); true = written
}

local ReceiptLedger = {}

local MAX_ID_LENGTH = 128

local function validId(id: any): boolean
	return type(id) == "string" and #id > 0 and #id <= MAX_ID_LENGTH
end

function ReceiptLedger.clean(raw: any, cap: number): { string }
	local out: { string } = {}
	if type(raw) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, id in ipairs(raw) do
		if validId(id) and not seen[id] then
			seen[id] = true
			table.insert(out, id)
		end
	end
	while #out > math.max(0, cap) do
		table.remove(out, 1)
	end
	return out
end

function ReceiptLedger.seen(list: { string }, id: string): boolean
	return table.find(list, id) ~= nil
end

-- Appends `id` unless it is already there; drops the oldest ids past `cap`. Returns whether it was added.
function ReceiptLedger.record(list: { string }, id: string, cap: number): boolean
	if not validId(id) or ReceiptLedger.seen(list, id) then
		return false
	end
	table.insert(list, id)
	while #list > math.max(1, cap) do
		table.remove(list, 1)
	end
	return true
end

-- Decides one receipt. Returns the decision and a short reason for "NotProcessedYet"
-- ("BadId" | "GrantFailed" | "SaveFailed").
function ReceiptLedger.process(request: Request): (Decision, string?)
	local list, id, pending = request.list, request.id, request.pending
	if not validId(id) then
		return "NotProcessedYet", "BadId"
	end
	if ReceiptLedger.seen(list, id) and not pending[id] then
		return "Granted", nil
	end
	if not ReceiptLedger.seen(list, id) then
		local ok = request.grant()
		if not ok then
			return "NotProcessedYet", "GrantFailed"
		end
		ReceiptLedger.record(list, id, request.cap)
		pending[id] = true
	end
	if not request.save() then
		return "NotProcessedYet", "SaveFailed"
	end
	pending[id] = nil
	return "Granted", nil
end

return table.freeze(ReceiptLedger)
