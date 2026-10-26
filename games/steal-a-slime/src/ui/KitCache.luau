--!strict
--[[
	KitCache

	Asks the server for the species kit meshes the previews are about to show (`RequestKits`, KitRequest), instead
	of every client getting every kit at join. SpeciesModel calls `want(speciesId)` when a kit is not in the
	player's kit folder yet; wants made in the same moment go out together, at most KitRequest.MAX per call and one
	call per GAP seconds (the server's rate limit). A refused or failed call is tried again, up to TRIES times per
	species. A species is asked for once: the server sends its kit when it has loaded (or never, when it failed),
	and the preview keeps its fallback look until then. Arrivals are the kit folder's business (init.client).
]]

export type Deps = {
	KitRequest: any, -- Shared.KitRequest
	invoke: (raw: string) -> boolean, -- sends one RequestKits (yields); true = the server accepted it
	delay: (seconds: number, fn: () -> ()) -> (), -- runs the sender later (task.delay)
}

export type KitCache = {
	want: (speciesId: string) -> (),
	asked: (speciesId: string) -> boolean, -- accepted by the server, or given up on (tests)
}

local KitCache = {}

KitCache.GAP = 0.3 -- seconds between two calls: above Validate.ACTIONS.RequestKits
KitCache.TRIES = 3

function KitCache.new(deps: Deps): KitCache
	local KitRequest = deps.KitRequest
	local asked: { [string]: boolean } = {}
	local queued: { [string]: boolean } = {}
	local tries: { [string]: number } = {}
	local order: { string } = {}
	local running = false

	-- Sends one batch, then the next one GAP seconds later while wants are left.
	local function pump()
		local batch: { string } = {}
		while #order > 0 and #batch < KitRequest.MAX do
			local id = table.remove(order, 1) :: string
			queued[id] = nil
			table.insert(batch, id)
		end
		local raw = KitRequest.encode(batch)[1]
		local ok = raw ~= nil and deps.invoke(raw)
		for _, id in batch do
			tries[id] = (tries[id] or 0) + 1
			if ok or tries[id] >= KitCache.TRIES then
				asked[id] = true
			elseif not queued[id] then
				queued[id] = true
				table.insert(order, id)
			end
		end
		if #order > 0 then
			deps.delay(KitCache.GAP, pump)
		else
			running = false
		end
	end

	local function want(speciesId: string)
		if asked[speciesId] or queued[speciesId] then
			return
		end
		if KitRequest.kitOf(speciesId) == nil or #speciesId > KitRequest.MAX_ID_LENGTH then
			asked[speciesId] = true -- no kit of its own: the preview keeps its fallback
			return
		end
		queued[speciesId] = true
		table.insert(order, speciesId)
		if not running then
			running = true
			deps.delay(0, pump)
		end
	end

	return {
		want = want,
		asked = function(speciesId: string): boolean
			return asked[speciesId] == true
		end,
	}
end

return table.freeze(KitCache)
