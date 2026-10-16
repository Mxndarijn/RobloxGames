--!strict
-- World budgets, counted on WorldLayout.build() in both fence modes:
--   uploaded  ranch_fence_20 has an asset id (forced here): one MeshAsset slot
--             per 20-stud panel. The caps below are asserted on this count.
--   fallback  no id yet (today): two phoenix_fence_segment per panel, so one
--             extra slot per panel (MESH_SLOT_BUDGET_FALLBACK).
-- Mesh slots = MeshAsset slots + pending BorderMesh slots + the WorldProps
-- skins (PROP_MESHES), split into fence / gate posts / border / decor (ranch
-- props, pad stands and everything else). See WorldLayout.MESH_SLOT_BUDGET.
-- Parts = Part nodes outside Map.Border must stay under PART_BUDGET (1400)
-- in both modes; Map.Border (main #54: walls, invisible slots and
-- primitive stand-ins) is held to BORDER_PART_BUDGET on its own.
local Config = require("../src/shared/Config")
local MeshAssets = require("../src/shared/MeshAssets")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

type Counts = {
	fence: number,
	posts: number, -- the GatePost closing the fence run at each gate
	props: number,
	pads: number,
	dex: number, -- plot DexBoard skins (in other)
	buy: number, -- plot BuyStand skins (in other)
	border: number,
	other: number,
	decor: number, -- props + pads + other
	total: number,
	parts: number,
	borderParts: number,
	panels: number,
	segments: number,
}

local propNames: { [string]: boolean } = {}
for _, p in WorldLayout.RANCH_PROPS do
	propNames[p.name] = true
end

local function count(nodes: { any }): Counts
	local c: Counts = {
		fence = 0,
		posts = 0,
		props = 0,
		pads = 0,
		dex = 0,
		buy = 0,
		border = 0,
		other = 0,
		decor = 0,
		total = 0,
		parts = 0,
		borderParts = 0,
		panels = 0,
		segments = 0,
	}
	local function walk(n: any, inBorder: boolean, inDecor: boolean)
		if n.class == "Part" then
			if inBorder then
				c.borderParts += 1
			else
				c.parts += 1
			end
		end
		local a = n.attributes or {}
		local mesh = a.MeshAsset or a.BorderMesh
		if mesh then
			if inBorder then
				c.border += 1
			elseif mesh == WorldLayout.GATE_POST_MESH and n.name == "GatePost" then
				c.posts += 1
			elseif mesh == WorldLayout.FENCE_MESH or mesh == WorldLayout.FENCE_SEGMENT then
				c.fence += 1
				if mesh == WorldLayout.FENCE_MESH then
					c.panels += 1
				else
					c.segments += 1
				end
			elseif inDecor and propNames[n.name] then
				c.props += 1
			elseif n.name == "Stand" then
				c.pads += 1
			else
				if mesh == WorldLayout.DEX_MESH and n.name == "DexMesh" then
					c.dex += 1
				elseif mesh == WorldLayout.BUY_STAND_MESH and n.name == "StandMesh" then
					c.buy += 1
				end
				c.other += 1
			end
		end
		for _, ch in n.children or {} do
			local top = n.name == WorldLayout.MAP_NAME
			walk(ch, inBorder or (top and ch.name == "Border"), inDecor or (top and ch.name == "Decor"))
		end
	end
	for _, root in nodes do
		walk(root, false, false)
	end
	for _ in WorldLayout.PROP_MESHES do
		c.other += 1
	end
	c.decor = c.props + c.pads + c.other
	c.total = c.fence + c.posts + c.decor + c.border
	return c
end

-- Builds the world as if ranch_fence_20 were uploaded, then restores the entry.
local function buildUploaded(): { any }
	local entry = MeshAssets.entries[WorldLayout.FENCE_MESH] :: any
	local was = entry.meshId
	entry.meshId = "rbxassetid://0"
	local ok, nodes = pcall(WorldLayout.build)
	entry.meshId = was
	assert(ok, nodes)
	return nodes
end

local uploaded = count(buildUploaded())
local current = count(WorldLayout.build())
local fallback = if WorldLayout.fenceUploaded() then nil else current

local P = Config.PLOT_COUNT

