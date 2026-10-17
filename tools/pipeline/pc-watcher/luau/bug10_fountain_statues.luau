-- Server datamodel: bug probe 10 (ADVISORY), the slime statues stacked on the fountain top (Map.Volcano.EmergeMesh = slime_fountain_emerge, Hull + CanCollide
-- since #252) are solid: nobody stands inside them and nothing snags on them. The stack's reference box is the MeshPart child "Mesh" (else the slot part),
-- in its own (oriented) frame. The stack parts are CanQuery false (MeshSwap), so the probe sets CanQuery true on them for its raycasts and restores it.
-- Checks (ok = every check true):
--   pushed_out_or_on_top  5 R15 dummies (HumanoidRootPart 8 studs over the box top) and 5 4-stud balls, dropped at the box centre and at +-0.3 of the half
--                         extents, watched 3.5 s: each must end OUTSIDE the bounding box (pushed out) or standing on the stack's top surface (feet within 1 stud
--                         of a downward raycast onto the stack at its x / z); never inside
--   jump_no_snag          2 R15 dummies running at the stack from 10 studs away (MoveTo its centre, Humanoid.Jump every 0.5 s) for 5 s: no run of >= 1 s with
--                         near-zero velocity (< 0.5) while airborne within 3 studs of the box (stuck in the air / wedged on the side)
-- Dummies and balls sit in a collision group that does not collide with itself; everything is destroyed, CanQuery restored. ~8 s.
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local volcano = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Volcano")
local slot = volcano and volcano:FindFirstChild("EmergeMesh")
if not slot then
	return { ok = false, summary = "Map.Volcano.EmergeMesh (fountain statues) missing", detail = {} }
end
local ref = slot:FindFirstChild("Mesh")
if not (ref and ref:IsA("BasePart")) then
	ref = if slot:IsA("BasePart") then slot else nil
end
if not ref then
	return { ok = false, summary = "EmergeMesh has no Mesh / part", detail = {} }
end
local stack = {}
local savedQuery = {}
for _, d in slot:GetDescendants() do
	if d:IsA("BasePart") then
		table.insert(stack, d)
	end
end
if slot:IsA("BasePart") then
	table.insert(stack, slot)
end
for _, p in stack do
	savedQuery[p] = p.CanQuery
	p.CanQuery = true
end
local GROUP = "BugProbe"
pcall(function()
	PhysicsService:RegisterCollisionGroup(GROUP)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
end)
local made = {}
local function track(inst)
	table.insert(made, inst)
	return inst
