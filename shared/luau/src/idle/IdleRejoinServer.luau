--!strict
--[[
	IdleRejoinServer (Roblox adapter, server)

	Keeps idle players in the game past Roblox's 20-minute idle kick. Clients report their idle seconds over
	`remote` (IdleRejoinClient); once IdleRejoin says so, the player is teleported back into this same server
	(TeleportOptions.ServerInstanceId), or into any server of the place when that fails (the server is full, or
	it is a private server). A client can only ever send itself back into the game.

	`dryRun` logs instead of teleporting (Studio, where TeleportService does not work); `teleport` replaces the
	real teleport (specs).
]]

local IdleRejoin = if script then require(script.Parent.IdleRejoin) else require("./IdleRejoin")

export type Deps = {
	remote: RemoteEvent, -- client to server: (idleSeconds: number)
	players: Players,
	teleportService: TeleportService?, -- needed unless `teleport` is given
	placeId: number,
	jobId: string,
	options: IdleRejoin.Options?,
	dryRun: boolean?,
	teleport: ((player: Player) -> (boolean, string?))?,
	now: (() -> number)?, -- default os.clock
	log: ((message: string) -> ())?, -- default print
	spawn: ((fn: () -> ()) -> ())?, -- default task.spawn (teleports yield)
}

export type Handle = { tracker: IdleRejoin.Tracker, destroy: (self: Handle) -> () }

local IdleRejoinServer = {}

local function realTeleport(deps: Deps): (player: Player) -> (boolean, string?)
	local service = deps.teleportService
	assert(service, "IdleRejoinServer: teleportService or teleport is required")
	return function(player: Player): (boolean, string?)
		local options = Instance.new("TeleportOptions")
		options.ServerInstanceId = deps.jobId
		options:SetTeleportData({ idleRejoin = true })
		local ok, err = pcall(service.TeleportAsync, service, deps.placeId, { player }, options)
		if ok then
			return true, nil
		end
		local anyOk, anyErr = pcall(service.TeleportAsync, service, deps.placeId, { player })
		if anyOk then
			return true, nil
		end
		return false, `{err}; {anyErr}`
	end
end

function IdleRejoinServer.start(deps: Deps): Handle
	local tracker = IdleRejoin.new(deps.options)
	local teleport = deps.teleport
		or if deps.dryRun
			then function(_player: Player): (boolean, string?)
				return true, nil
			end
			else realTeleport(deps)
	local now = deps.now or os.clock
	local log = deps.log or print
	local spawn = deps.spawn or function(fn: () -> ())
		task.spawn(fn)
	end

	local connections: { RBXScriptConnection } = {}
	table.insert(
		connections,
		deps.remote.OnServerEvent:Connect(function(player: Player, idleSeconds: unknown)
			if type(idleSeconds) ~= "number" or idleSeconds ~= idleSeconds or idleSeconds < 0 then
				return
			end
			if not tracker:idled(player.UserId, idleSeconds, now()) then
				return
			end
			spawn(function()
				local ok, err = teleport(player)
				if ok then
					local verb = if deps.dryRun then "would rejoin (dry run)" else "rejoining"
					log(`[IdleRejoin] {player.UserId} idle {math.floor(idleSeconds)} s: {verb}`)
				else
					log(`[IdleRejoin] {player.UserId} rejoin failed: {err}`)
				end
			end)
		end)
	)
	table.insert(
		connections,
		deps.players.PlayerRemoving:Connect(function(player: Player)
			tracker:forget(player.UserId)
		end)
	)

	local handle = { tracker = tracker }
	function handle.destroy(_self: Handle)
		for _, connection in connections do
			connection:Disconnect()
		end
		table.clear(connections)
	end
	return handle :: Handle
end

return table.freeze(IdleRejoinServer)
