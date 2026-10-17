--!strict
--[[
	StaticWorld (Lune, build-time only; not in the Rojo tree)

	StaticWorld.build(): { Instance }

	Runs Archer's WorldBuilder.build unchanged under Lune (Roblox datatypes
	from @lune/roblox injected as globals) and adds the hub SpawnLocation.
	scripts/gen-world.luau writes the result to world/*.rbxmx, which
	default.project.json places under Workspace, so the floor, plots and
	spawn exist before any character loads. At runtime the server still
	calls WorldBuilder.build, which reuses these parts (idempotent).
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local LayoutMath = require("../src/visuals/shared/LayoutMath")

local StaticWorld = {}

StaticWorld.SPAWN_NAME = "HubSpawn"
-- On the ground between the Plot_2 / Plot_3 paths, clear of the fountain
-- plinth (r 13.4) and the plaza props, well inside the 640-stud Ground.
StaticWorld.SPAWN_YAW = 67.5
StaticWorld.SPAWN_RADIUS = 64
-- An invisible pad flush with the plaza sand (top 0.05, the GroundTerrain surface is y = 0): the old visible 12 x 1 x 12 butter slab read as a random yellow
-- box on the plaza (v28 playtest) and wild slimes landed on it.
StaticWorld.SPAWN_SIZE = { 12, 0.05, 12 }
StaticWorld.SPAWN_TRANSPARENCY = 1

-- Loads a src/visuals/shared module with Roblox datatypes (Instance, CFrame,
-- NumberSequence, ...) from @lune/roblox as globals; its "./X" requires load
-- the same way; other paths (../../shared/Config) use a plain require.
local function loader(): (string) -> any
	local cache: { [string]: any } = {}
	local function load(name: string): any
		if cache[name] == nil then
			local env: { [string]: any } = { script = nil }
			for key, value in roblox :: any do
				if string.match(key, "^%u") then
					env[key] = value
				end
			end
			env.require = function(path: string): any
				local sibling = string.match(path, "^%./([%w_]+)$")
				if sibling then
					return load(sibling)
				end
				-- Outside src/visuals/shared (Config, Constants): pure, plain require.
				return (require :: any)(`../src/visuals/shared/{path}`)
			end
			local source = fs.readFile(`src/visuals/shared/{name}.luau`)
			cache[name] = luau.load(source, { debugName = name, environment = env, injectGlobals = true })()
		end
		return cache[name]
	end
	return load
end

-- A src/visuals/shared module loaded with Roblox datatypes (e.g. "Props" for tests).
function StaticWorld.visual(name: string): any
	return loader()(name)
end

function StaticWorld.spawnPosition(): { number }
	local n = LayoutMath.direction(StaticWorld.SPAWN_YAW, 0)
	local r = StaticWorld.SPAWN_RADIUS
	return { n[1] * r, StaticWorld.SPAWN_SIZE[2] / 2, n[3] * r }
end

local function spawnLocation(): any
	local spawn = roblox.Instance.new("SpawnLocation")
	local size, pos = StaticWorld.SPAWN_SIZE, StaticWorld.spawnPosition()
	spawn.Name = StaticWorld.SPAWN_NAME
	spawn.Size = roblox.Vector3.new(size[1], size[2], size[3])
	spawn.CFrame = roblox.CFrame.new(pos[1], pos[2], pos[3])
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Neutral = true
	spawn.Enabled = true
	spawn.Duration = 3
	spawn.Material = roblox.Enum.Material.SmoothPlastic
	spawn.Color = roblox.Color3.fromRGB(222, 198, 150) -- plaza sand, if it ever shows
	spawn.Transparency = StaticWorld.SPAWN_TRANSPARENCY
	spawn.TopSurface = roblox.Enum.SurfaceType.Smooth
	spawn.BottomSurface = roblox.Enum.SurfaceType.Smooth
	return spawn
end

-- Map, Plots (from WorldBuilder) and the SpawnLocation, as top-level instances.
function StaticWorld.build(): { any }
	local root = roblox.Instance.new("Folder")
	local built = loader()("WorldBuilder").build(root)
	-- Idempotence check: a second build must not add anything.
	local before = #root:GetDescendants()
	loader()("WorldBuilder").build(root)
	assert(#root:GetDescendants() == before, "WorldBuilder.build is not idempotent")
	built.map.Parent = nil
	built.plots.Parent = nil
	return { built.map, built.plots, spawnLocation() }
end

return StaticWorld