end
-- character stand-ins: an R15 rig when Roblox can build one, else a two-part Humanoid
local template, rigKind
do
	local done = false
	task.spawn(function()
		local ok, m = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
		if ok and typeof(m) == "Instance" and m:FindFirstChild("HumanoidRootPart") then
			template, rigKind = m, "R15"
		end
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 6 do
		task.wait(0.1)
	end
	if not template then
		local m = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Parent = m
		local head = Instance.new("Part")
		head.Name = "Head"
		head.Size = Vector3.new(2, 1, 1)
		head.Position = Vector3.new(0, 1.5, 0)
		head.Parent = m
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1, w.Parent = root, head, root
		local h = Instance.new("Humanoid")
		h.RigType = Enum.HumanoidRigType.R15
		h.HipHeight = 2.5
		h.Parent = m
		m.PrimaryPart = root
		template, rigKind = m, "2-part fallback"
	end
	track(template)
end
local function dummyAt(pos)
	local m = template:Clone()
	local root = m:FindFirstChild("HumanoidRootPart")
	local hum = m:FindFirstChildOfClass("Humanoid")
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = GROUP
			d.Anchored = false
		end
	end
	m.PrimaryPart = root
	m:PivotTo(CFrame.new(pos))
	m.Parent = workspace
	track(m)
	hum.WalkSpeed = 16
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return m, hum, root, hum.HipHeight + root.Size.Y / 2
end
local half = ref.Size / 2
local function inBox(pos)
	local l = ref.CFrame:PointToObjectSpace(pos)
	return math.abs(l.X) < half.X and math.abs(l.Y) < half.Y and math.abs(l.Z) < half.Z, l
end
local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Include
rp.FilterDescendantsInstances = stack
local checks = {}
local function set(name, ok, info)
	checks[name] = { ok = ok, info = info }
end

local function pushedOrOnTop()
	local offsets = { { 0, 0 }, { 0.3, 0.3 }, { -0.3, 0.3 }, { 0.3, -0.3 }, { -0.3, -0.3 } }
	local items = {}
	for _, o in offsets do
		local top = ref.CFrame * Vector3.new(half.X * o[1], half.Y, half.Z * o[2])
		local _, _, root, feet = dummyAt(top + Vector3.new(0, 8, 0))
		table.insert(items, { kind = "dummy", root = root, feet = feet })
		local ball = Instance.new("Part")
		ball.Shape = Enum.PartType.Ball
		ball.Size = Vector3.new(4, 4, 4)
		ball.Position = top + Vector3.new(0.8, 8, 0.8)
		ball.CollisionGroup = GROUP
		ball.CanTouch = false
		ball.Parent = workspace
		track(ball)
		table.insert(items, { kind = "ball", root = ball, feet = 2 })
	end
	task.wait(3.5)
	local bad, list, outside, onTop = 0, {}, 0, 0
	for _, it in items do
		local pos = it.root.Position
		local inside, l = inBox(pos)
		local hit = workspace:Raycast(pos + Vector3.new(0, 60, 0), Vector3.new(0, -120, 0), rp)
		local feetY = pos.Y - it.feet
		local on = hit ~= nil and math.abs(feetY - hit.Position.Y) <= 1
		if not inside then
			outside += 1
		elseif on then
			onTop += 1
		else
			bad += 1
			if #list < 6 then
				table.insert(list, { kind = it.kind, local_pos = { l.X, l.Y, l.Z }, feet_minus_surface = if hit then feetY - hit.Position.Y else nil })
			end
		end
	end
	set("pushed_out_or_on_top", bad == 0, { items = #items, outside_box = outside, on_top_surface = onTop, inside = bad, inside_list = list, box = { ref.Size.X, ref.Size.Y, ref.Size.Z }, rig = rigKind })
end

local function jumpNoSnag()
	local runs = {}
	local floorY = (ref.CFrame * Vector3.new(0, -half.Y, 0)).Y
	local axes = { ref.CFrame.RightVector, -ref.CFrame.RightVector, ref.CFrame.LookVector, -ref.CFrame.LookVector }
	local ext = { half.X, half.X, half.Z, half.Z }
	for n = 1, 2 do
		local axis = Vector3.new(axes[n * 2 - 1].X, 0, axes[n * 2 - 1].Z).Unit
		local start = ref.Position + axis * (ext[n * 2 - 1] + 10)
		local _, hum, root = dummyAt(Vector3.new(start.X, floorY + 3.6, start.Z))
		table.insert(runs, { hum = hum, root = root, still = 0, worst = 0, last = nil, axis = axis })
	end
	local t0, nextJump = os.clock(), 0
	while os.clock() - t0 < 5 do
		for _, r in runs do
			r.hum:MoveTo(ref.Position)
			if os.clock() > nextJump then
				r.hum.Jump = true
			end
			local pos = r.root.Position
			local _, l = inBox(pos)
			local dx, dz = math.max(math.abs(l.X) - half.X, 0), math.max(math.abs(l.Z) - half.Z, 0)
			local near = math.sqrt(dx * dx + dz * dz) <= 3 and math.abs(l.Y) < half.Y + 3
			local airborne = r.hum.FloorMaterial == Enum.Material.Air
			if near and airborne and r.root.AssemblyLinearVelocity.Magnitude < 0.5 then
				r.still += 0.1
				r.worst = math.max(r.worst, r.still)
			else
				r.still = 0
			end
		end
		if os.clock() > nextJump then
			nextJump = os.clock() + 0.5
		end
		task.wait(0.1)
	end
	local stuck, list = false, {}
	for _, r in runs do
		local inside = inBox(r.root.Position)
		if r.worst >= 1 then
			stuck = true
		end
		table.insert(list, { longest_still_airborne_near_s = r.worst, ended_inside_box = inside })
	end
	set("jump_no_snag", not stuck, { runs = list, rig = rigKind })
end

local jobs = { pushedOrOnTop, jumpNoSnag }
local names = { "pushed_out_or_on_top", "jump_no_snag" }
local pending = #jobs
for n, job in jobs do
	task.spawn(function()
		local ok, err = pcall(job)
		if not ok then
			set(names[n], false, "probe error: " .. tostring(err))
		end
		pending -= 1
	end)
end
local t0 = os.clock()
while pending > 0 and os.clock() - t0 < 16 do
	task.wait(0.1)
end
for _, name in names do
	if not checks[name] then
		set(name, nil, "did not finish in time")
	end
end
for _, inst in made do
	pcall(function()
		inst:Destroy()
	end)
end
for p, q in savedQuery do
	pcall(function()
		p.CanQuery = q
	end)
end
local parts, all, any = {}, true, false
for _, name in names do
	local c = checks[name]
	table.insert(parts, name .. " " .. (if c.ok == true then "PASS" elseif c.ok == false then "FAIL" else "n/a"))
	if c.ok == false then
		all = false
	elseif c.ok == true then
		any = true
	end
end
return {
	ok = if not all then false elseif any then true else nil,
	summary = table.concat(parts, ", "),
	detail = { checks = checks, rig = rigKind },
}
