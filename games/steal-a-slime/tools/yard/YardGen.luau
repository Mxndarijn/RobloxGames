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

local MeshAssets = require("../../src/shared/MeshAssets")
local PropClearance = require("../../src/visuals/shared/PropClearance")
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

local YardGen = {}

YardGen.SEED = 20261018
YardGen.CLEAR = 4 -- studs of air to every path / spoke / ramp / entrance / fence / spot (>= 4 per the brief)
YardGen.YARD_EDGE = 222 -- footprints stay inside this radius (the sand ends at r 228, the hem at 230.4)
YardGen.GAP = 13 -- min studs between two cluster centres
YardGen.MAX_PROPS = 72 -- keeps WorldLayout.PART_BUDGET (1400) and the soft mesh-slot budget (500) with headroom for others
YardGen.SINGLES_RESERVE = 12 -- clusters stop this many props short of MAX_PROPS so the singles always fit
YardGen.SCALE_JITTER = { 0.9, 1.15 }
YardGen.MESH_CAP = 4 -- most copies of one mesh in the yard (no visible repetition); CAP_OVERRIDE raises it for the common pieces
YardGen.CAP_OVERRIDE = {
	ranch_hay_bale = 6,
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
type Piece = { mesh: string, x: number, z: number, turn: number?, scale: number, face: boolean? }

local function p(mesh: string, x: number, z: number, turn: number?, scale: number, face: boolean?): Piece
	return { mesh = mesh, x = x, z = z, turn = turn, scale = scale, face = face }
end

-- Cluster templates. `where`: "wedge" (the gap between two plots), "arc" (the sand behind the plots) or "any".
type Template = { name: string, where: string, weight: number, pieces: { Piece }, spread: number }
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
	return out
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

function YardGen.generate(): { Row }
	local rng = Rng.new(YardGen.SEED)
	local rows: { Row } = {}
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

	-- A cluster at world (cx, cz): returns its rows when every piece fits, else nil.
	local function tryCluster(t: Template, cx: number, cz: number): { Row }?
		for _, c in centres do
			if (c[1] - cx) ^ 2 + (c[2] - cz) ^ 2 < YardGen.GAP ^ 2 then
				return nil
			end
		end
		local turn = rng:float() * 360 -- the cluster's own orientation
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
			local ox = (piece.x * YardGen.SPACING + (rng:float() - 0.5) * 1.2) * mirror
			local oz = piece.z * YardGen.SPACING + (rng:float() - 0.5) * 1.2
			local x, z = cx + ox * ct + oz * st, cz - ox * st + oz * ct
			local jitter = YardGen.SCALE_JITTER[1] + rng:float() * (YardGen.SCALE_JITTER[2] - YardGen.SCALE_JITTER[1])
			local scale = math.max(YardGen.MIN_SCALE, piece.scale * jitter)
			local angle, r = polarOf(x, z)
			local yaw: number
			if piece.face then
				-- front at the fountain (yaw = angle + 180), a little off
				yaw = 180 + (rng:float() - 0.5) * 40
			elseif piece.turn then
				yaw = wrap(turn + piece.turn * mirror + (rng:float() - 0.5) * 24 - angle)
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
				return nil
			end
			for _, m in mine do
				if PropClearance.rectsOverlap(PropClearance.footprint(m), PropClearance.footprint(prop), 0.8) then
					return nil
				end
			end
			table.insert(out, row)
			table.insert(mine, prop)
		end
		return out
	end

	local function commit(cluster: { Row }, cx: number, cz: number)
		for _, row in cluster do
			used[row.mesh] = (used[row.mesh] or 0) + 1
			row.name = nameFor(row.mesh)
			table.insert(rows, row)
			table.insert(placedProps, propOf(row))
		end
		table.insert(centres, { cx, cz })
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
			local cluster = tryCluster(pickTemplate("wedge"), cx, cz)
			if cluster then
				commit(cluster, cx, cz)
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
				local cluster = tryCluster(pickTemplate("arc"), cx, cz)
				if cluster then
					commit(cluster, cx, cz)
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
				a, r = rng:float() * 360, 89 + rng:float() * 7 -- the lawn band between the ring path and the fences
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

	return rows
end

return YardGen
