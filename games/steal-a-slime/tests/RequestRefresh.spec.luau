--!nocheck
-- Request spam must not buy world-wide work: the real server Script in the fake runtime only runs refreshView
-- (WorldView.reconcile over every slime + updatePlots) and flushStates for calls that got past Actions.handle's
-- guards. Unknown actions, "too fast" calls and Sync faster than STATE_MIN_INTERVAL are refused for free.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local USER_ID = 5150
local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-requestrefresh-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {})
fs.removeFile(path)
rt.workspace:SetAttribute("DataStoreMode", "Memory") -- in-memory store only (CLAUDE.md hard rule)
local server = rt.game:GetService("ServerScriptService"):FindFirstChild("Server")
server.Source = server.Source .. "\n_G.__requestRefresh = { world = world, WorldView = WorldView }\n"
rt:boot()
rt:advance(1)
-- selene: allow(global_usage)
local S = _G.__requestRefresh
local player = rt:addPlayer(USER_ID, "Spammer", roblox.Vector3.new(0, 10, 0))
rt:advance(2)
local request = rt.game:GetService("ReplicatedStorage"):FindFirstChild("Remotes"):FindFirstChild("Request")
local session = S.world.sessions[USER_ID]

-- Counts WorldView.reconcile calls (refreshView looks it up on every call) made by `fn`, without advancing the clock.
local function reconciles(fn: () -> ()): number
	local original = S.WorldView.reconcile
	local n = 0
	S.WorldView.reconcile = function(...)
		n += 1
		return original(...)
	end
	fn()
	S.WorldView.reconcile = original
	return n
end

local function invoke(...)
	return request.OnServerInvoke(player, ...)
end

-- The scenarios run here, at load time: Runtime keeps only the most recently built runtime "current" (players, etc.),
-- and the describe blocks run after every spec file has loaded.
local results = {}

results.junk = { messages = {} }
results.junk.reconciles = reconciles(function()
	for _ = 1, 50 do
		results.junk.messages[invoke("Explode").message] = true
		results.junk.messages[invoke("Sell", 5).message] = true
	end
end)

rt:advance(1)
results.limited = { tooFast = 0 }
results.limited.reconciles = reconciles(function()
	results.limited.first = invoke("Favorite", nil).ok
	for _ = 1, 50 do
		if invoke("Favorite", nil).message == "too fast" then
			results.limited.tooFast += 1
		end
	end
end)

rt:advance(1)
-- A Heartbeat push in the last 0.25 s would coalesce the Sync push; start from a quiet, already-pushed session.
session.dirty, session.lastPushAt = false, -math.huge
results.sync = { tooFast = 0 }
results.sync.reconciles = reconciles(function()
	results.sync.first = invoke("Sync").ok
	results.sync.pushedAt = session.lastPushAt
	for _ = 1, 50 do
		if invoke("Sync").message == "too fast" then
			results.sync.tooFast += 1
		end
	end
	results.sync.pushedAfter = session.lastPushAt
end)
rt:advance(Config.STATE_MIN_INTERVAL + 0.05)
results.sync.later = invoke("Sync").ok
results.errors = #rt.errors
rt:close()

describe("Request refresh guard (server Script)", function()
	it("boots with a session for the spammer", function()
		expect(session ~= nil).toBe(true)
	end)
	it("never refreshes the world for unknown actions or bad arguments", function()
		expect(results.junk.messages["unknown action"]).toBe(true)
		expect(results.junk.messages["bad argument"]).toBe(true)
		expect(results.junk.reconciles).toBe(0)
	end)
	it("refreshes once for an action that ran, not for the rate-limited repeats", function()
		expect(results.limited.first).toBe(true)
		expect(results.limited.tooFast).toBe(50)
		expect(results.limited.reconciles).toBe(1)
	end)
	it("throttles Sync to one per STATE_MIN_INTERVAL and still pushes State on the allowed one", function()
		expect(results.sync.first).toBe(true)
		expect(results.sync.pushedAt > -math.huge).toBe(true)
		expect(results.sync.tooFast).toBe(50)
		expect(results.sync.pushedAfter).toBe(results.sync.pushedAt)
		expect(results.sync.reconciles).toBe(1)
		expect(results.sync.later).toBe(true)
	end)
	it("raises no script errors", function()
		expect(results.errors).toBe(0)
	end)
end)
