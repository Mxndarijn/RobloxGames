--!strict
--[[
	TestHooks (pure, test sessions only; CONTRACT.md §8.12)

	Lets a scripted test session (Luau Execution task, tools/livetest Lune
	session, unit tests) grant cash and skip time on a live `world`, so a
	stand-in player can run the whole loop up to rebirth 6+ in seconds.

	Guard, so it can never be used in live play:
	  1. Nothing wires it to a remote, prompt or chat command (init.server
	     does not even require it; tests/TestHooks.spec fails if any other
	     src/ file mentions it). Only server code that already has full
	     authority can call it.
	  2. `enable(world)` refuses unless the server runs on the in-memory
	     store (workspace attribute DataStoreMode = "Memory"), which the
	     publish checks forbid in a shipped place (scripts/check-place,
	     tests/PlaceSafety.spec). Plain Lune unit tests (no `game`) have no
	     DataStore at all and are allowed.
	  3. Every hook errors unless `enable` succeeded for that world.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")
local Income = if script then require(script.Parent.Income) else require("./Income")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World

local TestHooks = {}

local enabled: { [World]: boolean } = setmetatable({}, { __mode = "k" }) :: any

-- True when no real DataStore can be written by this server.
function TestHooks.memoryMode(): boolean
	if not script then
		return true -- plain Lune: no DataStoreService exists
	end
	return (workspace :: any):GetAttribute(Constants.DATASTORE_MODE_ATTRIBUTE) == "Memory"
end

-- Turns the hooks on for `world`. Returns false (hooks stay off) on a real-DataStore server.
function TestHooks.enable(world: World): boolean
	if not TestHooks.memoryMode() then
		return false
	end
	enabled[world] = true
	return true
end

function TestHooks.isEnabled(world: World): boolean
	return enabled[world] == true
end

local function guard(world: World)
	if not enabled[world] then
		error("TestHooks are disabled (only test sessions on DataStoreMode = Memory may enable them)", 3)
	end
end

-- Adds cash without counting it as earned (goals stay honest).
function TestHooks.grantCash(world: World, userId: number, amount: number)
	guard(world)
	local session = assert(World.session(world, userId), "no session")
	session.data.cash += math.max(0, amount)
	World.markDirty(session)
end

--[[
	Skips `seconds` of play for every session: pays plot income as if that
	time passed (in Income.MAX_TICK chunks) and moves lock timers forward.
]]
function TestHooks.skipTime(world: World, seconds: number)
	guard(world)
	local left = math.max(0, seconds)
	while left > 0 do
		local dt = math.min(left, Income.MAX_TICK)
		Income.step(world, dt)
		left -= dt
	end
	for _, session in world.sessions do
		session.lockUntil -= seconds
	end
end

return TestHooks
