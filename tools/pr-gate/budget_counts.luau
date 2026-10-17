--!strict
-- PR gate budget counts for Steal a Slime, printed as JSON on stdout.
-- Run from games/steal-a-slime (tools/pr-gate/budget.sh does):
--   lune run ../../tools/pr-gate/budget_counts.luau
-- Counts WorldLayout.build() the same way tests/WorldBudget.spec does:
--   mesh_slots   MeshAsset + BorderMesh slots + WorldProps skins (PROP_MESHES)
--                + RUNTIME_SLOT_ALLOWANCE (what pc-watcher's perf_server counts),
--                soft-budgeted at WorldLayout.MESH_SLOT_BUDGET (500, warn only)
--   parts        Part nodes outside Map.Border (THEME.md 1200)
--   border_parts Part nodes inside Map.Border (WorldLayout.BORDER_PART_BUDGET)
--   meshes       slot count per kit mesh name (budget_check.py turns this into
--                triangles from shared/modeling-kit/out/<name>.fbx)
local serde = require("@lune/serde")

local WorldLayout = require("../../games/steal-a-slime/src/visuals/shared/WorldLayout")

local counts = {
	mesh_slots = 0,
	parts = 0,
	border_parts = 0,
	nodes = 0,
	meshes = {} :: { [string]: number },
}

local function addMesh(name: string)
	counts.mesh_slots += 1
	counts.meshes[name] = (counts.meshes[name] or 0) + 1
end

local function walk(n: any, inBorder: boolean)
	counts.nodes += 1
	if n.class == "Part" then
		if inBorder then
			counts.border_parts += 1
		else
			counts.parts += 1
		end
	end
	local a = n.attributes or {}
	local mesh = a.MeshAsset or a.BorderMesh
	if type(mesh) == "string" then
		addMesh(mesh)
	end
	for _, ch in n.children or {} do
		walk(ch, inBorder or (n.name == WorldLayout.MAP_NAME and ch.name == "Border"))
	end
end

for _, root in WorldLayout.build() do
	walk(root, false)
end
for _, mesh in WorldLayout.PROP_MESHES do
	addMesh(mesh)
end
-- The pc-watcher counts every MeshPart in the play world (tools/pipeline/
-- pc-watcher/luau/perf_server.luau), which includes some WorldLayout.build()
-- does not make: count them the same way or the gate passes what the watcher fails.
counts.build_mesh_slots = counts.mesh_slots
counts.mesh_slots += WorldLayout.RUNTIME_SLOT_ALLOWANCE

counts.source_budgets = {
	MESH_SLOT_BUDGET = WorldLayout.MESH_SLOT_BUDGET,
	PART_BUDGET = WorldLayout.PART_BUDGET,
	BORDER_PART_BUDGET = WorldLayout.BORDER_PART_BUDGET,
}

print(serde.encode("json", counts, true))
