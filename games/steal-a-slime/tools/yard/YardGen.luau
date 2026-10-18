--!strict
--[[
	YardGen (owner: Archer)

	The seeded generator behind src/visuals/shared/YardProps.luau (the cream sand yard's dressing). Pure Luau
	(no Roblox APIs): `lune run tools/yard/generate` writes the data file, tests/YardDress.spec regenerates it
	in memory and compares, so the committed rows can never drift from the seed and the rules below.

	It hand-places nothing: it builds small CLUSTERS (a stash of hay and crates, a feed corner, a garden, a rest
	spot, a camp, rocks, ...) from templates, scatters them over the sand with one Rng (SEED), and adds a few
	single props. Every piece gets its own yaw jitter, scale (x0.9..1.15 of the kit scale) and a slight tint, so
	no two clusters look alike. A candidate cluster is dropped unless EVERY piece clears:
	  * PropClearance's keep-clear zones with CLEAR (4) studs of air, not its default MARGIN: the ring path /
	    boardwalk, the eight spokes and gate ramps (inside each plot's entrance corridor), the plot fences, the
	    shop / board / NPC spots, the slide, landing band and parade lane;
	  * every other kit prop (RanchProps rows, the plaza showpieces) and every piece placed before it;
	  * the sand yard's edge (r YARD_EDGE), so nothing hangs over the grass band.
	Open sand is kept on purpose: clusters keep GAP studs from each other and a stratum may stay empty.

	Rows are polar like RanchProps (angle, r about the fountain; yaw relative to the angle). Kit fronts face local +Z.
]]

local Config = require("../../src/shared/Config")
local MeshAssets = require("../../src/shared/MeshAssets")
local PropClearance = require("../../src/visuals/shared/PropClearance")
local Ritual = require("../../src/shared/Ritual")
local Rng = require("../../src/shared/Rng")
local WorldLayout = require("../../src/visuals/shared/WorldLayout")

export type Row = {
	name: string,
	mesh: string,
	angle: number,
	r: number,
	yaw: number, -- relative to the angle, like RanchProps
	scale: number,
	tint: { number },
}

export type Patch = {
	name: string,
	kind: string, -- a PATCH_KINDS key
	angle: number,
	r: number,
	radius: number, -- the disc's radius
}

local YardGen = {}

YardGen.SEED = 20261018
YardGen.CLEAR = 4 -- studs of air to every path / spoke / ramp / entrance / fence / spot (>= 4 per the brief)
YardGen.YARD_EDGE = 222 -- footprints stay inside this radius (the sand ends at r 228, the hem at 230.4)
YardGen.GAP = 13 -- min studs between two cluster centres
YardGen.MAX_PROPS = 84 -- with MAX_PATCHES: keeps WorldLayout.PART_BUDGET (1400, build parts 1294 + props + patches) and the soft mesh-slot budget (500)
YardGen.MAX_PATCHES = 12 -- flat ground parts (dark sand, dirt, grass islands): parts, not mesh slots
YardGen.SINGLES_RESERVE = 6 -- clusters stop this many props short of MAX_PROPS so the singles always fit
YardGen.ANCHOR_GAP = 38 -- min studs between two anchor scenes' centres
YardGen.SCALE_JITTER = { 0.9, 1.15 }
YardGen.MESH_CAP = 4 -- most copies of one mesh in the yard (no visible repetition); CAP_OVERRIDE raises it for the common pieces
YardGen.CAP_OVERRIDE = {
	ranch_hay_bale = 9,
	ranch_border_fence_straight = 6,
	ranch_flower_planter = 5,
	ranch_bench = 6,
	ranch_barrel = 5,
	ranch_crate = 4,
	ranch_crate_goo = 3,
	ranch_border_rock_boulder = 3,
	ranch_border_rock_cluster = 3,
	ranch_border_rock_slab = 3,
}
YardGen.MIN_SCALE = 0.5 -- RanchProps' sane-scale floor (tests/RanchProps.spec)
YardGen.SPACING = 1.35 -- cluster template offsets are at kit scale 1; the props stand at ~1.2, so they are spread a little

-- One piece of a cluster: mesh, offset in the cluster frame (x right, z forward, studs at kit scale 1), yaw about
-- the cluster's turn (nil = free), base scale. `face` = turn the front at the plaza (benches, signs).
-- `exact` = an anchor's frame piece (a fence run): no position jitter and only a hair of scale / yaw, so the run still joins up.
type Piece = { mesh: string, x: number, z: number, turn: number?, scale: number, face: boolean?, exact: boolean? }

local function p(mesh: string, x: number, z: number, turn: number?, scale: number, face: boolean?): Piece
	return { mesh = mesh, x = x, z = z, turn = turn, scale = scale, face = face }
end

local function fence(mesh: string, x: number, z: number, turn: number, scale: number): Piece
	return { mesh = mesh, x = x, z = z, turn = turn, scale = scale, exact = true }
end

-- A ground patch under an anchor: a flat disc of `kind` (PATCH_KINDS) at (x, z) in the cluster frame, radius r.
type Patch = { kind: string, x: number, z: number, r: number }

-- Cluster templates. `where`: "wedge" (the gap between two plots), "arc" (the sand behind the plots) or "any".
type Template = {
	name: string,
	where: string, -- "wedge" | "arc" | "any"
	weight: number,
	pieces: { Piece },
	spread: number,
	anchor: boolean?, -- a big scene (placed first, offsets in studs, the front toward the plaza)
	wedge: number?, -- anchors: the gap between two plots (0..7) it stands in, on the sand behind the plots
	angle: number?, -- ... or the bearing it stands at (the sand behind a plot, between the farmyards)
	patches: { Patch }?,
}
local TEMPLATES: { Template } = {
	{
		name = "stash",
		where = "any",
		weight = 3,
		spread = 7,
		pieces = {
			p("ranch_hay_bale", 0, 0, 10, 1.25),
			p("ranch_hay_bale", 5.2, 1, 25, 1.2),
			p("ranch_crate", -3.8, 1.6, 20, 1.25),
			p("ranch_crate_goo", -3.2, -2.4, 40, 1.2),
			p("ranch_barrel", 2.2, -3.6, nil, 1.2),
		},
	},
	{
		name = "feed",
		where = "any",
		weight = 2,
		spread = 7.5,
		pieces = {
			p("ranch_feed_sacks", 0, 0, 20, 1.2),
			p("ranch_feed_sacks", 5.6, 1.4, 35, 1.1),
			p("ranch_wheelbarrow", -5.4, -1.2, 30, 1.2),
			p("ranch_goo_bucket", 2.6, -3.8, nil, 1.2),
		},
	},
	{
		name = "garden",
		where = "any",
		weight = 2,
		spread = 7.5,
		pieces = {
			p("ranch_flower_planter", 0, 0, 6, 1.2),
			p("ranch_flower_planter", 6.6, 0.8, 12, 1.15),
			p("ranch_sunflower_patch", 3.2, -6, nil, 1.1),
			p("ranch_birdhouse", -4.2, -2.2, nil, 1.2),
		},
	},
	{
		name = "pumpkins",
		where = "arc",
		weight = 2,
		spread = 7,
		pieces = {
			p("ranch_pumpkin_patch", 0, 0, nil, 1.3),
			p("ranch_pumpkin_patch", 7.2, 2.4, nil, 0.95),
			p("ranch_hay_bale", -5.4, 1.2, 25, 1.25),
		},
	},
	{
		name = "rest",
		where = "any",
		weight = 2,
		spread = 7,
		pieces = {
			p("ranch_bench", 0, 0, 5, 1.2, true),
			p("ranch_flower_planter", 5.4, 1.2, 10, 1.1),
			p("ranch_rain_barrel", -4.2, 1.4, nil, 1.15),
		},
	},
	{
		name = "rocks",
		where = "any",
		weight = 3,
		spread = 7,
		pieces = {
			p("ranch_border_rock_boulder", 0, 0, nil, 0.58),
			p("ranch_border_rock_cluster", 5.4, 2.2, nil, 0.52),
			p("ranch_border_rock_slab", -4.8, 2.6, nil, 0.52),
		},
	},
	{
		name = "trough",
		where = "any",
		weight = 2,
		spread = 7,
		pieces = {
			p("ranch_water_trough", 0, 0, 8, 1.2),
			p("ranch_hay_bale", -1, 4.4, 20, 1.2),
			p("ranch_goo_bucket", 6.4, 0.6, nil, 1.25),
		},
	},
	{
		name = "logs",
		where = "arc",
		weight = 2,
		spread = 8,
		pieces = {
			p("ranch_log_pile", 0, 0, 12, 1.2),
			p("ranch_barrel_stack", 7.6, 1, nil, 1.2),
			p("ranch_feed_trough", -2.4, -4.6, 15, 1.25),
		},
	},
	{
		name = "camp",
		where = "arc",
		weight = 1,
		spread = 8,
		pieces = {
			p("ranch_campfire", 0, 0, nil, 1.3),
			p("ranch_bench", 5.6, 1.4, nil, 1.2, true),
			p("ranch_bench", -4.6, 3.2, nil, 1.2, true),
			p("ranch_log_pile", -2, -6.6, 10, 1.0),
		},
	},
	{
		name = "rail",
		where = "wedge",
		weight = 2,
		spread = 7,
		pieces = {
			p("ranch_hitching_post", 0, 0, 4, 1.2),
			p("ranch_fence_stile", 6.2, 1.4, 12, 1.2),
			p("ranch_water_trough", -1.8, -4.4, 8, 1.1),
		},
	},
	{
		name = "dairy",
		where = "any",
		weight = 1,
		spread = 6,
		pieces = {
			p("ranch_milk_churn", 0, 0, nil, 1.2),
			p("ranch_milk_churn", 3, 1.4, nil, 1.1),
			p("ranch_goo_hive", -4.2, -1.4, nil, 1.2),
		},
	},
}

-- Anchor scenes: the big features of the outer yard band. Offsets are studs (SPACING does not apply), the cluster frame's +Z
-- faces the plaza, so a paddock opens toward the fountain. The small kit props stand round the big piece, so each reads as
-- a place (a paddock with hay and troughs, a pumpkin patch with its scarecrow), not a scatter.
local ANCHORS: { Template } = {
	{
		name = "windmill",
		where = "wedge",
		wedge = 3,
		weight = 1,
		spread = 16,
		anchor = true,
		pieces = {
			p("ranch_windmill", 0, -5, 0, 1.5),
			p("ranch_wagon", -17, 4, 90, 1.2),
			p("ranch_hay_bale", -9, 8.5, 20, 1.2),
			p("ranch_hay_bale", -4, 11.5, 100, 1.1),
			p("ranch_feed_sacks", 6, 11, 30, 1.15),
			p("ranch_wheelbarrow", 13, 6, 50, 1.1),
		},
		patches = { { kind = "dark", x = -1, z = 3, r = 15 } },
	},
	{
		name = "paddock",
		where = "wedge",
		wedge = 1,
		weight = 1,
		spread = 14,
		anchor = true,
		pieces = {
			fence("ranch_border_fence_straight", 0, -7.5, 0, 0.75),
			fence("ranch_border_fence_straight", -9.5, 1, 90, 0.75),
			fence("ranch_border_fence_straight", 9.5, 1, 90, 0.75),
			p("ranch_hay_bale", -4.5, -3, 10, 1.15),
			p("ranch_feed_trough", 3.5, -3, 10, 1.0),
			p("ranch_water_trough", -1.5, 4.5, 4, 1.0),
			p("ranch_goo_bucket", 6.5, 5, nil, 1.2),
		},
		patches = { { kind = "dirt", x = 0, z = 0, r = 10 } },
	},
	{
		name = "coop paddock",
		where = "wedge",
		wedge = 5,
		weight = 1,
		spread = 14,
		anchor = true,
		pieces = {
			fence("ranch_border_fence_straight", 0, -9, 0, 0.8),
			fence("ranch_border_fence_straight", -10.5, 0, 90, 0.8),
			fence("ranch_border_fence_straight", 10.5, 0, 90, 0.8),
			p("ranch_slime_coop", -3, -3, 4, 1.0),
			p("ranch_feed_sacks", 5, 3, 20, 1.0),
			p("ranch_hitching_post", -2, 6.5, 5, 1.1),
			p("ranch_goo_bucket", 7, 7.5, nil, 1.2),
		},
		patches = { { kind = "dirt", x = 0, z = 0, r = 11 } },
	},
	{
		name = "pumpkin patch",
		where = "wedge",
		wedge = 7,
		weight = 1,
		spread = 14,
		anchor = true,
		pieces = {
			p("ranch_pumpkin_patch", -8, 1, 0, 1.3),
			p("ranch_pumpkin_patch", 5, 2, 0, 1.2),
			p("ranch_pumpkin_patch", -1, 11.5, 0, 1.0),
			p("ranch_scarecrow", -1, -10, 10, 1.3),
			p("ranch_hay_bale", 13, -5, 25, 1.2),
			p("ranch_wheelbarrow", -16, 12, 30, 1.15),
			p("ranch_goo_sign", 12, 9, nil, 0.9, true),
		},
		patches = { { kind = "dirt", x = -1, z = 3, r = 12 } },
	},
	{
		name = "sunflower garden",
		where = "wedge",
		wedge = 2,
		weight = 1,
		spread = 14,
		anchor = true,
		pieces = {
			p("ranch_border_hedge_long", 0, -9, 0, 0.85),
			p("ranch_sunflower_patch", -7, 0, 0, 1.3),
			p("ranch_sunflower_patch", 7, 0.5, 0, 1.25),
			p("ranch_sunflower_patch", 0, 9.5, 0, 1.0),
			p("ranch_bench", -14, 6, 5, 1.2, true),
			p("ranch_flower_planter", 14, 7, 10, 1.15),
			p("ranch_flower_planter", 6, 16, 6, 1.1),
			p("ranch_birdhouse", -16, -3, nil, 1.2),
		},
		patches = { { kind = "grass", x = 0, z = 1, r = 14 } },
	},
	{
		name = "oak grove",
		where = "wedge",
		wedge = 0,
		weight = 1,
		spread = 16,
		anchor = true,
		pieces = {
			p("ranch_border_oak_round", 0, -4, 0, 1.1),
			p("ranch_border_sapling_trio", 15, -2, 40, 0.9),
			p("ranch_picnic_table", -3, 9, 15, 1.2),
			p("ranch_bench", 8, 8, 5, 1.2, true),
			p("ranch_border_rock_boulder", -13, 3, nil, 0.5),
			p("ranch_flower_planter", 9, 13.5, 8, 1.1),
		},
		patches = { { kind = "grass", x = 1, z = 1, r = 15 } },
	},
	{
		name = "pine camp",
		where = "wedge",
		wedge = 4,
		weight = 1,
		spread = 16,
		anchor = true,
		pieces = {
			p("ranch_border_pine_broad", -5, -5, nil, 1.1),
			p("ranch_border_pine_tall", 9, -6, nil, 0.7),
			p("ranch_campfire", 0, 7, nil, 1.3),
			p("ranch_bench", -8, 10.5, nil, 1.2, true),
			p("ranch_bench", 7.5, 11.5, nil, 1.2, true),
			p("ranch_log_pile", -13, 3, 15, 1.1),
			p("ranch_border_rock_cluster", 15, 4, nil, 0.5),
		},
		patches = { { kind = "grass", x = 0, z = 2, r = 15 } },
	},
	{
		name = "well yard",
		where = "wedge",
		angle = 142,
		weight = 1,
		spread = 14,
		anchor = true,
		pieces = {
			p("ranch_well", 0, 0, 0, 1.4),
			p("ranch_water_trough", 13, 2, 10, 1.2),
			p("ranch_milk_churn", -8, 2.5, nil, 1.2),
			p("ranch_milk_churn", -11, -1.5, nil, 1.1),
			p("ranch_goo_hive", -6.5, -7, nil, 1.2),
			p("ranch_goo_bucket", 6.5, 7.5, nil, 1.25),
			p("ranch_bench", 0, 10.5, 5, 1.2, true),
		},
		patches = { { kind = "dark", x = 1, z = 2, r = 13 } },
	},
	{
		name = "rock outcrop",
		where = "wedge",
		angle = 292,
		weight = 1,
		spread = 14,
		anchor = true,
		pieces = {
			p("ranch_border_rock_boulder", 0, -3, nil, 0.8),
			p("ranch_border_rock_boulder", 8, 1, nil, 0.7),
			p("ranch_border_rock_slab", -8, 1.5, nil, 0.6),
			p("ranch_border_sapling_trio", -2, -9, 20, 0.8),
			p("ranch_border_rock_cluster", 4, 8, nil, 0.55),
		},
		patches = { { kind = "dark", x = 0, z = 1, r = 12 } },
	},
}

-- Single props (a signpost here, a rain barrel there).
local SINGLES: { { mesh: string, scale: number, face: boolean? } } = {
	{ mesh = "ranch_goo_sign", scale = 1.1, face = true },
	{ mesh = "ranch_goo_sign", scale = 1.0, face = true },
	{ mesh = "ranch_horseshoe_pit", scale = 1.2 },
	{ mesh = "ranch_barrel_stack", scale = 1.2 },
	{ mesh = "ranch_rain_barrel", scale = 1.2 },
	{ mesh = "ranch_compost_bin", scale = 1.2 },
	{ mesh = "ranch_water_pump", scale = 1.2 },
	{ mesh = "ranch_weathervane", scale = 1.1 },
	{ mesh = "ranch_tool_rack", scale = 1.1, face = true },
	{ mesh = "ranch_picnic_table", scale = 1.2 },
	{ mesh = "ranch_scarecrow", scale = 1.2 },
	{ mesh = "ranch_wagon", scale = 1.2 },
}

local function wrap(deg: number): number
	return deg % 360
end

local function round2(x: number): number
	return math.floor(x * 100 + 0.5) / 100
end

local function meshSize(mesh: string, scale: number): { number }
	local native = (MeshAssets.get(mesh) :: any).size :: { number }
	return { native[1] * scale, native[2] * scale, native[3] * scale }
end

-- A slight tint: the slot colour multiplies the mesh's vertex colours (MeshTint), so near white = the kit's look.
local function tintOf(rng: Rng.Rng): { number }
	local k = 1 - 0.1 * rng:float()
	local function channel(v: number): number
		return math.clamp(math.floor(255 * v + 0.5), 0, 255)
	end
	return {
		channel(k + 0.025 * (rng:float() - 0.5)),
		channel(k + 0.025 * (rng:float() - 0.5)),
		channel(k - 0.04 * rng:float()),
	}
end

-- World pos (x, z) and world yaw of a polar row.
local function worldOf(row: { angle: number, r: number, yaw: number }): (number, number, number)
	local a = math.rad(row.angle)
	return math.sin(a) * row.r, math.cos(a) * row.r, wrap(row.angle + row.yaw)
end

local function propOf(row: Row): { pos: { number }, size: { number }, yaw: number }
	local x, z, yaw = worldOf(row)
	local size = meshSize(row.mesh, row.scale)
	return { pos = { x, size[2] / 2, z }, size = size, yaw = yaw }
end

-- The fixed obstacles' footprints: every non-yard kit prop (RanchProps rows, resolved by WorldLayout).
local function fixedProps(): { { pos: { number }, size: { number }, yaw: number } }
	local out = {}
	for _, prop in WorldLayout.RANCH_PROPS do
		if prop.cluster ~= "yard" then
			table.insert(out, prop)
		end
	end
	-- the plaza ritual circle (Ritual.centre), with a margin: it sits on the lawn band, where the singles like to stand
	local rx, rz = Ritual.centre()
	local reach = 2 * (Config.RITUAL.CIRCLE_RADIUS + 5)
	table.insert(out, { pos = { rx, 1, rz }, size = { reach, 2, reach }, yaw = 0 })
	return out
end

-- Meshes whose footprint is a canopy (trees, hedges): the small props of their scene may stand under it.
function YardGen.isCanopy(mesh: string): boolean
	return string.find(mesh, "^ranch_border_oak") ~= nil
		or string.find(mesh, "^ranch_border_pine") ~= nil
		or string.find(mesh, "^ranch_border_sapling") ~= nil
end

-- True if `prop` keeps CLEAR studs from every keep-clear zone, the yard edge and the world's other kit props.
function YardGen.fits(prop: { pos: { number }, size: { number }, yaw: number }, others: { any }, pad: number): boolean
	local grow = 2 * (YardGen.CLEAR - PropClearance.MARGIN)
	local fat = { pos = prop.pos, size = { prop.size[1] + grow, prop.size[2], prop.size[3] + grow }, yaw = prop.yaw }
	if #PropClearance.conflicts(fat) > 0 then
		return false
	end
	local reach = math.sqrt(prop.pos[1] ^ 2 + prop.pos[3] ^ 2) + math.sqrt(prop.size[1] ^ 2 + prop.size[3] ^ 2) / 2
	if reach > YardGen.YARD_EDGE then
		return false
	end
	local rect = PropClearance.footprint(prop)
	for _, o in others do
		if PropClearance.rectsOverlap(PropClearance.footprint(o), rect, pad) then
			return false
		end
	end
	return true
end

local function polarOf(x: number, z: number): (number, number)
	return math.deg(math.atan2(x, z)) % 360, math.sqrt(x * x + z * z)
end

function YardGen.generate(): ({ Row }, { Patch })
	local rng = Rng.new(YardGen.SEED)
	local rows: { Row } = {}
	local patches: { Patch } = {}
	local fixed = fixedProps()
	local placedProps: { any } = {}
	local centres: { { number } } = {}
	local counter: { [string]: number } = {}
	local used: { [string]: number } = {}

	local function nameFor(mesh: string): string
		local short = string.gsub(string.gsub(mesh, "^ranch_", ""), "^border_", "") :: string
		counter[short] = (counter[short] or 0) + 1
		return `Yard_{short}_{counter[short]}`
	end

	local function pickTemplate(where: string): Template
		local pool, total = {}, 0
		for _, t in TEMPLATES do
			if t.where == "any" or t.where == where then
				table.insert(pool, t)
				total += t.weight
			end
		end
		local roll = rng:float() * total
		for _, t in pool do
			roll -= t.weight
			if roll <= 0 then
				return t
			end
		end
		return pool[#pool]
	end

	-- True if a ground disc (x, z, radius) keeps CLEAR studs from every keep-clear zone and does not overlap another patch.
	local function patchFits(x: number, z: number, radius: number): boolean
		local box = {
			pos = { x, 0, z },
			size = {
				2 * radius + 2 * (YardGen.CLEAR - PropClearance.MARGIN),
				1,
				2 * radius + 2 * (YardGen.CLEAR - PropClearance.MARGIN),
			},
			yaw = 0,
		}
		if #PropClearance.conflicts(box) > 0 or math.sqrt(x * x + z * z) + radius > YardGen.YARD_EDGE then
			return false
		end
		for _, q in patches do
			local qa = math.rad(q.angle)
			local d2 = (math.sin(qa) * q.r - x) ^ 2 + (math.cos(qa) * q.r - z) ^ 2
			if d2 < (q.radius + radius + 1) ^ 2 then
				return false
			end
		end
		return true
	end

	-- A cluster at world (cx, cz): returns its rows (and the ground discs of an anchor) when every piece fits, else nil.
	-- `faceTurn` turns the cluster so its +Z faces the plaza (anchors); `gap` is the min distance to another cluster's centre.
	local function tryCluster(
		t: Template,
		cx: number,
		cz: number,
		gap: number?,
		faceTurn: boolean?
	): ({ Row }?, { any }?)
		for _, c in centres do
			if (c[1] - cx) ^ 2 + (c[2] - cz) ^ 2 < (gap or YardGen.GAP) ^ 2 then
				return nil
			end
		end
		local turn = rng:float() * 360 -- the cluster's own orientation
		if faceTurn then
			turn = wrap(math.deg(math.atan2(cx, cz)) + 180 + (rng:float() - 0.5) * 50)
		end
		local ct, st = math.cos(math.rad(turn)), math.sin(math.rad(turn))
		local mirror = if rng:float() < 0.5 then -1 else 1 -- no two clusters read as copies
		local out: { Row } = {}
		local mine: { any } = {}
		local extra: { [string]: number } = {}
		for _, piece in t.pieces do
			local n = (used[piece.mesh] or 0) + (extra[piece.mesh] or 0) + 1
			if n > (YardGen.CAP_OVERRIDE[piece.mesh] or YardGen.MESH_CAP) then
				return nil
			end
			extra[piece.mesh] = (extra[piece.mesh] or 0) + 1
			local spacing = if t.anchor then 1 else YardGen.SPACING
			local wobble = if t.anchor then 0.5 else 1.2
			if piece.exact then
				wobble = 0
			end
			local ox = (piece.x * spacing + (rng:float() - 0.5) * wobble) * mirror
			local oz = piece.z * spacing + (rng:float() - 0.5) * wobble
			local x, z = cx + ox * ct + oz * st, cz - ox * st + oz * ct
			local lo, hi = YardGen.SCALE_JITTER[1], YardGen.SCALE_JITTER[2]
			if piece.exact then
				lo, hi = 0.96, 1.04
			end
			local jitter = lo + rng:float() * (hi - lo)
			local scale = math.max(YardGen.MIN_SCALE, piece.scale * jitter)
			local angle, r = polarOf(x, z)
			local yaw: number
			if piece.face then
				-- front at the fountain (yaw = angle + 180), a little off
				yaw = 180 + (rng:float() - 0.5) * 40
			elseif piece.turn then
				local spin = if piece.exact then 4 else 24
				yaw = wrap(turn + piece.turn * mirror + (rng:float() - 0.5) * spin - angle)
			else
				yaw = rng:float() * 360
			end
			local row: Row = {
				name = "", -- numbered when the cluster is committed
				mesh = piece.mesh,
				angle = round2(angle),
				r = round2(r),
				yaw = round2(yaw),
				scale = round2(scale),
				tint = tintOf(rng),
			}
			local prop = propOf(row)
			if not YardGen.fits(prop, fixed, 1) or not YardGen.fits(prop, placedProps, 0.8) then
				if t.anchor and _G.DBG then
					local grow = 2 * (YardGen.CLEAR - PropClearance.MARGIN)
					local fat = {
						pos = prop.pos,
						size = { prop.size[1] + grow, prop.size[2], prop.size[3] + grow },
						yaw = prop.yaw,
					}
					local zone = table.concat(PropClearance.conflicts(fat), "/")
					local reach = math.sqrt(prop.pos[1] ^ 2 + prop.pos[3] ^ 2)
						+ math.sqrt(prop.size[1] ^ 2 + prop.size[3] ^ 2) / 2
					local f1, f2 = false, false
					for _, o in fixed do
						if PropClearance.rectsOverlap(PropClearance.footprint(o), PropClearance.footprint(prop), 1) then
							f1 = o.name
						end
					end
					for _, o in placedProps do
						if
							PropClearance.rectsOverlap(PropClearance.footprint(o), PropClearance.footprint(prop), 0.8)
						then
							f2 = true
						end
					end
					print(
						"FIT",
						t.name,
						piece.mesh,
						"zone=" .. zone,
						"edge=" .. tostring(reach > 222),
						"fixed=" .. tostring(f1),
						"placed=" .. tostring(f2),
						math.floor(r),
						math.floor(angle)
					)
				end
				return nil
			end
			for i, m in mine do
				-- a tree's footprint is its canopy: a bench or a table may stand under it (only the trunk is solid, and trees are decor)
				local shaded = YardGen.isCanopy(out[i].mesh) or YardGen.isCanopy(piece.mesh)
				if string.find(out[i].mesh, "fence") and string.find(piece.mesh, "fence") then
					shaded = true -- the run's corners join
				end
				if
					not shaded
					and PropClearance.rectsOverlap(PropClearance.footprint(m), PropClearance.footprint(prop), 0.8)
				then
					if _G.DBG then
						print("OVL", t.name, piece.mesh, out[i].mesh)
					end
					return nil
				end
			end
			-- no two copies of a mesh alike (tests/YardDress.spec; a fence run is one design, so fences are exempt): another yaw or scale, else try again
			for _, list in { rows, out } do
				for _, other in list do
					if other.mesh == row.mesh and not string.find(row.mesh, "fence") then
						local _, _, otherYaw = worldOf(other)
						local dyaw = math.abs(otherYaw - prop.yaw)
						dyaw = math.min(dyaw, 360 - dyaw)
						if dyaw <= 1.5 and math.abs(other.scale - row.scale) <= 0.03 then
							return nil
						end
					end
				end
			end
			table.insert(out, row)
			table.insert(mine, prop)
		end
		local discs = {}
		for _, patch in t.patches or {} do
			local x = cx + patch.x * mirror * ct + patch.z * st
			local z = cz - patch.x * mirror * st + patch.z * ct
			if #patches + #discs < YardGen.MAX_PATCHES and patchFits(x, z, patch.r) then
				local angle, r = polarOf(x, z)
				table.insert(discs, { kind = patch.kind, angle = round2(angle), r = round2(r), radius = patch.r })
			end
		end
		return out, discs
	end

	local function commit(cluster: { Row }, cx: number, cz: number, discs: { any }?)
		for _, d in discs or {} do
			table.insert(patches, {
				name = `Yard_patch_{d.kind}_{#patches + 1}`,
				kind = d.kind,
				angle = d.angle,
				r = d.r,
				radius = d.radius,
			})
		end
		for _, row in cluster do
			used[row.mesh] = (used[row.mesh] or 0) + 1
			row.name = nameFor(row.mesh)
			table.insert(rows, row)
			table.insert(placedProps, propOf(row))
		end
		table.insert(centres, { cx, cz })
	end

	-- 0. the anchor scenes: the big features of the outer band, each in its own gap between two plots (the farmyards already
	-- stand behind the plots), placed before any small cluster.
	for k, template in ANCHORS do
		local placed = false
		local bisector = template.angle or 360 / 8 * ((template.wedge :: number) + 0.5)
		for attempt = 1, 900 do
			-- the gap between two plots is narrow (36..65 studs at r 160..196): first the bisector, then the whole gap, then anywhere
			local half = if attempt <= 250 then 6 elseif attempt <= 550 then 13 elseif attempt <= 750 then 22 else 180
			local a = bisector + (rng:float() * 2 - 1) * half
			local r = 176 + rng:float() * 26
			local cx, cz = math.sin(math.rad(a)) * r, math.cos(math.rad(a)) * r
			local cluster, discs = tryCluster(template, cx, cz, YardGen.ANCHOR_GAP, true)
			if cluster then
				commit(cluster, cx, cz, discs)
				placed = true
				break
			end
		end
		if not placed then
			print(`anchor {template.name} found no place`)
		end
	end

	-- 1. the gap between each pair of plots: one or two clusters on the bisector, where it is wide enough.
	local step = 360 / 8
	for k = 0, 7 do
		local bisector = step * k + step / 2
		local wanted = 2
		local got = 0
		for _ = 1, 160 do
			if got >= wanted or #rows >= YardGen.MAX_PROPS - YardGen.SINGLES_RESERVE then
				break
			end
			local r = 118 + rng:float() * 66
			local a = bisector + (rng:float() - 0.5) * 6
			local cx, cz = math.sin(math.rad(a)) * r, math.cos(math.rad(a)) * r
			local cluster, discs = tryCluster(pickTemplate("wedge"), cx, cz)
			if cluster then
				commit(cluster, cx, cz, discs)
				got += 1
			end
		end
	end

	-- 2. the sand behind the plots: strata of 20 degrees round the ring, some left empty (open sand).
	local strata = 18
	for s = 0, strata - 1 do
		if rng:float() < 0.8 and #rows < YardGen.MAX_PROPS - YardGen.SINGLES_RESERVE then
			for _ = 1, 100 do
				local a = (s + rng:float()) * 360 / strata
				local r = 204 + rng:float() * 10
				local cx, cz = math.sin(math.rad(a)) * r, math.cos(math.rad(a)) * r
				local cluster, discs = tryCluster(pickTemplate("arc"), cx, cz)
				if cluster then
					commit(cluster, cx, cz, discs)
					break
				end
			end
		end
	end

	-- 3. single props, spread over the wedges, the arc and the lawns' edge (r 88..98 between the spokes).
	for i, single in SINGLES do
		for _ = 1, 200 do
			local a, r
			if i % 3 == 0 then
				a, r = rng:float() * 360, 93 + rng:float() * 6 -- the lawn band between the ring path and the fences
			else
				a, r = rng:float() * 360, 125 + rng:float() * 90
			end
			local cx, cz = math.sin(math.rad(a)) * r, math.cos(math.rad(a)) * r
			local ok = true
			for _, c in centres do
				if (c[1] - cx) ^ 2 + (c[2] - cz) ^ 2 < (YardGen.GAP - 3) ^ 2 then
					ok = false
					break
				end
			end
			if ok and #rows < YardGen.MAX_PROPS then
				local one: Template = {
					name = "single",
					where = "any",
					weight = 1,
					spread = 0,
					pieces = {
						{ mesh = single.mesh, x = 0, z = 0, turn = nil, scale = single.scale, face = single.face },
					},
				}
				local cluster = tryCluster(one, cx, cz)
				if cluster then
					commit(cluster, cx, cz)
					break
				end
			end
		end
	end

	-- 4. a few loose ground patches (darker sand, a grass island) away from the anchors, so the open sand is not one flat colour.
	local loose = { "dark", "grass", "dark", "dirt" }
	for _, kind in loose do
		for _ = 1, 200 do
			if #patches >= YardGen.MAX_PATCHES then
				break
			end
			local radius = 6 + rng:float() * 4
			local a, r = rng:float() * 360, 112 + rng:float() * 100
			local x, z = math.sin(math.rad(a)) * r, math.cos(math.rad(a)) * r
			local near = false
			for _, c in centres do
				if (c[1] - x) ^ 2 + (c[2] - z) ^ 2 < (radius + 4) ^ 2 then
					near = true
					break
				end
			end
			if not near and patchFits(x, z, radius) then
				table.insert(patches, {
					name = `Yard_patch_{kind}_{#patches + 1}`,
					kind = kind,
					angle = round2(a),
					r = round2(r),
					radius = round2(radius),
				})
				break
			end
		end
	end

	return rows, patches
end

return YardGen
