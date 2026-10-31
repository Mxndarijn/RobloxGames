--!strict
-- The obby world's backdrop layout (WorldLayout.obbyBackdrop, drawn by visuals/client/ObbyBackdrop): every mesh piece
-- names an uploaded kit mesh, islands stay clear of the course, the cloud sea lies below it, and the piece count stays
-- phone-friendly.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

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
