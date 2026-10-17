-- Server datamodel: release probe R2 (ADVISORY), the fountain top after the slime stack became solid (#264/#273): the REAL test player's
-- character (unanchored, server network ownership) is put on the fountain top and walks (Humanoid:MoveTo) a full circle around the
-- EmergeMesh Box, then to the slide entry (WorldLayout.SLIDE_PATH[1]).
-- The walkway ring is centred on the fountain TOP (xz centroid of the top surface from a coarse raycast grid, fallback the FountainMesh slot xz)
-- with 24 azimuths; per azimuth the radius is scanned from the outside inward (0.5 studs): the outermost point with fountain surface and
-- >= 2 studs margin to the rim edge (surface at +-2 studs in x and z) that is >= 2 studs outside the Box (character radius) starts the walkway
-- span (rOuter), the contiguous run of such valid samples inward ends at rInner; the waypoint is the middle of the span (not the rim edge).
-- No valid point = "no_walkway" with a reason (off_top / box_reaches_rim); a span narrower than 3 studs = "no_walkway" / "narrow".
-- Between waypoints, if the chord midpoint has no surface margin the route steps via that midpoint snapped to its own azimuth's span. Consecutive walkway waypoints are walked in azimuth order; at a gap the route never
-- cuts a chord: the gap (sector angles) is reported and the character is teleported to the first waypoint of the next contiguous run.
-- The Volcano colliders are CanQuery false, so the probe sets CanQuery true on the collidable ones for its raycasts and restores it.
-- Checks (ok = every non-nil check true):
--   circle_complete   n/a with < 6 walkway waypoints; else true when every walkway waypoint is reached (within 3 studs horizontally, MoveTo
--                     3 s each), never fell off (root 6+ below the walkway) and no gap is box_reaches_rim (surface exists but the Box/an obstruction
--                     leaves no clearance = the walkway is blocked: a real finding); off_top and narrow gaps are only reported (info.gaps)
--   reaches_slide     from the walkway waypoint nearest the slide entry: MoveTo the entry, within 3 studs horizontally within 8 s; the surface y at
--                     the entry vs the character y is recorded (stopped on top of something)
-- Per-waypoint results are in detail.extra.waypoints. The character ends where it started. Waypoints past ~20 s are "not_run". ~30 s max.
local Players = game:GetService("Players")
local ORDER = { "circle_complete", "reaches_slide" }
local checks = {}
local function set(name, ok, info)
	checks[name] = { ok = ok, info = info }
end
local function finish(extra)
	local parts, all, any = {}, true, false
	for _, name in ORDER do
		local c = checks[name] or { ok = nil, info = "not run" }
		checks[name] = c
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
		detail = { checks = checks, extra = extra },
	}
end
local function missing(msg)
	return { ok = false, summary = msg, detail = { checks = checks } }
end

local player = Players:GetPlayers()[1]
if not player then
	return finish("no real Player in the server")
end
-- character: the REAL test player's, unanchored with server network ownership for the probe and restored at the end -------------------
local char, hum, root = player.Character, nil, nil
hum = char and char:FindFirstChildOfClass("Humanoid")
root = char and char:FindFirstChild("HumanoidRootPart")
if not (root and hum) then
	return finish("the test player has no character")
end
local startCF = root.CFrame
local startAnchored = {}
for _, d in char:GetDescendants() do
	if d:IsA("BasePart") then
		startAnchored[d] = d.Anchored
	end
end
local startSpeed = hum.WalkSpeed
local function free()
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	hum.WalkSpeed = 16
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
end
local function teleport(cf)
	char:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end
local made = {}
local undo = {} -- functions that restore what the probe touched
local extraInfo = {}
local RS = game:GetService("ReplicatedStorage")
local volcano = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Volcano")
local slot = volcano and volcano:FindFirstChild("EmergeMesh")
local ref = slot and (slot:FindFirstChild("Mesh") or slot)
if not (ref and ref:IsA("BasePart")) then
	return missing("Map.Volcano.EmergeMesh (fountain statues) missing")
end
local layoutMod = RS:FindFirstChild("Visuals") and RS.Visuals:FindFirstChild("WorldLayout")
local slideEntry
if layoutMod then
	local okL, layout = pcall(require, layoutMod)
	local p = okL and layout.SLIDE_PATH and layout.SLIDE_PATH[1]
	slideEntry = p and Vector3.new(p[1], p[2], p[3])
