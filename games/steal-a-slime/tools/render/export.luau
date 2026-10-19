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
-- not uploaded yet (ranch_fence_20, the BorderMesh ring): the intended look. (default) stands the merge_vat model
-- (real VatDecor.pose) over every plot's MergeVat disc; --cylinder keeps the old primitive and writes scene[_pending]_cylinder.json. --fountain-tier <1..4> shows the
-- FEATURES.FountainTiers look (real FountainTierDecor poses + FountainTiers.LOOKS glow) and writes
-- scene[_pending]_tier_<n>.json.
-- --snow <level 0..1> [--snow-phase settle|melt] shows SnowGround v2 (the same SnowCover tints and colour lerp as the
-- client) on the part colours and the border terrain colours, and writes scene[_pending]_snow_<phase>_<level>.json.
-- --fountain-split draws the FEATURES.FountainSplit look instead of the single slime_fountain mesh: the 5 pieces of
-- MeshAssets.FOUNTAIN_SPLIT, each at the slot centre + its offset (same maths as server/MeshSwap.swapFountainSplit);
-- writes scene[_pending]_fountain_split.json. The assembled pieces must draw exactly what the whole mesh draws.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("../../src/visuals/tools/LuneGlobals")
local serde = require("@lune/serde")

local BorderTerrain = require("../../src/visuals/shared/BorderTerrain")
local Config = require("../../src/shared/Config")
local FloorLayout = require("../../src/visuals/shared/FloorLayout")
local FountainTierDecor = require("../../src/visuals/shared/FountainTierDecor")
local FountainTiers = require("../../src/shared/FountainTiers")
local GroundTerrain = require("../../src/visuals/shared/GroundTerrain")
local Habitats = require("../../src/shared/Habitats")
local MeshAssets = require("../../src/shared/MeshAssets")
local ParadeLane = require("../../src/shared/ParadeLane")
local PlotDecor = require("../../src/visuals/shared/PlotDecor")
local Props = require("../../src/visuals/shared/Props")
local Ritual = require("../../src/shared/Ritual")
local SnowCover = require("../../src/visuals/shared/SnowCover")
local VatDecor = require("../../src/visuals/shared/VatDecor")
local WorldBorder = require("../../src/visuals/shared/WorldBorder")
local WorldBuilder = require("../../src/visuals/shared/WorldBuilder")
local WorldLayout = require("../../src/visuals/shared/WorldLayout")

local PENDING = table.find(process.args, "--pending") ~= nil
local OUT = "tools/render/out"
local SKIN_ARG = table.find(process.args, "--skin")
-- Bug #16: the merge_vat model is the default look of every plot's vat; --cylinder exports the old primitive (before shot).
local CYLINDER = table.find(process.args, "--cylinder") ~= nil
local FOUNTAIN_SPLIT = table.find(process.args, "--fountain-split") ~= nil
local SKIN = if SKIN_ARG then process.args[SKIN_ARG + 1] else nil
local TIER_ARG = table.find(process.args, "--fountain-tier")
local TIER = if TIER_ARG then tonumber(process.args[TIER_ARG + 1]) else nil
assert(not TIER_ARG or (TIER and TIER >= 1 and TIER <= FountainTiers.MAX_TIER), "--fountain-tier needs 1..4")

local SNOW_ARG = table.find(process.args, "--snow")
local SNOW = if SNOW_ARG then tonumber(process.args[SNOW_ARG + 1]) else nil
assert(not SNOW_ARG or (SNOW and SNOW >= 0 and SNOW <= 1), "--snow needs a level 0..1")
local PHASE_ARG = table.find(process.args, "--snow-phase")
local SNOW_PHASE = if PHASE_ARG then process.args[PHASE_ARG + 1] else "settle"
assert(SNOW_PHASE == "settle" or SNOW_PHASE == "melt", "--snow-phase needs settle or melt")
-- The client quantizes the level and tints from the original colour (SnowGround): same maths here.
local snowTints = if SNOW then SnowCover.tints(SnowCover.quantize(SNOW), SNOW_PHASE == "settle") else nil

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
-- The prop spots (WorldLayout.PROP_SPOTS): since WorldShops the two stands replace the single ShopStand.
for name, build in
	{
		ItemShopStand = Props.shopStand,
		UpgradeShopStand = Props.shopStand,
		LeaderboardBoard = Props.leaderboardBoard,
		TutorialNpc = Props.tutorialNpc,
	}
