--!nocheck
-- The obby's picture signs (docs/obby-signs-proposal.html; Merijn: every step on one board, no words, one design for
-- all: a banner overhanging the lane, flying on boosters): every sign names known pictograms, no text sign is left,
-- every pictogram builds with @lune/roblox and reads on a phone, and in every course each sign is the same lane-wide
-- banner at the same height over its floor, clear of every part and of the other banners.
local roblox = require("@lune/roblox")

local ObbyCheck = require("./ObbyCheck")
local ObbyCourse = require("../src/shared/ObbyCourse")
local ObbySections = require("../src/shared/ObbySections")
local ObbySigns = require("../src/visuals/shared/ObbySigns")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local Kit = ObbySections.Kit
local SIGN = ObbyCourse.SIGN

local DEPS = {
	Instance = roblox.Instance,
	Enum = roblox.Enum,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Color3 = roblox.Color3,
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
}
local SEEDS = 3
local EPS = 1e-6

-- The 15 mechanics the proposal gives a sign: 12 needed, 3 nice to have (all picked).
local SIGNED = {
	"AimTheCannon",
	"RollingBlobs",
	"Climb",
	"GlowMemory",
	"BeatPads",
	"KeyRun",
	"ClueDoors",
	"StickyWalls",
	"MoonJump",
	"SpeedStrip",
	"ArrowMaze",
	"LightsOut",
	"VineSwing",
	"GeyserField",
	"Updraft",
}

local function eachCase(visit: (any, any) -> ())
	for _, idea in ObbySections.ALL do
		for _, case in ObbyCheck.cases(idea) do
			visit(idea, case)
		end
	end
end

local function paint(ids: { string })
	local gui = roblox.Instance.new("SurfaceGui")
	return ObbySigns.paint(gui, ObbyCourse.slotsOf("pic:" .. table.concat(ids, ",")), DEPS)
end

local function overlaps(a, b, slack)
	for k = 1, 5, 2 do
		if a[k] >= b[k + 1] - slack or b[k] >= a[k + 1] - slack then
			return false
		end
	end
	return true
end

-- The boxes a part fills at 16 times of its motion (a flood or a zone may hold a sign: they cover the section).
local function boxesOf(part)
	local kind = part.motion and part.motion.kind
	if part.zone or kind == "rise" or kind == "flood" then
		return {}
	end
	local x0, x1, y0, y1, z0, z1 = Kit.bounds(part)
	local out = { { x0, x1, y0, y1, z0, z1 } }
	if part.motion then
		local period = Kit.periodOf(part)
		for k = 0, 15 do
			local dx, dy, dz = Kit.offsetAt(part, k / 16 * period)
			table.insert(out, { x0 + dx, x1 + dx, y0 + dy, y1 + dy, z0 + dz, z1 + dz })
		end
	end
	return out
end

