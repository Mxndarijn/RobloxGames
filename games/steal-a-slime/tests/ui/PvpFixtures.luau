--!strict
-- Test doubles for the PvP client specs (never shipped, not under src/): a state.pvp builder shaped like
-- PvpService.view (built with the real Shared.PvpRules over the real Config.PVP_TOOLS), a fake clock, a fake send,
-- and a fake PvpEvent source.
local Config = require("../../src/shared/Config")
local PvpClient = require("../../src/ui/PvpClient")
local PvpRules = require("../../src/shared/PvpRules")

local PvpFixtures = {}

export type Call = { n: number, [number]: any }
export type Clock = { t: number }
export type Log = { calls: { Call } }

-- A state.pvp for a player at `rank` who bought everything unlocked: PvpService.view's shape (owned / best from
-- PvpRules, equipped = the best Knockback glove, nothing on cooldown, no shield, no zone).
function PvpFixtures.pvp(rank: number): { [string]: any }
	local data: PvpRules.Data = { cash = 0, rebirths = rank, pvp = PvpRules.emptyPvp() }
	local pvp = data.pvp :: PvpRules.Pvp
	for _, tool in Config.PVP_TOOLS do
		if PvpRules.isUnlocked(data, tool.id) then
			if tool.kind == "fun" then
				pvp.fun[tool.id] = true
			else
				pvp.tiers[tool.line] = math.max(pvp.tiers[tool.line] or 0, tool.tier)
			end
		end
	end
	local owned: { [string]: boolean } = {}
	for _, tool in Config.PVP_TOOLS do
		if PvpRules.owns(data, tool.id) then
			owned[tool.id] = true
		end
	end
	local best: { [string]: string } = {}
	for _, line in PvpRules.LINES do
		local tool = PvpRules.bestTool(data, line)
		if tool then
			best[line] = tool.id
		end
	end
	return { rank = rank, owned = owned, best = best, equipped = best.Knockback, cooldowns = {} }
end

-- A full State stand-in carrying that state.pvp.
function PvpFixtures.state(rank: number): { [string]: any }
	return { pvp = PvpFixtures.pvp(rank) }
end

-- A client on a manual clock (starts at 100); every send(action, ...) is recorded with its args packed (nils kept).
-- `sendResult` = what send returns ({ false, "reason" } = a refusal).
function PvpFixtures.client(sendResult: { any }?, rank: number?): (any, Log, Clock)
	local clock: Clock = { t = 100 }
	local log: Log = { calls = {} }
	local client = PvpClient.new({
		now = function()
			return clock.t
		end,
		send = function(...: any): (any, any)
			table.insert(log.calls, table.pack(...) :: Call)
			if sendResult then
				return sendResult[1], sendResult[2]
			end
			return nil, nil
		end,
	})
	if rank then
		client.applyState(PvpFixtures.state(rank))
	end
	return client, log, clock
end

-- A signal that counts live connections (Connect / Fire / Disconnect).
function PvpFixtures.signal(): any
	local self: any = { live = 0, total = 0, callbacks = {} }
	function self.Connect(_self: any, fn: any)
		self.live += 1
		self.total += 1
		local connection = { fn = fn, on = true }
		self.callbacks[connection] = true
		function connection.Disconnect()
			if connection.on then
				connection.on = false
				self.live -= 1
				self.callbacks[connection] = nil
			end
		end
		return connection
	end
	function self.Fire(_self: any, ...: any)
		for connection in table.clone(self.callbacks) do
			connection.fn(...)
		end
	end
	return self
end

-- A folder-like parent with FindFirstChild / ChildAdded that records lookups.
function PvpFixtures.folder(): any
	local self: any = { children = {}, lookups = 0, ChildAdded = PvpFixtures.signal() }
	function self.FindFirstChild(_self: any, name: string)
		self.lookups += 1
		return self.children[name]
	end
	function self.add(_self: any, name: string, child: any)
		child.Name = name
		self.children[name] = child
		self.ChildAdded:Fire(child)
	end
	return self
end

-- A PvpEvent RemoteEvent stand-in: `remote.OnClientEvent:Fire(event)` delivers one server event.
function PvpFixtures.eventSource(): any
	return { OnClientEvent = PvpFixtures.signal() }
end

return PvpFixtures
