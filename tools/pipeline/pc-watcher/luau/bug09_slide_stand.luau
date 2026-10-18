-- Server datamodel: B6 / bug 9 HARD proof for the walkable fountain slide: a player walks up the trough from the mouth to the head and
-- cannot get into it from the side. The HARD result (`ok`, which watcher.py step_shots turns into a failed run) is can_climb AND
-- cannot_enter_from_side only; the other three checks are notes (`soft_failed`).
-- The slide colliders (Map.Volcano.SlideColliders, shared/SlideColliders) are a SlideFloor<i> slab per segment i -> i + 1 of
-- WorldLayout.SLIDE_PATH with its top on the ride line, SlideJoint<i> fillers on the bends, SlideRail<i>L / R low walls (inner face on the
-- trough edge, top 3 studs over the ride line) and SlideSkirt<i> down to the ground on the low stretch; slimes ride anchored with
-- CanCollide off, so walkers and riders pass through each other.
-- Checks (each {ok = bool|nil, info}):
--   can_climb               an R15 dummy 4 studs past the mouth MoveTo-s the SLIDE_PATH waypoints mouth -> head (no jumping, 25 s, a stall of
--                           4 s ends it): it must reach one of the top 4 waypoints standing on the ramp (root 0.5..5.5 studs over the ride line,
--                           within the trough) and gain >= 75 % of the slide's height
--   cannot_enter_from_side  a 2-stud ball held at its height (LinearVelocity, 16 studs/s) is pushed sideways at every segment's middle from
--                           both sides, 1.5 over the ride line; its centre never gets past the rail's inner face. On the low stretch (floor
--                           top <= 4 studs over the ground) R15 dummies walk across the slide from both sides for 3 s and never stand in the
--                           trough. A ball start that overlaps other geometry (silo staves, the slide mesh) is skipped and counted
--   stays_on                (soft) R15 dummies set on the floor at 30 / 50 / 70 % of the slide stand 3 s: still on the ramp (0.5..5.5 over the
--                           ride line, within the trough) and moved < 3 studs (nothing slides or moves them off)
--   slimes_still_ride       (soft) a wild slime with Riding = true moves >= 3 studs and down >= 0.5 within 6 s; n/a when none rides in the window
--   bottom_reachable        (soft) an R15 dummy from 28 studs out / 14 aside the mouth MoveTo-s to the landing area (4 studs past the mouth):
--                           within 2.5 studs
-- Balls / dummies sit in their own collision group that does not collide with itself. Everything made is destroyed. ~30 s, the checks run
-- in parallel.
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
local floors, rails = {}, {} -- segment index -> floor slab; segment index -> { L = rail, R = rail }
local count, railCount, lo, hi = 0, 0, math.huge, 0
for _, p in folder:GetChildren() do
	if p:IsA("BasePart") then
		local f = tonumber(string.match(p.Name, "^SlideFloor(%d+)$"))
		local r = tonumber(string.match(p.Name, "^SlideRail(%d+)[LR]$"))
		if f then
			floors[f] = p
			count += 1
			lo, hi = math.min(lo, f), math.max(hi, f)
		end
		if r then
			rails[r] = rails[r] or {}
			rails[r][string.sub(p.Name, -1)] = p
			railCount += 1
		end
	end