describe("Obby picture signs: data", function()
	it("gives exactly the 15 proposal mechanics an entry sign, every picture known", function()
		local count = 0
		for id, pics in ObbySections.ENTRY_SIGNS do
			count += 1
			expect(table.find(SIGNED, id) ~= nil).toBe(true)
			expect(ObbySections.byId[id] ~= nil).toBe(true)
			for _, pic in string.split(pics, ",") do
				expect(ObbySigns.has(pic)).toBe(true)
			end
		end
		expect(count).toBe(#SIGNED)
		expect(ObbySections.ENTRY_SIGNS.AimTheCannon).toBe("cannon1,cannon2,cannon3,cannon4")
	end)

	it("every sign marker and section sign names known pictures, and no text sign is left", function()
		local bad = {}
		eachCase(function(_, case)
			for seed = 1, SEEDS do
				local section = case.build(seed)
				for _, pic in (if section.sign then string.split(section.sign, ",") else {}) do
					if not ObbySigns.has(pic) then
						table.insert(bad, `{case.name}: section sign {pic}`)
					end
				end
				for i, part in section.parts do
					local m = part.marker
					if m and string.sub(m, 1, 5) == "sign:" then
						table.insert(bad, `{case.name}: part {i} has a text sign {m}`)
					end
					for _, pic in ObbyCourse.picsOf(m) or {} do
						if not ObbySigns.has(pic) then
							table.insert(bad, `{case.name}: part {i} has an unknown picture {pic}`)
						end
					end
				end
			end
		end)
		if #bad > 0 then
			print("  " .. table.concat(bad, "\n  "))
		end
		expect(#bad).toBe(0)
	end)

	it("the checks refuse a text sign and an unknown picture", function()
		local function section(marker)
			return Kit.section(40, 0, { Kit.slab(20, 0, 0, 40, Kit.WIDTH, "pad", { marker = marker }) })
		end
		expect(ObbyCheck.fields(section("pic:fast"))).toBeNil()
		expect(ObbyCheck.fields(section("pic:safe,fast"))).toBeNil()
		expect(ObbyCheck.fields(section("sign:FAST")) ~= nil).toBe(true)
		expect(ObbyCheck.fields(section("pic:nope")) ~= nil).toBe(true)
		expect(ObbyCheck.fields(section("pic:fast,nope")) ~= nil).toBe(true)
	end)

	it("counts one banner per sign in the part budget, and nothing on the marked part", function()
		local s = Kit.section(40, 0, { Kit.slab(20, 0, 0, 40, Kit.WIDTH, "pad", { marker = "pic:fast" }) })
		expect(ObbyCheck.partCount(s)).toBe(1 + ObbyCourse.SIGN_PARTS)
		expect(ObbyCheck.partCount(s, "AimTheCannon")).toBe(1 + 2 * ObbyCourse.SIGN_PARTS)
		expect(ObbyCheck.partCount(s, "CrusherAlley")).toBe(1 + ObbyCourse.SIGN_PARTS)
	end)

	it("puts the marked parts' pictures of one spot on one banner, each over the part it marks", function()
		local s = Kit.section(40, 0, {
			Kit.slab(4, 0, 0, 8, Kit.WIDTH, "pad"),
			Kit.slab(24, 0, 6.5, 32, 11, "jelly", { marker = "pic:fast" }),
			Kit.slab(24, 0, -6.5, 32, 11, "jelly", { marker = "pic:safe" }),
		})
		local banners, missed = ObbyCourse.signs(s)
		expect(#missed).toBe(0)
		expect(#banners).toBe(1)
		expect(ObbyCourse.picsOf(banners[1].marker)[1]).toBe("safe")
		local slots = ObbyCourse.slotsOf(banners[1].marker)
		expect(slots[1].z).toBe(-6.5)
		expect(slots[2].z).toBe(6.5)
	end)

	it("keeps slots apart and on the banner when the parts are close or at the edge", function()
		local s = Kit.section(40, 0, {
			Kit.slab(4, 0, 0, 8, Kit.WIDTH, "pad"),
			Kit.slab(24, 0, 10, 32, 4, "jelly", { marker = "pic:low" }),
			Kit.slab(24, 0, 11, 32, 2, "jelly", { marker = "pic:high" }),
		})
		local slots = ObbyCourse.slotsOf(ObbyCourse.signs(s)[1].marker)
		local edge = SIGN.width / 2 - SIGN.pad - SIGN.slot / 2
		expect(slots[2].z - slots[1].z >= SIGN.slot + SIGN.pad - 0.01).toBe(true)
		expect(slots[2].z <= edge + 0.01).toBe(true)
	end)
end)

describe("Obby picture signs: pictograms", function()
	it("every pictogram builds in one slot, shows only digits as text, and the cannon board fits the lane", function()
		for _, id in ObbySigns.IDS do
			local root = paint({ id })
			expect(root.Name).toBe("Picture")
			local shapes = ObbySigns.shapes(root)
			expect(#shapes > 0).toBe(true)
			for _, s in shapes do
				if s.text then
					expect(string.match(s.text, "^[%d ]+$") ~= nil).toBe(true)
				end
			end
		end
		expect(SIGN.width).toBe(Kit.WIDTH)
		expect(4 * SIGN.slot + 5 * SIGN.pad <= SIGN.width).toBe(true)
	end)

	it("every pictogram has a main shape a phone reads at 26 studs, and no stroke too thin to see", function()
		local S = ObbySigns.SIZE
		local need = S.minShapePx / S.phonePxPerStud -- studs
		for _, id in ObbySigns.IDS do
			local biggest = 0
			for _, s in ObbySigns.shapes(paint({ id })) do
				biggest = math.max(biggest, math.max(s.w, s.h))
				if s.class == "Frame" and math.min(s.w, s.h) < S.minLine - EPS then
					error(`{id}: a {s.w} x {s.h} stud shape is under {S.minLine} studs`)
				end
			end
			if biggest < need then
				error(`{id}: biggest shape {biggest} studs, a phone needs {need}`)
			end
		end
	end)

	it("puts the cannon's four steps on one banner, numbered 1 to 4", function()
		local root = paint(string.split(ObbySections.ENTRY_SIGNS.AimTheCannon, ","))
		local slots, numbers = 0, {}
		for _, child in root:GetChildren() do
			if child:IsA("Frame") then
				slots += 1
				for _, d in child:GetChildren() do
					if d:IsA("TextLabel") then
						table.insert(numbers, d.Text)
					end
				end
			end
		end
		expect(slots).toBe(4)
		table.sort(numbers)
		expect(table.concat(numbers, ",")).toBe("1,2,3,4")
	end)
end)

describe("Obby picture signs: boosters", function()
	it("hangs a flaming booster under each end, all within the banner's hang and reach, and adds no parts", function()
		local banner = roblox.Instance.new("Part")
		banner.Size = roblox.Vector3.new(SIGN.thick, ObbyCourse.bannerHeight(), SIGN.width)
		ObbySigns.boosters(banner, DEPS)
		local flames, adorns = 0, 0
		for _, d in banner:GetDescendants() do
			expect(d:IsA("BasePart")).toBe(false)
			if d:IsA("ParticleEmitter") then
				flames += 1
				expect(string.find(d.Texture, "^rbxasset://") ~= nil).toBe(true)
			elseif d:IsA("HandleAdornment") then
				adorns += 1
			end
		end
		expect(flames).toBe(2)
		expect(adorns >= 2).toBe(true)
		local B = ObbySigns.SIZE.booster
		expect(B.body + B.nozzle <= SIGN.hang + EPS).toBe(true)
		expect(B.radius + 0.08 <= SIGN.reach + EPS).toBe(true)
	end)
end)

describe("Obby picture signs: in the course", function()
	it("every sign is the same lane-wide banner at the same height over its floor, clear of every part", function()
		local problems = {}
		eachCase(function(idea, case)
			local pick = { id = idea.id, tier = case.tier, variant = case.variant, seed = 1 }
			local course = ObbyCourse.build(1, { pick })
			local section = ObbyCourse.section(idea.id, case.variant, 1, case.tier)
			local dx, dy = ObbyCourse.START_LENGTH, 0
			-- the floors a banner may hang over: the first step (entry signs) and every marked part
			local tops, want = {}, 0
			local entry = ObbySections.entrySign(idea.id, section)
			if entry then
				want += #string.split(entry, ",")
				for _, part in section.parts do
					if part.step then
						local _, _, _, y1 = Kit.bounds(part)
						table.insert(tops, y1 + dy)
						break
					end
				end
			end
			for _, part in section.parts do
				local ids = ObbyCourse.picsOf(part.marker)
				if ids then
					want += #ids
					local _, _, _, y1 = Kit.bounds(part)
					table.insert(tops, y1 + dy)
				end
			end
			local banners, others, got = {}, {}, 0
			for _, part in course.parts do
				if part.look == "signpost" then
					table.insert(problems, `{case.name}: a post is left ({part.id})`)
				elseif part.look == "banner" then
					table.insert(banners, part)
					got += #ObbyCourse.picsOf(part.marker)
				else
					table.insert(others, part)
					if ObbyCourse.picsOf(part.marker) then
						table.insert(problems, `{case.name}: part {part.id} still carries {part.marker}`)
					end
				end
			end
			if got ~= want then
				table.insert(problems, `{case.name}: {got} pictures on banners, {want} asked for`)
			end
			local placed = {}
			for _, b in banners do
				local label = `{case.name} {b.id}`
				-- lane-wide, the one size, a hover
				if
					b.pos[3] ~= 0
					or b.size[3] ~= SIGN.width
					or b.size[1] ~= SIGN.thick
					or math.abs(b.size[2] - ObbyCourse.bannerHeight()) > EPS
				then
					table.insert(problems, `{label}: not the lane-wide banner`)
				end
				if not b.ghost or not (b.motion and b.motion.kind == "slide" and b.motion.axis == "y") then
					table.insert(problems, `{label}: not a hovering ghost`)
				end
				local x0, x1 = b.pos[1] - SIGN.reach, b.pos[1] + SIGN.reach
				if x0 < dx - EPS or x1 > dx + section.length + EPS then
					table.insert(problems, `{label}: outside its section`)
				end
				-- the same height over its floor
				local bottom = b.pos[2] - b.size[2] / 2
				local ok = false
				for _, top in tops do
					ok = ok or math.abs(bottom - top - SIGN.lift) < EPS
				end
				if not ok then
					table.insert(problems, `{label}: its bottom is not {SIGN.lift} over its floor`)
				end
				-- slots on the banner, apart
				local slots = ObbyCourse.slotsOf(b.marker)
				local edge = SIGN.width / 2 - SIGN.slot / 2
				for k, slot in slots do
					if math.abs(slot.z) > edge + EPS then
						table.insert(problems, `{label}: slot {k} off the banner`)
					end
					if k > 1 and slot.z - slots[k - 1].z < SIGN.slot - EPS then
						table.insert(problems, `{label}: slots {k - 1} and {k} overlap`)
					end
				end
				-- nothing overlaps it (boosters and hover included), nor another banner
				local box = ObbyCourse.bannerBox(b)
				for _, part in others do
					for _, other in boxesOf(part) do
						if overlaps(box, other, SIGN.clear) then
							table.insert(problems, `{label} overlaps {part.id} ({part.look})`)
							break
						end
					end
				end
				for _, other in placed do
					if overlaps(box, other, SIGN.clear) then
						table.insert(problems, `{label} overlaps another banner`)
					end
				end
				table.insert(placed, box)
			end
		end)
		if #problems > 0 then
			print("  " .. table.concat(problems, "\n  ", 1, math.min(#problems, 30)))
		end
		expect(#problems).toBe(0)
	end)

	it("hangs Two Roads' fork banner with the shield over the left road and the lightning over the right", function()
		local course = ObbyCourse.build(1, { { id = "TwoRoads", tier = "easy", variant = 1, seed = 1 } })
		local found = false
		for _, part in course.parts do
			if part.look == "banner" then
				local slots = ObbyCourse.slotsOf(part.marker)
				expect(slots[1].id).toBe("safe")
				expect(slots[1].z < 0).toBe(true)
				expect(slots[2].id).toBe("fast")
				expect(slots[2].z > 0).toBe(true)
				found = true
			end
		end
		expect(found).toBe(true)
	end)
end)
