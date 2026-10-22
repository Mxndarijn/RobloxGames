--!nocheck
-- A leaving player's save must not depend on the view refresh: the fake runtime boots the real server Script, the
-- WorldView refresh throws on the way out, and the progress made in the session still reaches the store.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local Vector3 = roblox.Vector3

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-leavesave-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {})
fs.removeFile(path)
rt.workspace:SetAttribute("DataStoreMode", "Memory")
local server = rt.game:GetService("ServerScriptService"):FindFirstChild("Server")
server.Source = server.Source .. "\n_G.__leaveSave = { world = world, WorldView = WorldView }\n"
rt:boot()
rt:advance(1)
-- selene: allow(global_usage)
local exported = _G.__leaveSave

describe("player leave", function()
	it("saves the session even when the view refresh fails", function()
		local userId = 7101
		local player = rt:addPlayer(userId, "Leaver", Vector3.new(0, 10, 0))
		rt:advance(1)
		local session = exported.world.sessions[userId]
		expect(session ~= nil).toBe(true)
		session.data.cash = 987654
		local original = exported.WorldView.reconcile
		exported.WorldView.reconcile = function()
			error("view refresh failed")
		end
		rt.game:GetService("Players").PlayerRemoving:Fire(player)
		rt:advance(1)
		exported.WorldView.reconcile = original
		table.remove(rt.players, table.find(rt.players, player))
		player:Destroy()
		rt:advance(1)
		expect(exported.world.sessions[userId]).toBeNil()
		rt:addPlayer(userId, "Leaver", Vector3.new(0, 10, 0))
		rt:advance(1)
		local again = exported.world.sessions[userId]
		expect(again ~= nil).toBe(true)
		expect(again.data.cash).toBe(987654)
	end)
end)
