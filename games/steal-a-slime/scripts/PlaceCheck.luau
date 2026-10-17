--!strict
--[[
	PlaceCheck (Lune): static void-safety checks on a built place.

	PlaceCheck.run(game): { string }  -- failure messages, empty = pass

	  * every Workspace BasePart is Anchored, except slimes (models under a
	    Slimes / WildSlimes folder or carrying a State attribute);
	  * a SpawnLocation exists, is Anchored + CanCollide and has solid,
	    anchored ground directly under its whole footprint;
	  * Map.Ground lies under every plot Base and HomeZone footprint;
	  * Workspace.FallenPartsDestroyHeight is below the server kill plane;
	  * every Part in WorldLayout exists in the place at its layout position;
	  * Workspace has no DataStoreMode attribute (the in-memory store and the
	    server TestHooks must never ship, CONTRACT.md §2 / §8.12).

	CLI: lune run scripts/check-place <place.rbxlx|rbxl>
]]

local roblox = require("@lune/roblox")

local Rescue = require("../src/server/Rescue")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local Vector3 = roblox.Vector3

local PlaceCheck = {}

local EPS = 0.05

local function isSlime(part: any): boolean
	local node = part.Parent
	while node and node.ClassName ~= "Workspace" do
		if node.Name == "Slimes" or node.Name == "WildSlimes" then
			return true
		end
		if node.ClassName == "Model" and node:GetAttribute("State") ~= nil then
			return true
		end
		node = node.Parent
	end
	return false
end

-- Corners, edge midpoints and centre of a part's bottom face, in world space.
local function footprint(part: any): { any }
	local half = part.Size / 2
	local points = {}
	for _, x in { -0.99, 0, 0.99 } do
		for _, z in { -0.99, 0, 0.99 } do
			table.insert(points, part.CFrame:PointToWorldSpace(Vector3.new(half.X * x, -half.Y, half.Z * z)))
		end
	end
	return points
end

-- True if `support` (an upright, anchored, collidable block) has its top face
-- under `point`, no higher than the point and at most `maxDrop` below it.
local function supports(support: any, point: any, maxDrop: number): boolean
	if not support.Anchored or not support.CanCollide then
		return false
	end
	if support.Shape ~= roblox.Enum.PartType.Block or support.CFrame.UpVector.Y < 0.999 then
		return false
	end
	local p = support.CFrame:PointToObjectSpace(point)
	local half = support.Size / 2
	if math.abs(p.X) > half.X + EPS or math.abs(p.Z) > half.Z + EPS then
		return false
	end
	local drop = p.Y - half.Y
	return drop >= -EPS and drop <= maxDrop
end

local function supportedBy(candidates: { any }, part: any, maxDrop: number): (boolean, string?)
	for _, point in footprint(part) do
		local ok = false
		for _, candidate in candidates do
			if candidate ~= part and supports(candidate, point, maxDrop) then
				ok = true
				break
			end
		end
		if not ok then
			return false, `({point.X}, {point.Y}, {point.Z})`
		end
	end
	return true, nil
end

local function findPath(root: any, path: { string }): any?
	local node = root
	for _, name in path do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function checkLayout(workspace: any, nodes: { WorldLayout.WorldNode }, path: { string }, failures: { string })
	for _, node in nodes do
		local childPath = table.clone(path)
		table.insert(childPath, node.name)
		local instance = findPath(workspace, childPath)
		local label = table.concat(childPath, ".")
		if not instance or instance.ClassName ~= node.class then
			table.insert(failures, `missing {node.class} Workspace.{label}`)
		elseif node.class == "Part" and node.pos then
			local pos = instance.CFrame.Position
			local d = Vector3.new(pos.X - node.pos[1], pos.Y - node.pos[2], pos.Z - node.pos[3])
			if d.Magnitude > EPS then
				table.insert(failures, `Workspace.{label} is off its WorldLayout position by {d.Magnitude}`)
			end
		end
		checkLayout(workspace, node.children or {}, childPath, failures)
	end
end

function PlaceCheck.run(game: any): { string }
	local failures = {}
	local workspace = game:GetService("Workspace")
	local parts = {}
	for _, instance in workspace:GetDescendants() do
		if instance:IsA("BasePart") and not instance:IsA("Terrain") then -- Terrain is a BasePart class but not a block part
			table.insert(parts, instance)
			if not instance.Anchored and not isSlime(instance) then
				table.insert(failures, `unanchored {instance:GetFullName()}`)
			end
		end
	end

	local spawns = {}
	for _, part in parts do
		if part.ClassName == "SpawnLocation" then
			table.insert(spawns, part)
		end
	end
	if #spawns == 0 then
		table.insert(failures, "no SpawnLocation in Workspace")
	end
	for _, spawn in spawns do
		if not spawn.Anchored or not spawn.CanCollide or not spawn.Enabled then
			table.insert(failures, `{spawn:GetFullName()} must be Anchored, CanCollide and Enabled`)
		end
		local ok, at = supportedBy(parts, spawn, 0.5)
		if not ok then
			table.insert(failures, `no solid ground under {spawn:GetFullName()} at {at}`)
		end
	end

	local ground = findPath(workspace, { WorldLayout.MAP_NAME, "Ground" })
	if not ground then
		table.insert(failures, "missing Workspace.Map.Ground")
	else
		local plots = workspace:FindFirstChild("Plots")
		local count = 0
		for _, plot in if plots then plots:GetChildren() else {} do
			for _, name in { "Base", "HomeZone" } do
				local part = plot:FindFirstChild(name)
				if not part then
					table.insert(failures, `missing {plot:GetFullName()}.{name}`)
				else
					count += 1
					-- HomeZone floats over the Base; any depth of Ground under it counts.
					local ok, at = supportedBy({ ground }, part, if name == "Base" then 0.5 else 100)
					if not ok then
						table.insert(failures, `Ground does not cover {part:GetFullName()} at {at}`)
					end
				end
			end
		end
		if count == 0 then
			table.insert(failures, "no plots in Workspace.Plots")
		end
	end

	if workspace.FallenPartsDestroyHeight > Rescue.KILL_PLANE_Y then
		table.insert(failures, `FallenPartsDestroyHeight {workspace.FallenPartsDestroyHeight} above the kill plane`)
	end

	if workspace:GetAttribute("DataStoreMode") ~= nil then
		table.insert(failures, "Workspace has a DataStoreMode attribute (test-only in-memory store)")
	end

	checkLayout(workspace, WorldLayout.build(), {}, failures)
	return failures
end

function PlaceCheck.load(path: string): any
	local fs = require("@lune/fs")
	return roblox.deserializePlace(fs.readFile(path))
end

return PlaceCheck