describe("world budget: mesh slots (ranch_fence_20 uploaded)", function()
	it("keeps the fence at 16 slots a plot (14 panels + 2 gate segments), FENCE_SLOT_BUDGET", function()
		expect(uploaded.panels).toBe(14 * P)
		expect(uploaded.segments).toBe(2 * P)
		expect(uploaded.fence).toBe(16 * P)
		expect(uploaded.fence <= WorldLayout.FENCE_SLOT_BUDGET).toBe(true)
	end)
	it("closes each gate's open fence end with one GatePost, GATE_POST_SLOT_BUDGET", function()
		expect(uploaded.posts).toBe(P)
		expect(uploaded.posts).toBe(WorldLayout.GATE_POST_SLOT_BUDGET)
		expect(current.posts).toBe(uploaded.posts)
	end)
	it("keeps ranch props + pad stands + the rest under DECOR_SLOT_BUDGET", function()
		expect(uploaded.props).toBe(#WorldLayout.RANCH_PROPS)
		expect(uploaded.pads).toBe(Config.PADS_MAX * P)
		expect(uploaded.decor <= WorldLayout.DECOR_SLOT_BUDGET).toBe(true)
	end)
	it("skins one DexBoard a plot inside the decor cap (C6), paid for by one entrance prop a plot", function()
		expect(uploaded.dex).toBe(P)
		local entrance = 0
		for _, p in WorldLayout.RANCH_PROPS do
			if p.cluster == "entrance" then
				entrance += 1
			end
		end
		expect(entrance).toBe(P)
		local budgeted = uploaded.fence + uploaded.posts + uploaded.decor + WorldLayout.BORDER_SLOT_BUDGET
		expect(budgeted <= WorldLayout.MESH_SLOT_BUDGET).toBe(true)
	end)
	it("skins one BuyStand a plot (ranch_shop_stand), filling decor to its cap", function()
		expect(uploaded.buy).toBe(P)
		expect(uploaded.decor).toBe(WorldLayout.DECOR_SLOT_BUDGET)
	end)
	it("splits MESH_SLOT_BUDGET 400 into fence 128 + gate posts 8 + border 104 + decor 160", function()
		expect(WorldLayout.MESH_SLOT_BUDGET).toBe(400)
		expect(WorldLayout.FENCE_SLOT_BUDGET).toBe(128)
		expect(WorldLayout.GATE_POST_SLOT_BUDGET).toBe(8)
		expect(WorldLayout.BORDER_SLOT_BUDGET).toBe(104)
		expect(WorldLayout.DECOR_SLOT_BUDGET).toBe(160)
		expect(
			WorldLayout.FENCE_SLOT_BUDGET
				+ WorldLayout.GATE_POST_SLOT_BUDGET
				+ WorldLayout.BORDER_SLOT_BUDGET
				+ WorldLayout.DECOR_SLOT_BUDGET
		).toBe(WorldLayout.MESH_SLOT_BUDGET)
	end)
	it("fits MESH_SLOT_BUDGET with the border at its share", function()
		local budgeted = uploaded.fence + uploaded.posts + uploaded.decor + WorldLayout.BORDER_SLOT_BUDGET
		expect(budgeted <= WorldLayout.MESH_SLOT_BUDGET).toBe(true)
		-- the budget is the real count, not a ceiling far above it
		expect(WorldLayout.MESH_SLOT_BUDGET - budgeted < 10).toBe(true)
	end)
	it("holds the border to its share, pinned at BORDER_SLOT_COUNT", function()
		-- Any change to the ring trips this so the budget is re-read.
		expect(uploaded.border).toBe(WorldLayout.BORDER_SLOT_COUNT)
		expect(uploaded.border <= WorldLayout.BORDER_SLOT_BUDGET).toBe(true)
		expect(uploaded.total <= WorldLayout.MESH_SLOT_BUDGET).toBe(true)
		expect(current.border).toBe(uploaded.border)
	end)
end)

describe("world budget: mesh slots (fallback until ranch_fence_20 is uploaded)", function()
	it("fits MESH_SLOT_BUDGET_FALLBACK with two segments a panel", function()
		if fallback then
			expect(fallback.panels).toBe(0)
			expect(fallback.segments).toBe(30 * P)
			expect(fallback.fence).toBe(uploaded.fence + 14 * P)
			expect(fallback.decor).toBe(uploaded.decor)
			local budgeted = fallback.fence + fallback.posts + fallback.decor + WorldLayout.BORDER_SLOT_BUDGET
			expect(budgeted <= WorldLayout.MESH_SLOT_BUDGET_FALLBACK).toBe(true)
		end
	end)
end)

describe("world budget: parts", function()
	it("sets PART_BUDGET to 1400 outside Map.Border", function()
		expect(WorldLayout.PART_BUDGET).toBe(1400)
	end)
	it("keeps the parts outside Map.Border under PART_BUDGET, uploaded and fallback", function()
		expect(uploaded.parts < WorldLayout.PART_BUDGET).toBe(true)
		if fallback then
			expect(fallback.parts).toBe(uploaded.parts + 14 * P)
			expect(fallback.parts < WorldLayout.PART_BUDGET).toBe(true)
		end
	end)
	it("holds Map.Border to BORDER_PART_BUDGET (same in both modes)", function()
		expect(uploaded.borderParts <= WorldLayout.BORDER_PART_BUDGET).toBe(true)
		expect(current.borderParts).toBe(uploaded.borderParts)
	end)
end)

return { uploaded = uploaded, current = current }
