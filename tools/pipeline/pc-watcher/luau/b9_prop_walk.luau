-- Server datamodel (play): bug B9 probe (ADVISORY), "every object uses its own collision box": players cannot walk through or stand inside any
-- prop. DATA-DRIVEN: the prop list is ReplicatedStorage.Shared.PropCollision.ENTRIES (the inventory; docs/COLLISION.md "B9"), so a new entry
-- there is probed with no edit to this file. Each entry is located with PropCollision.matches (find.under / mesh / names / parts), the same matcher
-- tests/PropCollision.spec uses against the booted world. Nothing in the world is changed; every dummy and probe part is destroyed.
-- Checks per kind (instances capped at MAX_PER_KIND = 2, every kind covered first):
--   static   (every instance of a kind that is not "off")
--     collidable   at least one CanCollide part (the instance's own parts, plus find.also for the fountain tower's colliders)
--     fidelity     a MeshPart with the entry's fidelity (Box / Hull / Default / PreciseConvexDecomposition) and CanCollide on
--     spawns       HubSpawn (every SpawnLocation) and every plot spawn (Base centre + 4) stand clear of its solids (feet, waist, head)
--     placement    no other Jolt / ambiguous prop's slot centre lies inside its solids (two props overlapping)
--   walk     an R15 dummy at WalkSpeed 16 from 4 sides (+-X, +-Z of the prop's frame; 4 studs outside the solids' bounding box) MoveTo-s a point just
--            past the far edge, i.e. through the centre. FAIL when the dummy's core (a 0.8-stud ball at the root) ever overlaps the prop's real collision
--            geometry (GetPartsInPart on its solids) = it is INSIDE, or, for the simple (Box / Hull / hand collider) kinds, when it ends past the
--            centre inside the footprint's width at ground level = it passed THROUGH. Round props deflecting the dummy ("around"), standing it on a
--            flat top ("on_top") or blocking it ("blocked") are PASS. A start spot that is not open ground inside the wall ring is n/a.
-- "off" entries are listed, not walked. HARD = Jolt-owned, or a Gojo entry that is already collidable; ambiguous / Gojo-off are reported only.
-- ok = no hard FAIL and at least one PASS. Result: { ok, summary, detail = { kinds = {kind = {status, owner, ...}}, pass, fail, na, off, hard_fail, soft_fail,
-- not_run, seconds } }; the summary names the failing kinds. ~45 s: the walks run in parallel (WIDTH dummies at once), a 38 s budget stops new walks.
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local Shared = RS:FindFirstChild("Shared")
local module = Shared and Shared:FindFirstChild("PropCollision")
if not module then
	return { ok = false, summary = "ReplicatedStorage.Shared.PropCollision missing", detail = {} }
end
local Config = require(Shared.Config)
local PropCollision = require(module)

local MAX_PER_KIND = 2
local WIDTH = 40 -- dummies walking at once
local BUDGET = 38 -- seconds of walking before the rest is "not run"
local GAP = 4 -- studs from the solids' box to the start spot
local GROUP = "B9PropWalk"
pcall(function()
	PhysicsService:RegisterCollisionGroup(GROUP)
end)
pcall(function()
	PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
end)

local made = {}
local function track(i)
	table.insert(made, i)
	return i
end
local t0all = os.clock()
local function r1(x)
	return math.floor(x * 10 + 0.5) / 10
end

-- the instances and solids of every entry --------------------------------------------------------------------------------------------------------
local function relPath(d)
	local full = d:GetFullName()
	return (full:gsub("^Workspace%.?", ""))
end
local function isDummy(d)
	return d:FindFirstAncestor("B9Dummy") ~= nil
end
local function solidsOf(inst)
	local out = {}
	if inst:IsA("BasePart") and inst.CanCollide then
		table.insert(out, inst)
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide then
			table.insert(out, d)
		end
	end
	return out
end

