--!nocheck
-- The obby world's backdrop layout (WorldLayout.obbyBackdrop, drawn by visuals/client/ObbyBackdrop): every mesh piece
-- names an uploaded kit mesh, islands stay clear of the course, the cloud sea lies below it, and the piece count stays
-- phone-friendly. Then the client module in the fake runtime: every visit (not just the first) gets its meshes.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Constants = require("../src/shared/Constants")
local Runtime = require("../tools/livetest/Runtime")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local UPLOADED = serde.decode("json", fs.readFile("../../shared/modeling-kit/uploaded.json"))
local MESH_KINDS = { island = true, landmark = true, cloud = true, bank = true }
local COURSE_CLEAR = 40 -- studs either side of the course line no island may reach into
local MAX_PIECES = 80 -- MeshParts the client builds on arrival

describe("Obby backdrop layout", function()
	local pieces = WorldLayout.obbyBackdrop()

	it("gives every mesh piece an uploaded kit mesh", function()
		for _, p in pieces do
			if MESH_KINDS[p.kind] then
				local entry = UPLOADED[p.model :: string]
				expect(entry ~= nil and entry.meshId ~= nil).toBe(true)
			else
				expect(p.kind).toBe("sea")
			end
		end
	end)

	it("keeps islands and landmarks clear of the course", function()
		for _, p in pieces do
			if p.kind == "island" or p.kind == "landmark" then
				expect(math.abs(p.pos[3]) - p.radius > COURSE_CLEAR).toBe(true)
			end
		end
	end)

	it("lays the cloud sea well below the course", function()
		local depth = WorldLayout.OBBY.world.seaDepth
		local banks = 0
		for _, p in pieces do
			if p.kind == "bank" or p.kind == "sea" then
				expect(p.pos[2] < -depth * 0.8).toBe(true)
				banks += if p.kind == "bank" then 1 else 0
			end
		end
		expect(banks >= 10).toBe(true)
	end)

	it("stays within the phone piece budget", function()
		expect(#pieces <= MAX_PIECES).toBe(true)
	end)

	it("builds the same layout every time", function()
		local again = WorldLayout.obbyBackdrop()
		expect(#again).toBe(#pieces)
		for i, p in pieces do
			expect(again[i].pos[1]).toBe(p.pos[1])
			expect(again[i].model).toBe(p.model)
		end
	end)
end)

-- The client module itself, in the fake runtime (every CreateMeshPartAsync takes FETCH_SECONDS of virtual time).
-- ObbyWorld builds the backdrop on every arrival and destroys it on the way out, and the mesh templates stay cached
-- between visits: the second visit (the next run, a respawn) must dress the world just like the first.
local FETCH_SECONDS = 1
local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-obby-backdrop-{os.time()}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt
rt = Runtime.new(path, {
	createMeshPart = function()
		rt:wait(FETCH_SECONDS)
		return roblox.Instance.new("MeshPart")
	end,
})
fs.removeFile(path)
local ObbyBackdrop = rt:require(rt.game:GetService("StarterPlayer").StarterPlayerScripts.VisualsClient.ObbyBackdrop)

local meshPieces = 0
for _, p in WorldLayout.obbyBackdrop() do
	if MESH_KINDS[p.kind] then
		meshPieces += 1
	end
end

local function visit()
	local folder
	rt:spawn(function()
		folder = ObbyBackdrop.build(rt.workspace)
	end)
	rt:advance(FETCH_SECONDS * 3, 0.5)
	local counts = { meshes = 0, sea = 0, folder = folder }
	for _, child in folder:GetChildren() do
		if child.ClassName == "MeshPart" then
			counts.meshes += 1
		elseif child.Name == "CloudSea" then
			counts.sea += 1
		end
	end
	return counts
end

local first = visit()
first.folder:Destroy()
local second = visit()
second.folder:Destroy()
local third = visit()

describe("Obby backdrop rebuild", function()
	it("dresses the first visit with every mesh piece", function()
		expect(meshPieces > 0).toBe(true)
		expect(first.meshes).toBe(meshPieces)
		expect(first.sea).toBe(1)
	end)
	it("dresses every later visit too, from the cached templates", function()
		expect(second.meshes).toBe(meshPieces)
		expect(third.meshes).toBe(meshPieces)
		expect(third.sea).toBe(1)
	end)
	it("builds under the given parent and leaves no strays behind", function()
		expect(third.folder.Parent).toBe(rt.workspace)
		local folders = 0
		for _, child in rt.workspace:GetChildren() do
			if child.Name == Constants.OBBY_BACKDROP then
				folders += 1
			end
		end
		expect(folders).toBe(1)
		expect(#rt.errors).toBe(0)
	end)
end)
