--!strict
-- pc-watcher shot targets resolve (Phoenix run on 8fd3ac5 skipped 183-186/191: targets named by MeshAsset, e.g. "ranch_well",
-- while luau/shot_find matches INSTANCE names, e.g. "Well"). Every `target` of a kind = "world" shot in
-- tools/pipeline/pc-watcher/shots/*.json must match (case-insensitive, exact or substring, like shot_find) an instance name in the
-- built world (world/*.rbxmx), or a name the server builds at runtime (a literal in src/). mesh_stand lists name MeshAssets that
-- must be placed. bug11_char_walk's findMesh targets must be built instances.
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local MeshAssets = require("../src/shared/MeshAssets")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local SHOTS = "../../tools/pipeline/pc-watcher/shots"
local WALK = "../../tools/pipeline/pc-watcher/luau/bug11_char_walk.luau"
-- Targets of shots whose geometry no longer exists (the part paths became terrain in #270). Owners: those shots' authors. This list
-- may only shrink: the spec fails when one of these resolves again (drop it here) or a new unresolved target appears.
local KNOWN_STALE = { path1 = true, path3 = true, ring1 = true, ring8 = true }

local function files(dir: string, ext: string, out: { string }): { string }
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			files(path, ext, out)
		elseif string.sub(name, -#ext) == ext then
			table.insert(out, path)
		end
	end
	return out
end

local worldNames: { string } = {}
for _, path in files("world", ".rbxmx", {}) do
	for n in string.gmatch(fs.readFile(path), 'name="Name">([^<]*)<') do
		table.insert(worldNames, string.lower(n))
	end
end
local srcText = {}
for _, path in files("src", ".luau", {}) do
	table.insert(srcText, string.lower(fs.readFile(path)))
end
local src = table.concat(srcText, "\n")

local function inWorld(target: string): boolean
	local t = string.lower(target)
	for _, n in worldNames do
		if n == t or string.find(n, t, 1, true) then
			return true
		end
	end
	return false
end

local function resolves(target: string): boolean
	return inWorld(target) or string.find(src, string.lower(target), 1, true) ~= nil
end

local function shots(): { { file: string, shot: any } }
	local out = {}
	for _, path in files(SHOTS, ".json", {}) do
		local d = serde.decode("json", fs.readFile(path))
		local list = if d[1] ~= nil then d else { d }
		for _, s in list do
			table.insert(out, { file = path, shot = s })
		end
	end
	return out
end

describe("pc-watcher shot targets", function()
	it("every world shot target is a built or runtime instance name", function()
		local missing, checked = {}, 0
		for _, e in shots() do
			local s = e.shot
			if s.kind == "world" and type(s.target) == "string" then
				checked += 1
				local stale = KNOWN_STALE[string.lower(s.target)]
				if stale then
					if resolves(s.target) then
						table.insert(missing, `{e.file}: "{s.target}" resolves again, drop it from KNOWN_STALE`)
					end
				elseif not resolves(s.target) then
					table.insert(missing, `{e.file}: target "{s.target}"`)
				end
			end
		end
		expect(checked > 50).toBe(true)
		if #missing > 0 then
			print(table.concat(missing, "\n"))
		end
		expect(#missing).toBe(0)
	end)
	it("the bug-11 mesh-collision shots target the placed RanchProps instances", function()
		local want = {
			["183-bug11-hull-stand.json"] = "Well",
			["184-bug11-box-stand.json"] = "Wagon_5",
			["185-bug11-pcd-stand.json"] = "FenceStile_8",
			["186-bug11-walk-stile.json"] = "FenceStile_8",
			["191-bug11-walk-loft.json"] = "BarnLoft_2",
		}
		for file, target in want do
			local s = serde.decode("json", fs.readFile(`{SHOTS}/{file}`))
			expect(s.target).toBe(target)
			expect(inWorld(target)).toBe(true)
		end
	end)
	it("mesh_stand meshes are MeshAssets that are placed in the world", function()
		local layout = fs.readFile("src/visuals/shared/RanchProps.luau")
			.. fs.readFile("src/visuals/shared/WorldLayout.luau")
		for _, e in shots() do
			local list = e.shot.mesh_stand
			if type(list) == "table" then
				for _, mesh in list do
					expect(MeshAssets.entries[mesh] ~= nil).toBe(true)
					expect(string.find(layout, `"{mesh}"`, 1, true) ~= nil).toBe(true)
				end
			end
		end
	end)
	it("bug11_char_walk finds its meshes by built instance name", function()
		local walk = fs.readFile(WALK)
		local n = 0
		for name in string.gmatch(walk, 'findMesh%("([^"]+)"%)') do
			n += 1
			expect(inWorld(name)).toBe(true)
		end
		expect(n >= 2).toBe(true)
	end)
end)
