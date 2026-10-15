--!strict
-- lune run scripts/gen-world  (from the repo root)
-- Regenerates world/Map.rbxmx, world/Plots.rbxmx and world/HubSpawn.rbxmx
-- from WorldLayout via WorldBuilder. Rerun after changing src/visuals layouts.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local StaticWorld = require("./StaticWorld")

if not fs.isDir("world") then
	fs.writeDir("world")
end
for _, instance in StaticWorld.build() do
	local path = `world/{instance.Name}.rbxmx`
	fs.writeFile(path, roblox.serializeModel({ instance }, true))
	print(`wrote {path} ({#instance:GetDescendants() + 1} instances)`)
end
