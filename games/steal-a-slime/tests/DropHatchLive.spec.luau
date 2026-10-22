--!nocheck
-- The drop tube is taken only from the top of the tower (server/BaseFloors), through the REAL server Script
-- (tools/livetest/Runtime, memory store): as the owner's tower grows and shrinks, only the top jar's DropHatch is
-- shown, solid and has its DropPrompt on; every jar below it has its hatch hidden, non-colliding and its prompt off.
local fs = require("@lune/fs")
local process = require("@lune/process")

local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-drophatch-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {})
fs.removeFile(path)
rt.workspace:SetAttribute("DataStoreMode", "Memory")
local server = rt.game:GetService("ServerScriptService"):FindFirstChild("Server")
server.Source = server.Source .. "\n_G.__drophatch = { world = world }\n"
rt:boot()
rt:advance(1)
rt:addPlayer(2003, "Climber")
rt:advance(2)
-- selene: allow(global_usage)
local world = _G.__drophatch.world
local session = world.sessions[2003]
assert(session, "player did not load")
local Config = require("../src/shared/Config")

local function plot()
	for _, d in rt.workspace:GetDescendants() do
		if d.Name == `Plot_{session.plotIndex}` then
			return d
		end
	end
	return nil
end

-- { [floor]: { shown, solid, prompt on } } for every upper jar standing now
local function hatches()
	local out = {}
	for f = 2, #Config.BASE_FLOORS do
		local floor = plot():FindFirstChild(`Floor_{f}`)
		local hatch = floor and floor:FindFirstChild("DropHatch")
		if hatch then
			local prompt = hatch:FindFirstChild("DropPrompt", true)
			out[f] = { hatch.Transparency < 1, hatch.CanCollide, prompt ~= nil and prompt.Enabled }
		end
	end
	return out
end

-- { [floor]: the stair-top landing is solid } for every upper jar standing now
local function stairTops()
	local out = {}
	for f = 2, #Config.BASE_FLOORS do
		local floor = plot():FindFirstChild(`Floor_{f}`)
		local landing = floor and floor:FindFirstChild("StairLanding_1")
		if landing then
			out[f] = landing.CanCollide
		end
	end
	return out
end

local tops = {}
local function grow(floors)
	session.data.padsUnlocked = (floors - 1) * Config.PADS_PER_FLOOR
	rt:advance(2)
	tops[floors] = stairTops()
	return hatches()
end

local four = grow(#Config.BASE_FLOORS)
local two = grow(2)
local three = grow(3)

describe("stair top (the flat landing stands only on the top jar)", function()
	it("makes only the top jar's landing solid, and follows the top as the tower changes", function()
		for f = 2, #Config.BASE_FLOORS do
			expect(tops[#Config.BASE_FLOORS][f]).toBe(f == #Config.BASE_FLOORS)
		end
		expect(tops[2][2]).toBe(true)
		expect(tops[3][2]).toBe(false)
		expect(tops[3][3]).toBe(true)
	end)
end)

describe("drop hatches (only the top jar drops you down the tube)", function()
	it("opens only the top jar's hatch on a full tower", function()
		for f = 2, #Config.BASE_FLOORS do
			local open = f == #Config.BASE_FLOORS
			expect(four[f]).toEqual({ open, open, open })
		end
	end)
	it("moves the open hatch down when the tower shrinks and back up when it grows", function()
		expect(two[2]).toEqual({ true, true, true })
		expect(two[3]).toBe(nil)
		expect(three[2]).toEqual({ false, false, false })
		expect(three[3]).toEqual({ true, true, true })
	end)
end)
