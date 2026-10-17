--!strict
--[[
	PvpMount (FEATURES.PvP, docs/PVP-CLIENT.md)

	The one hook init.client calls. With the flag off it returns nil and does nothing: no PvpClient, no Instances,
	no connections, no remote looked up. With it on it builds the PvpClient (real wiring injected by init.client),
	mounts PvpHud and connects the PvP inputs:
	  * the PvpEvent RemoteEvent under the Remotes folder, found with FindFirstChild / ChildAdded (never
	    WaitForChild: with the server side not shipped yet the event simply never appears);
	  * the player attribute "PvpShieldUntil";
	  * the number keys (env.input).
	Everything Roblox-side comes in through `env`, so tests/ui/PvpMount.spec.luau runs it under Lune.

	env = {
	  enabled: boolean,                 Config.FEATURES.PvP (the FeatureOverride-wrapped table)
	  gui: Instance,                    the ScreenGui
	  banners: Instance?,               Hud's Banners stack (the chips go there)
	  itemIcons: any,                   ItemIcons registry
	  now: () -> number,                server time
	  send: (action, ...) -> (any, any),  the Request path; may return (false, reason)
	  player: any,                      GetAttribute / GetAttributeChangedSignal
	  remotes: any?,                    the Remotes folder-like (FindFirstChild, ChildAdded); nil = look up via root
	  root: any?,                       ReplicatedStorage-like, used when `remotes` is nil
	  remotesName: string?,             the folder's name under root (Constants.REMOTES_FOLDER)
	  input: any?,                      UserInputService-like (InputBegan, GetFocusedTextBox)
	  eventName: string?,               Constants.PVP_EVENT or "PvpEvent"
	  stubRank: (() -> number?)?,       Studio preview (PcwPvpStub): fake state.pvp when the server sent none
	  catalog: any?,
	}
]]

local PvpClient = require(script.Parent.PvpClient)
local PvpHud = require(script.Parent.PvpHud)

local PvpMount = {}

PvpMount.SHIELD_ATTRIBUTE = "PvpShieldUntil"

-- Calls `found(instance)` once for the child `name` of `parent` (now, or when it appears). Returns a disconnect.
local function watchChild(parent: any, name: string, found: (any) -> ()): () -> ()
	local existing = parent:FindFirstChild(name)
	if existing then
		found(existing)
		return function() end
	end
	local connection: any = nil
	connection = parent.ChildAdded:Connect(function(child: any)
		if child.Name == name then
			if connection then
				connection:Disconnect()
			end
			found(child)
		end
	end)
	return function()
		connection:Disconnect()
	end
end

function PvpMount.mount(env: any)
	if env.enabled ~= true then
		return nil
	end
	local client = PvpClient.new({ now = env.now, send = env.send, catalog = env.catalog, flag = true })
	local hud = PvpHud.new(env.gui, env.itemIcons, client, { banners = env.banners, input = env.input })
	local disconnects: { () -> () } = {}
	local self: any = { client = client, hud = hud }

	-- The shield attribute (fallback behind State.pvp.shieldUntil).
	local player = env.player
	local function readShield()
		client.setShieldAttribute(player:GetAttribute(PvpMount.SHIELD_ATTRIBUTE))
	end
	local attr = player:GetAttributeChangedSignal(PvpMount.SHIELD_ATTRIBUTE):Connect(readShield)
	table.insert(disconnects, function()
		attr:Disconnect()
	end)
	readShield()

	-- PvpEvent: fires into the adapter. Watches the Remotes folder first when it is not there yet.
	local eventName = env.eventName or PvpClient.EVENT_NAME
	local function watchEvent(folder: any)
		table.insert(
			disconnects,
			watchChild(folder, eventName, function(remote: any)
				local connection = remote.OnClientEvent:Connect(function(ev: any)
					client.applyEvent(ev)
				end)
				table.insert(disconnects, function()
					connection:Disconnect()
				end)
			end)
		)
	end
	if env.remotes then
		watchEvent(env.remotes)
	elseif env.root then
		table.insert(disconnects, watchChild(env.root, env.remotesName or "Remotes", watchEvent))
	end

	-- The latest State snapshot (init.client render): state.pvp, or the preview stub when there is none.
	function self.applyState(state: any)
		local view = state
		local rank = if env.stubRank then env.stubRank() else nil
		if type(state) == "table" and state.pvp == nil and type(rank) == "number" then
			view = table.clone(state)
			view.pvp = PvpClient.stubState(rank, env.catalog)
		end
		client.applyState(view)
	end

	function self.layout(screen: any)
		hud.layout(screen)
	end

	function self.tick()
		hud.tick()
	end

	function self.destroy()
		for _, disconnect in disconnects do
			disconnect()
		end
		table.clear(disconnects)
		hud.destroy()
	end

	return self
end

return PvpMount