end
if count == 0 then
	return { ok = false, error = "no SlideFloor parts", summary = "no SlideFloor parts", detail = {} }
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
-- The ride line under / over `pos`: per segment the horizontal projection, kept only when pos is -4..8 studs over that segment's ride
-- height (the spiral's laps share x / z). Returns horizontal distance, height over the ride line and the segment, or math.huge.
local function rideAt(pos)
	local best, bestH, bestSeg = math.huge, nil, nil
	for i = 1, #path - 1 do
		local a, b = path[i], path[i + 1]
		local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
		local ap = Vector3.new(pos.X - a.X, 0, pos.Z - a.Z)
		local t = if ab.Magnitude > 1e-3 then math.clamp(ap:Dot(ab) / ab:Dot(ab), 0, 1) else 0
		local h = pos.Y - (a.Y + (b.Y - a.Y) * t)
		local d = (ap - ab * t).Magnitude
		if h > -4 and h < 8 and d < best then
			best, bestH, bestSeg = d, h, i
		end
	end
	return best, bestH, bestSeg
end
-- Trough half-width (inner rail face) of segment i's floor slab: the slab reaches the rail's outer face.
local function halfOf(i)
	local floor = floors[i]
	local rail = rails[i] and (rails[i].L or rails[i].R)
	return floor.Size.X / 2 - (if rail then rail.Size.X else 0.8)
end
-- Standing on the ramp: within the trough and the root 0.5..5.5 studs over the ride line.
local function onRamp(pos)
	local d, h, seg = rideAt(pos)
	local half = if seg and floors[seg] then halfOf(seg) else 4.2
	return d < half + 0.3 and h ~= nil and h > 0.5 and h < 5.5, d, h
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
local function groundAt(pos, from)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = made
	local hit = workspace:Raycast(Vector3.new(pos.X, from, pos.Z), Vector3.new(0, -from - 20, 0), rp)
	return hit and hit.Position.Y
end
-- A 2-stud ball at `pos` driven at 16 studs/s along `dir` with its height held; nil when its start overlaps other geometry.
local function pushedBall(pos, dir)
	local b = Instance.new("Part")
	b.Shape = Enum.PartType.Ball
	b.Size = Vector3.new(2, 2, 2)
	b.Position = pos
	b.Anchored = true
	b.CollisionGroup = GROUP
	b.CanTouch = false
	b.Transparency = 0.6
	b.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.4, 0, 1, 1)
	b.Parent = workspace
	track(b)
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = made
	for _, hit in workspace:GetPartsInPart(b, op) do
		if hit.CanCollide then
			b:Destroy()
			return nil
		end
	end
	local a = Instance.new("Attachment")
	a.Parent = b
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = a
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = dir * 16
	lv.MaxForce = b:GetMass() * 400
	lv.Parent = b
	b.Anchored = false
	pcall(function()
		b:SetNetworkOwner(nil)
	end)
	return b
end

local checks = {}
local function set(name, ok, info)
	checks[name] = { ok = ok, info = info }
