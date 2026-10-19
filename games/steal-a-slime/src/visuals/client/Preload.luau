--!strict
--[[
	Preload (owner: Archer) -> VisualsClient.Preload

	Kit meshes stream in lazily, so the world looks wrong (grey placeholders,
	low LODs) until the player moves. start() asks ContentProvider to fetch
	every MeshPart that MeshSwap replicates into workspace.Map /
	workspace.Plots, in batches, and every one added later. It only warms the
	cache: nothing waits on it, a failed fetch is ignored, and it never touches
	the world.

	It preloads MeshPart instances, never raw mesh id strings: PreloadAsync
	fetches a string as an image, so a mesh id fails with "Asset type does not
	match requested type" and warms nothing.
]]

local Preload = {}

Preload.BATCH = 40
Preload.ROOTS = { "Map", "Plots" }

-- Engine access, overridable by specs. `preload` gets one batch of Instances.
export type Context = {
	preload: (batch: { Instance }) -> (),
	waitForRoot: (name: string) -> Instance?,
	spawn: (fn: (...any) -> (), ...any) -> (),
}

local function defaultContext(): Context
	local ContentProvider = game:GetService("ContentProvider")
	return {
		preload = function(batch)
			pcall(ContentProvider.PreloadAsync, ContentProvider, batch)
		end,
		waitForRoot = function(name)
			return workspace:WaitForChild(name, 30)
		end,
		spawn = function(fn, ...)
			task.spawn(fn, ...)
		end,
	}
end

-- Splits `items` into lists of at most `size`.
function Preload.batches(items: { any }, size: number): { { any } }
	local out: { { any } } = {}
	for i = 1, #items, size do
		table.insert(out, table.move(items, i, math.min(i + size - 1, #items), 1, {}))
	end
	return out
end

-- Starts the preload; returns a cleanup that stops watching for new MeshParts.
function Preload.start(ctx: Context?): () -> ()
	local connections: { RBXScriptConnection } = {}
	local stopped = false
	local cleanup = function()
		stopped = true
		for _, conn in connections do
			conn:Disconnect()
		end
		table.clear(connections)
	end
	local c: Context = ctx or defaultContext()
	local function preload(items: { Instance })
		for _, batch in Preload.batches(items, Preload.BATCH) do
			c.preload(batch)
		end
	end
	for _, rootName in Preload.ROOTS do
		c.spawn(function()
			local root = c.waitForRoot(rootName)
			if not root or stopped then
				return
			end
			local queue: { Instance } = {}
			for _, d in root:GetDescendants() do
				if d:IsA("MeshPart") then
					table.insert(queue, d)
				end
			end
			preload(queue)
			table.insert(
				connections,
				root.DescendantAdded:Connect(function(d)
					if d:IsA("MeshPart") then
						c.spawn(preload, { d })
					end
				end)
			)
		end)
	end
	return cleanup
end

return Preload
