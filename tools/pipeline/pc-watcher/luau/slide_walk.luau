-- Server datamodel: B6 / bug 9 HARD proof for the fountain slide after #252 made it a solid block (floor slab + a fill 11 studs above the ride line):
-- nobody can enter the ride channel or climb the slide. The HARD result (`ok`, which watcher.py step_shots turns into a failed run) is
-- cannot_enter AND cannot_climb only; the other three checks are notes (`soft_failed`). Merijn's "can't stand on the slide" is cannot_stand_on.
-- Checks (each {ok = bool|nil, info}); the slide is a SOLID block since #252 (floor slab + SlideFill 11 studs above the ride line; slimes ride
-- anchored with CanCollide off), so players must neither enter nor climb it:
--   cannot_enter       4-stud balls (+ a 2 x 5 upright capsule at mid) dropped just above the fill top at start / mid / end of every segment never
--                      end with their centre inside any collider box (the ride channel between floor slab and fill); they sit on the fill or roll off
--   cannot_climb       an R15 dummy at the exit (the mouth) MoveTo-ing up the slide path waypoint by waypoint for 5 s, jumping every 0.6 s, gains
--                      <= 3 studs of height while within 7.5 studs of the path
--   cannot_stand_on    R15 dummies dropped onto the fill top (3 segments) do not stay standing on it (soft: the fill top may be standable; reported)
--   slimes_still_ride  (soft) a wild slime with Riding = true moves >= 3 studs and down >= 0.5 within 6 s; n/a when none rides in the window
--   bottom_reachable   (soft) an R15 dummy from 28 studs out / 14 aside the mouth MoveTo-s to the landing area (4 studs past the mouth): within 2.5 studs
-- Balls / dummies sit in their own collision group that does not collide with itself. Everything made is destroyed. ~8 s, the checks run in parallel.
-- ==== shared slide probe body (identical in slide_walk.luau and bug09_slide_stand.luau; selftest compares them) ====
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local volcano = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Volcano")
local folder = volcano and volcano:FindFirstChild("SlideColliders")
if not folder then
	return { ok = false, error = "Map.Volcano.SlideColliders missing", summary = "Map.Volcano.SlideColliders missing", detail = {} }
end
local layoutMod = RS:FindFirstChild("Visuals") and RS.Visuals:FindFirstChild("WorldLayout")
if not layoutMod then
	return { ok = false, error = "WorldLayout missing", summary = "ReplicatedStorage.Visuals.WorldLayout missing", detail = {} }