end
local topParts = {}
for _, d in volcano:GetDescendants() do
	if d:IsA("BasePart") and d.CanCollide and not d:IsDescendantOf(slot) and d ~= slot then
		table.insert(topParts, d)
		local q = d.CanQuery
		d.CanQuery = true
		table.insert(undo, function()
			d.CanQuery = q
		end)
	end
end
local rp = RaycastParams.new()
rp.FilterType = Enum.RaycastFilterType.Include
rp.FilterDescendantsInstances = topParts
local half = ref.Size / 2
local boxBottom = (ref.CFrame * Vector3.new(0, -half.Y, 0)).Y
local function surfaceAt(x, z)
	local hit = workspace:Raycast(Vector3.new(x, boxBottom + 30, z), Vector3.new(0, -60, 0), rp)
	if hit and math.abs(hit.Position.Y - boxBottom) <= 8 then
		return hit.Position.Y
	end
	return nil
end
local function v3(v)
	return { math.round(v.X * 10) / 10, math.round(v.Y * 10) / 10, math.round(v.Z * 10) / 10 }
end
local function flat(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local N, MARGIN, CLEAR = 24, 2, 2
-- fountain top centre: xz centroid of the surface hits of a coarse grid over the FountainMesh footprint
local fountain = volcano:FindFirstChild("FountainMesh", true)
local fcf, fsize
if fountain and fountain:IsA("BasePart") then
	fcf, fsize = fountain.CFrame, fountain.Size
elseif fountain and fountain:IsA("Model") then
	fcf, fsize = fountain:GetBoundingBox()
end
local gridC = if fcf then fcf.Position else ref.Position
local gridH = if fsize then Vector3.new(fsize.X, 0, fsize.Z) / 2 else Vector3.new(30, 0, 30)
local sx, sz, sn = 0, 0, 0
for gx = -gridH.X, gridH.X, 3 do
	for gz = -gridH.Z, gridH.Z, 3 do
		local x, z = gridC.X + gx, gridC.Z + gz
		if surfaceAt(x, z) then
			sx, sz, sn = sx + x, sz + z, sn + 1
		end
	end
end
local centre = if sn > 0 then Vector3.new(sx / sn, boxBottom, sz / sn) else Vector3.new(gridC.X, boxBottom, gridC.Z)
extraInfo.centre = v3(centre)
extraInfo.centre_source = if sn > 0
	then ("surface centroid of " .. sn .. " grid hits")
	else "FountainMesh / slot xz (no surface hit)"
extraInfo.slide_entry = slideEntry and v3(slideEntry)
local function withMargin(x, z)
	local y = surfaceAt(x, z)
	if not y then
		return nil
	end
	for _, d in { { MARGIN, 0 }, { -MARGIN, 0 }, { 0, MARGIN }, { 0, -MARGIN } } do
		if not surfaceAt(x + d[1], z + d[2]) then
			return nil
		end
	end
	return y
end
local function clearOfBox(p)
	local l = ref.CFrame:PointToObjectSpace(p)
	return not (math.abs(l.X) < half.X + CLEAR and math.abs(l.Z) < half.Z + CLEAR and math.abs(l.Y) < half.Y + 1)
end
-- walkway span at azimuth a: the outermost valid sample (surface with MARGIN around it AND clear of the Box) and the contiguous run of valid
-- samples inward from it; the waypoint is the middle of that run (not the rim edge)
local function spanAt(a)
	local run, sawBlocked = {}, false
	for r = 40, 1, -0.5 do
		local x, z = centre.X + math.cos(a) * r, centre.Z + math.sin(a) * r
		local y = withMargin(x, z)
		if y and clearOfBox(Vector3.new(x, y + 3, z)) then
			table.insert(run, { r = r, x = x, y = y, z = z })
		elseif #run > 0 then
			break
		elseif y then
			sawBlocked = true
		end
	end
	if #run == 0 then
		return nil, sawBlocked
	end
	local rOuter, rInner = run[1].r, run[#run].r
	local rMid = (rInner + rOuter) / 2
	local x, z = centre.X + math.cos(a) * rMid, centre.Z + math.sin(a) * rMid
	local y = withMargin(x, z)
	local pick = { r = rMid, x = x, y = y, z = z }
	if not (y and clearOfBox(Vector3.new(x, y + 3, z))) then
		pick = run[1]
		for _, smp in run do
			if math.abs(smp.r - rMid) < math.abs(pick.r - rMid) then
				pick = smp
			end
		end
	end
	return { x = pick.x, y = pick.y, z = pick.z, r = pick.r, rInner = rInner, rOuter = rOuter, width = rOuter - rInner }, sawBlocked
end
local waypoints = {}
for i = 0, N - 1 do
	local a = i * 2 * math.pi / N
	local wp = { i = i + 1, az = i * 360 / N }
	local sp, sawBlocked = spanAt(a)
	if sp then
		wp.rInner, wp.rOuter, wp.width = sp.rInner, sp.rOuter, sp.width
		if sp.width < 3 then
			wp.status, wp.reason = "no_walkway", "narrow"
		else
			wp.x, wp.y, wp.z, wp.r = sp.x, sp.y, sp.z, sp.r
		end
	else
		wp.status = "no_walkway"
		wp.reason = if sawBlocked then "box_reaches_rim" else "off_top"
	end
	table.insert(waypoints, wp)
end
-- contiguous runs in azimuth order (cyclic); the order starts right after a gap so no run is split
local startIdx = 1
for i = 1, N do
	if waypoints[i].status and not waypoints[i % N + 1].status then
		startIdx = i % N + 1
		break
	end
end
local order, gaps, walkable = {}, {}, 0
for k = 0, N - 1 do
	local wp = waypoints[(startIdx - 1 + k) % N + 1]
	if not wp.status then
		walkable += 1
		wp.run_start = k == 0 or waypoints[(startIdx - 1 + k - 1) % N + 1].status ~= nil
		table.insert(order, wp)
	end
end
do
	local cur
	for k = 0, N - 1 do
		local wp = waypoints[(startIdx - 1 + k) % N + 1]
		if wp.status then
			if not cur then
				cur = { from_deg = wp.az, to_deg = wp.az, reasons = {} }
				table.insert(gaps, cur)
			end
			cur.to_deg = wp.az
			cur.reasons[wp.reason] = true
		else
			cur = nil
		end
	end
	for _, g in gaps do
		local list = {}
		for k in g.reasons do
			table.insert(list, k)
		end
		table.sort(list)
		g.reasons = table.concat(list, "+")
		g.box_reaches_rim = string.find(g.reasons, "box_reaches_rim", 1, true) ~= nil
	end
end
extraInfo.gaps = gaps
extraInfo.walkable = walkable
local function out()
	local list = {}
	for _, wp in waypoints do
		table.insert(list, {
			i = wp.i,
			az = wp.az,
			status = wp.status or "?",
			reason = wp.reason,
			r = wp.r and (math.round(wp.r * 10) / 10),
			r_inner = wp.rInner and (math.round(wp.rInner * 10) / 10),
			r_outer = wp.rOuter and (math.round(wp.rOuter * 10) / 10),
			width = wp.width and (math.round(wp.width * 10) / 10),
			at = wp.x and v3(Vector3.new(wp.x, wp.y, wp.z)),
			stopped_at = wp.stopped_at,
		})
	end
	return list
end
local function run()
	if walkable == 0 then
		set("circle_complete", nil, "no walkway waypoint around the Box (all off the top or box-blocked)")
		set("reaches_slide", nil, "no walkway waypoint to start from")
		extraInfo.waypoints = out()
		return
	end
	free()
	local t0, reached, fell, blockedWps = os.clock(), 0, false, 0
	local lastGood, prev
	for _, wp in order do
		if os.clock() - t0 > 20 then
			wp.status = "not_run"
			continue
		end
		local target = Vector3.new(wp.x, wp.y, wp.z)
		if wp.run_start then
			-- first waypoint of a contiguous run: teleport (no chord across a gap)
			teleport(CFrame.new(wp.x, wp.y + 3.5, wp.z))
			task.wait(if lastGood then 0.3 else 0.5)
		elseif prev then
			-- follow the curve: when the straight chord's midpoint has no surface margin, step via that midpoint snapped to its azimuth's walkway
			local mid = (Vector3.new(prev.x, 0, prev.z) + Vector3.new(wp.x, 0, wp.z)) / 2
			if not withMargin(mid.X, mid.Z) then
				local sp = spanAt(math.atan2(mid.Z - centre.Z, mid.X - centre.X))
				if sp then
					local via = Vector3.new(sp.x, sp.y, sp.z)
					local tv = os.clock()
					while os.clock() - tv < 2 do
						hum:MoveTo(via)
						task.wait(0.1)
						if flat(root.Position, via) <= 3 or root.Position.Y < sp.y - 6 then
							break
						end
					end
				end
			end
		end
		prev = wp
		local t1 = os.clock()
		while os.clock() - t1 < 3 do
			hum:MoveTo(target)
			task.wait(0.1)
			if flat(root.Position, target) <= 3 or root.Position.Y < wp.y - 6 then
				break
			end
		end
		local p = root.Position
		if p.Y < wp.y - 6 then
			fell = true
			wp.status, wp.stopped_at = "fell_off", v3(p)
			teleport(CFrame.new((lastGood or target + Vector3.new(0, 3, 0)) + Vector3.new(0, 1, 0)))
		elseif flat(p, target) <= 3 then
			wp.status, reached, lastGood = "reached", reached + 1, p
		else
			wp.status, wp.stopped_at = "blocked", v3(p)
			blockedWps += 1
		end
	end
	extraInfo.waypoints = out()
	local rimGap = false
	for _, g in gaps do
		rimGap = rimGap or g.box_reaches_rim
	end
	if walkable < 6 then
		set("circle_complete", nil, { walkable = walkable, note = "fewer than 6 walkway waypoints", gaps = #gaps })
	else
		set("circle_complete", reached == walkable and not fell and not rimGap, {
			walkable = walkable,
			reached = reached,
			blocked = blockedWps,
			fell_off = fell,
			gaps = #gaps,
			box_reaches_rim_gap = rimGap,
			elapsed = math.round((os.clock() - t0) * 10) / 10,
		})
	end
	if not slideEntry then
		set("reaches_slide", nil, "WorldLayout.SLIDE_PATH missing")
		return
	end
	local near
	for _, wp in order do
		if
			not near
			or flat(Vector3.new(wp.x, 0, wp.z), slideEntry) < flat(Vector3.new(near.x, 0, near.z), slideEntry)
		then
			near = wp
		end
	end
	teleport(CFrame.new(near.x, near.y + 3.5, near.z))
	task.wait(0.4)
	local t2 = os.clock()
	while os.clock() - t2 < 8 and flat(root.Position, slideEntry) > 3 do
		hum:MoveTo(slideEntry)
		task.wait(0.1)
	end
	local hit =
		workspace:Raycast(Vector3.new(slideEntry.X, slideEntry.Y + 30, slideEntry.Z), Vector3.new(0, -60, 0), rp)
	local dist = flat(root.Position, slideEntry)
	set("reaches_slide", dist <= 3, {
		from_waypoint = near.i,
		stopped_at = v3(root.Position),
		entry = v3(slideEntry),
		distance = math.round(dist * 10) / 10,
		surface_y_at_entry = hit and (math.round(hit.Position.Y * 10) / 10),
		surface_part = hit and hit.Instance.Name,
		char_y = math.round(root.Position.Y * 10) / 10,
		note = "char_y - surface_y_at_entry ~ 3 = standing on that surface; entry.y is the slide path start",
	})
end

local ok, err = pcall(run)
for _, o in made do
	pcall(function()
		o:Destroy()
	end)
end
for _, fn in undo do
	pcall(fn)
end
pcall(function()
	hum:MoveTo(root.Position)
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	char:PivotTo(startCF)
	root.AssemblyLinearVelocity = Vector3.zero
	hum.WalkSpeed = startSpeed
	pcall(function()
		root:SetNetworkOwnershipAuto()
	end)
	for d, a in startAnchored do
		d.Anchored = a
	end
end)
if not ok then
	for _, name in ORDER do
		if not checks[name] then
			set(name, false, "probe error: " .. tostring(err))
		end
	end
	return finish("probe error: " .. tostring(err))
end
return finish(extraInfo)
