--!nocheck
--[[
	Static z-fighting finder (no boot needed):
	  lune run tools/livetest/zfight build.rbxlx [Workspace.Map.Volcano] [eps=0.02]
	Lists same-rotation Block parts whose faces share a plane and overlap
	(the flicker you see on coplanar decals / slabs). Exit 0 always.
]]
local process = require("@lune/process")

local Checks = require("./Checks")
local Runtime = require("./Runtime")

local rt = Runtime.new(process.args[1] or "build.rbxlx", {})
local root = rt.game
for _, name in string.split(process.args[2] or "Workspace.Map", ".") do
	root = root and root:FindFirstChild(name)
end
assert(root, "no such instance")
local found = Checks.zFighting(rt, root, 200, tonumber(process.args[3]))
for _, line in found do
	print(line)
end
print(`{#found} coplanar overlapping face pair(s) under {root:GetFullName()}`)
