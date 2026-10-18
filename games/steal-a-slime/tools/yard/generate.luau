--!nocheck
-- lune run tools/yard/generate   (from games/steal-a-slime)
-- Regenerates src/visuals/shared/YardProps.luau (the sand yard's dressing) from YardGen's seed and prints a summary.
-- Then: stylua src/visuals/shared/YardProps.luau && lune run scripts/gen-world   (world/Map.rbxmx carries the slots).
local YardGen = require("./YardGen")
local fs = require("@lune/fs")

local rows = YardGen.generate()
local out = {
	"--!strict",
	"--[[",
	"\tYardProps (owner: Archer; GENERATED, do not edit by hand)",
	"",
	"\tThe sand yard's dressing: small clusters in the gaps between plots and on the sand behind them, plus a few single",
	"\tprops. `lune run tools/yard/generate` writes this file from tools/yard/YardGen.luau (seed "
		.. YardGen.SEED
		.. "); tests/YardDress.spec",
	"\tregenerates it in memory and fails when the two differ.",
	"",
	"\tRow: { name, mesh, angle, r, yaw (relative to the angle, like RanchProps), scale (uniform), tint { r, g, b } (MeshTint) }.",
	'\tRanchProps turns each row into a "yard" placement; WorldLayout makes the mesh slot.',
	"]]",
	"",
	"return table.freeze({",
	"\tSEED = " .. YardGen.SEED .. ",",
	"\tROWS = {",
}
for _, r in rows do
	table.insert(
		out,
		string.format(
			'\t\t{ "%s", "%s", %s, %s, %s, %s, { %d, %d, %d } },',
			r.name,
			r.mesh,
			r.angle,
			r.r,
			r.yaw,
			r.scale,
			r.tint[1],
			r.tint[2],
			r.tint[3]
		)
	)
end
table.insert(out, "\t} :: { { any } },")
table.insert(out, "})")
table.insert(out, "")
fs.writeFile("src/visuals/shared/YardProps.luau", table.concat(out, "\n"))
local byMesh = {}
for _, r in rows do
	byMesh[r.mesh] = (byMesh[r.mesh] or 0) + 1
end
print(`wrote {#rows} props`)
local names = {}
for m in byMesh do
	table.insert(names, m)
end
table.sort(names)
for _, m in names do
	print(string.format("  %-30s %d", m, byMesh[m]))
end
