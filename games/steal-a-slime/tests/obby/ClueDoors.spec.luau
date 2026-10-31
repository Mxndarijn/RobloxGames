--!strict
-- Clue Doors (obby idea 29): every variant and the generator through ObbyCheck, the variant list against its design
-- file, and what the shared checks can't see in a clue room: an independent solver finds exactly the rolled door for
-- every clue (many seeds), the right corridor is the only safe way through, wrong corridors look exactly like the
-- right one, the right door is spread over the slots, easy symbols differ in colour and shape, and a walker started
-- on any door floor still never reaches the exit.
local T = require("../TestRunner")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local describe, it, expect = T.describe, T.it, T.expect
local ClueDoors = require("../../src/shared/ObbySections/ClueDoors")
local Kit = require("../../src/shared/ObbySections/Kit")
local ObbyCheck = require("../ObbyCheck")

local SEEDS = 200 -- more than the shared 20

type Sym = ClueDoors.Sym
type Room = ClueDoors.Room

-- Every case (variant index, tier, name) to inspect.
local function eachCase(fn: (string, number, string) -> ())
	for i, v in ClueDoors.variants do
		fn(`#{i} {v.name}`, i, v.tier)
	end
	for _, tier in (ClueDoors.generator :: any).tiers do
		fn(`generator {tier}`, 0, tier)
	end
end

local function same(a: Sym, b: Sym): boolean
	return a.t == b.t and a.shape == b.shape and a.col == b.col and a.kind == b.kind and a.n == b.n
end

local function copy(s: Sym): Sym
	local c = table.clone(s)
	c.cross = nil
	return c
end