local descendants = workspace:GetDescendants()
local function locate(find)
	local out = {}
	for _, d in descendants do
		if
			d.Parent
			and (d:IsA("BasePart") or d:IsA("Model") or d:IsA("Folder"))
			and not (d:IsA("MeshPart") and d.Name == "Mesh")
		then
			local a = d:GetAttribute("MeshAsset")
			if
				PropCollision.matches(
					find,
					relPath(d),
					d.Name,
					if type(a) == "string" then a else nil,
					d:IsA("BasePart")
				) and not isDummy(d)
			then
				table.insert(out, d)
			end
		end
	end
	return out
end

local kinds = {} -- ordered: { entry, instances, extra (solids of find.also), status, notes }
local byKind = {}
for _, e in PropCollision.ENTRIES do
	local rec = { entry = e, instances = {}, extra = {}, fails = {}, passes = 0, notes = {}, nas = {} }
	if e.find then
		rec.instances = locate(e.find)
		if e.also then
			for _, inst in locate(e.also) do
				for _, p in solidsOf(inst) do
					table.insert(rec.extra, p)
				end
			end
		end
	end
	table.insert(kinds, rec)
	byKind[e.kind] = rec
end
local function hard(e)
	return e.owner == "jolt" or (e.owner == "gojo" and e.collision ~= "off")
end
local function fail(rec, what)
	table.insert(rec.fails, what)
end

-- static checks ------------------------------------------------------------------------------------------------------------------------------------
local FLOORS = { ground_and_hub_spawn = true, plot_base = true, plot_pads = true, terrain = true }
local blockers, centres = {}, {}
for _, rec in kinds do
	local e = rec.entry
	if e.collision ~= "off" then
		for _, inst in rec.instances do
			local own = solidsOf(inst)
			local mesh = if inst:IsA("MeshPart")
				then inst
				else inst:FindFirstChild("Mesh") or inst:FindFirstChild("VatMesh")
			if #own + #rec.extra == 0 then
				fail(rec, "no collidable part: " .. relPath(inst))
			end
			if PropCollision.FIDELITIES[e.collision] then
				if
					not (
						mesh
						and mesh:IsA("MeshPart")
						and mesh.CanCollide
						and mesh.CollisionFidelity.Name == e.collision
					)
				then
					fail(
						rec,
						("%s: not a CanCollide %s MeshPart (%s)"):format(
							relPath(inst),
							e.collision,
							mesh and mesh:IsA("MeshPart") and mesh.CollisionFidelity.Name or "no mesh"
						)
					)
				end
			end
			if not FLOORS[e.kind] then
				for _, p in own do
					table.insert(blockers, { kind = e.kind, inst = inst, part = p })
				end
				if inst:IsA("BasePart") and e.owner ~= "gojo" and e.walk ~= false then
					table.insert(centres, { kind = e.kind, inst = inst, pos = inst.Position })
				end
			end
		end
		if not FLOORS[e.kind] then
			for _, p in rec.extra do
				table.insert(blockers, { kind = e.kind, inst = false, part = p })
			end
		end
	end
end
local function inside(part, pos)
	local p = part.CFrame:PointToObjectSpace(pos)
	local h = part.Size / 2
	return math.abs(p.X) <= h.X and math.abs(p.Y) <= h.Y and math.abs(p.Z) <= h.Z
end
local spawns = {}
for _, d in descendants do
	if d:IsA("SpawnLocation") then
		table.insert(spawns, { name = relPath(d), pos = d.Position + Vector3.new(0, 3, 0) })
	end
end
local plots = workspace:FindFirstChild("Plots")
if plots then
	for _, plot in plots:GetChildren() do
		local base = plot:FindFirstChild("Base")
		if base and base:IsA("BasePart") then
			table.insert(
				spawns,
				{ name = plot.Name .. " spawn", pos = base.Position + Vector3.new(0, base.Size.Y / 2 + 4, 0) }
			)
		end
	end
end
for _, s in spawns do
	for _, b in blockers do
		for _, y in { 0.5, 3, 5.5 } do
			if inside(b.part, Vector3.new(s.pos.X, y, s.pos.Z)) then
				fail(byKind[b.kind], s.name .. " stands inside " .. relPath(b.part))
				break
			end
		end
	end
