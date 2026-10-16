--!nocheck
-- lune run tools/render/export [--pending]   (from games/steal-a-slime)
-- Builds the real world (WorldBuilder + the WorldProps Props models) under
-- @lune/roblox, applies what server/MeshSwap would do with the uploaded
-- meshes (one uniform fit into each slot, standing on its bottom; slot and
-- MeshStandIn parts hidden), stages a few habitat pads, and writes every
-- visible part and mesh with its world CFrame to tools/render/out/scene.json
-- for render_world.py. --skin <id> wears a Config.PLOT_SKINS skin on Plot_1 (real PlotDecor.applySkin
-- floor, fence / gate tint on the meshes, the skin decor in the Mailbox_1 slot) and writes
-- scene[_pending]_skin_<id>.json. --pending also swaps meshes that are in the kit but
-- not uploaded yet (ranch_fence_20, the BorderMesh ring): the intended look.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("../../src/visuals/tools/LuneGlobals")
local serde = require("@lune/serde")

local Config = require("../../src/shared/Config")
local Habitats = require("../../src/shared/Habitats")
local MeshAssets = require("../../src/shared/MeshAssets")
local Props = require("../../src/visuals/shared/Props")
local BorderTerrain = require("../../src/visuals/shared/BorderTerrain")
local WorldBorder = require("../../src/visuals/shared/WorldBorder")
local WorldBuilder = require("../../src/visuals/shared/WorldBuilder")
local PlotDecor = require("../../src/visuals/shared/PlotDecor")
local WorldLayout = require("../../src/visuals/shared/WorldLayout")

local PENDING = table.find(process.args, "--pending") ~= nil
local OUT = "tools/render/out"
local SKIN_ARG = table.find(process.args, "--skin")
local SKIN = if SKIN_ARG then process.args[SKIN_ARG + 1] else nil

-- Render staging: which pads show a new habitat mesh (plot, pad, habitat id).
local HABITAT_PADS = {
	{ 1, 2, "crystal_grotto" },
	{ 1, 3, "candy_patch" },
	{ 1, 6, "crystal_grotto" },
	{ 2, 1, "candy_patch" },
	{ 3, 4, "crystal_grotto" },
	{ 5, 7, "candy_patch" },
}

local function swappable(name: string): boolean
	local e = MeshAssets.get(name)
	if not e or not e.size then
		return false
	end
	return e.meshId ~= nil or (PENDING and fs.isFile(`../../shared/modeling-kit/out/{name}.fbx`))
end

local root = roblox.Instance.new("Folder")
root.Name = "Workspace"
local built = WorldBuilder.build(root)
for name, build in
	{ ShopStand = Props.shopStand, LeaderboardBoard = Props.leaderboardBoard, TutorialNpc = Props.tutorialNpc }
do
	local spot = WorldLayout.PROP_SPOTS[name]
	local model = build()
	-- Model:PivotTo (not in @lune/roblox): the pivot is the primary part.
	local target = CFrame.new(spot.pos[1], spot.pos[2], spot.pos[3]) * CFrame.Angles(0, math.rad(spot.yaw), 0)
	local move = target * model.PrimaryPart.CFrame:Inverse()
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = move * d.CFrame
		end
	end
	local mesh = WorldLayout.PROP_MESHES[name]
	if mesh then
		model:SetAttribute("MeshAsset", mesh)
	end
	model.Parent = built.map
end

-- Plot skin on Plot_1 (the floor colour / material through the real PlotDecor.applySkin).
local skinDef = nil
if SKIN then
	skinDef = PlotDecor.skin(SKIN)
	assert(skinDef.id == SKIN, `unknown plot skin {SKIN}`)
	PlotDecor.applySkin(built.plots:FindFirstChild("Plot_1"), SKIN, nil, nil)
end

local hidden: { [Instance]: boolean } = {}
local meshes = {}

local function cfOf(cf): { number }
	return { cf:GetComponents() }