end
local floors, fills, boxes = {}, {}, {} -- boxes: every collider part (a centre inside one is inside the slide's solid)
local wedges = {} -- fill index -> { L = wedge, R = wedge } (the roof)
for _, p in folder:GetChildren() do
	if p:IsA("BasePart") then
		table.insert(boxes, p)
		local f = tonumber(string.match(p.Name, "^SlideFloor(%d+)$"))
		local l = tonumber(string.match(p.Name, "^SlideFill(%d+)$"))
		local w, side = string.match(p.Name, "^SlideFill(%d+)([LR])$") -- bug 9 ridge roof: two WedgeParts per fill
		if f then
			floors[f] = p
		end
		if l then
			fills[l] = p
		end
		if w then
			wedges[tonumber(w)] = wedges[tonumber(w)] or {}
			wedges[tonumber(w)][side] = p
		end
	end
end
-- bug 9: the fill is the box (ride line up FILL) with a two-wedge ridge roof ON TOP of it. The probes work on the envelope: the box
-- stretched up to the ridge (same frame, bottom on the ride line), so "top" = the ridge; inSolid / inBox still use the real parts.
for i, pr in wedges do
	local box = fills[i]
	if box and pr.L and pr.R then
		local rise = pr.L.Size.Y
		fills[i] = { CFrame = box.CFrame * CFrame.new(0, rise / 2, 0), Size = box.Size + Vector3.new(0, rise, 0), wedgeRoof = true, box = box }
	end
end
local count = 0
for _ in floors do
	count += 1
end
if count == 0 or not fills[1] then
	return { ok = false, error = "no SlideFloor / SlideFill parts", summary = "no SlideFloor / SlideFill parts", detail = {} }
end
local path = {}
for _, p in require(layoutMod).SLIDE_PATH do
	table.insert(path, Vector3.new(p[1], p[2], p[3]))
end

local GROUP = "SlideProbe"
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
local function inBox(p, pos, grow)
	local l = p.CFrame:PointToObjectSpace(pos)
	local h = p.Size / 2 + Vector3.new(grow, grow, grow)
	if p:IsA("WedgePart") and l.Y / h.Y > l.Z / h.Z then
		return false -- above the wedge's slope: empty
	end
	return math.abs(l.X) < h.X and math.abs(l.Y) < h.Y and math.abs(l.Z) < h.Z
end
local function inSolid(pos)
	for _, p in boxes do
		if inBox(p, pos, 0) then
			return p
		end
	end
	return nil
end
-- horizontal distance to the slide path polyline
local function pathDist(pos)
	local best = math.huge
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local ap = Vector3.new(pos.X - a.X, 0, pos.Z - a.Z)
		local t = if ab.Magnitude > 1e-3 then math.clamp(ap:Dot(ab) / ab:Dot(ab), 0, 1) else 0
		best = math.min(best, (ap - ab * t).Magnitude)
	end
	return best
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
	return m, hum, root
end
local function ballAt(pos, size)
	local b = Instance.new("Part")
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.new(size, size, size)
	b.Position = pos
	b.CollisionGroup = GROUP
	b.CanTouch = false
	b.Transparency = 0.6
	b.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.4, 0, 1, 1)
	b.Parent = workspace
	return track(b)
end
local function groundAt(pos, from)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = made
	local hit = workspace:Raycast(Vector3.new(pos.X, from, pos.Z), Vector3.new(0, -from - 20, 0), rp)
	return hit and hit.Position.Y
end

local checks = {}
local function set(name, ok, info)
	checks[name] = { ok = ok, info = info }
end
local lastFloor = floors[count]
local fwd = lastFloor.CFrame.LookVector
local out = Vector3.new(fwd.X, 0, fwd.Z).Unit -- the slide's direction at the mouth (away from the fountain)
local side = Vector3.new(-out.Z, 0, out.X)
local mouth = lastFloor.Position + fwd * (lastFloor.Size.Z / 2)

