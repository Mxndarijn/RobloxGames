--!strict
--[[
	SettingsController (client)

	Holds the Settings menu values on the client. Each setting lives on a LocalPlayer attribute
	(PlayerSettings TABS `attribute`), so every client script (sound, visuals, the HUD) reads the same value with
	PlayerSettings.get. `load` applies the saved values from the first State once; after that every change,
	whoever made it (the Settings card, the Sound sliders), is sent back with Request("SetSettings", changes)
	`sendDelay` seconds after the last change, only the ids that differ from what the server already has.

	Dependencies come in through `deps`: the player (GetAttribute / SetAttribute / GetAttributeChangedSignal),
	PlayerSettings, `send(action, ...)` and `delay(seconds, fn)`.
]]

export type Deps = {
	player: any,
	PlayerSettings: any,
	send: (action: string, ...any) -> (),
	delay: (seconds: number, fn: () -> ()) -> (),
	sendDelay: number?,
}

local SettingsController = {}

-- Seconds after the last change before it is sent: above the SetSettings rate limit (0.5 s).
SettingsController.SEND_DELAY = 0.6

function SettingsController.new(deps: Deps)
	local player = deps.player
	local PlayerSettings = deps.PlayerSettings
	local schema = PlayerSettings.schema
	local sendDelay = deps.sendDelay or SettingsController.SEND_DELAY
	local loaded = false
	local sent: { [string]: any } = PlayerSettings.defaults()
	local token = 0
	local listeners: { (id: string) -> () } = {}
	local conns: { any } = {}
	local self = {}

	function self.get(id: string): any
		return PlayerSettings.get(player, id)
	end

	function self.values(): { [string]: any }
		local out: { [string]: any } = {}
		for _, def in schema.defs do
			out[def.id] = PlayerSettings.get(player, def.id)
		end
		return out
	end

	-- Sets one setting (cleaned; an unknown id is ignored).
	function self.set(id: string, value: any)
		local entry = PlayerSettings.entry(id)
		local clean = schema:value(id, value)
		if entry and clean ~= nil then
			player:SetAttribute(entry.attribute, clean)
		end
	end

	-- Every setting back to its default.
	function self.reset()
		for id, value in PlayerSettings.defaults() do
			self.set(id, value)
		end
	end

	-- `fn(id)` after any setting changed.
	function self.onChanged(fn: (id: string) -> ())
		table.insert(listeners, fn)
	end

	function self.isLoaded(): boolean
		return loaded
	end

	local function flush()
		local now = self.values()
		local _, changed = schema:apply(sent, now)
		if #changed == 0 then
			return
		end
		local changes: { [string]: any } = {}
		for _, id in changed do
			changes[id] = now[id]
		end
		sent = now
		deps.send("SetSettings", changes)
	end

	local function queue()
		token += 1
		local mine = token
		deps.delay(sendDelay, function()
			if mine == token then
				flush()
			end
		end)
	end

	-- Applies the saved values (State.settings) the first time it is called; later calls do nothing, so a State
	-- push never undoes a change the player is still making.
	function self.load(saved: any)
		if loaded then
			return
		end
		local clean = PlayerSettings.clean(saved)
		for id, value in clean do
			self.set(id, value)
		end
		sent = clean
		loaded = true
	end

	for _, def in schema.defs do
		local entry = PlayerSettings.entry(def.id)
		if entry then
			table.insert(
				conns,
				player:GetAttributeChangedSignal(entry.attribute):Connect(function()
					for _, fn in listeners do
						fn(def.id)
					end
					if loaded then
						queue()
					end
				end)
			)
		end
	end

	function self.destroy()
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		table.clear(listeners)
	end

	return self
end

return SettingsController