end
for _, c in centres do
	for _, b in blockers do
		if
			b.kind ~= c.kind
			and b.inst ~= c.inst
			and not (b.inst and (c.inst:IsDescendantOf(b.inst) or b.inst:IsDescendantOf(c.inst)))
			and inside(b.part, Vector3.new(c.pos.X, math.max(c.pos.Y, 0.5), c.pos.Z))
		then
			fail(
				byKind[c.kind],
				"placement centre of " .. relPath(c.inst) .. " is inside " .. relPath(b.part) .. " (" .. b.kind .. ")"
			)
			break
		end
	end
end

-- R15 stand-in -----------------------------------------------------------------------------------------------------------------------------------------
local template
do
	local done = false
	task.spawn(function()
		local ok, m = pcall(function()
			return Players:CreateHumanoidModelFromDescription(
				Instance.new("HumanoidDescription"),
				Enum.HumanoidRigType.R15
			)
		end)
		if ok and typeof(m) == "Instance" and m:FindFirstChild("HumanoidRootPart") then
			template = m
		end
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 6 do
		task.wait(0.1)
	end
end
local rigKind = if template then "R15" else "2-part fallback"
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
	template = m
end
track(template)

-- walk jobs ----------------------------------------------------------------------------------------------------------------------------------------------
local wallRadius = 285 -- starts beyond the border wall ring (r 292) are not open ground
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundAt(x, z)
	local ignore = {}
	for _, d in made do
		table.insert(ignore, d)
	end
	rayParams.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(Vector3.new(x, 90, z), Vector3.new(0, -120, 0), rayParams)
	return hit and hit.Position.Y, hit and hit.Instance
end

-- frame (centre x/z, yaw, half extents, top y) of an instance's solids
local function frameOf(inst, list)
	local cf
	if inst:IsA("BasePart") then
		cf = inst.CFrame
	elseif inst:IsA("Model") then
		cf = inst:GetPivot()
	else
		cf = CFrame.new(list[1].Position)
	end
	local z = -cf.LookVector
	local yaw = math.atan2(z.X, z.Z)
	local base = CFrame.new(cf.Position) * CFrame.Angles(0, yaw, 0)
	local minX, maxX, minZ, maxZ, minY, maxY = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	for _, p in list do
		local h = p.Size / 2
		for _, sx in { -1, 1 } do
			for _, sy in { -1, 1 } do
				for _, sz in { -1, 1 } do
					local q =
						base:PointToObjectSpace(p.CFrame:PointToWorldSpace(Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)))
					minX, maxX = math.min(minX, q.X), math.max(maxX, q.X)
					minZ, maxZ = math.min(minZ, q.Z), math.max(maxZ, q.Z)
					minY, maxY = math.min(minY, q.Y), math.max(maxY, q.Y)
				end
			end
		end
	end
	local centre = base:PointToWorldSpace(Vector3.new((minX + maxX) / 2, 0, (minZ + maxZ) / 2))
	return {
		cx = centre.X,
		cz = centre.Z,
		yaw = yaw,
		hx = (maxX - minX) / 2,
		hz = (maxZ - minZ) / 2,
		top = cf.Position.Y + maxY,
		bottom = cf.Position.Y + minY,
	}
end

local jobs = {}
local order = {}
for _, rec in kinds do
	table.insert(order, rec)
end
local rank = { jolt = 1, ambiguous = 2, gojo = 3 }
table.sort(order, function(a, b)
	local ra, rb = rank[a.entry.owner], rank[b.entry.owner]
	if ra ~= rb then
		return ra < rb
	end
	return false
end)
for pass = 1, MAX_PER_KIND do
	for _, rec in order do
		local e = rec.entry
		local inst = rec.instances[pass]
		if inst and e.collision ~= "off" and e.walk ~= false and e.find then
			local list = solidsOf(inst)
			for _, p in rec.extra do
				table.insert(list, p)
			end
			local fr = if #list > 0 then frameOf(inst, list) else nil
			if fr and fr.bottom > 3 then
				rec.elevated = true -- hovers above a walker's reach (the stacked slimes on the fountain top): static checks only
			elseif fr then
				for _, side in PropCollision.sides(fr.cx, fr.cz, fr.yaw, fr.hx, fr.hz, GAP) do
					table.insert(jobs, { rec = rec, inst = inst, solids = list, frame = fr, side = side })
				end
			end
		end
	end