-- a) balls dropped from just above the fill never rest inside the ride channel ------------------------------------------------------------
local function cannotEnter()
	local list = {}
	for i = 1, count do
		local fill = fills[i]
		if fill then
			for _, k in { 0.1, 0.5, 0.9 } do
				local top = fill.CFrame * Vector3.new(0, fill.Size.Y / 2, (0.5 - k) * fill.Size.Z)
				local at = top + Vector3.new(0, 3, 0)
				if inSolid(at) then
					continue -- another lap / joint block: not a clean drop point
				end
				table.insert(list, { part = ballAt(at, 4), seg = i, k = k, shape = "ball" })
				if k == 0.5 then
					local cyl = Instance.new("Part") -- 2 x 5 upright capsule-ish body
					cyl.Shape = Enum.PartType.Cylinder
					cyl.Size = Vector3.new(5, 2, 2)
					cyl.CFrame = CFrame.new(top + Vector3.new(0.7, 4.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
					cyl.CollisionGroup = GROUP
					cyl.CanTouch = false
					cyl.Transparency = 0.6
					cyl.Parent = workspace
					track(cyl)
					if inSolid(cyl.Position) then
						cyl:Destroy()
					else
						table.insert(list, { part = cyl, seg = i, k = k, shape = "capsule" })
					end
				end
			end
		end
	end
	task.wait(3)
	local inside, below, onTop, off = {}, 0, 0, 0
	for _, e in list do
		local pos = e.part.Position
		local solid = inSolid(pos)
		if solid then
			table.insert(inside, string.format("seg %d k=%.1f %s inside %s", e.seg, e.k, e.shape, solid.Name))
		elseif pos.Y < -1 then
			below += 1
		elseif fills[e.seg] and fills[e.seg].CFrame:PointToObjectSpace(pos).Y > fills[e.seg].Size.Y / 2
			and math.abs(fills[e.seg].CFrame:PointToObjectSpace(pos).X) < fills[e.seg].Size.X / 2 then
			onTop += 1 -- above the fill top plane and within its width: resting on the fill
		else
			off += 1
		end
	end
	set("cannot_enter", #inside == 0, {
		dropped = #list, inside_channel = #inside, inside_list = { table.unpack(inside, 1, math.min(#inside, 6)) },
		rest_on_top = onTop, rolled_off = off, fell_to_void = below,
	})
end

-- b) a dummy at the exit walking up the slide gains no height along it ---------------------------------------------------------------------
local function cannotClimb()
	local g = groundAt(mouth + out * 8, mouth.Y + 30) or mouth.Y
	local _, hum, root = dummyAt(Vector3.new(mouth.X, g + 3.2, mouth.Z) + out * 8)
	task.wait(0.6)
	local startY = root.Position.Y
	local gain, wp, t0, nextJump = 0, #path - 1, os.clock(), 0
	local seen, airGain = 0, 0
	while os.clock() - t0 < 5 and root.Parent do
		local target = path[math.max(wp, 1)]
		hum:MoveTo(Vector3.new(target.X, startY, target.Z))
		if os.clock() > nextJump then
			hum.Jump = true
			nextJump = os.clock() + 0.6
		end
		task.wait(0.1)
		local pos = root.Position
		if pathDist(pos) <= 7.5 then
			seen += 1
			-- only GROUNDED height counts: a jump apex (~7 studs for R15) is not climbing
			if hum.FloorMaterial ~= Enum.Material.Air then
				gain = math.max(gain, pos.Y - startY)
			else
				airGain = math.max(airGain, pos.Y - startY)
			end
		end
		if Vector3.new(pos.X - target.X, 0, pos.Z - target.Z).Magnitude < 3 and wp > 1 then
			wp -= 1
		end
	end
	set("cannot_climb", gain <= 3, { max_gain_along_slide = gain, max_jump_apex = airGain, start_y = startY, waypoint_reached = #path - 1 - wp, samples_near_slide = seen, rig = rigKind })
end

-- c) dummies dropped on top of the fill do not stay standing there -------------------------------------------------------------------------
local function cannotStandOn()
	local picks, drops = {}, {}
	for _, frac in { 0.25, 0.5, 0.75 } do
		local i = math.max(1, math.floor(frac * count))
		local fill = fills[i]
		if fill then
			local top = fill.CFrame * Vector3.new(0, fill.Size.Y / 2, 0)
			local at = top + Vector3.new(0, 3.6, 0)
			if not inSolid(at) and not inSolid(at + Vector3.new(0, 3, 0)) then
				table.insert(picks, i)
				local _, hum, root = dummyAt(at)
				table.insert(drops, { seg = i, hum = hum, root = root })
			end
		end
	end
	task.wait(3.5)
	local standing, list = 0, {}
	for _, d in drops do
		local pos = d.root.Position
		local fill = fills[d.seg]
		local l = fill.CFrame:PointToObjectSpace(pos)
		local above = l.Y - fill.Size.Y / 2
		local over = math.abs(l.X) < fill.Size.X / 2 + 0.5 and math.abs(l.Z) < fill.Size.Z / 2 + 0.5
		local on = over and above > 1.5 and above < 5 and d.root.AssemblyLinearVelocity.Magnitude < 2
		if on then
			standing += 1
		end
		table.insert(list, { seg = d.seg, standing_on_top = on, above_top = above, over_footprint = over })
	end
	if #drops == 0 then
		set("cannot_stand_on", nil, "no clean drop point above any fill")
	else
		set("cannot_stand_on", standing == 0, {
			dropped = #drops, standing_on_top = standing, drops = list,
			note = if standing > 0 then "the fill top (11 studs above the ride line) is standable: nothing in the colliders prevents it" else nil,
		})
	end
end

-- d) slimes still ride the slide ---------------------------------------------------------------------------------------------------------
local function slimesRide()
	local wild = workspace:FindFirstChild("WildSlimes")
	local seen = {}
	local t0 = os.clock()
	while os.clock() - t0 < 6 do
		if wild then
			for _, m in wild:GetChildren() do
				if m:IsA("Model") and m:GetAttribute("Riding") == true then
					local pos = m:GetPivot().Position
					local s = seen[m]
					if not s then
						seen[m] = { first = pos, last = pos, samples = 1 }
					else
						s.last = pos
						s.samples += 1
					end
				end
			end
		end
		task.wait(0.2)
	end
	local riding, progressed, best = 0, 0, 0
	for _, s in seen do
		riding += 1
		local d = (s.last - s.first).Magnitude
		best = math.max(best, d)
		if d >= 3 and s.last.Y < s.first.Y - 0.5 then
			progressed += 1
		end
	end
	if riding == 0 then
		set("slimes_still_ride", nil, "no wild slime had Riding = true in the 6 s window")
	else
		set("slimes_still_ride", progressed > 0, { riding_seen = riding, progressed_down = progressed, best_displacement = best })
	end
