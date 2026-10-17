-- Server datamodel: bug 9 follow-up proof (ADVISORY), nobody stays on top of the slide fill. The fill is a ridge roof of two WedgeParts
-- (SlideFill<i>L / SlideFill<i>R, faces >= 60 deg, friction 0; server/FountainColliders) plus a backstop (server/SlideTopWatch) that moves a
-- character who stays on the roof for 0.3 s to the ground beside the slide.
--   roof_shape   every SlideFill wedge pair is steep (atan(height / width) >= 59.9 deg) and frictionless; counts the pairs
--   dropped      the local player's character is put 4 studs above the ridge of a mid-slide segment (and again over a joint fill when
--                one exists); within 5 s its root must be beside the segment (|across| >= half width) or past its ends; the character is
--                put back where it was afterwards. n/a when nobody is in the game.
-- ok = no FAIL. Everything is restored.
local Players = game:GetService("Players")
local volcano = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Volcano")
local folder = volcano and volcano:FindFirstChild("SlideColliders")
if not folder then
	return { ok = false, summary = "Map.Volcano.SlideColliders missing", detail = {} }
end
local pairs_ = {} -- name stem -> { L = wedge, R = wedge }
local pairCount, steepest, flattest, grippy = 0, 0, 90, 0
for _, p in folder:GetChildren() do
	local stem, side = string.match(p.Name, "^(Slide%a*Fill%d+)([LR])$")
	if stem and p:IsA("WedgePart") then
		pairs_[stem] = pairs_[stem] or {}
		pairs_[stem][side] = p
		local angle = math.deg(math.atan2(p.Size.Y, p.Size.Z))
		steepest, flattest = math.max(steepest, angle), math.min(flattest, angle)
		local friction = p.CustomPhysicalProperties and p.CustomPhysicalProperties.Friction or 1
		if friction > 0 then
			grippy += 1
		end
	end
end
for _, pr in pairs_ do
	if pr.L and pr.R then
		pairCount += 1
	end
end
local checks = {}
checks.roof_shape = {
	ok = if pairCount == 0 then nil else (flattest >= 59.9 and grippy == 0),
	info = { fills = pairCount, steepest_deg = steepest, flattest_deg = flattest, wedges_with_friction = grippy },
}

local player = Players:GetPlayers()[1]
local character = player and player.Character
local root = character and character:FindFirstChild("HumanoidRootPart")
local function dropOn(stem)
	local pr = pairs_[stem]
	if not (pr and pr.L and pr.R) then
		return { ok = nil, info = stem .. " missing" }
	end
	local cf = pr.L.CFrame -- Z = right (toward the centreline from the left), Y = up, X = forward
	local height, half = pr.L.Size.Y, pr.L.Size.Z
	local mid = (pr.L.Position + pr.R.Position) / 2
	local apex = mid + cf.YVector * (height / 2)
	local home = character:GetPivot()
	character:PivotTo(CFrame.new(apex + Vector3.new(0, 4, 0)))
	root.AssemblyLinearVelocity = Vector3.zero
	local t0, off, across, along = os.clock(), false, 0, 0
	while os.clock() - t0 < 5 and root.Parent do
		task.wait(0.2)
		local d = root.Position - mid
		across, along = math.abs(d:Dot(cf.ZVector)), math.abs(d:Dot(cf.XVector))
		if across >= half or along >= pr.L.Size.X / 2 then
			off = true
			break
		end
	end
	local seconds = os.clock() - t0
	character:PivotTo(home)
	root.AssemblyLinearVelocity = Vector3.zero
	return { ok = off, info = { stem = stem, off_slide = off, seconds = seconds, across = across, half_width = half, along = along } }
end
if root and character then
	local segs = {}
	for stem in pairs_ do
		local n = tonumber(string.match(stem, "(%d+)$"))
		table.insert(segs, { stem = stem, n = n, joint = string.find(stem, "Joint", 1, true) ~= nil })
	end
	table.sort(segs, function(a, b)
		return a.n < b.n
	end)
	local pickSeg, pickJoint
	for _, s in segs do
		if not s.joint and s.n >= #segs / 4 and not pickSeg then
			pickSeg = s.stem
		elseif s.joint and s.n >= #segs / 4 and not pickJoint then
			pickJoint = s.stem
		end
	end
	checks.dropped_segment = if pickSeg then dropOn(pickSeg) else { ok = nil, info = "no segment fill" }
	checks.dropped_joint = if pickJoint then dropOn(pickJoint) else { ok = nil, info = "no joint fill" }
else
	checks.dropped_segment = { ok = nil, info = "no player character in the game" }
	checks.dropped_joint = { ok = nil, info = "no player character in the game" }
end
local parts, bad = {}, {}
for _, name in { "roof_shape", "dropped_segment", "dropped_joint" } do
	local c = checks[name]
	table.insert(parts, name .. " " .. (if c.ok == true then "PASS" elseif c.ok == false then "FAIL" else "n/a"))
	if c.ok == false then
		table.insert(bad, name)
	end
end
return { ok = #bad == 0, summary = table.concat(parts, ", "), detail = { checks = checks } }