end

-- Model:GetBoundingBox: AABB of the parts in the primary part's frame.
local function boundingBox(model)
	local frame = model.PrimaryPart and model.PrimaryPart.CFrame.Rotation or CFrame.new()
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local h = d.Size / 2
			for _, s in
				{
					{ 1, 1, 1 },
					{ 1, 1, -1 },
					{ 1, -1, 1 },
					{ 1, -1, -1 },
					{ -1, 1, 1 },
					{ -1, 1, -1 },
					{ -1, -1, 1 },
					{ -1, -1, -1 },
				}
			do
				local p = frame:PointToObjectSpace(d.CFrame * Vector3.new(h.X * s[1], h.Y * s[2], h.Z * s[3]))
				lo, hi = lo:Min(p), hi:Max(p)
			end
		end
	end
	return frame * CFrame.new((lo + hi) / 2), hi - lo
end

local swapped: { [Instance]: { [string]: boolean } } = {}
for _, scope in { built.map, built.plots } do
	swapped[scope] = {}
	for _, inst in scope:GetDescendants() do
		local name = inst:GetAttribute("MeshAsset")
			or (PENDING and (inst:GetAttribute("BorderMesh") or inst:GetAttribute("FenceMesh")))
		if typeof(name) == "string" and (inst:IsA("BasePart") or inst:IsA("Model")) and swappable(name) then
			local cf, box
			local size, drop
			-- Blender imports the kit FBX on its documented axes, which is where
			-- MeshSwap turns a Part slot's upload back to (MeshAssets.IMPORT_YAW):
			-- no turn here. A WorldProps Model skin keeps the upload's own front
			-- (turned IMPORT_YAW from the kit axes) and its MeshSize, like MeshSwap.
			local turn = 0
			local tint = nil
			if skinDef and skinDef.fence and inst:IsDescendantOf(built.plots:FindFirstChild("Plot_1")) then
				tint = { skinDef.fence[1] / 255, skinDef.fence[2] / 255, skinDef.fence[3] / 255 }
			end
			local skinMesh = skinDef and skinDef.decor and inst.Name == "Mailbox_1"
			if skinMesh then
				-- The skin decor stands where the mailbox mesh stands, same scale (PlotDecor.applySkinDecor).
				local native = (MeshAssets.get(skinDef.decor) :: any).size
				local scale = inst.Size.Y / (MeshAssets.get("ranch_mailbox") :: any).size[2]
				name = skinDef.decor
				cf, box = inst.CFrame, inst.Size
				size = { native[1] * scale, native[2] * scale, native[3] * scale }
				drop = (box.Y - size[2]) / 2
			elseif inst:IsA("Model") then
				cf, box = boundingBox(inst)
				for _, d in inst:GetDescendants() do
					hidden[d] = true
				end
				local unit = WorldLayout.meshSize(name, 1)
				local fixed = WorldLayout.meshSize(name, box.Y / unit[2])
				size, drop = fixed, 0
				cf = cf * CFrame.new(0, (fixed[2] - box.Y) / 2, (fixed[3] - box.Z) / 2)
				turn = math.rad(MeshAssets.IMPORT_YAW)
			else
				cf, box = inst.CFrame, inst.Size
				size, _, drop = MeshAssets.fit(name, { box.X, box.Y, box.Z })
			end
			hidden[inst] = true
			table.insert(meshes, {
				tint = tint,
				mesh = name,
				cf = cfOf(cf * CFrame.new(0, -drop, 0) * CFrame.Angles(0, turn, 0)),
				size = size,
				path = inst:GetFullName(),
			})
			swapped[scope][name] = true
		end
	end
	for _, d in scope:GetDescendants() do
		local s = d:GetAttribute("MeshStandIn")
		if d:IsA("BasePart") and s and swapped[scope][s] then
			hidden[d] = true
		end
	end
end