end
local lastFloor = floors[hi]
local fwd = lastFloor.CFrame.LookVector
local out = Vector3.new(fwd.X, 0, fwd.Z).Unit -- the slide's direction at the mouth (away from the fountain)
local side = Vector3.new(-out.Z, 0, out.X)
local mouth = path[#path]

-- a) a dummy past the mouth walks up the ramp to the head -------------------------------------------------------------------------------
local function canClimb()
	local startXZ = mouth + out * 4
	local g = groundAt(startXZ, mouth.Y + 30) or (mouth.Y - 0.7)
	local _, hum, root = dummyAt(Vector3.new(startXZ.X, g + 3.2, startXZ.Z))
	task.wait(0.6)
	local startY = root.Position.Y
	local wp, topWp, maxY, rampSamples = #path, #path + 1, startY, 0
	local t0 = os.clock()
	local lastProgress, stuckAt = t0, nil
	while os.clock() - t0 < 25 and root.Parent do
		local target = path[wp]
		hum:MoveTo(target)
		task.wait(0.1)
		local pos = root.Position
		local on = onRamp(pos)
		if on then
			rampSamples += 1
			maxY = math.max(maxY, pos.Y)
		end
		local flat = Vector3.new(pos.X - target.X, 0, pos.Z - target.Z)
		local passed = false
		if wp > 1 then
			local ahead = path[wp - 1] - target
			passed = flat:Dot(Vector3.new(ahead.X, 0, ahead.Z)) > 0
		end
		if flat.Magnitude < 2.5 or passed then
			if on then
				topWp = math.min(topWp, wp)
			end
			if wp == 1 then
				break
			end
			wp -= 1
			lastProgress = os.clock()
		elseif os.clock() - lastProgress > 4 then
			stuckAt = wp
			break
		end
	end
	local _, finalD, finalH = onRamp(root.Position)
	local need = path[1].Y - path[#path].Y
	local gain = maxY - startY
	set("can_climb", topWp <= 4 and gain >= 0.75 * need, {
		top_waypoint = if topWp <= #path then topWp else nil, waypoints = #path, gain = gain, slide_height = need,
		stuck_at_waypoint = stuckAt, ramp_samples = rampSamples, seconds = os.clock() - t0,
		final_off_centre = if finalD == math.huge then nil else finalD, final_over_ride = finalH, rig = rigKind,
	})
end

-- b) nothing gets into the trough from the side -----------------------------------------------------------------------------------------
local function cannotEnterFromSide()
	local balls, walkers, skipped = {}, {}, 0
	for i = lo, hi do
		local floor = floors[i]
		if floor then
			local right = floor.CFrame.RightVector
			for _, s in { -1, 1 } do
				local at = floor.CFrame * Vector3.new(s * (floor.Size.X / 2 + 2.5), floor.Size.Y / 2 + 1.5, 0)
				local b = pushedBall(at, -s * right)
				if b then
					table.insert(balls, { part = b, seg = i, s = s, deepest = math.huge })
				else
					skipped += 1
				end
			end
		end
	end
	for i = hi - 1, lo, -1 do -- low stretch walkers, the mouth segment left out (its open end is the way in)
		if #walkers >= 8 then
			break
		end
		local floor = floors[i]
		if floor then
			local top = floor.CFrame * Vector3.new(0, floor.Size.Y / 2, 0)
			local right = floor.CFrame.RightVector
			local starts = {}
			for _, s in { -1, 1 } do
				local xz = top + right * s * (floor.Size.X / 2 + 4)
				local g = groundAt(xz, top.Y + 30)
				if g and top.Y - g <= 4 then
					table.insert(starts, { xz = xz, g = g, s = s })
				end
			end
			for _, st in starts do
				local _, hum, root = dummyAt(Vector3.new(st.xz.X, st.g + 3.2, st.xz.Z))
				table.insert(walkers, { hum = hum, root = root, seg = i, s = st.s, goal = top - right * st.s * (floor.Size.X / 2 + 4), inside = false })
			end
		end
	end
	local t0 = os.clock()
	while os.clock() - t0 < 3 do
		for _, w in walkers do
			w.hum:MoveTo(w.goal)
		end
		task.wait(0.1)
		for _, e in balls do
			if e.part.Parent then
				local l = floors[e.seg].CFrame:PointToObjectSpace(e.part.Position)
				e.deepest = math.min(e.deepest, l.X * e.s) -- signed: > 0 on the start side
			end
		end
		for _, w in walkers do
			local floor = floors[w.seg]
			local l = floor.CFrame:PointToObjectSpace(w.root.Position)
			if math.abs(l.X) < halfOf(w.seg) - 0.2 and l.Y > floor.Size.Y / 2 - 0.5 then
				w.inside = true
			end
		end
	end
	local entered = {}
	for _, e in balls do
		if e.deepest < halfOf(e.seg) then
			table.insert(entered, string.format("seg %d %s ball %.1f from the centre (rail inner face %.1f)", e.seg, if e.s < 0 then "L" else "R", e.deepest, halfOf(e.seg)))
		end
	end
	for _, w in walkers do
		if w.inside then
			table.insert(entered, string.format("seg %d %s walker stood in the trough", w.seg, if w.s < 0 then "L" else "R"))
		end
	end
	if #balls == 0 and #walkers == 0 then
		set("cannot_enter_from_side", nil, { note = "no clear start point beside any segment", skipped = skipped, rails = railCount })
	else
		set("cannot_enter_from_side", #entered == 0, {
			balls = #balls, walkers = #walkers, skipped_overlap = skipped, rails = railCount, entered = #entered,
			entered_list = { table.unpack(entered, 1, math.min(#entered, 6)) },
		})
	end
end

-- c) a dummy standing on the ramp stays there ------------------------------------------------------------------------------------------
local function staysOn()
	local drops = {}
	for _, frac in { 0.3, 0.5, 0.7 } do
		local i = lo + math.floor(frac * (hi - lo))
		local floor = floors[i]
		if floor then
			local top = floor.CFrame * Vector3.new(0, floor.Size.Y / 2, 0)
			local _, _, root = dummyAt(top + Vector3.new(0, 3.2, 0))
			table.insert(drops, { seg = i, root = root, start = top })
		end
	end
	task.wait(3)
	local stayed, list = 0, {}
	for _, d in drops do
		local pos = d.root.Position
		local on, dist, h = onRamp(pos)
		local moved = Vector3.new(pos.X - d.start.X, 0, pos.Z - d.start.Z).Magnitude
		local ok = on and moved < 3
		if ok then
			stayed += 1
		end
		table.insert(list, { seg = d.seg, on_ramp = on, moved = moved, off_centre = if dist == math.huge then nil else dist, over_ride = h })
	end
	if #drops == 0 then
		set("stays_on", nil, "no floor slab to stand on")
	else
		set("stays_on", stayed == #drops, { placed = #drops, stayed = stayed, drops = list })
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

local jobs = { canClimb, cannotEnterFromSide, staysOn, slimesRide, bottomReachable }
local names = { "can_climb", "cannot_enter_from_side", "stays_on", "slimes_still_ride", "bottom_reachable" }
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
while pending > 0 and os.clock() - t0 < 32 do
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
		table.insert(if name == "can_climb" or name == "cannot_enter_from_side" then violations else soft, line)
	end
end
return {
	ok = #violations == 0,
	summary = summary,
	violations = violations,
	soft_failed = soft,
	detail = { checks = checks, rig = rigKind, segments = count, rails = railCount },
}
