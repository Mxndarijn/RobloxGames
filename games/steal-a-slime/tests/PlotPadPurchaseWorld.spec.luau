--!nocheck
-- The same bug on the real world: the booted server with WorldShopsStrict on, a stand-in owner and the real LockButton /
-- BuyPadPrompt / MergeVat prompt parts of all 8 plots. The owner stands at THEIR pad, far from the Item Shop stand, and
-- fires the real LockPrompt: it must lock. Far away, or someone else's prompt, it must not.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local PlotPadGuard = require("../src/server/PlotPadGuard")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-padbuy-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {
	createMeshPart = function(_meshId, options)
		local part = roblox.Instance.new("MeshPart")
		if options and options.CollisionFidelity then
			part.CollisionFidelity = options.CollisionFidelity
		end
		return part
	end,
})
fs.removeFile(path)
rt.workspace:SetAttribute("DataStoreMode", "Memory") -- in-memory store only (CLAUDE.md hard rule)
-- Expose the server's world to this spec (in memory only, like tools/livetest/session.luau).
local server = rt.game:GetService("ServerScriptService"):FindFirstChild("Server")
server.Source = server.Source .. "\n_G.__padSpec = { world = world, WorldView = WorldView }\n"
rt:boot()
rt:advance(2)
-- selene: allow(global_usage)
local S = _G.__padSpec
local TestHooks = rt:require(server:FindFirstChild("TestHooks"))
local world = S.world
TestHooks.enable(world)

local function lockPromptOf(plotIndex)
	return S.WorldView.plot(plotIndex).LockButton:FindFirstChild("LockPrompt")
end

-- The scenarios run here, at load time: Runtime keeps only the most recently built runtime "current" (players, etc.),
-- and the describe blocks run after every spec file has loaded.
local ItemCounter = rt.workspace.Map.ItemShopStand.Counter
local results = {}
local players = {}
for i = 1, Config.PLOT_COUNT do
	players[i] = rt:addPlayer(3000 + i, `PadOwner{i}`)
	rt:advance(3) -- joined: the data loaded and the server moved them to their plot
end
for i = 1, Config.PLOT_COUNT do
	local userId = 3000 + i
	local player = players[i]
	local session = world.sessions[userId]
	local prompt = lockPromptOf(session.plotIndex)
	local button = prompt.Parent
	local r = { plotIndex = session.plotIndex }
	results[i] = r
	r.shopDistance = (button.CFrame.Position - ItemCounter.CFrame.Position).Magnitude
	session.lockUntil = rt.workspace:GetServerTimeNow() - 1 -- the join lock is over
	rt:advance(0.3)
	TestHooks.grantCash(world, userId, 10_000_000)
	local cash = session.data.cash
	local root = player.Character.HumanoidRootPart
	-- far from the pad (and from the shop): refused, nothing charged, not locked
	root.CFrame = roblox.CFrame.new(0, 5, 0)
	prompt.Triggered:Fire(player)
	rt:advance(0.3)
	r.farCharged = session.data.cash < cash
	r.farLocked = session.lockUntil > rt.workspace:GetServerTimeNow()
	-- at the pad: it locks and charges
	root.CFrame = button.CFrame + roblox.Vector3.new(0, 3, 3)
	rt:advance(0.6)
	prompt.Triggered:Fire(player)
	rt:advance(0.5)
	r.nearLocked = session.lockUntil > rt.workspace:GetServerTimeNow()
	-- the next plot's owner stands at this same pad and fires the prompt: refused, the lock is untouched
	local neighbour = players[i % Config.PLOT_COUNT + 1]
	neighbour.Character.HumanoidRootPart.CFrame = button.CFrame + roblox.Vector3.new(0, 3, -3)
	rt:advance(0.6)
	local lockUntil = session.lockUntil
	local neighbourSession = world.sessions[neighbour.UserId]
	local neighbourLock = neighbourSession.lockUntil
	local neighbourCash = neighbourSession.data.cash
	prompt.Triggered:Fire(neighbour)
	rt:advance(0.3)
	r.neighbourChanged = session.lockUntil ~= lockUntil or neighbourSession.lockUntil ~= neighbourLock
	r.neighbourCharged = neighbourSession.data.cash < neighbourCash
end
local bootErrors = #rt.errors

describe("plot pad prompts on the real world (WorldShopsStrict on)", function()
	it("strict is on and the Item Shop stand exists", function()
		expect(Config.FEATURES.WorldShopsStrict).toBe(true)
		expect(Config.FEATURES.WorldShops).toBe(true)
		expect(ItemCounter ~= nil).toBe(true)
	end)
	it(
		"all 8 plots: the LockPrompt sits on the LockButton and the guard range covers its activation distance",
		function()
			expect(Config.PLOT_COUNT).toBe(8)
			for i = 1, Config.PLOT_COUNT do
				local prompt = lockPromptOf(i)
				expect(prompt ~= nil).toBe(true)
				expect(prompt.MaxActivationDistance).toBe(Config.PLOT_PAD_PROMPT_DISTANCE)
				expect(S.WorldView.plotPromptPart(i, "Lock")).toBe(prompt.Parent)
				expect(PlotPadGuard.range() >= prompt.MaxActivationDistance).toBe(true)
			end
		end
	)
	it("every owner at their own LockButton locks the base although the Item Shop is out of range", function()
		for i, r in results do
			expect(r.plotIndex ~= nil).toBe(true)
			expect(r.shopDistance > Config.SHOP_RANGE).toBe(true)
			expect(r.nearLocked).toBe(true)
			expect(i > 0).toBe(true)
		end
	end)
	it("far from the pad the prompt is refused: no charge, no lock", function()
		for _, r in results do
			expect(r.farCharged).toBe(false)
			expect(r.farLocked).toBe(false)
		end
	end)
	it("a neighbour firing someone else's LockPrompt does not change that lock", function()
		for _, r in results do
			expect(r.neighbourChanged).toBe(false)
			expect(r.neighbourCharged).toBe(false)
		end
	end)
	it("boots clean", function()
		expect(bootErrors).toBe(0)
	end)
end)