end

local GROUND_OK = 2.5 -- the start must stand on ground, not on a roof
local function walk(job)
	local rec, fr, side = job.rec, job.frame, job.side
	local e = rec.entry
	local label = ("%s %s"):format(relPath(job.inst), side.name)
	local sx, sz = side.start[1], side.start[2]
	if math.sqrt(sx * sx + sz * sz) > wallRadius then
		table.insert(rec.nas, label .. ": start outside the wall ring")
		return
	end
	local gy, gpart = groundAt(sx, sz)
	if not gy or gy > GROUND_OK then
		table.insert(rec.nas, label .. ": start not on open ground")
		return
	end
	local overlap = OverlapParams.new()
	overlap.FilterType = Enum.RaycastFilterType.Exclude
	overlap.FilterDescendantsInstances = made
	for _, hit in workspace:GetPartBoundsInBox(CFrame.new(sx, gy + 3.5, sz), Vector3.new(3, 5, 3), overlap) do
		if hit.CanCollide and hit ~= gpart and not hit:IsA("Terrain") then
			table.insert(rec.nas, label .. ": start blocked by " .. relPath(hit))
			return
		end
	end
	local m = template:Clone()
	local root = m:FindFirstChild("HumanoidRootPart")
	local hum = m:FindFirstChildOfClass("Humanoid")
	m.Name = "B9Dummy"
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = GROUP
			d.Anchored = false
		end
	end
	m.PrimaryPart = root
	m:PivotTo(CFrame.new(sx, gy + 3.2, sz))
	m.Parent = workspace
	track(m)
	hum.WalkSpeed = 16
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local tx, tz = side.target[1], side.target[2]
	local dist = math.sqrt((tx - sx) ^ 2 + (tz - sz) ^ 2)
	local limit = math.min(dist / 16 + 1.5, 6)
	local solidsParams = OverlapParams.new()
	solidsParams.FilterType = Enum.RaycastFilterType.Include
	solidsParams.FilterDescendantsInstances = job.solids
	local core = Instance.new("Part")
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(0.8, 0.8, 0.8)
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.CanTouch = false
	core.Transparency = 1
	core.Parent = workspace
	track(core)
	local through, still = false, 0
	local t0 = os.clock()
	hum:MoveTo(Vector3.new(tx, gy, tz))
	while os.clock() - t0 < limit do
		task.wait(0.1)
		if not root.Parent then
			break
		end
		core.Position = root.Position
		if #workspace:GetPartsInPart(core, solidsParams) > 0 then
			through = true
			break
		end
		local v = root.AssemblyLinearVelocity
		if math.sqrt(v.X * v.X + v.Z * v.Z) < 1 and os.clock() - t0 > 0.9 then
			still += 1
			if still >= 4 then
				break
			end
		else
			still = 0
		end
		if (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(tx, 0, tz)).Magnitude < 2 then
			break
		end
	end
	local p = root.Position
	local dx, dz = p.X - fr.cx, p.Z - fr.cz
	local along = dx * side.dir[1] + dz * side.dir[2]
	local lateral = math.abs(dx * -side.dir[2] + dz * side.dir[1])
	local halfLateral = if math.abs(side.dir[1] * math.cos(fr.yaw) - side.dir[2] * math.sin(fr.yaw)) > 0.5
		then fr.hz
		else fr.hx
	local feet = p.Y - 3
	local tall = fr.top - gy >= 1.5 -- lower than a step (half-sunk boulders): walked over, only "inside" counts
	local onTop = tall and feet >= fr.top - 0.5
	local simple = tall and e.collision ~= "PreciseConvexDecomposition" and e.kind ~= "fountain_tower"
	local outcome
	if through then
		outcome = "inside"
	elseif simple and along > 0.5 and lateral < halfLateral - 0.5 and not onTop then
		outcome = "through"
	elseif onTop then
		outcome = "on_top"
	elseif along > 0.5 then
		outcome = "around"
	else
		outcome = "blocked"
	end
	if outcome == "inside" or outcome == "through" then
		fail(
			rec,
			("%s: %s (along %s, lateral %s of %s)"):format(label, outcome, r1(along), r1(lateral), r1(halfLateral))
		)
	else
		rec.passes += 1
		rec.notes[outcome] = (rec.notes[outcome] or 0) + 1
	end
	m:Destroy()
