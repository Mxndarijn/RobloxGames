-- Server datamodel: bug probe 8 (ADVISORY), a locked base must not be enterable by others. Picks a plot with a
-- LockBarrier (an UNOWNED one when there is one: OwnerUserId 0), fakes a locked owner on it (attributes OwnerUserId =
-- -9001, LockUntil = now + 60, Locked = true, re-asserted every 0.1 s because WorldView.updatePlots rewrites them from
-- the sessions) and, as a NON-owner, pushes (a) a 4-stud physics ball and (b) a Humanoid dummy (MoveTo) from 26 studs
-- outside the entrance (the barrier's Front side, where the gate and Sign are) towards the plot centre for 4 s.
-- ok = neither ever gets inside the plot footprint (|x|,|z| < half size - 3 in the plot frame). Everything spawned is
-- destroyed and the attributes restored. The barrier panels' CanCollide state is reported (they ship as ghosts).
local plots = workspace:FindFirstChild("Plots")
if not plots then
	return { ok = false, summary = "workspace.Plots missing", detail = {} }
end
local plot
for _, p in plots:GetChildren() do
	if p:IsA("Model") and p:FindFirstChild("LockBarrier") then
		if p:GetAttribute("OwnerUserId") == 0 or p:GetAttribute("OwnerUserId") == nil then
			plot = p
			break
		end
		plot = plot or p
	end
end
local barrier = plot and plot:FindFirstChild("LockBarrier")
local front, back = barrier and barrier:FindFirstChild("Front"), barrier and barrier:FindFirstChild("Back")
if not (front and back) then
	return { ok = false, summary = "no plot with a LockBarrier Front/Back panel", detail = {} }
end
local names = { "OwnerUserId", "LockUntil", "Locked" }
local saved = {}
for _, n in names do
	saved[n] = plot:GetAttribute(n)
end
local made = {}
local alive = true
local function restore()
	alive = false
	for _, o in made do
		pcall(function()
			o:Destroy()
		end)
	end
	for _, n in names do
		pcall(function()
			plot:SetAttribute(n, saved[n])
		end)
	end
end
local ok, result = pcall(function()
	local centre = (front.Position + back.Position) / 2
	local rot = front.CFrame - front.Position
	local frame = CFrame.new(centre) * rot
	local half = math.abs(frame:PointToObjectSpace(front.Position).Z)
	local outward = (front.Position - centre) * Vector3.new(1, 0, 1)
	outward = outward.Unit
	local function assertLock()
		plot:SetAttribute("OwnerUserId", -9001)
		plot:SetAttribute("LockUntil", workspace:GetServerTimeNow() + 60)
		plot:SetAttribute("Locked", true)
	end
	assertLock()
	task.spawn(function()
		while alive do
			assertLock()
			task.wait(0.1)
		end
	end)
	local ground = workspace:Raycast(centre + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0))
	local gy = ground and ground.Position.Y or (front.Position.Y - front.Size.Y / 2)
	local start = Vector3.new(centre.X, gy, centre.Z) + outward * (half + 26)
	local target = Vector3.new(centre.X, gy, centre.Z)
	local function inside(p)
		local l = frame:PointToObjectSpace(Vector3.new(p.X, centre.Y, p.Z))
		return math.abs(l.X) < half - 3 and math.abs(l.Z) < half - 3
	end
	local ball = Instance.new("Part")
	ball.Name = "PcwBugBall"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(4, 4, 4)
	ball.Position = start + Vector3.new(0, 3, 0)
	ball.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.05, 0, 1, 1)
	ball.Parent = workspace
	table.insert(made, ball)
	local dummy = Instance.new("Model")
	dummy.Name = "PcwBugDummy"
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Position = start + Vector3.new(4, 4, 0)
	root.Parent = dummy
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(2, 1, 1)
	head.Position = root.Position + Vector3.new(0, 1.5, 0)
	head.Parent = dummy
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1, weld.Parent = root, head, root
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = 2.5
	hum.WalkSpeed = 20
	hum.Parent = dummy
	dummy.PrimaryPart = root
	dummy.Parent = workspace
	table.insert(made, dummy)
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local ballIn, dummyIn, dummyMoved = false, false, 0
	local t0, last = os.clock(), root.Position
	while os.clock() - t0 < 4 do
		local dir = target - ball.Position
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude > 1 then
			local v = ball.AssemblyLinearVelocity
			ball.AssemblyLinearVelocity = Vector3.new(dir.Unit.X * 18, v.Y, dir.Unit.Z * 18)
		end
		hum:MoveTo(target)
		ballIn = ballIn or inside(ball.Position)
		dummyIn = dummyIn or inside(root.Position)
		dummyMoved = dummyMoved + (root.Position - last).Magnitude
		last = root.Position
		task.wait(0.1)
	end
	local panels = {}
	for _, panel in barrier:GetChildren() do
		if panel:IsA("BasePart") then
			panels[panel.Name] = panel.CanCollide
		end
	end
	return {
		plot = plot.Name,
		ball_inside = ballIn,
		dummy_inside = dummyIn,
		dummy_moved = dummyMoved,
		ball_end = { ball.Position.X, ball.Position.Y, ball.Position.Z },
		half = half,
		barrier_cancollide = panels,
	}
end)
restore()
if not ok then
	return { ok = false, summary = "probe error: " .. tostring(result), detail = { plot = plot.Name } }
end
local r = result
local fine = not r.ball_inside and not r.dummy_inside
local movedNote = if r.dummy_moved < 3 then " (dummy barely moved: ball verdict only)" else ""
return {
	ok = fine,
	summary = string.format("locked %s: non-owner ball %s, dummy %s the base%s", r.plot, r.ball_inside and "ENTERED" or "stayed out of", r.dummy_inside and "ENTERED" or "stayed out of", movedNote),
	detail = r,
}
