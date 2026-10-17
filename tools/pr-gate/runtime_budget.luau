--!nocheck
-- Runtime budget counts for Steal a Slime, printed as JSON on stdout. Run from the game dir
-- (the tree to count; tools/pr-gate/runtime_budget.sh does, for HEAD and for the PR base):
--   lune run ../../tools/pr-gate/runtime_budget.luau
-- Executes pc-watcher's perf_server.luau against the booted fake runtime (runtime_count.luau).
--   runtime_parts            Studio-equivalent: offline + STUDIO_OFFSET (what the watcher gates on)
--   runtime_parts_offline    raw fake-runtime count
--   runtime_parts_transient  slimes / characters / splash, not counted
--   mesh_slots               max(mesh_slots_build, mesh_slots_runtime + offset): matches Studio
--   mesh_slots_build         budget_counts.luau (WorldLayout.build() + RUNTIME_SLOT_ALLOWANCE)
--   mesh_slots_runtime       raw MeshParts in the fake runtime (no offset)
--   unique_meshes            distinct MeshIds among the world MeshParts: offline + UNIQUE_MESH_OFFSET (16, see runtime_count.luau)
--   unique_meshes_offline    raw fake-runtime count
local process = require("@lune/process")
local serde = require("@lune/serde")

local RuntimeCount = require("./runtime_count")

local t0 = os.clock()
local rt = RuntimeCount.boot()
local res = RuntimeCount.count(rt)
local offset = RuntimeCount.STUDIO_OFFSET

local built = process.exec("lune", { "run", "../../tools/pr-gate/budget_counts.luau" })
assert(built.ok, `budget_counts failed: {built.stderr}`)
local meshesBuild = serde.decode("json", built.stdout).mesh_slots

print(serde.encode("json", {
	runtime_parts = res.runtime_parts + offset,
	runtime_parts_offline = res.runtime_parts,
	offset = offset,
	runtime_parts_transient = res.runtime_parts_transient,
	unique_meshes = res.unique_meshes + RuntimeCount.UNIQUE_MESH_OFFSET,
	unique_meshes_offline = res.unique_meshes,
	mesh_slots = math.max(meshesBuild, res.mesh_slots + offset),
	mesh_slots_runtime = res.mesh_slots,
	mesh_slots_build = meshesBuild,
	seconds = math.floor((os.clock() - t0) * 10) / 10,
}, true))
