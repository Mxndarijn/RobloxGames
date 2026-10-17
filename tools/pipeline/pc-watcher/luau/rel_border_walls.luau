-- Server datamodel: release probe R4 (ADVISORY), WorldBorder (visuals/shared/WorldBorder.luau): Map.Border.Walls holds WALL_SEGMENTS (48)
-- invisible anchored CanCollide blocks (Wall1..Wall48) whose inner faces form a closed polygon at RADIUS 292.
-- Checks (ok = every non-nil check true):
--   wall_count        exactly 48 BaseParts under Map.Border.Walls (else every Wall<N> part under Map)
--   all_collide       every segment CanCollide
--   no_gap            walls sorted by bearing; for each adjacent pair the nearest centre-line END points (CFrame * (+-Size.X/2, 0, 0)) are < 2 studs
--                     apart (a character is 2 studs wide); reports count, max gap, offenders
--   walk_blocked      the REAL test player's character (unanchored, server network ownership) starts 8 studs inside the middle of one wall and
--                     MoveTo-s 20 studs past it for 4 s: never gets past the wall's centre line radius
-- The character ends where it started. ~8 s.
local Players = game:GetService("Players")
local ORDER = { "wall_count", "all_collide", "no_gap", "walk_blocked" }
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
local EXPECT, MAX_GAP = 48, 2
local walls = {}
local border = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Border")
local folder = border and border:FindFirstChild("Walls")
if folder then
	for _, w in folder:GetChildren() do
		if w:IsA("BasePart") then
			table.insert(walls, w)
		end
	end
else
	for _, d in (workspace:FindFirstChild("Map") or workspace):GetDescendants() do
		if d:IsA("BasePart") and string.match(d.Name, "^Wall%d+$") and d.Parent and not d.Parent:IsA("Model") then
			table.insert(walls, d)
		end
	end
end
if #walls == 0 then
	return missing("Map.Border.Walls missing / empty")
end
set("wall_count", #walls == EXPECT, { count = #walls, expected = EXPECT, folder = if folder then "Map.Border.Walls" else "Wall<N> search under Map" })
local off = {}
for _, w in walls do
	if not w.CanCollide then
		table.insert(off, w.Name)
	end
end
set("all_collide", #off == 0, { checked = #walls, not_colliding = off })

-- bearing around the map centre; ends along the segment's long axis (the wall's own X axis, length = Size.X)
local function bearing(w)
	return math.atan2(w.Position.X, w.Position.Z)
end
table.sort(walls, function(a, b)
	return bearing(a) < bearing(b)
end)
local function ends(w)
	local h = Vector3.new(w.Size.X / 2, 0, 0)
	local a, b = w.CFrame * h, w.CFrame * -h
	return { Vector3.new(a.X, 0, a.Z), Vector3.new(b.X, 0, b.Z) }
end
local maxGap, offenders = 0, {}
for i, w in walls do
	local nxt = walls[i % #walls + 1]
	local gap = math.huge
	for _, a in ends(w) do
		for _, b in ends(nxt) do
			gap = math.min(gap, (a - b).Magnitude)
		end
	end
	maxGap = math.max(maxGap, gap)
	if gap >= MAX_GAP then
		table.insert(offenders, { a = w.Name, b = nxt.Name, gap = math.round(gap * 100) / 100 })
	end
end
set("no_gap", #offenders == 0 and #walls > 1, { segments = #walls, max_gap = math.round(maxGap * 100) / 100, limit = MAX_GAP, offenders = offenders })

local function run()
	local w = walls[math.max(1, #walls // 2)]
	local out = Vector3.new(w.Position.X, 0, w.Position.Z).Unit
	local wallR = Vector3.new(w.Position.X, 0, w.Position.Z).Magnitude
	local startPos = out * (wallR - 2 - 8)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char, table.unpack(walls) }
	local hit = workspace:Raycast(Vector3.new(startPos.X, 120, startPos.Z), Vector3.new(0, -240, 0), rp)
	local groundY = if hit then hit.Position.Y else 0
	free()
	teleport(CFrame.new(startPos.X, groundY + 3.5, startPos.Z))
	task.wait(0.5)
	local target = out * (wallR + 20)
	local maxR, t0, passed = 0, os.clock(), false
	while os.clock() - t0 < 4 do
		hum:MoveTo(Vector3.new(target.X, root.Position.Y, target.Z))
		task.wait(0.1)
		local r = Vector3.new(root.Position.X, 0, root.Position.Z).Magnitude
		maxR = math.max(maxR, r)
		if r > wallR then
			passed = true
		end
	end
	set("walk_blocked", not passed, { wall = w.Name, wall_radius = wallR, max_radius_reached = maxR, start_radius = wallR - 10 })
end
extraInfo.max_gap = maxGap

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
