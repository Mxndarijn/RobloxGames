--!strict
--[[
	PvpModels (the ONE place to hook up how PvP items look in the hand, CONTRACT.md §26.3)

	One row per Config.PVP_TOOLS id: `mesh` (a MeshAssets name), `size` (studs; the mesh's native size from
	MeshAssets, the mesh is fitted into it at one uniform scale), `grip` (Tool.Grip convention: `pos` studs, `rotDeg`
	degrees; the item's frame is placed so that RightGripAttachment = item * grip) and `pieces`, the placeholder built
	from Parts while the mesh has no meshId or fails to load. server/PvpHeld builds the held model from this table only.

	Mesh grips: `pos` is the hand point measured from the mesh's bbox centre in the mesh's own axes, as the uploaded
	mesh comes in (the kit's front, Blender -Y, is the MeshPart's -Z; the modelers' offsets in
	shared/modeling-kit/sheets/<mesh>_rounds.md use the opposite X and Z signs). Blasters, the Slime Hat Launcher and
	Goo Fireworks already point their muzzle along -Z (forward), pistol grip below. Gloves stand upright with the cuff
	at the bottom and turn 90 degrees about X (and roll so the back of the hand is up) to punch forward. The Bounce Pad
	is held by its -X rim and turns so the pad reaches forward. `held` scales a mesh in the hand only (the traps and
	the pad keep their native `size` for the placed marker). The grip places the mesh only: the placeholder pieces
	sit on the bare RightGripAttachment.

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
export type Item = { mesh: string, size: { number }, held: number?, grip: Grip, pieces: { Piece } }

local PvpModels = {}

PvpModels.MODEL_NAME = "PvpHeld" -- the Model under the character (server/PvpHeld)
PvpModels.ITEM_ATTRIBUTE = "ItemId" -- on that Model: which item it shows
PvpModels.MESH_ATTRIBUTE = "Mesh" -- on that Model: true when it is the uploaded mesh, not the placeholder

local NO_GRIP: Grip = table.freeze({ pos = table.freeze({ 0, 0, 0 }), rotDeg = table.freeze({ 0, 0, 0 }) })
local UPRIGHT = { 0, 0, 0 } -- also every muzzle item: the mesh's -Z is already forward
local PUNCH = { 90, 0, 180 } -- an upright glove (cuff down) turned so the fist points forward, back of the hand up

local function grip(pos: { number }, rotDeg: { number }): Grip
	return { pos = pos, rotDeg = rotDeg }
end

-- The mesh's native size (MeshAssets), else `fallback` for a mesh without a recorded size.
local function sizeOf(mesh: string, fallback: { number }): { number }
	local entry = MeshAssets.get(mesh)
	return if entry and entry.size then entry.size else fallback
end

local WHITE: RGB = { 245, 245, 245 }
local GOO: RGB = { 90, 230, 80 }
local GOO_DARK: RGB = { 50, 170, 60 }
local METAL: RGB = { 120, 125, 140 }
local WOOD: RGB = { 160, 110, 65 }

-- Glove colours per tier: Bonk red, Bounce blue, Boom orange, Thunder yellow, Royal gold with a purple cuff.
-- `hand`: the hand centre inside the cuff, from the mesh's bbox centre.
local GLOVES: { { mitt: RGB, cuff: RGB, hand: { number } } } = {
	{ mitt = { 220, 50, 50 }, cuff = WHITE, hand = { -0.08, -0.51, 0.03 } },
	{ mitt = { 60, 140, 240 }, cuff = WHITE, hand = { -0.08, -0.61, 0.03 } },
	{ mitt = { 255, 130, 30 }, cuff = { 60, 60, 60 }, hand = { 0.15, -0.57, 0.16 } },
	{ mitt = { 255, 220, 40 }, cuff = { 110, 60, 200 }, hand = { 0, -0.73, 0.08 } },
	{ mitt = { 255, 200, 60 }, cuff = { 120, 40, 160 }, hand = { -0.04, -0.81, 0.12 } },
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
	local mesh = `pvp_knock_glove_{tier}`
	return {
		mesh = mesh,
		size = sizeOf(mesh, { 1.6 * s, 1.5 * s, 2.1 * s }),
		grip = grip(c.hand, PUNCH),
		pieces = pieces,
	}
end

local TRAP_HELD = 0.5 -- a trap in the hand is half its placed size
local TRAP_BACK = 1 -- mesh studs: the hand sits this far behind a trap's centre, so the disc rests forward on the palm
local PAD_HELD = 0.6 -- the Bounce Pad in the hand

-- A goo blob held in the palm: a flat puddle disc with a wobbling dome; bigger and darker per tier.
local function trap(tier: number): Item
	local s = 1 + (tier - 1) * 0.15
	local mesh = `pvp_goo_trap_{tier}`
	local size = sizeOf(mesh, { 1.8 * s, 1.1 * s, 1.8 * s })
	return {
		mesh = mesh,
		size = size,
		held = TRAP_HELD,
		grip = grip({ 0, -size[2] / 2, TRAP_BACK }, UPRIGHT),
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
-- `hand`: the palm centre on the (rear) pistol grip, from the mesh's bbox centre.
local BLASTERS: { { body: RGB, hand: { number } } } = {
	{ body = { 80, 200, 255 }, hand = { 0, -0.668, 0.695 } },
	{ body = { 255, 140, 40 }, hand = { 0, -0.845, 1.0 } },
	{ body = { 170, 60, 230 }, hand = { 0, -0.899, 0.922 } },
}
local function blaster(tier: number): Item
	local body = BLASTERS[tier].body
	local barrel = 1.4 + tier * 0.35
	local mesh = `pvp_goo_blaster_{tier}`
	return {
		mesh = mesh,
		size = sizeOf(mesh, { 1, 1.6, 1.2 + barrel }),
		grip = grip(BLASTERS[tier].hand, UPRIGHT),
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

-- Round items rest on the palm: the hand sits under the ball, not inside it (studs below the bbox centre).
local BALLOON_LIFT = -0.6
local DANCE_LIFT = -1.0

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
	-- a party popper held upright by its lower cone
	FunConfetti = {
		mesh = "pvp_fun_confetti",
		size = sizeOf("pvp_fun_confetti", { 0.9, 0.9, 1.6 }),
		grip = grip({ 0.04, -0.53, 0.04 }, UPRIGHT),
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
		size = sizeOf("pvp_fun_balloon", { 1.7, 4.4, 1.7 }),
		grip = grip({ 0, BALLOON_LIFT, 0 }, UPRIGHT),
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
		size = sizeOf("pvp_fun_bubbles", { 1.4, 2.8, 0.4 }),
		grip = grip({ 0.11, -1.21, 0 }, UPRIGHT),
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
	-- a bounce pad carried flat by its rim, reaching forward
	FunBouncePad = {
		mesh = "pvp_fun_bounce_pad",
		size = sizeOf("pvp_fun_bounce_pad", { 1.9, 0.6, 1.9 }),
		held = PAD_HELD,
		grip = grip({ -1.3, 0.28, 0 }, { 0, -90, 0 }),
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
		size = sizeOf("pvp_fun_squeaky", { 1.6, 2.9, 1 }),
		grip = grip({ 0, -0.63, 0 }, UPRIGHT),
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
		size = sizeOf("pvp_fun_hat_launcher", { 1.1, 1.6, 2.4 }),
		grip = grip({ 0, -0.47, 0.87 }, UPRIGHT),
		pieces = {
			{ shape = "Cylinder", axis = "Z", size = { 0.8, 2, 0.8 }, pos = { 0, 0.4, -0.8 }, color = { 90, 90, 110 } },
			{ shape = "Cylinder", size = { 0.65, 0.5, 0.65 }, pos = { 0, 0.95, -1.6 }, color = { 60, 200, 120 } },
			{ shape = "Cylinder", size = { 1, 0.1, 1 }, pos = { 0, 0.7, -1.6 }, color = { 60, 200, 120 } },
		},
	},
	-- a disco ball with a lit fuse
	FunDanceBomb = {
		mesh = "pvp_fun_dance_bomb",
		size = sizeOf("pvp_fun_dance_bomb", { 1.3, 1.8, 1.3 }),
		grip = grip({ 0, DANCE_LIFT, 0 }, UPRIGHT),
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
	-- a goo rocket launcher: muzzle forward, pistol grip
	FunFireworks = {
		mesh = "pvp_fun_fireworks",
		size = sizeOf("pvp_fun_fireworks", { 0.7, 3, 0.7 }),
		grip = grip({ 0, -0.34, 0.51 }, UPRIGHT),
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

-- The grip the held model is welded with (Tool.Grip convention). The uploaded mesh uses the item's grip with `pos`
-- scaled like the mesh (`scale` = its fit scale, default the item's `held`); the placeholder pieces are built around
-- the fist already, so they sit on the bare RightGripAttachment.
function PvpModels.mount(item: Item, mesh: boolean, scale: number?): Grip
	if not mesh then
		return NO_GRIP
	end
	local k = scale or item.held or 1
	local p = item.grip.pos
	return { pos = { p[1] * k, p[2] * k, p[3] * k }, rotDeg = item.grip.rotDeg }
end

function PvpModels.get(id: string?): Item?
	return if id then ITEMS[id] else nil
end

-- The uploaded mesh for item `id`, or nil while it has none (the placeholder pieces are used).
function PvpModels.meshId(id: string?): string?
	local item = PvpModels.get(id)
	return if item then MeshAssets.meshId(item.mesh) else nil
end

local function isMarker(itemId: string?): boolean
	return itemId == "FunBouncePad" or (itemId ~= nil and string.sub(itemId, 1, 7) == "GooTrap")
end

-- Every mesh a placed marker may use (the server publishes these as MeshPart templates).
local markerMeshes: { string } = {}
for id, item in ITEMS do
	if isMarker(id) then
		table.insert(markerMeshes, item.mesh)
	end
end
table.sort(markerMeshes)
PvpModels.MARKER_MESHES = table.freeze(markerMeshes)

-- The mesh a placed Goo Trap / Bounce Pad marker may use (TrapPlaced itemId), nil for other items.
function PvpModels.markerMesh(itemId: string?): string?
	if isMarker(itemId) then
		local item = PvpModels.get(itemId)
		return item and item.mesh
	end
	return nil
end

-- The placeholder pieces a placed Goo Trap / Bounce Pad marker shows while its mesh has no meshId (the same pieces as
-- in the hand), nil for other items.
function PvpModels.markerParts(itemId: string?): { Piece }?
	if isMarker(itemId) then
		local item = PvpModels.get(itemId)
		return item and item.pieces
	end
	return nil
end

return PvpModels
