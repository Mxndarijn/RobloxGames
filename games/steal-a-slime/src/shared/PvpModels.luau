--!strict
--[[
	PvpModels (the ONE place to hook up how PvP items look in the hand, CONTRACT.md §26.3)

	One row per Config.PVP_TOOLS id: `mesh` (a MeshAssets name), `size` (studs; an uploaded mesh is fitted into it
	at one uniform scale), `grip` (Tool.Grip convention: `pos` studs, `rotDeg` degrees; the item's frame is placed
	so that RightGripAttachment = item * grip) and `pieces`, the placeholder built from Parts while the mesh has no
	meshId. server/PvpHeld builds the held model from this table only.

	Item frame (the same as a Tool handle held in the arm-forward pose): +Y up, -Z forward along the arm, +X to
	the holder's right; the origin is the fist. A piece is { shape, size, pos, rotDeg?, color (RGB 0..255),
	material?, transparency? }; a Cylinder's size is { diameter, length, diameter } with the length along `axis`
	(default Y).

	Hooking up an uploaded mesh is one MeshAssets entry for its name: PvpModels.meshId then returns it and the
	pieces are only the fallback when CreateMeshPartAsync fails.
]]

local MeshAssets = if script then require(script.Parent.MeshAssets) else require("./MeshAssets")

export type RGB = { number }
export type Piece = {
	shape: "Block" | "Ball" | "Cylinder",
	size: { number },
	pos: { number },
	rotDeg: { number }?,
	axis: ("X" | "Y" | "Z")?,
	color: RGB,
	material: string?,
	transparency: number?,
}
export type Grip = { pos: { number }, rotDeg: { number } }
export type Item = { mesh: string, size: { number }, grip: Grip, pieces: { Piece } }

local PvpModels = {}

PvpModels.MODEL_NAME = "PvpHeld" -- the Model under the character (server/PvpHeld)
PvpModels.ITEM_ATTRIBUTE = "ItemId" -- on that Model: which item it shows
PvpModels.MESH_ATTRIBUTE = "Mesh" -- on that Model: true when it is the uploaded mesh, not the placeholder

local NO_GRIP: Grip = { pos = { 0, 0, 0 }, rotDeg = { 0, 0, 0 } }

local WHITE: RGB = { 245, 245, 245 }
local GOO: RGB = { 90, 230, 80 }
local GOO_DARK: RGB = { 50, 170, 60 }
local METAL: RGB = { 120, 125, 140 }
local WOOD: RGB = { 160, 110, 65 }

-- Glove colours per tier: Bonk red, Bounce blue, Boom orange, Thunder yellow, Royal gold with a purple cuff.
local GLOVES: { { mitt: RGB, cuff: RGB } } = {
	{ mitt = { 220, 50, 50 }, cuff = WHITE },
	{ mitt = { 60, 140, 240 }, cuff = WHITE },
	{ mitt = { 255, 130, 30 }, cuff = { 60, 60, 60 } },
	{ mitt = { 255, 220, 40 }, cuff = { 110, 60, 200 } },
	{ mitt = { 255, 200, 60 }, cuff = { 120, 40, 160 } },
}

-- A chunky boxing mitt round the fist, bigger each tier; tier 4 and 5 get a bolt / crown stud on top.
local function glove(tier: number): Item
	local c = GLOVES[tier]
	local s = 0.75 + (tier - 1) * 0.05
	local pieces: { Piece } = {
		{ shape = "Ball", size = { 1.6 * s, 1.5 * s, 1.7 * s }, pos = { 0, 0.05, -0.25 * s }, color = c.mitt },
		{ shape = "Ball", size = { 0.6 * s, 0.6 * s, 0.75 * s }, pos = { -0.7 * s, 0.2, -0.3 * s }, color = c.mitt },
		{
			shape = "Cylinder",
			axis = "Z",
			size = { 1.25 * s, 0.6, 1.25 * s },
			pos = { 0, 0, 0.55 * s },
			color = c.cuff,
			material = "Fabric",
		},
	}
	if tier >= 4 then
		table.insert(pieces, {
			shape = "Block",
			size = { 0.25, 0.55, 0.25 },
			pos = { 0, 0.8 * s, -0.25 * s },
			rotDeg = { 0, 0, 20 },
			color = if tier == 5 then { 255, 240, 120 } else { 255, 255, 255 },
			material = "Neon",
		})
	end
	return {
		mesh = `pvp_knock_glove_{tier}`,
		size = { 1.6 * s, 1.5 * s, 2.1 * s },
		grip = NO_GRIP,
		pieces = pieces,
	}
end