end

-- e) the slide exit can be reached from the plaza ------------------------------------------------------------------------------------------
local function bottomReachable()
	local landing = mouth + out * 4
	local startXZ = mouth + out * 28 + side * 14
	local g0 = groundAt(startXZ, mouth.Y + 30) or mouth.Y
	local _, hum, root = dummyAt(Vector3.new(startXZ.X, g0 + 3.2, startXZ.Z))
	task.wait(0.5)
	local target = Vector3.new(landing.X, root.Position.Y, landing.Z)
	local t0, best = os.clock(), math.huge
	while os.clock() - t0 < 6 and root.Parent do
		hum:MoveTo(target)
		task.wait(0.1)
		local d = Vector3.new(root.Position.X - landing.X, 0, root.Position.Z - landing.Z).Magnitude
		best = math.min(best, d)
		if d <= 2.5 then
			break
		end
	end
	set("bottom_reachable", best <= 2.5, { closest = if best == math.huge then nil else best, start_distance = (startXZ - landing).Magnitude, landing = { landing.X, landing.Y, landing.Z } })
end

local jobs = { cannotEnter, cannotClimb, cannotStandOn, slimesRide, bottomReachable }
local names = { "cannot_enter", "cannot_climb", "cannot_stand_on", "slimes_still_ride", "bottom_reachable" }
local pending = #jobs
for n, job in jobs do
	task.spawn(function()
		local ok, err = pcall(job)
		if not ok then
			set(names[n], nil, "probe error: " .. tostring(err))
		end
		pending -= 1
	end)
end
local t0 = os.clock()
while pending > 0 and os.clock() - t0 < 16 do
	task.wait(0.1)
end
for n, name in names do
	if not checks[name] then
		set(name, nil, "did not finish in time")
	end
end
for _, inst in made do
	pcall(function()
		inst:Destroy()
	end)
end
local parts = {}
for _, name in names do
	local c = checks[name]
	table.insert(parts, name .. " " .. (if c.ok == true then "PASS" elseif c.ok == false then "FAIL" else "n/a"))
end
local summary = table.concat(parts, ", ")
-- ==== end of shared body ====
local HttpService = game:GetService("HttpService")
local violations, soft = {}, {}
for _, name in names do
	local c = checks[name]
	if c.ok == false then
		local okJ, j = pcall(HttpService.JSONEncode, HttpService, c.info)
		local line = name .. ": " .. (if okJ then j else tostring(c.info))
		table.insert(if name == "cannot_enter" or name == "cannot_climb" then violations else soft, line)
	end
end
return {
	ok = #violations == 0,
	summary = summary,
	violations = violations,
	soft_failed = soft,
	detail = { checks = checks, rig = rigKind, segments = count },
}
