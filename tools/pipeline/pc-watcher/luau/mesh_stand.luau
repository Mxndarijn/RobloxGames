-- Server datamodel: bug 11 part 1 proof, real mesh collision (MeshAssets.COLLISION) on converted props. For each mesh in %%MESHES%%
-- (comma separated MeshAsset names) the first placed instance (a "Mesh" MeshPart whose parent carries MeshAsset = name) gets two balls:
--   stand  a 4-stud ball dropped 8 studs above the mesh's bounding box top at its centre must come to rest on or beside the mesh, never
--          below its bounding box middle (fell through / sank into it), and not fall to the ground inside the box
--   walk   a 4-stud ball 10 studs out on the mesh's thinnest horizontal axis, 2 studs above the box bottom, pushed at it at 30 studs/s for
--          1.5 s must still be on its starting side of the mesh centre (walked into / through it = FAIL)
-- Each mesh reports PASS / FAIL / n/a (not placed or not colliding) with the measured numbers. ok = no FAIL; an advisory (watcher notes it).
-- Balls sit in a collision group that does not collide with itself. Everything made is destroyed. ~4 s per mesh, the meshes run in parallel.
local PhysicsService = game:GetService("PhysicsService")
local GROUP = "MeshStandProbe"
pcall(function()
	PhysicsService:RegisterCollisionGroup(GROUP)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
end)
local names = {}
for n in string.gmatch(%%MESHES%%, "[^,]+") do
	table.insert(names, n)
end
local made = {}
local function findMesh(name)
	for _, root in { workspace:FindFirstChild("Map"), workspace:FindFirstChild("Plots") } do
		if root then
			for _, d in root:GetDescendants() do
				if d:IsA("MeshPart") and d.Name == "Mesh" and d.Parent and d.Parent:GetAttribute("MeshAsset") == name then
					return d
				end
			end
		end
	end
	return nil
end
local function ball(pos)
	local b = Instance.new("Part")
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.new(4, 4, 4)
	b.CanQuery = false
	b.CanTouch = false
	b.CollisionGroup = GROUP
	b.Transparency = 1
	b.Position = pos
	b.Parent = workspace
	table.insert(made, b)
	return b
end
local results = {}
local pending = #names
for _, name in names do
	task.spawn(function()
		local res = { mesh = name, status = "n/a" }
		results[name] = res
		local ok, err = pcall(function()
			local m = findMesh(name)
			if not m then
				res.info = "no placed instance"
			elseif not m.CanCollide then
				res.info = "found but CanCollide is false"
			else
				res.fidelity = m.CollisionFidelity.Name
				local c, size = m.CFrame, m.Size
				local top = c.Position.Y + size.Y / 2
				local bottom = c.Position.Y - size.Y / 2
				local stand = ball(Vector3.new(c.Position.X, top + 8 + 2, c.Position.Z))
				local axis = if size.X <= size.Z then c.RightVector else c.LookVector
				local dir = Vector3.new(axis.X, 0, axis.Z).Unit
				local start = Vector3.new(c.Position.X, bottom + 2, c.Position.Z) + dir * 10
				if start.Y < 2.5 then
					start = Vector3.new(start.X, 2.5, start.Z)
				end
				local walk = ball(start)
				walk.AssemblyLinearVelocity = -dir * 30
				local t0 = os.clock()
				while os.clock() - t0 < 1.5 do
					walk.AssemblyLinearVelocity = Vector3.new(-dir.X * 30, walk.AssemblyLinearVelocity.Y, -dir.Z * 30)
					task.wait()
				end
				task.wait(0.5)
				local sy = stand.Position.Y
				local side = (walk.Position - c.Position):Dot(dir)
				res.stand_y = sy
				res.box_top = top
				res.walk_side = side
				res.stand_ok = sy > c.Position.Y and sy > 2
				res.walk_ok = side > 0
				res.status = if res.stand_ok and res.walk_ok then "PASS" else "FAIL"
			end
		end)
		if not ok then
			res.status, res.info = "FAIL", tostring(err)
		end
		pending -= 1
	end)
end
local t0 = os.clock()
while pending > 0 and os.clock() - t0 < 12 do
	task.wait(0.1)
end
for _, b in made do
	pcall(function()
		b:Destroy()
	end)
end
local parts, fail, pass = {}, 0, 0
local list = {}
for _, name in names do
	local r = results[name] or { mesh = name, status = "n/a", info = "timed out" }
	table.insert(list, r)
	table.insert(parts, name .. " " .. r.status)
	if r.status == "FAIL" then
		fail += 1
	elseif r.status == "PASS" then
		pass += 1
	end
end
return {
	ok = fail == 0 and pass > 0,
	summary = table.concat(parts, "; "),
	detail = { meshes = list, pass = pass, fail = fail },
}
