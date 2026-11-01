--!strict
--[[
	Key Run (obby idea 20, docs/obby-variants/20.json; contract/obby-sections.md)

	A locked purple gate stands across the lane near the end, with one lock icon per key it needs. Gold keys float on
	islands, ledges and rides off the straight path: fetch them, the locks fill, the gate fades open. Falling or
	touching red goo puts you back on the start pad and every key back where it was (ObbyFx clears keys on a reset).

	Numbers against the checks (tests/ObbyCheck):
	* Every hole on the main path is at least 5 studs (a walker steps over same-height holes up to about 4.4), so
	  holding forward never even reaches the gate, and the path past it needs a jump too: the gate is the second
	  lock, not the only one (tests/obby/KeyRun.spec takes the gates away and walks again).
	* A gate is GATE_HIGH tall (over a 7.2-stud jump) and spans the whole lane, or reaches 2 studs past its floor's
	  edge into the air where the lane goes on beside it, so you can't jump over or round it, not even off a +3
	  ledge just before it.
	* Islands that only hold keys are `route = "key"` steps: the checks reach each one from the path and back.
	* With an 8-wide path, an 8-wide island and a 4-stud gap only fit on one side of the 24-stud lane, so the path
	  hugs one edge (or weaves: Scatter's map) and the islands sit on the other.
	* Timing (contract §10): crushers (a red goo block slamming down, as Crusher Alley) over path pads give windows
	  that tests/ObbyCheck measures: easy 1.4..2.0 s, medium 1.0..1.4 s, hard 0.75..1.0 s.

	Kit gaps, simplified (listed in the KeyRun summary): a countdown that resets the keys (here a goo flood rises on
	the first key's clock, and touching it resets you), keys that only glow when they are next (here a locked cage
	round each later key that opens on the key count), a clock face on the gate.

	Variants are appended, never reordered (a pick stores the index). Hand-made variants ignore the seed; Scatter's
	map is M.generator, and the four Scatter variants are fixed spot picks on that map.
]]

local Kit = if script then require(script.Parent.Kit) else require("./Kit")

local KEY = "k" -- the key group every variant uses
local KEY_SIZE = 1.5
local KEY_UP = 2.5 -- a key's centre over the floor top: chest height
local GATE_HIGH = 11 -- over a 7.2-stud jump from a +3 ledge
local CRUSHER_LIFT = 11 -- a crusher's bottom over its floor at rest (as Crusher Alley)
local CRUSHER_THICK = 4
local CRUSHER_LONG = 6
local POST = 2 -- a still goo post's footprint
local POST_HIGH = 6 -- taller than a hop

-- Crusher periods per tier (s), tightened to one step short of failing the windows (tests/ObbyCheck measures):
-- easy about 1.5 s, medium 1.0 s, hard 0.75 s.
local CRUSH = { easy = 3.6, medium = 2.7, hard = 2.2 }
-- Scatter's hub crusher: its crossing has a jump on each side, so it runs a little slower.
-- Hazard Guard's ring doors: open just over 1 s past the walk through (tests/obby/KeyRun.spec).
local DOOR = 2.3
local HUB_CRUSH = { easy = 4.0, medium = 3.3, hard = 2.8 }

-- The first floor every variant starts on, full lane width.
local ENTRY_LONG = 10

local function merge(base: { [string]: any }, extra: { [string]: any }?): { [string]: any }
	for k, v in (extra or {}) :: { [string]: any } do
		base[k] = v
	end
	return base
end

-- A floor from x0 to x1 and z0 to z1 with its top at `top`.
local function pad(
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	top: number,
	tone: number?,
	extra: { [string]: any }?
): Kit.Part
	return Kit.slab((x0 + x1) / 2, top, (z0 + z1) / 2, x1 - x0, z1 - z0, "jelly", merge({ tone = tone or 1 }, extra))
end

-- A solid block from `base` up to `top` (stairs, ledges on pillars): a step on its top.
local function pillar(
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	top: number,
	base: number,
	tone: number?,
	extra: { [string]: any }?
): Kit.Part
	local part = pad(x0, x1, z0, z1, top, tone, extra)
	part.size = { x1 - x0, top - base, z1 - z0 }
	part.pos = { (x0 + x1) / 2, (top + base) / 2, (z0 + z1) / 2 }
	return part
end

local function entry(): Kit.Part
	return pad(0, ENTRY_LONG, -Kit.HALF, Kit.HALF, 0, 3)
end

-- A gold key floating over a floor top at (x, z).
local function key(x: number, top: number, z: number, extra: { [string]: any }?): Kit.Part
	return Kit.prop(
		{ KEY_SIZE, KEY_SIZE, KEY_SIZE },
		{ x, top + KEY_UP, z },
		"key",
		merge({ key = KEY, ghost = true }, extra)
	)
end

-- The locked gate: a wall at x on a floor top, from z0 to z1 (default the whole lane), open with `need` keys.
local function gate(x: number, top: number, need: number, z0: number?, z1: number?, marker: string?): Kit.Part
	local a, b = z0 or -Kit.HALF, z1 or Kit.HALF
	return Kit.prop(
		{ 1, GATE_HIGH, b - a },
		{ x, top + GATE_HIGH / 2, (a + b) / 2 },
		"gate",
		{ gate = { group = KEY, need = need }, marker = marker }
	)
end

-- A cage round a key (the next-key-glows stand-in): a gate box that opens once you hold `need` keys.
local function cage(x: number, top: number, z: number, need: number): Kit.Part
	local s = 6 -- a limb outside it stays over ObbyFx.KEY_PAD (1.5) from the key inside
	return Kit.prop({ s, s, s }, { x, top + s / 2, z }, "gate", { gate = { group = KEY, need = need } })
end

-- A still red goo post standing on a floor top.
local function post(x: number, z: number, top: number, high: number?): Kit.Part
	local h = high or POST_HIGH
	return Kit.hazard({ POST, h, POST }, { x, top + h / 2, z })
end

-- A crusher `wide` across centred on (x, z) over a floor top, slamming every `period` s.
local function crusher(x: number, z: number, wide: number, top: number, period: number, phase: number?): Kit.Part
	local bottom = top + CRUSHER_LIFT
	return Kit.hazard({ CRUSHER_LONG, CRUSHER_THICK, wide }, { x, bottom + CRUSHER_THICK / 2, z }, {
		motion = { kind = "punch", axis = "y", amp = -CRUSHER_LIFT, period = period, phase = phase or 0 },
	})
end

local function island(x0: number, z0: number, top: number?, tone: number?, extra: { [string]: any }?): Kit.Part
	return pad(x0, x0 + 8, z0, z0 + 8, top or 0, tone or 2, merge({ route = "key" }, extra))
end

---------------------------------------------------------------------------
-- Scatter: one fixed map of 8 tested island spots, the seed picks which hold keys
---------------------------------------------------------------------------

--[[
	The map (110 long): the entry, a path on the left (z -12..-4) with four spots on the right, a full-width hub with a
	crusher, a path on the right (z 4..12) with four spots on the left, then the gate pad. Near spots sit 4 studs off
	the path, far spots 5.5. Each row of spots runs on like a path, so the holes between entry, rows, hub and gate pad
	are 5 studs: no walker crosses them. Every spot is built (empty ones are decoys); the keys go on the picked ones.
]]
local MAP_LENGTH = 110
local SPOTS = table.freeze({
	{ x = 12, side = 1, far = false }, -- R1
	{ x = 21, side = 1, far = true }, -- R2
	{ x = 30, side = 1, far = false }, -- R3
	{ x = 39, side = 1, far = true }, -- R4
	{ x = 65, side = -1, far = true }, -- L1
	{ x = 74, side = -1, far = false }, -- L2
	{ x = 83, side = -1, far = true }, -- L3
	{ x = 92, side = -1, far = false }, -- L4
})
local NEAR = { 1, 3, 6, 8 }
local FAR = { 2, 4, 5, 7 }

-- A drifting key: on its group's clock it floats up 14 studs over 7 s (out of reach after about 5), then sinks back.
local function drift(): Kit.Motion
	return { kind = "path", points = { { 0, 0, 0 }, { 0, 14, 0 } }, hold = 1, period = 16 }
end

local function spotZ(spot: { x: number, side: number, far: boolean }): number
	local off = if spot.far then 1.5 else 0
	return if spot.side > 0 then 0 + off else -8 - off
end

-- The map with keys on `picked` spots (indices into SPOTS); `drifting` (one of them) floats off after the first grab.
local function scatter(picked: { number }, drifting: number?, tier: string): Kit.Section
	local parts: { Kit.Part } = {}
	table.insert(parts, pad(0, 7, -Kit.HALF, Kit.HALF, 0, 3))
	table.insert(parts, pad(12, 47, -12, -4, 0, 1))
	local has: { [number]: boolean } = {}
	for _, i in picked do
		has[i] = true
	end
	local keys: { Kit.Part } = {}
	local function spot(i: number)
		local s = SPOTS[i]
		local z0 = spotZ(s)
		table.insert(parts, island(s.x, z0, 0, if s.far then 3 else 2))
		if has[i] then
			local k = key(s.x + 4, 0, z0 + 4)
			if i == drifting then
				k.motion = drift()
				k.start = "drift"
			elseif drifting then
				k.trigger = "drift"
			end
			table.insert(keys, k)
		end
	end
	for i = 1, 4 do
		spot(i)
	end
	table.insert(parts, pad(52, 60, -Kit.HALF, Kit.HALF, 0, 3))
	table.insert(parts, pad(65, 100, 4, 12, 0, 1))
	for i = 5, 8 do
		spot(i)
	end
	table.insert(parts, pad(105, MAP_LENGTH, -Kit.HALF, Kit.HALF, 0, 3))
	table.insert(parts, crusher(56, 0, Kit.WIDTH, 0, HUB_CRUSH[tier] or HUB_CRUSH.medium))
	-- Medium adds a crusher on the left path, hard one on each path (out of step with the hub).
	if tier ~= "easy" then
		table.insert(parts, crusher(34, -8, 8, 0, CRUSH[tier] or CRUSH.medium, 0.5))
	end
	if tier == "hard" then
		table.insert(parts, crusher(78, 8, 8, 0, CRUSH.hard, 0.25))
	end
	table.insert(parts, gate(107.5, 0, #picked))
	for _, k in keys do
		table.insert(parts, k)
	end
	return Kit.section(MAP_LENGTH, 0, parts)
end

-- `n` distinct entries of `list` in a seeded order.
local function draw(rng: any, list: { number }, n: number): { number }
	local pool = table.clone(list)
	local out = {}
	for _ = 1, math.min(n, #pool) do
		table.insert(out, table.remove(pool, rng:int(1, #pool)) :: number)
	end
	return out
end

-- Easy: 2 or 3 keys on near spots. Medium: 3 anywhere, one may drift. Hard: 4 with at least 2 far, one may drift.
local function generate(seed: number, tier: string): Kit.Section
	local rng = Kit.rng(seed)
	local picked: { number }
	if tier == "easy" then
		picked = draw(rng, NEAR, rng:int(2, 3))
	elseif tier == "hard" then
		picked = draw(rng, FAR, 2)
		local rest = {}
		for i = 1, #SPOTS do
			if not table.find(picked, i) then
				table.insert(rest, i)
			end
		end
		for _, i in draw(rng, rest, 2) do
			table.insert(picked, i)
		end
	else
		picked = draw(rng, { 1, 2, 3, 4, 5, 6, 7, 8 }, 3)
	end
	table.sort(picked)
	local drifting = nil
	if tier ~= "easy" and rng:float() < 0.5 then
		drifting = picked[rng:int(1, #picked)]
	end
	return scatter(picked, drifting, tier)
end

---------------------------------------------------------------------------
-- Hand-made variants
---------------------------------------------------------------------------

-- Three walls of a goo ring 10 across centred on (cx, cz), plus the open side as two 3-stud stubs and a door that
-- slams down over the 4-stud opening. `open` is the side: "-x", "+x", "-z" or "+z".
local RING = 10
local RING_HIGH = 8
local function ring(parts: { Kit.Part }, cx: number, cz: number, open: string, period: number, phase: number)
	local h = RING_HIGH
	local half = RING / 2 - 0.5
	for _, side in { "-x", "+x", "-z", "+z" } do
		local alongZ = side == "-x" or side == "+x"
		local sign = if side == "-x" or side == "-z" then -1 else 1
		local wx = if alongZ then cx + sign * half else cx
		local wz = if alongZ then cz else cz + sign * half
		if side ~= open then
			local size = if alongZ then { 1, h, RING } else { RING, h, 1 }
			table.insert(parts, Kit.hazard(size, { wx, h / 2, wz }))
		else
			for _, s in { -1, 1 } do
				local o = s * 3.5
				local size = if alongZ then { 1, h, 3 } else { 3, h, 1 }
				local pos = if alongZ then { wx, h / 2, wz + o } else { wx + o, h / 2, wz }
				table.insert(parts, Kit.hazard(size, pos))
			end
			-- The door is as tall as the ring, so it shuts the whole opening when it is down.
			local size = if alongZ then { 2, h, 4 } else { 4, h, 2 }
			table.insert(
				parts,
				Kit.hazard(size, { wx, CRUSHER_LIFT + h / 2, wz }, {
					motion = { kind = "punch", axis = "y", amp = -CRUSHER_LIFT, period = period, phase = phase },
				})
			)
		end
	end
	table.insert(parts, key(cx, 0, cz))
end

local M = {}
M.id = "KeyRun"
M.name = "Key Run"
M.idea = 20

M.variants = {
	{
		-- Two keys right on the path, each beside a still goo post; the second sits under a crusher, so you grab it
		-- between slams.
		name = "Key Line",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {
				pad(0, 10, -5, 5, 0, 3),
				pad(15, 25, -5, 5, 0, 1),
				pad(30, 40, -5, 5, 0, 2),
				pad(45, 60, -5, 5, 0, 3),
				key(20, 0, -2),
				post(20, 2.5, 0),
				key(35, 0, 2),
				post(35, -2.5, 0),
				crusher(35, 0, 10, 0, CRUSH.easy),
				gate(50, 0, 2),
			}
			return Kit.section(60, 0, parts)
		end,
	},
	{
		-- A straight path along the left edge, three islands 5 studs off on the right, one key each, the gate at the
		-- end. A goo post where you jump out first, a crusher on the path between the last two islands.
		name = "Three Islands",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {
				entry(),
				pad(15, 30, -12, -4, 0, 1),
				island(18, 1),
				pad(35, 58, -12, -4, 0, 2),
				island(36, 1),
				island(48, 1),
				pad(63, 70, -12, -4, 0, 3),
				key(22, 0, 5),
				key(40, 0, 5),
				key(52, 0, 5),
				post(22, -10, 0),
				crusher(46, -8, 8, 0, CRUSH.easy),
				gate(66.5, 0, 3),
			}
			return Kit.section(70, 0, parts)
		end,
	},
	{
		-- Both keys sit up a staircase of +3 steps beside the floor; climb, grab, drop the 9 studs back down (not
		-- straight ahead: red goo waits at the foot), then time a full-width crusher before the gate.
		name = "Up and Back",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {
				entry(),
				pad(15, 40, -Kit.HALF, Kit.HALF, 0, 1),
				pillar(16, 24, -12, -4, 3, 0, 2, { route = "key" }),
				pillar(24, 32, -12, -4, 6, 0, 3, { route = "key" }),
				pillar(32, 40, -12, -4, 9, 0, 2, { route = "key" }),
				pad(40, 56, -Kit.HALF, Kit.HALF, 0, 1),
				key(28, 6, -8),
				key(36, 9, -8),
				Kit.hazard({ 4, 1, 8 }, { 42, 0.5, -8 }),
				crusher(47, 0, Kit.WIDTH, 0, CRUSH.easy),
				gate(54, 0, 2),
			}
			return Kit.section(56, 0, parts)
		end,
	},
	{
		-- Four keys, the gate needs three: skip the one you like least (on a +3 ledge, behind a goo post, or the far
		-- one you only reach from another island). A crusher guards the path before the gate.
		name = "Spare Key",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			local parts = {
				entry(),
				pad(15, 40, -12, -4, 0, 1),
				island(16, 0),
				island(28, 0, 3, 3),
				island(40, 0),
				island(52, 4, 0, 3),
				pad(40, 74, -12, -4, 0, 2),
				key(20, 0, 4),
				key(32, 3, 4),
				key(44, 0, 5.5),
				post(44, 1.5, 0, 5),
				key(56, 0, 8),
				crusher(60, -8, 8, 0, CRUSH.easy),
				gate(68, 0, 3),
			}
			return Kit.section(74, 0, parts)
		end,
	},
	{
		-- Scatter's map with three near keys split left and right: you cross the path once.
		name = "Scatter: Both Sides",
		tier = "easy",
		build = function(_seed: number): Kit.Section
			return scatter({ 1, 3, 6 }, nil, "easy")
		end,
	},
	{
		-- Two keys on the bridge, one on a ledge 9 studs under it: drop down, climb three +3 steps back up. A crusher
		-- slams on the bridge past the ledge.
		name = "Under the Bridge",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {
				entry(),
				pad(15, 59, -4, 4, 0, 1),
				pad(24, 40, -Kit.HALF, Kit.HALF, -9, 2, { route = "key" }),
				pillar(40, 46, 4, 12, -6, -10, 3, { route = "key" }),
				pillar(46, 52, 4, 12, -3, -10, 2, { route = "key" }),
				pillar(52, 58, 4, 12, 0, -10, 3, { route = "key" }),
				pad(64, 76, -Kit.HALF, Kit.HALF, 0, 3),
				key(20, 0, 0),
				key(54, 0, 0),
				key(32, -9, 0),
				crusher(46, 0, 8, 0, CRUSH.medium),
				gate(69, 0, 3),
			}
			return Kit.section(76, 0, parts)
		end,
	},
	{
		-- Each key sits in a ring of red goo with one 4-stud opening, each facing another way, and a goo door slams
		-- down over every opening: find the gap, wait for the door, walk in, grab, walk out.
		name = "Hazard Guard",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {
				entry(),
				pad(15, 42, -Kit.HALF, Kit.HALF, 0, 1),
				pad(47, 72, -Kit.HALF, Kit.HALF, 0, 2),
				gate(66, 0, 3),
			}
			ring(parts, 23, 6.5, "-x", DOOR, 0)
			ring(parts, 35, -6.5, "+z", DOOR, 0.33)
			ring(parts, 55, 6.5, "+x", DOOR, 0.66)
			return Kit.section(72, 0, parts)
		end,
	},
	{
		-- Two keys on path pads (the first under a crusher); the third sits on a ledge 9 studs up that only an orange
		-- spring pad reaches, and the pad throws for barely 1.1 s of every 2.4 (its rim glows before).
		name = "Bounce Key",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {
				entry(),
				pad(15, 27, -12, -4, 0, 1),
				Kit.slab(24, 0, 4, 8, 8, "spring", {
					route = "key",
					marker = "rings1",
					motion = { kind = "bounce", power = 65, duty = 0.45, period = 2.4 },
				}),
				pad(31, 39, 0, 8, 9, 3, { route = "key" }),
				pad(32, 44, -12, -4, 0, 2),
				pad(49, 64, -12, -4, 0, 3),
				key(21, 0, -8),
				key(38, 0, -8),
				key(35, 9, 4),
				crusher(21, -8, 8, 0, CRUSH.medium),
				gate(55, 0, 3),
			}
			return Kit.section(64, 0, parts)
		end,
	},
	{
		-- Grab any key and the others float up 2 studs a second, out of reach in about 5 s; they sink back after 8. A
		-- crusher on the path between the first two keys eats into that time.
		name = "Drifting Keys",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local function drifting(x: number, top: number, z: number): Kit.Part
				return key(x, top, z, { motion = drift(), start = "drift", trigger = "drift" })
			end
			local parts = {
				entry(),
				pad(15, 36, -12, -4, 0, 1),
				island(24, 0),
				pad(41, 56, -12, -4, 0, 2),
				island(46, 0),
				pad(61, 70, -12, -4, 0, 3),
				drifting(18, 0, -8),
				drifting(28, 0, 4),
				drifting(50, 0, 4),
				crusher(31, -8, 8, 0, CRUSH.medium),
				gate(64, 0, 3),
			}
			return Kit.section(70, 0, parts)
		end,
	},
	{
		-- A key rides a pad sliding across the lane: it comes within 4 studs of the path for 1.3 s of every 2.6.
		name = "Ride for It",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local ride = { kind = "slide", axis = "z", amp = 2, period = 2.6 }
			local parts = {
				entry(),
				pad(15, 34, -12, -4, 0, 1),
				pad(24, 32, 2, 10, 0, 3, { route = "key", motion = table.clone(ride) }),
				pad(39, 54, -12, -4, 0, 2),
				island(42, 0),
				pad(59, 66, -12, -4, 0, 3),
				key(18, 0, -8),
				key(28, 0, 6, { motion = table.clone(ride) }),
				key(46, 0, 4),
				crusher(44, -8, 8, 0, CRUSH.medium),
				gate(62, 0, 3),
			}
			return Kit.section(66, 0, parts)
		end,
	},
	{
		-- The gate stands right by the entry, on the corridor; the keys wait at the far end of a spur on the other
		-- side of the lane (8 studs off, too far to jump across): go out, come back, then through. Crushers on both.
		name = "Out and Back",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {
				entry(),
				pad(14, 24, 4, 12, 0, 2, { route = "key" }),
				pad(28, 38, 4, 12, 0, 3, { route = "key" }),
				pad(42, 52, 4, 12, 0, 2, { route = "key" }),
				pad(56, 66, 4, 12, 0, 3, { route = "key" }),
				pad(15, 34, -12, -4, 0, 1),
				pad(39, 56, -12, -4, 0, 2),
				pad(61, 76, -12, -4, 0, 1),
				key(59, 0, 6),
				key(61.5, 0, 10),
				key(64, 0, 6),
				crusher(33, 8, 8, 0, CRUSH.medium),
				crusher(47, -8, 8, 0, CRUSH.medium, 0.5),
				gate(20, 0, 3, -Kit.HALF, 2),
			}
			return Kit.section(76, 0, parts)
		end,
	},
	{
		-- Three gates in a row, one key each: the key before a gate opens it, the room behind holds the next key. A
		-- crusher in each room, and the last key sits on a +3 ledge.
		name = "Two Gates",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {
				entry(),
				pad(15, 30, -Kit.HALF, Kit.HALF, 0, 1),
				pad(35, 54, -Kit.HALF, Kit.HALF, 0, 2),
				pad(59, 80, -Kit.HALF, Kit.HALF, 0, 1),
				pillar(68, 74, 4, 12, 3, 0, 3, { route = "key" }),
				pad(85, 92, -Kit.HALF, Kit.HALF, 0, 3),
				key(18, 0, 0),
				gate(24, 0, 1),
				crusher(41, 0, Kit.WIDTH, 0, CRUSH.medium),
				key(47, 0, -6),
				gate(51, 0, 2),
				crusher(64, 0, Kit.WIDTH, 0, CRUSH.medium, 0.4),
				key(71, 3, 8),
				gate(77.5, 0, 3),
			}
			return Kit.section(92, 0, parts)
		end,
	},
	{
		-- Night falls over the section: the glowing keys are the only bright things, the island edges faintly lit;
		-- 5-stud jumps to islands you can barely see, and a crusher on the dark path.
		name = "Keys in the Dark",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			local parts = {
				entry(),
				pad(15, 33, -12, -4, 0, 1),
				island(17, 1, 0, 2, { marker = "rail" }),
				island(33, 1, 0, 2, { marker = "rail" }),
				pad(38, 58, -12, -4, 0, 1),
				island(48, 1, 0, 2, { marker = "rail" }),
				pad(63, 72, -12, -4, 0, 3),
				key(21, 0, 5),
				key(37, 0, 5),
				key(52, 0, 5),
				crusher(44, -8, 8, 0, CRUSH.medium),
				gate(67, 0, 3),
				Kit.prop(
					{ 72, 24, Kit.WIDTH },
					{ 36, 6, 0 },
					"dark",
					{ zone = { kind = "dark", light = 10 }, ghost = true }
				),
			}
			return Kit.section(72, 0, parts)
		end,
	},
	{
		-- Scatter's map with two keys at the far end and one near the start: the right order saves a long walk.
		name = "Scatter: Far Pair",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			return scatter({ 2, 7, 8 }, nil, "medium")
		end,
	},
	{
		-- Scatter's map with three keys, one drifts off after your first grab.
		name = "Scatter: One Drifts",
		tier = "medium",
		build = function(_seed: number): Kit.Section
			return scatter({ 3, 4, 6 }, 4, "medium")
		end,
	},
	{
		-- The first key starts a clock (the sign on the gate); 9 s later red goo floods the islands and the path up to
		-- the gate, and touching it puts every key back. Islands at 5.5-stud jumps, a crusher on the way.
		name = "Countdown Lock",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local clock = { trigger = "clock" }
			local parts = {
				entry(),
				pad(15.5, 35.5, -12, -4, 0, 1),
				island(18, 1.5),
				island(36, 1.5),
				pad(41, 61, -12, -4, 0, 2),
				island(52, 1.5),
				pad(66.5, 80, -12, -4, 0, 3),
				key(22, 0, 5.5, clock),
				key(40, 0, 5.5, clock),
				key(56, 0, 5.5, clock),
				crusher(29, -8, 8, 0, CRUSH.hard),
				Kit.hazard({ 56, 1, Kit.WIDTH }, { 40, -3.5, 0 }, {
					start = "clock",
					motion = { kind = "rise", speed = 3, delay = 9, stop = 5 },
				}),
				gate(70, 0, 3, nil, nil, "sign:9 s"),
			}
			return Kit.section(80, 0, parts)
		end,
	},
	{
		-- Four keys in four corners round a hub with a crusher, 5.5-stud jumps diagonally between them; the order
		-- decides how often you cross the hub. A second full-width crusher, out of step, guards the gate pad.
		name = "Four Corners",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {
				entry(),
				pad(15.5, 23.5, -12, -4, 0, 1),
				pad(15.5, 23.5, 4, 12, 0, 2, { route = "key" }),
				pad(29, 37, -4, 4, 0, 3),
				pad(42.5, 50.5, -12, -4, 0, 1),
				pad(42.5, 50.5, 4, 12, 0, 2, { route = "key" }),
				pad(56, 68, -Kit.HALF, Kit.HALF, 0, 3),
				key(19.5, 0, -8),
				key(19.5, 0, 8),
				key(46.5, 0, -8),
				key(46.5, 0, 8),
				crusher(33, 0, 8, 0, HUB_CRUSH.hard),
				crusher(60, 0, Kit.WIDTH, 0, 2.5, 0.5),
				gate(66.5, 0, 4),
			}
			return Kit.section(68, 0, parts)
		end,
	},
	{
		-- Keys in order 3-1-2 along the path: only the far key is free; the first sits in a cage that opens with one
		-- key, the middle one in a cage that opens with two. Run to the end, back to the start, then the middle, past
		-- two out-of-step crushers each way.
		name = "Next Key Glows",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			local parts = {
				entry(),
				pad(15.5, 35.5, -12, -4, 0, 1),
				island(16, 1.5),
				island(36, 1.5),
				pad(41, 61, -12, -4, 0, 2),
				island(52, 1.5),
				pad(66.5, 80, -12, -4, 0, 3),
				key(20, 0.5, 6.5),
				cage(20, 0, 6.5, 1),
				key(40, 0.5, 6.5),
				cage(40, 0, 6.5, 2),
				key(56, 0, 5.5),
				crusher(28, -8, 8, 0, CRUSH.hard),
				crusher(48, -8, 8, 0, CRUSH.hard, 0.5),
				gate(70, 0, 3),
			}
			return Kit.section(80, 0, parts)
		end,
	},
	{
		-- Scatter's map with four keys over both ends and both sides, two of them on far spots.
		name = "Scatter: Four Wide",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			return scatter({ 1, 4, 5, 8 }, nil, "hard")
		end,
	},
	{
		-- Scatter's map with four keys; the second one drifts once you grab another, so take it first.
		name = "Scatter: Four and Drift",
		tier = "hard",
		build = function(_seed: number): Kit.Section
			return scatter({ 2, 3, 6, 8 }, 2, "hard")
		end,
	},
}

M.generator = {
	tiers = { "easy", "medium", "hard" },
	build = generate,
	examples = 6,
}

-- For the spec: the map's spots and the picking rule.
M.SPOTS = SPOTS
M.scatter = scatter

return M