do
	local spot = WorldLayout.PROP_SPOTS[name] or WorldLayout.PROP_SPOTS.ItemShopStand -- ShopStand became ItemShopStand
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
			local size, scale, drop
			-- Blender imports the kit FBX on its documented axes, which is where
			-- MeshSwap turns a Part slot's upload back to (MeshAssets.IMPORT_YAW):
			-- no turn here. A WorldProps Model skin keeps the upload's own front
			-- (turned IMPORT_YAW from the kit axes) and its MeshSize, like MeshSwap.
			local turn = 0
			local tint = nil
			if skinDef and skinDef.fence and inst:IsDescendantOf(built.plots:FindFirstChild("Plot_1")) then
				tint = { skinDef.fence[1] / 255, skinDef.fence[2] / 255, skinDef.fence[3] / 255 }
			end
			if inst:IsA("BasePart") and inst:GetAttribute("MeshTint") == true then
				-- WorldBorder giants: MeshSwap copies the slot's Color onto the mesh
				tint = { inst.Color.R, inst.Color.G, inst.Color.B }
				-- SnowGround frosts the MeshPart colour (its slot's SnowKind), like the part tints below
				local kind = if snowTints
					then SnowCover.classify(inst.Name, "", false, 1, 1, 0, inst:GetAttribute(SnowCover.KIND_ATTRIBUTE))
					else nil
				if kind then
					local w = if kind == "grass" then snowTints.grass else snowTints.path
					tint = { SnowCover.lerpColor(tint[1], tint[2], tint[3], w) }
				end
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
				size, scale, drop = MeshAssets.fit(name, { box.X, box.Y, box.Z })
			end
			hidden[inst] = true
			local splitReady = FOUNTAIN_SPLIT and name == "slime_fountain" and inst:IsA("BasePart")
			if splitReady then
				for _, piece in MeshAssets.FOUNTAIN_SPLIT do
					splitReady = splitReady and swappable(piece)
				end
			end
			if splitReady then
				-- MeshSwap.swapFountainSplit: slot cf, standing on the bottom, each piece moved by its offset (slot axes, scaled)
				local k = scale or 1
				for _, piece in MeshAssets.FOUNTAIN_SPLIT do
					local entry = MeshAssets.get(piece) :: any
					local at = cf
						* CFrame.new(0, -drop, 0)
						* CFrame.new(entry.offset[1] * k, entry.offset[2] * k, entry.offset[3] * k)
					table.insert(meshes, {
						tint = tint,
						mesh = piece,
						cf = cfOf(at * CFrame.Angles(0, turn, 0)),
						size = { entry.size[1] * k, entry.size[2] * k, entry.size[3] * k },
						path = `{inst:GetFullName()}.{piece}`,
					})
				end
			else
				table.insert(meshes, {
					tint = tint,
					mesh = name,
					cf = cfOf(cf * CFrame.new(0, -drop, 0) * CFrame.Angles(0, turn, 0)),
					size = size,
					path = inst:GetFullName(),
				})
			end
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

-- Fountain tier decor (client FountainTierFx): the ring / crest poses at the tier, tinted like MeshPart.Color.
if TIER then
	for _, pose in FountainTierDecor.poses(TIER) do
		table.insert(meshes, {
			tint = { pose.color[1] / 255, pose.color[2] / 255, pose.color[3] / 255 },
			mesh = pose.mesh,
			cf = cfOf(CFrame.new(pose.position[1], pose.position[2], pose.position[3])),
			size = pose.size,
			path = `Workspace.FountainTier.{pose.mesh}`,
		})
	end
end

-- Merge vat (server MeshSwap.swapPlotVats): the mesh over every plot's disc, the disc and its goo hidden.
-- --cylinder keeps the primitive disc (the focus point for views 16 / 17 is Plot_1's disc either way).
local vatFocus = nil
for _, plot in built.plots:GetChildren() do
	local disc = plot:FindFirstChild("MergeVat")
	if disc then
		local pos = disc.CFrame.Position
		if plot.Name == "Plot_1" then
			vatFocus = { pos.X, pos.Y, pos.Z }
		end
		if not CYLINDER then
			local pose = VatDecor.pose(pos.X, pos.Y, pos.Z)
			local base = plot:FindFirstChild("Base")
			hidden[disc] = true
			for _, d in disc:GetDescendants() do
				hidden[d] = true
			end
			table.insert(meshes, {
				mesh = VatDecor.MESH,
				cf = cfOf(CFrame.new(pose.position[1], pose.position[2], pose.position[3]) * base.CFrame.Rotation),
				size = pose.size,
				path = `Workspace.Plots.{plot.Name}.MergeVat.VatMesh`,
			})
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
			if snowTints then
				local kind = SnowCover.classify(
					d.Name,
					d.Material.Name,
					d.Parent ~= nil and d.Parent.Name == "Paths",
					d.Size.X,
					d.Size.Z,
					d.Transparency,
					d:GetAttribute(SnowCover.KIND_ATTRIBUTE)
				)
				if kind then
					local w = if kind == "grass" then snowTints.grass else snowTints.path
					c = Color3.new(SnowCover.lerpColor(c.R, c.G, c.B, w))
				end
			end
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
			if TIER and TIER > 1 and d.Name == "CraterGlow" then
				local look = FountainTiers.look(TIER)
				c = Color3.fromRGB(look.glow[1], look.glow[2], look.glow[3])
			end
			table.insert(
				lights,
				{ pos = { p.X, p.Y, p.Z }, color = { c.R, c.G, c.B }, range = d.Range, brightness = d.Brightness }
			)
		end
	end
end

-- The goo lane (server/ParadeView.place, a runtime folder): the one smooth kit mesh at its pivot (like a MeshSwap
-- slot: no turn here, Blender imports on the documented axes) once it is uploaded or --pending; else the strips.
if swappable(ParadeLane.MESH) then
	local at = ParadeLane.MESH_PIVOT
	table.insert(meshes, {
		mesh = ParadeLane.MESH,
		cf = cfOf(CFrame.new(at[1], at[2], at[3])),
		size = (MeshAssets.get(ParadeLane.MESH) :: any).size,
		path = "Workspace.Map.Plaza.ParadeLane.Lane",
	})
else
	for _, strip in ParadeLane.strips() do
		table.insert(parts, {
			name = `Workspace.Map.Plaza.ParadeLane.{strip.name}`,
			shape = "Cylinder",
			size = strip.size,
			cf = strip.cf,
			color = { ParadeLane.COLOR[1] / 255, ParadeLane.COLOR[2] / 255, ParadeLane.COLOR[3] / 255 },
			material = "SmoothPlastic",
			transparency = 0,
		})
	end
end

-- The co-op ritual circle (server/RitualView, a runtime model): disc, ring, spots and orb.
local ritualAt = nil
if Config.FEATURES.CoopRitual then
	local R = Config.RITUAL
	local cx, cz = Ritual.centre()
	ritualAt = { cx, cz, R.CIRCLE_RADIUS }
	local function ritualPart(shape: string, size: { number }, at: { number }, color: { number }, material: string)
		local cf = if shape == "Cylinder"
			then { at[1], at[2], at[3], 0, -1, 0, 1, 0, 0, 0, 0, 1 }
			else { at[1], at[2], at[3], 1, 0, 0, 0, 1, 0, 0, 0, 1 }
		table.insert(parts, {
			name = "Workspace.Map.RitualCircle",
			shape = shape,
			size = size,
			cf = cf,
			color = { color[1] / 255, color[2] / 255, color[3] / 255 },
			material = material,
			transparency = 0,
		})
	end
	ritualPart(
		"Cylinder",
		{ 0.24, R.CIRCLE_RADIUS * 2, R.CIRCLE_RADIUS * 2 },
		{ cx, 0.12, cz },
		{ 86, 62, 150 },
		"SmoothPlastic"
	)
	ritualPart(
		"Cylinder",
		{ 0.2, (R.CIRCLE_RADIUS - 0.7) * 2, (R.CIRCLE_RADIUS - 0.7) * 2 },
		{ cx, 0.2, cz },
		{ 120, 96, 200 },
		"SmoothPlastic"
	)
	for _, spot in Ritual.spots() do
		ritualPart(
			"Cylinder",
			{ 0.2, R.STAND_RADIUS * 1.6, R.STAND_RADIUS * 1.6 },
			{ spot[1], 0.42, spot[2] },
			{ 190, 160, 255 },
			"Neon"
		)
	end
	ritualPart("Ball", { 2.6, 2.6, 2.6 }, { cx, 4.2, cz }, { 190, 160, 255 }, "Neon")
	-- the rule sign (RuleSign): a thin board on the plaza side, turned to face the fountain axis
	local sx, sz = Ritual.signSpot()
	local d = math.sqrt(sx * sx + sz * sz)
	local ux, uz = sx / d, sz / d -- unit vector from the axis to the sign; the board's width runs across it
	table.insert(parts, {
		name = "Workspace.Map.RitualCircle",
		shape = "Block",
		size = { 6, 1.8, 0.3 },
		cf = { sx, 1, sz, uz, 0, ux, 0, 1, 0, -ux, 0, uz },
		color = { 60 / 255, 40 / 255, 110 / 255 },
		material = "SmoothPlastic",
		transparency = 0,
	})
end

-- The border hills (server/BorderTerrainView writes them as voxel terrain): the same seeded
-- heightfield sampled on an 8-stud grid; render_world.py turns it into a coloured mesh.
local terrain = nil
if not table.find(process.args, "--no-terrain") then
	local grid = BorderTerrain.sample(BorderTerrain.field(), 8)
	local heights, mats = {}, {}
	local letter = { Grass = "G", LeafyGrass = "L", Rock = "R", Slate = "S", Snow = "W" }
	for i, h in grid.heights do
		heights[i] = math.floor(h * 10 + 0.5) / 10
		mats[i] = letter[grid.materials[i]]
	end
	local colors = BorderTerrain.COLORS
	if snowTints then
		colors = {}
		for name, c in BorderTerrain.COLORS do
			local w = if name == "Rock" or name == "Slate" then snowTints.rock else snowTints.terrainGrass
			local r, g, b = SnowCover.lerpColor(c[1] / 255, c[2] / 255, c[3] / 255, w)
			colors[name] = { r * 255, g * 255, b * 255 }
		end
	end
	terrain = {
		step = grid.step,
		min = grid.min,
		n = grid.n,
		heights = heights,
		materials = table.concat(mats),
		colors = colors,
		inner = BorderTerrain.INNER,
		floor = BorderTerrain.FLOOR,
	}
end

-- The inner ground (server/GroundTerrainView): one material per 4-stud cell; render_world.py blends them like the
-- voxel renderer does and shades them with the SlimeGrass / SlimeGround / SlimeSand look (tint x soft ColorMap).
local ground = nil
if not table.find(process.args, "--no-terrain") then
	local grid = GroundTerrain.grid()
	local letter = { Grass = "G", Ground = "D", Sand = "S" }
	local mats = {}
	for i, m in grid.materials do
		-- server/FloorTerrain: the grass under the floor is sand (its tufts would poke through it)
		local j, k = (i - 1) // grid.n, (i - 1) % grid.n
		mats[i] = letter[FloorLayout.groundMaterial(grid.min + k * grid.cell, grid.min + j * grid.cell, m)]
	end
	local tint, low = {}, {}
	for name, c in GroundTerrain.COLORS do
		local w = if not snowTints then 0 elseif name == "Grass" then snowTints.terrainGrass else snowTints.path
		local r, g, b = SnowCover.lerpColor(c[1] / 255, c[2] / 255, c[3] / 255, w)
		tint[name] = { r * 255, g * 255, b * 255 }
		local dark, depth = GroundTerrain.DARK[name], GroundTerrain.MAP_DEPTH[name]
		low[name] = {}
		for k = 1, 3 do
			low[name][k] = 1 - (1 - dark[k] / c[k]) * depth
		end
	end
	ground = { cell = grid.cell, min = grid.min, n = grid.n, materials = table.concat(mats), tint = tint, low = low }
end

fs.writeDir(OUT)
local suffix = (if PENDING then "_pending" else "")
	.. (if SKIN then `_skin_{SKIN}` else "")
	.. (if TIER then `_tier_{TIER}` else "")
	.. (if CYLINDER then "_cylinder" else "")
	.. (if FOUNTAIN_SPLIT then "_fountain_split" else "")
	.. (if SNOW then `_snow_{SNOW_PHASE}_{SNOW}` else "")
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
		ground = ground,
		vat = vatFocus,
		ritual = ritualAt,
		lane = ParadeLane.WAYPOINTS,
		laneStart = ParadeLane.MOUTH,
		slideEnd = WorldLayout.SLIDE_PATH[#WorldLayout.SLIDE_PATH],
	})
)
local counts = {}
for _, m in meshes do
	counts[m.mesh] = (counts[m.mesh] or 0) + 1
end
print(`wrote {OUT}/scene{suffix}.json: {#parts} parts, {#meshes} meshes, {#lights} lights (pending={PENDING})`)
