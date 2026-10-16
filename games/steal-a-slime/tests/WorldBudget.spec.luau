--!strict
-- World budgets, counted on WorldLayout.build() in both fence modes:
--   uploaded  ranch_fence_20 has an asset id (forced here): one MeshAsset slot
--             per 20-stud panel. MESH_SLOT_BUDGET is this count.
--   fallback  no id yet (today): two phoenix_fence_segment per panel, so one
--             extra slot per panel (MESH_SLOT_BUDGET_FALLBACK).
-- Mesh slots = MeshAsset slots + the WorldProps skins (PROP_MESHES).
-- Parts = Part nodes outside Map.Border must stay under PART_BUDGET (THEME.md
-- 1200) in both modes; Map.Border (main #54: walls, invisible slots and
-- primitive stand-ins) is held to BORDER_PART_BUDGET on its own.
local Config = require("../src/shared/Config")
local MeshAssets = require("../src/shared/MeshAssets")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

type Counts = { slots: number, parts: number, border: number, panels: number, segments: number }

local function count(nodes: { any }): Counts
	local c: Counts = { slots = 0, parts = 0, border = 0, panels = 0, segments = 0 }
	local function walk(n: any, inBorder: boolean)
		if n.class == "Part" then
			if inBorder then
				c.border += 1
			else
				c.parts += 1
			end
		end
		local mesh = n.attributes and n.attributes.MeshAsset
		if mesh then
			c.slots += 1
			if mesh == WorldLayout.FENCE_MESH then
				c.panels += 1
			elseif mesh == WorldLayout.FENCE_SEGMENT then
				c.segments += 1
			end
		end
		for _, ch in n.children or {} do
			walk(ch, inBorder or (n.name == WorldLayout.MAP_NAME and ch.name == "Border"))
		end
	end
	for _, root in nodes do
		walk(root, false)
	end
	for _ in WorldLayout.PROP_MESHES do
		c.slots += 1
	end
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

describe("world budget: mesh slots", function()
	it("fits MESH_SLOT_BUDGET with ranch_fence_20 uploaded (14 panels + 2 segments a plot)", function()
		expect(uploaded.panels).toBe(14 * P)
		expect(uploaded.segments).toBe(2 * P)
		expect(uploaded.slots <= WorldLayout.MESH_SLOT_BUDGET).toBe(true)
		-- the budget is the real count, not a ceiling far above it
		expect(WorldLayout.MESH_SLOT_BUDGET - uploaded.slots < 10).toBe(true)
	end)
	it("fits MESH_SLOT_BUDGET_FALLBACK until it is uploaded (two segments a panel)", function()
		if fallback then
			expect(fallback.panels).toBe(0)
			expect(fallback.segments).toBe(30 * P)
			expect(fallback.slots).toBe(uploaded.slots + 14 * P)
			expect(fallback.slots <= WorldLayout.MESH_SLOT_BUDGET_FALLBACK).toBe(true)
		end
	end)
end)

describe("world budget: parts", function()
	it("keeps the parts outside Map.Border under PART_BUDGET, uploaded and fallback", function()
		expect(uploaded.parts < WorldLayout.PART_BUDGET).toBe(true)
		if fallback then
			expect(fallback.parts).toBe(uploaded.parts + 14 * P)
			expect(fallback.parts < WorldLayout.PART_BUDGET).toBe(true)
		end
	end)
	it("holds Map.Border to BORDER_PART_BUDGET (same in both modes)", function()
		expect(uploaded.border <= WorldLayout.BORDER_PART_BUDGET).toBe(true)
		expect(current.border).toBe(uploaded.border)
	end)
end)

return { uploaded = uploaded, current = current }
