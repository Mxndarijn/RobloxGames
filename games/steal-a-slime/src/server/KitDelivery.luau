--!strict
--[[
	KitDelivery (pure)

	Hands species kit meshes to the one player who asked for them (`RequestKits`, KitRequest), so a client only
	downloads the kits its SlimeDex / rebirth previews show. The adapter (WorldView) does the copying through
	`deps.deliver`, into a folder only that player replicates.

	  request(userId, kits)  a loaded kit goes out now, one still loading goes out when it arrives (kitLoaded), a
	                         failed or never-uploaded kit never does (the preview keeps its fallback look); each
	                         kit reaches a player at most once
	  kitLoaded(kit, mesh)   SlimeMesh finished loading `kit`: every player waiting for it gets it
	  forget(userId)         the player left
]]

export type Deps = {
	loaded: (kit: string) -> any?, -- the loaded kit mesh, nil while it is loading or when it failed
	failed: (kit: string) -> boolean, -- the kit will never load (fetch failed, or no upload)
	deliver: (userId: number, kit: string, mesh: any) -> (),
}

export type KitDelivery = {
	deps: Deps,
	sent: { [number]: { [string]: boolean } },
	waiting: { [string]: { [number]: boolean } },
}

local KitDelivery = {}

function KitDelivery.new(deps: Deps): KitDelivery
	return { deps = deps, sent = {}, waiting = {} }
end

local function send(self: KitDelivery, userId: number, kit: string, mesh: any)
	local sent = self.sent[userId]
	if sent == nil then
		sent = {}
		self.sent[userId] = sent
	end
	if sent[kit] then
		return
	end
	sent[kit] = true
	self.deps.deliver(userId, kit, mesh)
end

-- Returns how many kits went out now.
function KitDelivery.request(self: KitDelivery, userId: number, kits: { string }): number
	local count = 0
	local sent = self.sent[userId]
	for _, kit in kits do
		if sent and sent[kit] then
			continue
		end
		local mesh = self.deps.loaded(kit)
		if mesh ~= nil then
			send(self, userId, kit, mesh)
			sent = self.sent[userId]
			count += 1
		elseif not self.deps.failed(kit) then
			local waiting = self.waiting[kit]
			if waiting == nil then
				waiting = {}
				self.waiting[kit] = waiting
			end
			waiting[userId] = true
		end
	end
	return count
end

function KitDelivery.kitLoaded(self: KitDelivery, kit: string, mesh: any)
	local waiting = self.waiting[kit]
	if waiting == nil then
		return
	end
	self.waiting[kit] = nil
	for userId in waiting do
		send(self, userId, kit, mesh)
	end
end

function KitDelivery.forget(self: KitDelivery, userId: number)
	self.sent[userId] = nil
	for kit, waiting in self.waiting do
		waiting[userId] = nil
		if next(waiting) == nil then
			self.waiting[kit] = nil
		end
	end
end

return table.freeze(KitDelivery)
