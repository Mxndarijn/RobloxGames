-- Server datamodel: bug probe 10 (ADVISORY), the slime statues on the fountain top are walk-in. The statues are the
-- slime_fountain_emerge mesh (Map.Volcano.EmergeMesh) plus any MeshPart / BasePart under it. For each one a 4-stud
-- character-sized ball is dropped from 6 studs above its bounding box top at the box centre and at 4 more points inside
-- its footprint (centre +-0.3 of the half extents), watched 2 s. ok = no ball ends with its centre inside a statue's
-- (oriented) bounding box, i.e. the statues collide. ok = false with a reason if no statue part is found. Balls destroyed.
local volcano = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Volcano")
local root = volcano and volcano:FindFirstChild("EmergeMesh")
if not root then
	return { ok = false, summary = "Map.Volcano.EmergeMesh (fountain statues) missing", detail = {} }
end
local statues = {}
if root:IsA("BasePart") then
	table.insert(statues, root)
end
for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then
		table.insert(statues, d)
	end
end
if #statues == 0 then
	return { ok = false, summary = "EmergeMesh has no parts", detail = {} }
end
local PhysicsService = game:GetService("PhysicsService")
local GROUP = "BugProbe"
pcall(function()
	PhysicsService:RegisterCollisionGroup(GROUP)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
end)
local made = {}
local ok, result = pcall(function()
	local balls = {}
	for si, s in statues do
		local h = s.Size / 2
		for _, o in { { 0, 0 }, { 0.3, 0.3 }, { -0.3, 0.3 }, { 0.3, -0.3 }, { -0.3, -0.3 } } do
			local top = s.CFrame * Vector3.new(h.X * o[1], h.Y, h.Z * o[2])
			local b = Instance.new("Part")
			b.Shape = Enum.PartType.Ball
			b.Size = Vector3.new(4, 4, 4)
			b.Position = top + Vector3.new(0, 6, 0)
			b.CollisionGroup = GROUP
			b.Parent = workspace
			table.insert(made, b)
			table.insert(balls, { ball = b, statue = si })
		end
	end
	task.wait(2)
	local inside, list = 0, {}
	for _, e in balls do
		local s = statues[e.statue]
		local l = s.CFrame:PointToObjectSpace(e.ball.Position)
		if math.abs(l.X) < s.Size.X / 2 and math.abs(l.Y) < s.Size.Y / 2 and math.abs(l.Z) < s.Size.Z / 2 then
			inside += 1
			if #list < 6 then
				table.insert(list, { statue = s:GetFullName(), local_pos = { l.X, l.Y, l.Z } })
			end
		end
	end
	local info = {}
	for i, s in statues do
		if i <= 6 then
			table.insert(info, { name = s.Name, size = { s.Size.X, s.Size.Y, s.Size.Z }, can_collide = s.CanCollide, class = s.ClassName })
		end
	end
	return { statues = #statues, balls = #balls, inside = inside, inside_list = list, parts = info }
end)
for _, b in made do
	pcall(function()
		b:Destroy()
	end)
end
if not ok then
	return { ok = false, summary = "probe error: " .. tostring(result), detail = {} }
end
return {
	ok = result.inside == 0,
	summary = string.format("%d / %d balls ended INSIDE a statue's bounding box (%d statue parts)", result.inside, result.balls, result.statues),
	detail = result,
}