-- A goo blob held in the palm: a flat puddle disc with a wobbling dome; bigger and darker per tier.
local function trap(tier: number): Item
	local s = 1 + (tier - 1) * 0.15
	return {
		mesh = `pvp_goo_trap_{tier}`,
		size = { 1.8 * s, 1.1 * s, 1.8 * s },
		grip = NO_GRIP,
		pieces = {
			{
				shape = "Cylinder",
				size = { 1.8 * s, 0.25, 1.8 * s },
				pos = { 0, 0.35, -0.5 },
				color = GOO_DARK,
				material = "SmoothPlastic",
			},
			{
				shape = "Ball",
				size = { 1.2 * s, 0.8 * s, 1.2 * s },
				pos = { 0, 0.65, -0.5 },
				color = GOO,
				material = "Glass",
				transparency = 0.25,
			},
			{ shape = "Ball", size = { 0.35, 0.35, 0.35 }, pos = { 0.3 * s, 0.95 * s, -0.7 }, color = WHITE },
		},
	}
end

-- A goo blaster: body over the fist, barrel forward, a goo tank on top; tier colours and a longer barrel.
local BLASTERS: { RGB } = { { 80, 200, 255 }, { 255, 140, 40 }, { 170, 60, 230 } }
local function blaster(tier: number): Item
	local body = BLASTERS[tier]
	local barrel = 1.4 + tier * 0.35
	return {
		mesh = `pvp_goo_blaster_{tier}`,
		size = { 1, 1.6, 1.2 + barrel },
		grip = NO_GRIP,
		pieces = {
			{ shape = "Block", size = { 0.55, 0.75, 1.5 }, pos = { 0, 0.45, -0.55 }, color = body },
			{
				shape = "Cylinder",
				axis = "Z",
				size = { 0.5, barrel, 0.5 },
				pos = { 0, 0.5, -1.3 - barrel / 2 + 0.2 },
				color = METAL,
				material = "Metal",
			},
			{
				shape = "Cylinder",
				axis = "Z",
				size = { 0.7, 0.25, 0.7 },
				pos = { 0, 0.5, -1.1 - barrel },
				color = GOO,
				material = "Neon",
			},
			{
				shape = "Ball",
				size = { 0.8, 0.8, 0.8 },
				pos = { 0, 1.05, -0.35 },
				color = GOO,
				material = "Glass",
				transparency = 0.2,
			},
		},
	}
end

