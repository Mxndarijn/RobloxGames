--!strict
--[[
	ObbyClock (VisualsClient module, contract/obby-sections.md §5)

	The local player's own obby clocks and keys. Nothing here reaches the server: every runner has their own.
	  * clocks  a part with `trigger = G` starts clock G the first time the player touches it (`start(G)`); parts with
	            `start = G` play their motion on `elapsed(G)` instead of server time, and sit at rest until it starts
	  * keys    a part with `key = G` adds one key of group G (`addKey(G)`); a gate `{ group = G, need = n }` opens
	            once `keys(G) >= n`
	`clear()` forgets every clock and key: ObbyFx calls it on every reset to the start pad (ObbyFall.onReset).
	The clock is os.clock(), so it runs at frame accuracy and never jumps with the server's time.
]]

local ObbyClock = {}

local startedAt: { [string]: number } = {}
local keyCount: { [string]: number } = {}

-- Starts clock `group` now; true when it was not running yet (the caller plays the "go" tick then).
function ObbyClock.start(group: string): boolean
	if startedAt[group] ~= nil then
		return false
	end
	startedAt[group] = os.clock()
	return true
end

function ObbyClock.running(group: string): boolean
	return startedAt[group] ~= nil
end

-- Seconds since clock `group` started, or nil while it has not.
function ObbyClock.elapsed(group: string): number?
	local at = startedAt[group]
	return if at then os.clock() - at else nil
end

function ObbyClock.addKey(group: string): number
	local n = (keyCount[group] or 0) + 1
	keyCount[group] = n
	return n
end

function ObbyClock.keys(group: string): number
	return keyCount[group] or 0
end

function ObbyClock.clear()
	table.clear(startedAt)
	table.clear(keyCount)
end

return ObbyClock