-- The solver: which doors fit the room's board(s), worked out from the symbols alone.
local function fits(room: Room): { number }
	local out = {}
	local board = room.boards[1]
	for i, door in room.doors do
		local ok = false
		local kind = room.kind
		if kind == "match" or kind == "slime" then
			ok = same(door, board[1])
		elseif kind == "shape" then
			ok = door.shape == board[1].shape
		elseif kind == "shadow" then
			ok = board[1].t == "shadow" and door.kind == board[1].kind
		elseif kind == "count" then
			ok = door.n == board[1].n
		elseif kind == "cross" then
			ok = true
			for _, s in board do
				expect(s.cross).toBe(true)
				ok = ok and not same(door, copy(s))
			end
		elseif kind == "next" then
			-- the shortest period the row repeats with, then the symbol that comes next
			local row = {}
			for _, s in board do
				if s.t ~= "blank" then
					table.insert(row, s)
				end
			end
			local period = #row
			for p = 1, #row - 1 do
				local good = true
				for k = p + 1, #row do
					good = good and same(row[k], row[k - p])
				end
				if good then
					period = p
					break
				end
			end
			ok = same(door, row[#row + 1 - period])
		elseif kind == "mix" then
			local colour, shape = board[1], room.boards[2][1]
			expect(colour.t).toBe("splash")
			expect(shape.t).toBe("grey")
			ok = door.col == colour.col and door.shape == shape.shape
		else
			error(`unknown clue kind {kind}`)
		end
		if ok then
			table.insert(out, i)
		end
	end
	return out
end

local function isTrap(p: Kit.Part): boolean
	local m = p.motion
	return m ~= nil and m.kind == "melt" and (m.away or 0) < 0
end

-- The corridor floor of `room` at z (step or trapdoor).
local function corridorAt(section: Kit.Section, room: Room, z: number): Kit.Part?
	for _, p in section.parts do
		if not p.ghost and not p.hazard and p.size[2] <= 1.01 then
			local x0, x1, _, y1 = Kit.bounds(p)
			if
				math.abs(x0 - room.x0) < 1e-6
				and math.abs(x1 - room.x1) < 1e-6
				and math.abs(p.pos[3] - z) < 1e-6
				and math.abs(y1 - room.top) < 1e-6
			then
				return p
			end
		end
	end
	return nil
end

local function gap(a: Kit.Part, b: Kit.Part, t: number?): (number, number)
	local adx, ady, adz = Kit.offsetAt(a, t)
	local bdx, bdy, bdz = Kit.offsetAt(b, t)
	local ax0, ax1, _, ay1, az0, az1 = Kit.bounds(a)
	local bx0, bx1, _, by1, bz0, bz1 = Kit.bounds(b)
	ax0, ax1, az0, az1, ay1 = ax0 + adx, ax1 + adx, az0 + adz, az1 + adz, ay1 + ady
	bx0, bx1, bz0, bz1, by1 = bx0 + bdx, bx1 + bdx, bz0 + bdz, bz1 + bdz, by1 + bdy
	local gx = math.max(0, bx0 - ax1, ax0 - bx1)
	local gz = math.max(0, bz0 - az1, az0 - bz1)
	return math.sqrt(gx * gx + gz * gz), by1 - ay1
end

local TIMES: { number } = {}
for k = 0, 36 do
	table.insert(TIMES, k * 0.1)
end

-- Can the exit pad be reached from the entry pad over floors only, leaving out `skip`? With `t` every jump is
-- taken at that moment; without, each jump at any moment (you wait on a floor for it).
local function reaches(section: Kit.Section, t: number?, skip: { [Kit.Part]: boolean }): boolean
	local floors, first, last = {}, nil, nil
	for _, p in section.parts do
		if p.step then
			first = first or p
			last = p
		end
		if not p.ghost and not p.hazard and not isTrap(p) and p.size[2] <= 1.01 and not skip[p] then
			table.insert(floors, p)
		end
	end
	local seen = { [first :: Kit.Part] = true }
	local queue = { first :: Kit.Part }
	while #queue > 0 do
		local a = table.remove(queue) :: Kit.Part
		if a == last then
			return true
		end
		for _, b in floors do
			if not seen[b] then
				for _, when in if t then { t } else TIMES do
					local g, rise = gap(a, b, when)
					if g <= Kit.GAP_MAX and rise <= Kit.RISE_MAX then
						seen[b] = true
						table.insert(queue, b)
						break
					end
				end
			end
		end
	end
	return false
end

-- Can the exit pad be reached from the entry pad, waiting on any floor for its moment (every jump at some time)?
local function reachesSometime(section: Kit.Section, skip: { [Kit.Part]: boolean }): boolean
	return reaches(section, nil, skip)
end

describe("Clue Doors", function()
	it("passes every shared check for every variant and the generator, seeds 1..20", function()
		local problems = {}
		for _, case in ObbyCheck.cases(ClueDoors :: any) do
			for _, p in ObbyCheck.run(case) do
				table.insert(problems, p)
			end
		end
		expect(table.concat(problems, "\n")).toBe("")
	end)

	it("builds every variant of docs/obby-variants/29.json, in its order and tiers", function()
		local doc = serde.decode("json", fs.readFile("docs/obby-variants/29.json"))
		local design = doc.ideas[1]
		expect(ClueDoors.id).toBe("ClueDoors")
		expect(ClueDoors.name).toBe(design.name)
		expect(ClueDoors.idea).toBe(design.id)
		expect(#ClueDoors.variants).toBe(#design.variants)
		for i, v in design.variants do
			expect(ClueDoors.variants[i].name).toBe(v.name)
			expect(ClueDoors.variants[i].tier).toBe(v.tier)
		end
		expect(ClueDoors.generator ~= nil).toBe(true)
	end)

	it("solves every clue to exactly the rolled door, for many seeds", function()
		local bad = {}
		eachCase(function(name, index, tier)
			for seed = 1, SEEDS do
				local _, rooms = ClueDoors.inspect(index, seed, tier)
				for k, room in rooms do
					local found = fits(room)
					if #found ~= 1 or found[1] ~= room.right then
						table.insert(
							bad,
							`{name} seed {seed} room {k} ({room.kind}): fits {table.concat(found, ",")}, right {room.right}`
						)
					end
				end
			end
		end)
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("makes the right corridor the only safe way: a step behind it, identical trapdoors behind the others", function()
		local bad = {}
		eachCase(function(name, index, tier)
			for seed = 1, SEEDS, 7 do
				local section, rooms = ClueDoors.inspect(index, seed, tier)
				for k, room in rooms do
					local right = corridorAt(section, room, room.centres[room.right])
					if not right or not right.step or right.motion then
						table.insert(bad, `{name} seed {seed} room {k}: the right corridor is not a plain step`)
						continue
					end
					for i, z in room.centres do
						if i ~= room.right then
							local p = corridorAt(section, room, z)
							if not p or p.step or not isTrap(p) then
								table.insert(bad, `{name} seed {seed} room {k}: door {i} has no trapdoor`)
							elseif
								p.look ~= right.look
								or p.tone ~= right.tone
								or ObbyCheck.encode(p.size) ~= ObbyCheck.encode(right.size)
								or p.marker
							then
								table.insert(bad, `{name} seed {seed} room {k}: door {i}'s corridor looks different`)
							end
						end
					end
					-- the course can be crossed with the right corridor, and not without it
					if not reachesSometime(section, {}) then
						table.insert(bad, `{name} seed {seed}: can't be crossed on safe floors`)
					end
					if reachesSometime(section, { [right] = true }) then
						table.insert(bad, `{name} seed {seed} room {k}: crossed without the right corridor`)
					end
				end
			end
		end)
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("spreads the right door over every slot", function()
		local bad = {}
		eachCase(function(name, index, tier)
			local counts: { [string]: { [number]: number } } = {}
			for seed = 1, SEEDS do
				local _, rooms = ClueDoors.inspect(index, seed, tier)
				for k, room in rooms do
					local key = `{k}/{#room.doors}`
					counts[key] = counts[key] or {}
					counts[key][room.right] = (counts[key][room.right] or 0) + 1
				end
			end
			for key, c in counts do
				local n = tonumber(string.match(key, "/(%d+)")) :: number
				local total = 0
				for i = 1, n do
					total += c[i] or 0
				end
				for i = 1, n do
					local share = (c[i] or 0) / total
					if total >= 30 and (share < 0.5 / n or share > 1.6 / n) then
						table.insert(bad, `{name} room {key}: door {i} right {share * 100}% of the time`)
					end
				end
			end
		end)
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("gives easy match doors different colours and shapes, and every door its own symbol", function()
		local bad = {}
		eachCase(function(name, index, tier)
			for seed = 1, SEEDS do
				local _, rooms = ClueDoors.inspect(index, seed, tier)
				for _, room in rooms do
					for i = 1, #room.doors do
						for j = i + 1, #room.doors do
							local a, b = room.doors[i], room.doors[j]
							if same(a, b) then
								table.insert(bad, `{name} seed {seed}: doors {i} and {j} look the same`)
							end
							if room.kind == "match" and (a.col == b.col or a.shape == b.shape) then
								table.insert(bad, `{name} seed {seed}: match doors share a colour or shape`)
							end
							if (room.kind == "slime" or room.kind == "shadow") and a.kind == b.kind then
								table.insert(bad, `{name} seed {seed}: two doors with the same slime outline`)
							end
						end
					end
				end
			end
		end)
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("stops a walker holding forward from every door floor too, not just at the jump in", function()
		local bad = {}
		eachCase(function(name, index, tier)
			for seed = 1, 20, 3 do
				local section, rooms = ClueDoors.inspect(index, seed, tier)
				for k, room in rooms do
					-- the door floor ends at the door wall (room.x0 - 1), or runs on under it to room.x0 when the
					-- doorways have goo lintels: start the walker there
					local parts = {}
					local started = false
					for _, p in section.parts do
						local x0, x1 = Kit.bounds(p)
						if
							p.step
							and not started
							and (math.abs(x1 - (room.x0 - 1)) < 1e-6 or math.abs(x1 - room.x0) < 1e-6)
						then
							started = true
							table.insert(parts, p)
						elseif x0 >= room.x0 - 2 then
							table.insert(parts, p)
						end
					end
					if not started then
						table.insert(bad, `{name} seed {seed} room {k}: no door floor`)
						continue
					end
					local cut = { length = section.length, rise = section.rise, parts = parts }
					local why = ObbyCheck.straightWalk(cut)
					if why then
						table.insert(bad, `{name} seed {seed} room {k}: {why}`)
					end
				end
			end
		end)
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("shows a blinking board long enough and often enough to read", function()
		for _, case in ObbyCheck.cases(ClueDoors :: any) do
			local section = case.build(1)
			for _, p in section.parts do
				local m = p.motion
				if m and m.kind == "flip" and not m.solid and p.ghost then
					-- a blinking board shows its clue at least 0.8 s a flash, at most 3.6 s apart
					local period = Kit.periodOf(p)
					expect(period <= 3.6 + 1e-6).toBe(true)
					expect((m.duty or 0) * period >= 0.8 - 1e-6).toBe(true)
				end
			end
		end
	end)
	it("keeps a wrong corridor too long to run and jump across before its trapdoor drops", function()
		-- the furthest a runner gets from the door wall over a trapdoor: a jump in (taken at the wall), 0.25 s of
		-- running, a jump out
		local jump = Kit.WALK * 2 * Kit.JUMP_SPEED / Kit.GRAVITY
		local bad = {}
		eachCase(function(name, index, tier)
			for seed = 1, 20, 3 do
				local section, rooms = ClueDoors.inspect(index, seed, tier)
				for k, room in rooms do
					local nextX = math.huge
					for _, p in section.parts do
						local x0 = Kit.bounds(p)
						if p.step and x0 >= room.x1 - 1e-6 then
							nextX = math.min(nextX, x0)
						end
					end
					local reach = (room.x0 - 1) + jump + Kit.WALK * 0.25 + jump
					if reach > nextX - 1 then
						table.insert(
							bad,
							`{name} seed {seed} room {k}: a runner reaches {reach}, the next floor is at {nextX}`
						)
					end
				end
			end
		end)
		expect(table.concat(bad, "\n")).toBe("")
	end)

	it("makes every moving hop matter: some of the time it is out of reach", function()
		-- consecutive steps with a moving one between them: reachable at some times (the shared check) and out of
		-- reach (gap over GAP_MAX or rise over RISE_MAX) at others, so the hop needs timing
		local MOVING = {
			["Shape Only"] = 0,
			["Count the Dots"] = 1,
			["Cross Out"] = 1,
			["What Comes Next"] = 0,
			["Shadow Clue"] = 1,
			["Blink Board"] = 0,
			["Side Glance"] = 1,
			["Two Rooms"] = 1,
			["Mix Clue"] = 1,
			["Closing Doors"] = 1,
			["Remember It"] = 1,
			["Clue Up High"] = 1,
		}
		local bad = {}
		for i, v in ClueDoors.variants do
			local need = MOVING[v.name]
			if need == nil then
				continue
			end
			local section = ClueDoors.inspect(i, 1)
			local steps = {}
			for _, p in section.parts do
				if p.step and not p.route then
					table.insert(steps, p)
				end
			end
			local timed = 0
			for k = 1, #steps - 1 do
				local a, b = steps[k], steps[k + 1]
				local moving = (a.motion and a.motion.kind == "slide") or (b.motion and b.motion.kind == "slide")
				if moving then
					local period =
						math.max(if a.motion then Kit.periodOf(a) else 0, if b.motion then Kit.periodOf(b) else 0)
					local ok, blocked = false, false
					for s = 0, 63 do
						local g, rise = gap(a, b, s / 64 * period)
						if g <= Kit.GAP_MAX and rise <= Kit.RISE_MAX then
							ok = true
						else
							blocked = true
						end
					end
					if not ok then
						table.insert(bad, `{v.name}: steps {k}-{k + 1} never in reach`)
					end
					if blocked then
						timed += 1
					end
				end
			end
			if timed < need then
				table.insert(bad, `{v.name}: {timed} timed jumps, want at least {need}`)
			end
		end
		expect(table.concat(bad, "\n")).toBe("")
	end)
end)