local ITEMS: { [string]: Item } = {
	KnockGlove1 = glove(1),
	KnockGlove2 = glove(2),
	KnockGlove3 = glove(3),
	KnockGlove4 = glove(4),
	KnockGlove5 = glove(5),
	GooTrap1 = trap(1),
	GooTrap2 = trap(2),
	GooTrap3 = trap(3),
	GooBlaster1 = blaster(1),
	GooBlaster2 = blaster(2),
	GooBlaster3 = blaster(3),
	-- a party popper: striped cone pointing forward
	FunConfetti = {
		mesh = "pvp_fun_confetti",
		size = { 0.9, 0.9, 1.6 },
		grip = NO_GRIP,
		pieces = {
			{
				shape = "Cylinder",
				axis = "Z",
				size = { 0.55, 1.2, 0.55 },
				pos = { 0, 0.1, -0.5 },
				color = { 255, 80, 140 },
			},
			{
				shape = "Cylinder",
				axis = "Z",
				size = { 0.85, 0.3, 0.85 },
				pos = { 0, 0.1, -1.15 },
				color = { 255, 220, 60 },
			},
			{ shape = "Ball", size = { 0.3, 0.3, 0.3 }, pos = { 0.2, 0.35, -1.3 }, color = { 80, 200, 255 } },
		},
	},
	-- a goo balloon on a string above the fist
	FunBalloon = {
		mesh = "pvp_fun_balloon",
		size = { 1.7, 4.4, 1.7 },
		grip = NO_GRIP,
		pieces = {
			{ shape = "Cylinder", size = { 0.06, 2.6, 0.06 }, pos = { 0, 1.4, 0 }, color = WHITE },
			{
				shape = "Ball",
				size = { 1.6, 1.9, 1.6 },
				pos = { 0, 3.5, 0 },
				color = { 255, 90, 150 },
				material = "Glass",
				transparency = 0.15,
			},
			{ shape = "Ball", size = { 0.3, 0.3, 0.3 }, pos = { 0, 2.55, 0 }, color = { 255, 90, 150 } },
		},
	},
	-- a bubble wand: a stick with a see-through hoop
	FunBubbles = {
		mesh = "pvp_fun_bubbles",
		size = { 1.4, 2.8, 0.4 },
		grip = NO_GRIP,
		pieces = {
			{ shape = "Cylinder", size = { 0.18, 1.8, 0.18 }, pos = { 0, 0.75, 0 }, color = { 120, 200, 255 } },
			{
				shape = "Cylinder",
				axis = "Z",
				size = { 1.3, 0.12, 1.3 },
				pos = { 0, 2.1, 0 },
				color = { 180, 230, 255 },
				material = "Glass",
				transparency = 0.5,
			},
			{
				shape = "Cylinder",
				axis = "Z",
				size = { 1.45, 0.08, 1.45 },
				pos = { 0, 2.1, 0.05 },
				color = { 120, 200, 255 },
				transparency = 0.1,
			},
		},
	},
	-- a folded bounce pad carried flat on the palm
	FunBouncePad = {
		mesh = "pvp_fun_bounce_pad",
		size = { 1.9, 0.6, 1.9 },
		grip = NO_GRIP,
		pieces = {
			{ shape = "Cylinder", size = { 1.9, 0.3, 1.9 }, pos = { 0, 0.3, -0.5 }, color = { 255, 100, 200 } },
			{
				shape = "Cylinder",
				size = { 1.4, 0.12, 1.4 },
				pos = { 0, 0.5, -0.5 },
				color = WHITE,
				material = "Fabric",
			},
		},
	},
	-- a squeaky toy hammer: handle up, a fat head on top
	FunSqueaky = {
		mesh = "pvp_fun_squeaky",
		size = { 1.6, 2.9, 1 },
		grip = NO_GRIP,
		pieces = {
			{ shape = "Cylinder", size = { 0.25, 2.2, 0.25 }, pos = { 0, 0.8, 0 }, color = WOOD, material = "Wood" },
			{
				shape = "Cylinder",
				axis = "X",
				size = { 0.95, 1.5, 0.95 },
				pos = { 0, 2.2, 0 },
				color = { 255, 220, 50 },
			},
			{
				shape = "Cylinder",
				axis = "X",
				size = { 1.0, 0.2, 1.0 },
				pos = { 0.75, 2.2, 0 },
				color = { 230, 50, 50 },
			},
			{
				shape = "Cylinder",
				axis = "X",
				size = { 1.0, 0.2, 1.0 },
				pos = { -0.75, 2.2, 0 },
				color = { 230, 50, 50 },
			},
		},
	},
	-- a tube launcher with a slime hat sitting in its mouth
	FunHatLauncher = {
		mesh = "pvp_fun_hat_launcher",
		size = { 1.1, 1.6, 2.4 },
		grip = NO_GRIP,
		pieces = {
			{ shape = "Cylinder", axis = "Z", size = { 0.8, 2, 0.8 }, pos = { 0, 0.4, -0.8 }, color = { 90, 90, 110 } },
			{ shape = "Cylinder", size = { 0.65, 0.5, 0.65 }, pos = { 0, 0.95, -1.6 }, color = { 60, 200, 120 } },
			{ shape = "Cylinder", size = { 1, 0.1, 1 }, pos = { 0, 0.7, -1.6 }, color = { 60, 200, 120 } },
		},
	},
	-- a disco ball with a lit fuse
	FunDanceBomb = {
		mesh = "pvp_fun_dance_bomb",
		size = { 1.3, 1.8, 1.3 },
		grip = NO_GRIP,
		pieces = {
			{
				shape = "Ball",
				size = { 1.3, 1.3, 1.3 },
				pos = { 0, 0.45, -0.35 },
				color = { 200, 160, 255 },
				material = "Foil",
			},
			{ shape = "Cylinder", size = { 0.12, 0.45, 0.12 }, pos = { 0, 1.25, -0.35 }, color = { 60, 50, 40 } },
			{
				shape = "Ball",
				size = { 0.2, 0.2, 0.2 },
				pos = { 0, 1.5, -0.35 },
				color = { 255, 170, 40 },
				material = "Neon",
			},
		},
	},
	-- a goo rocket on a stick
	FunFireworks = {
		mesh = "pvp_fun_fireworks",
		size = { 0.7, 3, 0.7 },
		grip = NO_GRIP,
		pieces = {
			{ shape = "Cylinder", size = { 0.12, 1.4, 0.12 }, pos = { 0, 0.3, 0 }, color = WOOD, material = "Wood" },
			{ shape = "Cylinder", size = { 0.55, 1.4, 0.55 }, pos = { 0, 1.6, 0 }, color = { 230, 50, 60 } },
			{ shape = "Ball", size = { 0.55, 0.7, 0.55 }, pos = { 0, 2.45, 0 }, color = GOO, material = "Neon" },
		},
	},
}

for _, item in ITEMS do
	for _, piece in item.pieces do
		table.freeze(piece)
	end
	table.freeze(item.pieces)
	table.freeze(item)
end
PvpModels.ITEMS = table.freeze(ITEMS)

-- Every held-item mesh name (in MeshAssets.NAMES; none is a world slot).
local meshes: { string } = {}
for _, item in ITEMS do
	table.insert(meshes, item.mesh)
end
table.sort(meshes)
PvpModels.MESHES = table.freeze(meshes)

function PvpModels.get(id: string?): Item?
	return if id then ITEMS[id] else nil
end

-- The uploaded mesh for item `id`, or nil while it has none (the placeholder pieces are used).
function PvpModels.meshId(id: string?): string?
	local item = PvpModels.get(id)
	return if item then MeshAssets.meshId(item.mesh) else nil
end

-- The mesh a placed Goo Trap / Bounce Pad marker may use (TrapPlaced itemId), nil for other items.
function PvpModels.markerMesh(itemId: string?): string?
	if itemId == "FunBouncePad" or (itemId and string.sub(itemId, 1, 7) == "GooTrap") then
		local item = PvpModels.get(itemId)
		return item and item.mesh
	end
	return nil
end

return PvpModels
