--!strict
--[[
	Preload (owner: Archer) -> VisualsClient.Preload

	v30 C2: kit meshes streamed in lazily, so the world looked wrong (grey
	placeholders, low LODs) until the player moved. start() asks
	ContentProvider to fetch every uploaded mesh id (MeshAssets.allMeshIds)
	right away, then every MeshPart that MeshSwap replicates into
	workspace.Map / workspace.Plots, in batches. It only warms the cache:
	nothing waits on it, a failed id is ignored, and it never touches the world.
]]

local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MeshAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshAssets"))

local Preload = {}

Preload.BATCH = 40

-- Splits `items` into lists of at most `size`.
function Preload.batches(items: { any }, size: number): { { any } }
	local out: { { any } } = {}
	for i = 1, #items, size do
		table.insert(out, table.move(items, i, math.min(i + size - 1, #items), 1, {}))
	end
	return out
end

local function preload(items: { any })
	for _, batch in Preload.batches(items, Preload.BATCH) do
		pcall(ContentProvider.PreloadAsync, ContentProvider, batch)
	end
end

local started = false

function Preload.start()
	if started then
		return
	end
	started = true
	-- Ids first: they cover meshes the server has not swapped in yet.
	task.spawn(preload, MeshAssets.allMeshIds())
	-- Then the replicated MeshParts themselves (also warms their materials).
	for _, rootName in { "Map", "Plots" } do
		task.spawn(function()
			local root = workspace:WaitForChild(rootName, 30)
			if not root then
				return
			end
			local queue: { Instance } = {}
			for _, d in root:GetDescendants() do
				if d:IsA("MeshPart") then
					table.insert(queue, d)
				end
			end
			preload(queue)
			root.DescendantAdded:Connect(function(d)
				if d:IsA("MeshPart") then
					task.spawn(preload, { d })
				end
			end)
		end)
	end
end

return Preload
