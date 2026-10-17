-- Server datamodel: release probe R2 (ADVISORY), the fountain top after the slime stack became solid (#264/#273): the REAL test player's
-- character (unanchored, server network ownership) is put on the fountain top and walks (Humanoid:MoveTo) a full circle around the
-- EmergeMesh Box, then to the slide entry (WorldLayout.SLIDE_PATH[1]).
-- The walkway circle is centred on the Box (xz) with radius = half the Box diagonal + 1.5, 12 waypoints; a waypoint with no fountain
-- surface within 8 studs of the Box bottom (off the top) is "off_walkway" and skipped, one inside the Box is "inside_box" and skipped.
-- The Volcano colliders are CanQuery false, so the probe sets CanQuery true on the collidable ones for its raycasts and restores it.
-- Checks (ok = every non-nil check true):
--   circle_complete   >= 6 walkway waypoints, every one reached within 3 studs (horizontal) within 3 s, never fell off (root 6+ below the walkway)
--   reaches_slide     MoveTo the slide entry: within 3 studs horizontally within 8 s
-- Per-waypoint reached / blocked positions are in detail.extra.waypoints. The character ends where it started. ~35 s.
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
local function insideBox(p)
	local l = ref.CFrame:PointToObjectSpace(p)
	return math.abs(l.X) < half.X + 1 and math.abs(l.Z) < half.Z + 1 and math.abs(l.Y) < half.Y + 1
end
local function v3(v)
	return { math.round(v.X * 10) / 10, math.round(v.Y * 10) / 10, math.round(v.Z * 10) / 10 }
end
local radius = math.sqrt(half.X ^ 2 + half.Z ^ 2) + 1.5
local centre = ref.Position
local waypoints = {}
for i = 0, 11 do
	local a = i * math.pi / 6
	local x, z = centre.X + math.cos(a) * radius, centre.Z + math.sin(a) * radius
	local y = surfaceAt(x, z)
	local wp = { i = i + 1, x = x, z = z, y = y }
	if not y then
		wp.status = "off_walkway"
	elseif insideBox(Vector3.new(x, y + 3, z)) then
		wp.status = "inside_box"
	end
	table.insert(waypoints, wp)
end
extraInfo.radius = radius
extraInfo.centre = v3(centre)
extraInfo.slide_entry = slideEntry and v3(slideEntry)

local function flat(a, b)
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end
local function run()
	local first
	for _, wp in waypoints do
		if not wp.status then
			first = wp
			break
		end
	end
	if not first then
		set("circle_complete", nil, "no walkway waypoint around the Box (all off the top or inside it)")
		extraInfo.waypoints = waypoints
		return
	end
	free()
	teleport(CFrame.new(first.x, first.y + 3.5, first.z))
	task.wait(0.5)
	local t0, lastGood, walkable, reached, fell = os.clock(), Vector3.new(first.x, first.y + 3.5, first.z), 0, 0, false
	for _, wp in waypoints do
		if wp.status then
			continue
		end
		walkable += 1
		if os.clock() - t0 > 22 then
			wp.status = "not_run"
			continue
		end
		local target = Vector3.new(wp.x, wp.y, wp.z)
		local t1 = os.clock()
		while os.clock() - t1 < 3 do
			hum:MoveTo(target)
			task.wait(0.1)
			if flat(root.Position, target) <= 3 then
				break
			end
			if root.Position.Y < wp.y - 6 then
				break
			end
		end
		local p = root.Position
		if p.Y < wp.y - 6 then
			fell = true
			wp.status, wp.stopped_at = "fell_off", v3(p)
			teleport(CFrame.new(lastGood + Vector3.new(0, 1, 0)))
		elseif flat(p, target) <= 3 then
			wp.status, reached, lastGood = "reached", reached + 1, p
		else
			wp.status, wp.stopped_at = "blocked", v3(p)
		end
		wp.x, wp.z, wp.y = math.round(wp.x * 10) / 10, math.round(wp.z * 10) / 10, math.round(wp.y * 10) / 10
	end
	extraInfo.waypoints = waypoints
	if walkable < 6 then
		set("circle_complete", nil, { walkable = walkable, note = "fewer than 6 walkway waypoints" })
	else
		set("circle_complete", reached == walkable and not fell, { walkable = walkable, reached = reached, fell_off = fell })
	end
	if not slideEntry then
		set("reaches_slide", nil, "WorldLayout.SLIDE_PATH missing")
		return
	end
	local t2 = os.clock()
	while os.clock() - t2 < 8 and flat(root.Position, slideEntry) > 3 do
		hum:MoveTo(slideEntry)
		task.wait(0.1)
	end
	set("reaches_slide", flat(root.Position, slideEntry) <= 3, { stopped_at = v3(root.Position), entry = v3(slideEntry), distance = flat(root.Position, slideEntry) })
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
