--!strict
--[[
	Crusher Alley (obby idea 1, docs/obby-variants/1.json; contract/obby-sections.md)

	Red see-through crushers slam down on a beat over the walking path: read the beat, wait in a safe pocket, go when
	it lifts. Touching a crusher sends you back to the start pad (it is a `hazard`).

	This is the reference idea module: copy its shape for a new idea. Each variant is a `build(seed)` returning
	Kit.section(length, rise, parts); hand-made variants ignore the seed. Variants are appended, never reordered (a
	pick stores the index).

	Crusher timing: a crusher is a `punch` on y, its bottom CRUSHER_LIFT above the floor at rest, slamming down to the
	floor. Kit.punchAt keeps it below head height for about 45 % of its period, so the window a runner gets is about
	0.55 x period minus the 0.7 s it takes to walk under it (tests/ObbyCheck measures it exactly). Tuned per §10:
	easy windows 1.4..2.0 s.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local CRUSHER_LIFT = 11 -- studs from the floor to a crusher's bottom at rest: well over a head (5) plus a jump
local CRUSHER_THICK = 4 -- crusher block height
local CRUSHER_LONG = 8 -- along the course: about half a second to walk under
local ENTRY_LONG = 10 -- the entry pad before the jump in
local ENTRY_GAP = 4 -- every variant opens with a jump: a 4-stud hole is too long to walk over (ObbyCheck.walkStop)

-- A crusher `long` x `wide` centred on (x, z) over a floor whose top is `top`, slamming every `period` s.
local function crusher(x: number, z: number, wide: number, top: number, period: number, phase: number): Kit.Part
	local bottom = top + CRUSHER_LIFT
	return Kit.hazard({ CRUSHER_LONG, CRUSHER_THICK, wide }, { x, bottom + CRUSHER_THICK / 2, z }, {
		motion = { kind = "punch", axis = "y", amp = -CRUSHER_LIFT, period = period, phase = phase },
	})
end

-- The entry pad and the jump onto the alley floor that starts at x = ENTRY_LONG + ENTRY_GAP.
local function entry(parts: { Kit.Part })
	table.insert(parts, Kit.slab(ENTRY_LONG / 2, 0, 0, ENTRY_LONG, Kit.WIDTH, "jelly", { tone = 1 }))
end

local FLOOR_FROM = ENTRY_LONG + ENTRY_GAP

local M = {}
M.id = "CrusherAlley"
M.name = "Crusher Alley"
M.idea = 1

M.variants = {
	{
		-- One big crusher over a wide floor: learn the shadow and the wobble. A pocket to land in, then the slam,
		-- then a hop up onto the exit ledge.
		name = "First Slam",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length, rise = 44, 1.5
			local parts = {}
			entry(parts)
			local floorTo = 37 -- the alley floor, then a 2-stud gap up onto the exit ledge
			table.insert(
				parts,
				Kit.slab((FLOOR_FROM + floorTo) / 2, 0, 0, floorTo - FLOOR_FROM, Kit.WIDTH, "goo", { tone = 2 })
			)
			table.insert(parts, crusher(27, 0, Kit.WIDTH, 0, 4, 0))
			local ledge = length - (floorTo + 2)
			table.insert(parts, Kit.slab(length - ledge / 2, rise, 0, ledge, Kit.WIDTH, "jelly", { tone = 3 }))
			return Kit.section(length, rise, parts)
		end,
	},
	{
		-- Three crushers going up and down together with 6-stud pockets between them: wait once, or pocket to pocket.
		name = "Slow Trio",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 60
			local parts = {}
			entry(parts)
			table.insert(
				parts,
				Kit.slab((FLOOR_FROM + length) / 2, 0, 0, length - FLOOR_FROM, Kit.WIDTH, "goo", { tone = 1 })
			)
			local pocket = 6
			local first = FLOOR_FROM + 3 + CRUSHER_LONG / 2 -- a 3-stud landing before the first one
			for i = 0, 2 do
				table.insert(parts, crusher(first + i * (CRUSHER_LONG + pocket), 0, Kit.WIDTH, 0, 4, 0))
			end
			return Kit.section(length, 0, parts)
		end,
	},
	{
		-- Three walled lanes side by side, one crusher each on its own beat: look along the row and take the lane
		-- that is open now (the walls stop you switching halfway).
		name = "Pick a Lane",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local length = 44
			local parts = {}
			entry(parts)
			table.insert(
				parts,
				Kit.slab((FLOOR_FROM + length) / 2, 0, 0, length - FLOOR_FROM, Kit.WIDTH, "goo", { tone = 3 })
			)
			local wallFrom, wallTo = 16, 38
			local split = 4.5 -- the lane walls' centres: an 8-wide middle lane, 7-wide outer lanes
			for _, z in { -split, split } do
				table.insert(parts, Kit.wall((wallFrom + wallTo) / 2, z, wallTo - wallFrom, nil, true, { tone = 2 }))
			end
			local outer = Kit.HALF - split - 0.5
			local x = 27
			-- Faster than the draft (3 / 3.4 / 3.8 s): one lane alone gives 0.7..1.2 s, picking the open lane about 2 s.
			table.insert(parts, crusher(x, -(split + 0.5 + outer / 2), outer, 0, 2.6, 0))
			table.insert(parts, crusher(x, 0, 2 * split - 1, 0, 3, 0.3))
			table.insert(parts, crusher(x, split + 0.5 + outer / 2, outer, 0, 3.4, 0.6))
			return Kit.section(length, 0, parts)
		end,
	},
}

return M