-- Habitat pads (client HabitatFx): the mesh at native footprint on the pad
-- bottom, Y scaled to pad height / seat; the stand and pad hide.
for _, h in HABITAT_PADS do
	local pad = built.plots:FindFirstChild(`Plot_{h[1]}`):FindFirstChild(`Pad_{h[2]}`)
	local habitat = Habitats.get(h[3])
	local slot = Habitats.slotMesh(h[3])
	if slot then
		hidden[pad] = true
		for _, d in pad:GetDescendants() do
			hidden[d] = true
		end
		for i = #meshes, 1, -1 do
			if meshes[i].path:find(pad:GetFullName(), 1, true) == 1 then
				table.remove(meshes, i)
			end
		end
		local sy = pad.Size.Y / habitat.seat
		local size = { slot.size[1], slot.size[2] * sy, slot.size[3] }
		local cf = pad.CFrame * CFrame.new(0, -pad.Size.Y / 2 + size[2] / 2, 0)
		table.insert(meshes, { mesh = habitat.kit, cf = cfOf(cf), size = size, path = pad:GetFullName() .. ".Habitat" })
	end
end

local plots = {}
for i = 1, #built.plots:GetChildren() do
	local centre, yaw = WorldLayout.plotCentre(i)
	table.insert(plots, { centre = centre, yaw = yaw })
end

local parts, lights = {}, {}
for _, scope in { built.map, built.plots } do
	for _, d in scope:GetDescendants() do
		if d:IsA("BasePart") and not hidden[d] and d.Transparency < 1 then
			local c = d.Color
			table.insert(parts, {
				name = d:GetFullName(),
				shape = d:IsA("Part") and d.Shape.Name or "Block",
				size = { d.Size.X, d.Size.Y, d.Size.Z },
				cf = cfOf(d.CFrame),
				color = { c.R, c.G, c.B },
				material = d.Material.Name,
				transparency = d.Transparency,
			})
		elseif d:IsA("PointLight") and d.Parent:IsA("BasePart") then
			local c, p = d.Color, d.Parent.CFrame.Position
			table.insert(
				lights,
				{ pos = { p.X, p.Y, p.Z }, color = { c.R, c.G, c.B }, range = d.Range, brightness = d.Brightness }
			)
		end
	end
end

-- The border hills (server/BorderTerrainView writes them as voxel terrain): the same seeded
-- heightfield sampled on an 8-stud grid; render_world.py turns it into a coloured mesh.
local terrain = nil
if not table.find(process.args, "--no-terrain") then
	local grid = BorderTerrain.sample(BorderTerrain.field(), 8)
	local heights, mats = {}, {}
	local letter = { Grass = "G", LeafyGrass = "L", Rock = "R" }
	for i, h in grid.heights do
		heights[i] = math.floor(h * 10 + 0.5) / 10
		mats[i] = letter[grid.materials[i]]
	end
	terrain = {
		step = grid.step,
		min = grid.min,
		n = grid.n,
		heights = heights,
		materials = table.concat(mats),
		colors = BorderTerrain.COLORS,
		inner = BorderTerrain.INNER,
		floor = BorderTerrain.FLOOR,
	}
end

fs.writeDir(OUT)
local suffix = (if PENDING then "_pending" else "") .. (if SKIN then `_skin_{SKIN}` else "")
fs.writeFile(
	`{OUT}/scene{suffix}.json`,
	serde.encode("json", {
		pending = PENDING,
		parts = parts,
		meshes = meshes,
		lights = lights,
		plots = plots,
		wallRadius = WorldBorder.RADIUS,
		ringPath = WorldLayout.RING_PATH_RADIUS,
		terrain = terrain,
	})
)
local counts = {}
for _, m in meshes do
	counts[m.mesh] = (counts[m.mesh] or 0) + 1
end
print(
	`wrote {OUT}/scene{suffix}.json: {#parts} parts, {#meshes} meshes, {#lights} lights (pending={PENDING})`
)
