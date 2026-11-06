--!strict
--[[
	LocalizedTree (adapter): translated text on instances the server makes (ProximityPrompt ActionText /
	ObjectText, TextLabels in world BillboardGuis and SurfaceGuis), where every client needs its own language.

	Server: LocalizedTree.set(inst, "ActionText", Localize.msg("plot.lock"), { english = ..., encode = ... })
	  writes the English text (what Roblox shows before the client runs), keeps the message in the attribute
	  `L10n_<Property>` (JSON) and tags the instance `Localized`.
	Client: LocalizedTree.watch(translator, deps) writes `translator.text(message)` into the property of
	  every tagged instance, again when the attribute or the property changes (a server update arrives in
	  English), and turns AutoLocalize off on it so Roblox does not translate or capture the text a second
	  time. Returns a handle with destroy().
]]

local LocalizedTree = {}

LocalizedTree.TAG = "Localized"
LocalizedTree.PREFIX = "L10n_"

export type ServerDeps = {
	english: (message: any) -> string, -- Localize.english bound to the game's catalog
	encode: (value: any) -> string, -- HttpService:JSONEncode
	addTag: (inst: any, tag: string) -> (), -- CollectionService:AddTag
}

export type ClientDeps = {
	collection: any, -- CollectionService
	decode: (text: string) -> any, -- HttpService:JSONDecode
}

export type Handle = { destroy: () -> () }

-- Sets `inst[property]` to the English text of `message` and records the message for clients. Skips the
-- write when nothing changed, so a per-tick caller does not re-replicate.
function LocalizedTree.set(inst: any, property: string, message: any, deps: ServerDeps)
	local attr = LocalizedTree.PREFIX .. property
	local encoded = deps.encode(message)
	if inst:GetAttribute(attr) == encoded and inst:HasTag(LocalizedTree.TAG) then
		-- Same message again: the property already holds it (translated by the watcher on a client), so a
		-- per-frame caller writes nothing and the label never flashes English.
		return
	end
	inst:SetAttribute(attr, encoded)
	local english = deps.english(message)
	if inst[property] ~= english then
		inst[property] = english
	end
	if not inst:HasTag(LocalizedTree.TAG) then
		deps.addTag(inst, LocalizedTree.TAG)
	end
end

-- The property names an instance carries messages for.
function LocalizedTree.properties(inst: any): { string }
	local out = {}
	for name in inst:GetAttributes() do
		local property = string.match(name, "^" .. LocalizedTree.PREFIX .. "(.+)$")
		if property then
			table.insert(out, property)
		end
	end
	table.sort(out)
	return out
end

function LocalizedTree.watch(translator: { text: (any) -> string }, deps: ClientDeps): Handle
	local connections: { [any]: { any } } = {}

	local function apply(inst: any, property: string)
		local raw = inst:GetAttribute(LocalizedTree.PREFIX .. property)
		if type(raw) ~= "string" then
			return
		end
		local ok, message = pcall(deps.decode, raw)
		if not ok then
			return
		end
		local text = translator.text(message)
		if inst[property] ~= text then
			inst[property] = text
		end
	end

	local function track(inst: any)
		if connections[inst] then
			return
		end
		local list = {}
		local hooked: { [string]: boolean } = {}
		connections[inst] = list
		pcall(function()
			inst.AutoLocalize = false
		end)
		local function hook(property: string)
			if not hooked[property] then
				hooked[property] = true
				table.insert(
					list,
					inst:GetPropertyChangedSignal(property):Connect(function()
						apply(inst, property)
					end)
				)
			end
			apply(inst, property)
		end
		for _, property in LocalizedTree.properties(inst) do
			hook(property)
		end
		table.insert(
			list,
			inst.AttributeChanged:Connect(function(name: string)
				local property = string.match(name, "^" .. LocalizedTree.PREFIX .. "(.+)$")
				if property then
					hook(property)
				end
			end)
		)
	end

	local function untrack(inst: any)
		for _, c in connections[inst] or {} do
			c:Disconnect()
		end
		connections[inst] = nil
	end

	local added = deps.collection:GetInstanceAddedSignal(LocalizedTree.TAG):Connect(track)
	local removed = deps.collection:GetInstanceRemovedSignal(LocalizedTree.TAG):Connect(untrack)
	for _, inst in deps.collection:GetTagged(LocalizedTree.TAG) do
		track(inst)
	end

	return {
		destroy = function()
			added:Disconnect()
			removed:Disconnect()
			for inst in connections do
				untrack(inst)
			end
		end,
	}
end

return table.freeze(LocalizedTree)
