--!strict
--[[
	IdleRejoinClient (Roblox adapter, client)

	Roblox fires `Player.Idled` only on the client: two minutes after the last input and every 30 seconds after
	that, with the seconds since that input. This passes each report to the server over `remote`
	(IdleRejoinServer decides and teleports).
]]

export type Deps = {
	player: Player, -- Players.LocalPlayer
	remote: RemoteEvent,
}

export type Handle = { destroy: (self: Handle) -> () }

local IdleRejoinClient = {}

function IdleRejoinClient.start(deps: Deps): Handle
	local connection: RBXScriptConnection? = deps.player.Idled:Connect(function(idleSeconds: number)
		deps.remote:FireServer(idleSeconds)
	end)
	local handle = {}
	function handle.destroy(_self: Handle)
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end
	return handle :: Handle
end

return table.freeze(IdleRejoinClient)
