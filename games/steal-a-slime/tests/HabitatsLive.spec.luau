--!nocheck
-- FEATURES.Habitats on, through the REAL server Script (tools/livetest/Runtime,
-- memory store): WorldView writes Habitat / HabitatFrom / HabitatAt on the
-- owner's Pad_<j> and flips it back to base when the slime is carried off.
-- The flag is switched on in the built place's Config source only; the
-- shipped Config keeps it off (Habitats.spec, LiveBoot.spec).
local fs = require("@lune/fs")
local process = require("@lune/process")

local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-habitats-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {})
fs.removeFile(path)
rt.workspace:SetAttribute("DataStoreMode", "Memory")
local config = rt.game:GetService("ReplicatedStorage").Shared.Config
local patched, n = string.gsub(config.Source, "Habitats = false,", "Habitats = true,")
assert(n == 1, "FEATURES.Habitats not found in Config")
config.Source = patched
local server = rt.game:GetService("ServerScriptService"):FindFirstChild("Server")
server.Source = server.Source .. "\n_G.__habitats = { world = world }\n"
rt:boot()
rt:advance(1)
rt:addPlayer(2002, "Keeper")
rt:advance(2)
-- selene: allow(global_usage)
local world = _G.__habitats.world -- same export as tools/livetest/session.luau
local session = world.sessions[2002]
assert(session, "player did not load")

local function pad(j)
	for _, d in rt.workspace:GetDescendants() do
		if d.Name == `Pad_{j}` and d.Parent and d.Parent:GetAttribute("PlotIndex") == session.plotIndex then
			return d
		end
	end
	return nil
end

local function read(part)
	return { part:GetAttribute("Habitat"), part:GetAttribute("HabitatFrom") }
end

local empty = read(pad(3))
table.insert(session.data.slimes, {
	id = "hab1",
	name = "Rock",
	tier = 6,
	color = { 200, 180, 255 },
	size = 1,
	pattern = "Plain",
	eyes = "Round",
	mouth = "Smile",
	mutation = "None",
	pad = 3,
	species = "rock_candy",
})
rt:advance(1)
local placed = read(pad(3))
local placedAt = pad(3):GetAttribute("HabitatAt")
world.carriedBy.hab1 = 999 -- carried off by a thief
rt:advance(1)
local stolen = read(pad(3))

describe("Habitats live (FEATURES.Habitats on, fake runtime)", function()
	it("boots without script errors", function()
		expect(#rt.errors).toBe(0)
	end)
	it("marks empty pads base", function()
		expect(empty).toEqual({ "base", "base" })
	end)
	it("writes the slime's habitat on its pad with a server-time stamp", function()
		expect(placed).toEqual({ "crystal_grotto", "base" })
		expect(type(placedAt)).toBe("number")
	end)
	it("reverts the pad to base when the slime is carried off", function()
		expect(stolen).toEqual({ "base", "crystal_grotto" })
		expect(pad(3):GetAttribute("HabitatAt") > placedAt).toBe(true)
	end)
end)
