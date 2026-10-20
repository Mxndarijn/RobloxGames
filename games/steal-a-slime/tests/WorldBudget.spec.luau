--!strict
-- World budgets, counted on WorldLayout.build().
-- Mesh slots = MeshAsset slots + pending BorderMesh slots + the WorldProps skins (PROP_MESHES), split into border /
-- decor (ranch props, pad stands and everything else). MeshParts are a soft budget (no hard per-category caps here;
-- #80's split was folded into the triangle / unique-mesh limits, see WorldLayout.MESH_SLOT_BUDGET): the asserts
-- below pin the layout only.
-- Parts = Part nodes outside Map.Border must stay under PART_BUDGET (1400); Map.Border (main #54: walls, invisible
-- slots and primitive stand-ins) is held to BORDER_PART_BUDGET on its own.
local Config = require("../src/shared/Config")
local SlimeLooks = require("../src/shared/SlimeLooks")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

type Counts = {
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
}

local propNames: { [string]: boolean } = {}
for _, p in WorldLayout.RANCH_PROPS do
	propNames[p.name] = true
end

local function count(nodes: { any }): Counts
	local c: Counts = {
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
			elseif inDecor and propNames[n.name] then
				c.props += 1
			elseif n.name == "Stand" then
				c.pads += 1
			else
				if n.name == "DexMesh" then
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
	c.total = c.decor + c.border
	return c
end

local uploaded = count(WorldLayout.build())

local P = Config.PLOT_COUNT

describe("world budget: mesh slots", function()
	it("keeps one slot per ranch prop and per pad stand", function()
		expect(uploaded.props).toBe(#WorldLayout.RANCH_PROPS)
		expect(uploaded.pads).toBe(Config.PADS_PER_FLOOR * P)
	end)
	it("skins no SlimeDex board on the plots, and keeps one entrance prop a plot", function()
		expect(uploaded.dex).toBe(0)
		local entrance = 0
		for _, p in WorldLayout.RANCH_PROPS do
			if p.cluster == "entrance" then
				entrance += 1
			end
		end
		expect(entrance).toBe(P)
	end)
	it("skins no BuyStand on the plots", function()
		expect(uploaded.buy).toBe(0)
	end)
	it("keeps the soft MeshPart budget a warning level, with the Studio calibration offset", function()
		expect(WorldLayout.MESH_SLOT_BUDGET).toBe(500)
		expect(WorldLayout.RUNTIME_SLOT_ALLOWANCE).toBe(16)
		-- soft: reported, never asserted (the pr-gate / pc-watcher warn above it)
		print(
			`[WorldBudget] mesh slots {uploaded.total + WorldLayout.RUNTIME_SLOT_ALLOWANCE} (soft {WorldLayout.MESH_SLOT_BUDGET})`
		)
	end)
	it("does not spend world slots on the per-type slime kit meshes", function()
		local kits = {}
		for _, kit in SlimeLooks.KITS do
			kits[kit] = true
		end
		for _, node in WorldLayout.build() do
			local stack = { node }
			while #stack > 0 do
				local n = table.remove(stack) :: any
				local a = n.attributes or {}
				expect(kits[a.MeshAsset] == nil and kits[a.BorderMesh] == nil).toBe(true)
				for _, child in n.children or {} do
					table.insert(stack, child)
				end
			end
		end
	end)
	it("pins the border at BORDER_SLOT_COUNT", function()
		-- Any change to the ring trips this so the budget is re-read.
		expect(uploaded.border).toBe(WorldLayout.BORDER_SLOT_COUNT)
	end)
end)

describe("world budget: parts", function()
	it("sets PART_BUDGET to 1400 outside Map.Border", function()
		expect(WorldLayout.PART_BUDGET).toBe(1400)
	end)
	it("keeps the parts outside Map.Border under PART_BUDGET", function()
		expect(uploaded.parts < WorldLayout.PART_BUDGET).toBe(true)
	end)
	it("holds Map.Border to BORDER_PART_BUDGET", function()
		expect(uploaded.borderParts <= WorldLayout.BORDER_PART_BUDGET).toBe(true)
	end)
end)

return { uploaded = uploaded, current = uploaded }
