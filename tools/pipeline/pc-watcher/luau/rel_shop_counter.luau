-- Server datamodel: release probe R5 (ADVISORY), the in-world shop stands (#269 / #276): the counter of ItemShopStand / UpgradeShopStand
-- (fallback ShopStand for the item shop while FEATURES.WorldShops is off) is solid (MeshAssets.COLLISION ranch_shop_stand = Hull).
-- The stand's box = the union of its CanCollide parts in the stand's pivot frame; its front = the pivot's +-Z side nearer the map centre.
-- The REAL test player's character (unanchored, server network ownership) is placed 8 studs in front and:
--   *_blocked   MoveTo-s the box centre for 3 s: its root is never inside the box (0.3 shrink) and never behind it (past the far face)
--   *_jump      then MoveTo + Humanoid.Jump repeatedly for 3 s: ends standing on the counter top or in front of it, never inside the box,
--               and never "stuck" (speed < 0.5 for >= 1 s while inside the box)
-- Per stand: box size, front direction, minimum distance to the box centre, end position. The character ends where it started. ~16 s.
local Players = game:GetService("Players")
local ORDER = { "item_blocked", "item_jump", "upgrade_blocked", "upgrade_jump" }
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
local function v3(v)
	return { math.round(v.X * 10) / 10, math.round(v.Y * 10) / 10, math.round(v.Z * 10) / 10 }
end
local function boxOf(stand)
	local pivot = stand:GetPivot()
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	local n, collide = 0, {}
	for _, d in stand:GetDescendants() do
		if d:IsA("BasePart") and d.CanCollide then
			table.insert(collide, d)
		end
	end
	if #collide == 0 then
		for _, d in stand:GetDescendants() do
			if d:IsA("BasePart") then
				table.insert(collide, d)
			end
		end
	end
	for _, d in collide do
		local h = d.Size / 2
		for sx = -1, 1, 2 do
			for sy = -1, 1, 2 do
				for sz = -1, 1, 2 do
					local l = pivot:PointToObjectSpace(d.CFrame * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
					lo, hi = lo:Min(l), hi:Max(l)
				end
			end
		end
		n += 1
	end
	if n == 0 then
		return nil
	end
	return pivot, lo, hi, n
end

local function testStand(prefix, stand)
	local pivot, lo, hi, nParts = boxOf(stand)
	if not pivot then
		set(prefix .. "_blocked", nil, "stand has no parts")
		set(prefix .. "_jump", nil, "stand has no parts")
		return
	end
	local centre = (lo + hi) / 2
	local half = (hi - lo) / 2
	local function toLocal(p)
		return pivot:PointToObjectSpace(p) - centre
	end
	local function insideBox(l, shrink)
		return math.abs(l.X) < half.X - shrink and math.abs(l.Z) < half.Z - shrink and l.Y > -half.Y and l.Y < half.Y
	end
	-- front = the local +-Z side nearer the map centre
	local fPlus = pivot:PointToWorldSpace(centre + Vector3.new(0, 0, half.Z + 8))
	local fMinus = pivot:PointToWorldSpace(centre + Vector3.new(0, 0, -half.Z - 8))
	local sign = if Vector3.new(fPlus.X, 0, fPlus.Z).Magnitude <= Vector3.new(fMinus.X, 0, fMinus.Z).Magnitude then 1 else -1
	local startPos = pivot:PointToWorldSpace(centre + Vector3.new(0, 0, sign * (half.Z + 8)))
	local target = pivot:PointToWorldSpace(centre)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { char, stand }
	local hit = workspace:Raycast(startPos + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0), rp)
	local groundY = if hit then hit.Position.Y else target.Y - half.Y
	local feetOff = hum.HipHeight + root.Size.Y / 2
	local function place()
		free()
		teleport(CFrame.new(startPos.X, groundY + feetOff + 0.2, startPos.Z))
		task.wait(0.4)
	end
	local info = { box = v3(half * 2), parts = nParts, front_sign = sign }

	-- walk into the counter front
	place()
	local t0, minDist, entered, behind = os.clock(), math.huge, false, false
	while os.clock() - t0 < 3 do
		hum:MoveTo(Vector3.new(target.X, root.Position.Y, target.Z))
		task.wait(0.05)
		local l = toLocal(root.Position)
		minDist = math.min(minDist, Vector3.new(l.X, 0, l.Z).Magnitude)
		if insideBox(l, 0.3) then
			entered = true
		end
		if l.Z * sign < -(half.Z + 0.5) then
			behind = true
		end
	end
	info.min_distance_to_centre = minDist
	info.ended_at = v3(root.Position)
	info.entered_box, info.got_behind = entered, behind
	set(prefix .. "_blocked", not entered and not behind, info)

	-- jump at it
	place()
	local t1, still, worst, nextJump = os.clock(), 0, 0, 0
	while os.clock() - t1 < 3 do
		hum:MoveTo(Vector3.new(target.X, root.Position.Y, target.Z))
		if os.clock() >= nextJump then
			hum.Jump = true
			nextJump = os.clock() + 0.6
		end
		task.wait(0.1)
		local l = toLocal(root.Position)
		if insideBox(l, 0.3) and root.AssemblyLinearVelocity.Magnitude < 0.5 then
			still += 0.1
			worst = math.max(worst, still)
		else
			still = 0
		end
	end
	task.wait(0.4)
	local l = toLocal(root.Position)
	local endedInside = insideBox(l, 0.3)
	local onTop = not endedInside and math.abs(l.X) <= half.X and math.abs(l.Z) <= half.Z and l.Y >= half.Y
	set(prefix .. "_jump", not endedInside and worst < 1, {
		ended_at = v3(root.Position), ended_inside = endedInside, on_top = onTop,
		in_front = not endedInside and not onTop, longest_still_inside_s = worst,
	})
end

local function standOf(name)
	return workspace:FindFirstChild(name, true)
end
local itemStand = standOf("ItemShopStand") or standOf("ShopStand")
local upgradeStand = standOf("UpgradeShopStand")
if not (itemStand or upgradeStand) then
	return missing("no ItemShopStand / UpgradeShopStand / ShopStand in the world")
end
extraInfo.item_stand = itemStand and itemStand:GetFullName()
extraInfo.upgrade_stand = upgradeStand and upgradeStand:GetFullName()
local function run()
	if itemStand then
		testStand("item", itemStand)
	end
	if upgradeStand then
		testStand("upgrade", upgradeStand)
	end
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
