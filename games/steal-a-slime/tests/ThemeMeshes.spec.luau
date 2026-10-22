--!strict
-- Themed goo jar tower meshes (CONTRACT.md §15): which mesh a plot slot shows under its plot skin, the companions a
-- theme adds, where a companion stands on its piece's slot, and that every built theme is complete in MeshAssets.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local Config = require("../src/shared/Config")
local JarMeshes = require("../src/visuals/shared/JarMeshes")
local MeshAssets = require("../src/shared/MeshAssets")
local TestRunner = require("./TestRunner")
local ThemeMeshes = require("../src/shared/ThemeMeshes")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function only(names: { string }): (string) -> boolean
	return function(name: string): boolean
		return table.find(names, name) ~= nil
	end
end

-- The tower pieces a theme repaints (models/_goo_jar.py themed_pieces): every jar piece but the glass, the door ring
-- and the crown.
local function themedPieces(): { string }
	local out = {}
	for name in JarMeshes :: any do
		if
			not string.find(name, "@", 1, true)
			and not string.find(name, "glass", 1, true)
			and name ~= "goo_jar_door_ring"
			and name ~= "goo_jar_crown"
		then
			table.insert(out, name)
		end
	end
	table.sort(out)
	return out
end

describe("ThemeMeshes.look", function()
	it("shows the themed piece when it exists, else the classic piece", function()
		local has = only({ "goo_jar_foot@garden" })
		expect(ThemeMeshes.look("goo_jar_foot", "garden", has)).toBe("goo_jar_foot@garden")
		expect(ThemeMeshes.look("goo_jar_stair", "garden", has)).toBe("goo_jar_stair")
		expect(ThemeMeshes.look("goo_jar_foot", "candy", has)).toBe("goo_jar_foot")
	end)
	it("classic, a missing or a junk skin keep the classic piece", function()
		local has = function()
			return true
		end
		expect(ThemeMeshes.look("goo_jar_foot", Config.PLOT_SKIN_DEFAULT, has)).toBe("goo_jar_foot")
		expect(ThemeMeshes.look("goo_jar_foot", nil, has)).toBe("goo_jar_foot")
		expect(ThemeMeshes.look("goo_jar_foot", 7, has)).toBe("goo_jar_foot")
	end)
end)

describe("ThemeMeshes.companion", function()
	it("adds the props on the foot and the hat on the mascot, only when built", function()
		local has = only({ "goo_jar_props@garden", "goo_jar_hat@garden" })
		expect(ThemeMeshes.companion("goo_jar_foot", "garden", has)).toBe("goo_jar_props@garden")
		expect(ThemeMeshes.companion("goo_jar_mascot", "garden", has)).toBe("goo_jar_hat@garden")
		expect(ThemeMeshes.companion("goo_jar_stair", "garden", has)).toBeNil()
		expect(ThemeMeshes.companion("goo_jar_foot", "crystal", has)).toBeNil()
		expect(ThemeMeshes.companion("goo_jar_foot", "classic", has)).toBeNil()
	end)
end)

describe("ThemeMeshes.place", function()
	it("scales the companion and turns its offset half round (x and z flip) onto the slot", function()
		local piece = { size = { 2, 2, 2 }, centre = { 1, 1, 1 } }
		local companion = { size = { 1, 0.5, 1 }, centre = { 2, 3, 0 } }
		local size, offset = ThemeMeshes.place(piece, companion, 2)
		expect(table.concat(size, ",")).toBe("2,1,2")
		expect(table.concat(offset, ",")).toBe("-2,4,2")
	end)
	it("every companion has a JarMeshes box, and so does the piece it rides on", function()
		for name in JarMeshes :: any do
			local base = string.match(name, "^(.-)@")
			if base then
				local piece = nil
				for p, c in ThemeMeshes.COMPANIONS do
					if c == base then
						piece = p
					end
				end
				expect(`{name}: {piece ~= nil and (JarMeshes :: any)[piece] ~= nil}`).toBe(`{name}: true`)
			end
		end
	end)
end)

describe("themed meshes in MeshAssets", function()
	it("a theme with any uploaded mesh has every piece and both companions, each with a size", function()
		for _, skin in Config.PLOT_SKINS do
			local id = skin.id
			if MeshAssets.meshId(`goo_jar_foot@{id}`) == nil then
				continue -- not built yet: its plots keep the classic tower
			end
			local names = themedPieces()
			for _, base in ThemeMeshes.COMPANIONS do
				table.insert(names, base)
			end
			for _, base in names do
				local entry = MeshAssets.get(`{base}@{id}`)
				local ok = entry ~= nil and entry.meshId ~= nil and entry.size ~= nil
				expect(`{base}@{id}: {ok}`).toBe(`{base}@{id}: true`)
			end
		end
	end)
	it(
		"the generated MeshAssets block matches the kit's uploaded.json (rerun tools/goo_jar_theme_assets.py)",
		function()
			local record = serde.decode("json", fs.readFile("../../shared/modeling-kit/uploaded.json"))
			local n = 0
			for name, upload in record do
				if string.find(name, "@", 1, true) and upload.meshId and upload.meshSize then
					n += 1
					local entry = MeshAssets.get(name)
					local ok = entry ~= nil
						and entry.meshId == upload.meshId
						and tostring(entry.assetId) == tostring(upload.assetId)
						and entry.size ~= nil
						and math.abs(entry.size[2] - upload.meshSize[2]) < 1e-3
					expect(`{name}: {ok}`).toBe(`{name}: true`)
				end
			end
			expect(n > 0).toBe(true)
		end
	)
	it("themed pieces keep their classic piece's size (they drop into the classic slot)", function()
		for _, skin in Config.PLOT_SKINS do
			for _, base in themedPieces() do
				local themed = MeshAssets.get(`{base}@{skin.id}`)
				local classic = MeshAssets.get(base)
				if themed and themed.size and classic and classic.size then
					for axis = 1, 3 do
						local off = math.abs(themed.size[axis] - classic.size[axis])
						expect(`{base}@{skin.id} axis {axis}: {off <= 0.3}`).toBe(`{base}@{skin.id} axis {axis}: true`)
					end
				end
			end
		end
	end)
end)