end

local active, notRun = 0, 0
local cursor = 0
local done = 0
local total = #jobs
local function launch()
	while cursor < total and active < WIDTH do
		cursor += 1
		local job = jobs[cursor]
		if os.clock() - t0all > BUDGET then
			job.rec.skipped = (job.rec.skipped or 0) + 1
			notRun += 1
			done += 1
		else
			active += 1
			task.spawn(function()
				local ok, err = pcall(walk, job)
				if not ok then
					table.insert(
						job.rec.nas,
						relPath(job.inst) .. " " .. job.side.name .. ": " .. tostring(err):sub(1, 80)
					)
				end
				active -= 1
				done += 1
			end)
		end
	end
end
local tWalk = os.clock()
while done < total and os.clock() - t0all < BUDGET + 12 do
	launch()
	task.wait(0.1)
end

-- result -----------------------------------------------------------------------------------------------------------------------------------------------------
for _, d in made do
	pcall(function()
		d:Destroy()
	end)
end
for _, d in workspace:GetChildren() do
	if d.Name == "B9Dummy" then
		pcall(function()
			d:Destroy()
		end)
	end
end
local out, passN, failN, naN, offN, hardFail, softFail = {}, 0, 0, 0, 0, {}, {}
for _, rec in kinds do
	local e = rec.entry
	local status
	if e.collision == "off" then
		status = "off"
		offN += 1
	elseif #rec.fails > 0 then
		status = "FAIL"
		failN += 1
		table.insert(if hard(e) then hardFail else softFail, e.kind)
	elseif
		(#rec.instances > 0 or e.find == nil) and (rec.passes > 0 or e.walk == false or e.find == nil or rec.elevated)
	then
		status = "PASS"
		passN += 1
	else
		status = "n/a"
		naN += 1
	end
	out[e.kind] = {
		status = status,
		owner = e.owner,
		collision = e.collision,
		hard = hard(e),
		instances = #rec.instances,
		walks_passed = rec.passes,
		outcomes = rec.notes,
		fails = rec.fails,
		na = rec.nas,
		not_run = rec.skipped,
	}
end
local parts = {
	("%d kinds: %d PASS, %d FAIL, %d n/a, %d off"):format(#kinds, passN, failN, naN, offN),
	("walks %d (%d not run), %s, %ss"):format(total, notRun, rigKind, r1(os.clock() - t0all)),
}
if #hardFail > 0 then
	table.insert(parts, "HARD fail: " .. table.concat(hardFail, ", "))
end
if #softFail > 0 then
	table.insert(parts, "soft fail: " .. table.concat(softFail, ", "))
end
return {
	ok = #hardFail == 0 and passN > 0,
	summary = table.concat(parts, "; "),
	detail = {
		kinds = out,
		pass = passN,
		fail = failN,
		na = naN,
		off = offN,
		hard_fail = hardFail,
		soft_fail = softFail,
		walks = total,
		not_run = notRun,
		rig = rigKind,
		walk_seconds = r1(os.clock() - tWalk),
		seconds = r1(os.clock() - t0all),
		flags = { WorldShops = Config.FEATURES.WorldShops },
	},
}
