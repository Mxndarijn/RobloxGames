-- Server datamodel: bug probe 11 part 2 (ADVISORY), a REAL character walk over the PreciseConvexDecomposition / Box meshes of bug #11 (docs/COLLISION.md
-- "What Studio must confirm": the ball drops of luau/mesh_stand do not prove a character can climb a stile or stand on a loft). The real test player's
-- character is unanchored and server-owned for the probe, with the game's own WalkSpeed 16 and the Humanoid's own jump settings (never raised); it is
-- restored at the end exactly like bug08 (CFrame, Anchored states, WalkSpeed, network ownership). Nothing is created (no Instance to Destroy).
-- Parts are found by name among the descendants of workspace.Map and workspace.Plots (a MeshPart, or a Model that contains one); positions in the
-- result are in the local frame of the mesh (stile / loft).
-- Checks (one per call, see PART; ok = the check is true; false if any false):
--   stile_over       ranch_fence_stile: both horizontal axes are tried without jumping (the thinner first); the first whose walk is blocked is the crossing
--                    axis (neither blocked = the stile blocks nothing, thinner axis used). Then MoveTo from 8 studs beyond one face to 8 studs beyond the
--                    other for 8 s with a jump every 0.25 s. ok = ends past the centre on the far side by > 3 studs, root never below the stile base - 1,
--                    and not at rest inside the mesh's bounding box
--   barn_loft        ranch_barn_loft: walk_under_ok = from 8 studs in front the character walks (MoveTo) to the centre at ground level through the open floor
--                    (n/a when an upward ray from the ground at the centre hits the mesh within 5 studs: no open floor); stand_on_ok = teleported 4 studs
--                    above the top centre, after 2 s the feet rest within 3 studs above the bbox top (not fallen through to the ground)
local Players = game:GetService("Players")
-- PART = "stile_over" | "barn_loft": ONE check per call (a single execute_luau call must stay well under 60 s); the walks share a 32 s budget.
local PART = %%PART%%
local ORDER = { PART }
local BUDGET = 32
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
local function r1(x)
	return math.floor(x * 10 + 0.5) / 10
end

local player = Players:GetPlayers()[1]
if not player then
	return finish("no real Player in the server")
end
local char, hum, root
local function bind()
	char = player.Character
	hum = char and char:FindFirstChildOfClass("Humanoid")
	root = char and char:FindFirstChild("HumanoidRootPart")
	return root ~= nil and hum ~= nil
end
if not bind() then
	return finish("the test player has no character")
end
local startCF = root.CFrame
local startAnchored = {}
for _, d in char:GetDescendants() do
	if d:IsA("BasePart") then
		startAnchored[d.Name] = d.Anchored
	end
end
local startSpeed = hum.WalkSpeed
local t0all = os.clock()
local function free()
	for _, d in char:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	hum.WalkSpeed = 16 -- the game's own value
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
end
local function teleport(cf)
	char:PivotTo(cf)
	root.AssemblyLinearVelocity = Vector3.zero
end

-- finding -----------------------------------------------------------------------------------------------------------------------------------
-- Returns { part = BasePart, cf, size } (world bounding box oriented like the mesh) for the first mesh named `name` under workspace.Map / Plots.
local function findMesh(name)
	for _, rootName in { "Map", "Plots" } do
		local folder = workspace:FindFirstChild(rootName)
		if folder then
			for _, d in folder:GetDescendants() do
				if d.Name == name and (d:IsA("BasePart") or d:IsA("Model")) then
					if d:IsA("Model") then
						local cf, size = d:GetBoundingBox()
						local mp = d:FindFirstChildWhichIsA("MeshPart", true)
						return { inst = d, part = mp, cf = cf, size = size, where = d:GetFullName() }
					end
					return { inst = d, part = d, cf = d.CFrame, size = d.Size, where = d:GetFullName() }
				end
			end
		end
	end
	return nil
end
local function groundAt(pos, top, ignore)
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	p.FilterDescendantsInstances = { char, ignore }
	local hit = workspace:Raycast(Vector3.new(pos.X, top + 60, pos.Z), Vector3.new(0, -400, 0), p)
	return hit and hit.Position.Y
end
local function standOffset()
	return hum.HipHeight + root.Size.Y / 2 + 0.3
end
-- Drops the character on the ground under the world point (x, z) facing `lookAt`.
local function placeOnGround(pos, lookAt, topHint, ignore)
	local g = groundAt(pos, topHint, ignore) or (topHint - 20)
	local at = Vector3.new(pos.X, g + standOffset(), pos.Z)
	teleport(CFrame.lookAt(at, Vector3.new(lookAt.X, at.Y, lookAt.Z)))
	hum.Jump = false
	task.wait(0.4)
end
-- MoveTo `target` (world) for up to `secs`; jumpEvery > 0 sets hum.Jump on that period. Stops early when stalled 1.5 s (after 2 s) or within `stopWithin`.
-- Calls onSample(pos, t) every 0.05 s. Returns seconds used.
local function walkTo(target, secs, jumpEvery, stopWithin, onSample)
	secs = math.min(secs, math.max(0.1, BUDGET - (os.clock() - t0all)))
	local t0, lastJump = os.clock(), -1
	local movePos, moveT
	while true do
		local t = os.clock() - t0
		if t >= secs or not root.Parent then
			return t
		end
		hum:MoveTo(target)
		if jumpEvery > 0 and t - lastJump >= jumpEvery then
			hum.Jump = true
			lastJump = t
		end
		task.wait(0.05)
		t = os.clock() - t0
		local pos = root.Position
		if onSample then
			onSample(pos, t)
		end
		local flat = Vector3.new(pos.X, 0, pos.Z)
		if not movePos or (flat - movePos).Magnitude > 0.5 then
			movePos, moveT = flat, t
		end
		if stopWithin and (Vector3.new(target.X, 0, target.Z) - flat).Magnitude <= stopWithin then
			return t
		end
		if t >= 2 and t - moveT >= 1.5 then
			return t
		end
	end
end
-- a) stile_over ------------------------------------------------------------------------------------------------------------------------------
local function stileCheck()
	local m = findMesh("FenceStile_8") -- RanchProps instance of ranch_fence_stile
	if not m then
		set("stile_over", nil, "no ranch_fence_stile under workspace.Map / workspace.Plots")
		return
	end
	local cf, size = m.cf, m.size
	local baseY = cf.Position.Y - size.Y / 2
	-- walk along local axis `ax` ("X"|"Z") from -(half+8) to +(half+8) at ground level; jumps on request
	local function cross(ax, jump, secs)
		local half = (if ax == "X" then size.X else size.Z) / 2
		local dir = if ax == "X" then Vector3.new(1, 0, 0) else Vector3.new(0, 0, 1)
		local from = cf:PointToWorldSpace(-dir * (half + 8))
		local to = cf:PointToWorldSpace(dir * (half + 8))
		placeOnGround(from, to, cf.Position.Y + size.Y, m.inst)
		local minY = math.huge
		walkTo(to, secs, if jump then 0.25 else 0, 1.5, function(pos)
			minY = math.min(minY, pos.Y)
		end)
		task.wait(jump and 1 or 0.2)
		hum.Jump = false
		local l = cf:PointToObjectSpace(root.Position)
		local along = if ax == "X" then l.X else l.Z
		local inBox = math.abs(l.X) < size.X / 2 and math.abs(l.Y) < size.Y / 2 and math.abs(l.Z) < size.Z / 2
		return { axis = ax, jump = jump, end_local = { r1(l.X), r1(l.Y), r1(l.Z) }, far_side_by = r1(along), min_root_y_above_base = r1(minY - baseY), inside_bbox = inBox }
	end
	local axes = if size.X <= size.Z then { "X", "Z" } else { "Z", "X" }
	local tried, chosen = {}, nil
	for _, ax in axes do
		local r = cross(ax, false, 4)
		r.blocked = r.far_side_by <= 3
		table.insert(tried, r)
		if r.blocked and not chosen then
			chosen = ax
			break
		end
	end
	chosen = chosen or axes[1]
	local r = cross(chosen, true, 8)
	local passed = r.far_side_by > 3 and r.min_root_y_above_base >= -1 and not r.inside_bbox
	r.bbox_size = { r1(size.X), r1(size.Y), r1(size.Z) }
	set("stile_over", passed, {
		where = m.where, crossing_axis = chosen, blocks_without_jumping = tried[#tried].blocked or false, tried_without_jump = tried, with_jumps = r,
		note = "positions in the stile's local frame; far_side_by = studs past the centre along the axis",
	})
end

-- b) barn_loft -------------------------------------------------------------------------------------------------------------------------------
local function loftCheck()
	local m = findMesh("BarnLoft_2") -- RanchProps instance of ranch_barn_loft
	if not m then
		set("barn_loft", nil, "no ranch_barn_loft under workspace.Map / workspace.Plots")
		return
	end
	local cf, size = m.cf, m.size
	local top = cf.Position.Y + size.Y / 2
	local info = { where = m.where, bbox_size = { r1(size.X), r1(size.Y), r1(size.Z) } }
	local walkUnder, standOn
	-- walk under: from 8 studs in front (local -Z) to the centre at ground level
	local from = cf:PointToWorldSpace(Vector3.new(0, 0, -(size.Z / 2 + 8)))
	local centre = Vector3.new(cf.Position.X, 0, cf.Position.Z)
	local gFrom = groundAt(from, top, m.inst)
	local gCentre
	do
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Include
		p.FilterDescendantsInstances = { m.inst }
		local down = RaycastParams.new()
		down.FilterType = Enum.RaycastFilterType.Exclude
		down.FilterDescendantsInstances = { char, m.inst }
		local hit = workspace:Raycast(Vector3.new(centre.X, top + 60, centre.Z), Vector3.new(0, -400, 0), down)
		gCentre = hit and hit.Position.Y
		if gCentre then
			local up = workspace:Raycast(Vector3.new(centre.X, gCentre + 0.5, centre.Z), Vector3.new(0, size.Y + 20, 0), p)
			info.clearance_above_ground_at_centre = if up then r1(up.Position.Y - gCentre) else nil
			info.upward_ray_hits_mesh = up ~= nil
		end
	end
	local clearance = info.clearance_above_ground_at_centre
	if not gCentre or not gFrom then
		info.walk_under = "no ground found under the loft / in front of it"
	elseif not clearance or clearance < 5 then
		info.walk_under = "no open floor at the centre (clearance " .. tostring(clearance) .. " < 5): n/a"
	else
		placeOnGround(from, centre, top, m.inst)
		walkTo(Vector3.new(centre.X, gCentre + standOffset(), centre.Z), 6, 0, 1.5)
		local l = cf:PointToObjectSpace(root.Position)
		walkUnder = math.abs(l.X) < 4 and math.abs(l.Z) < 4 and root.Position.Y < gCentre + clearance
		info.walk_under = { end_local = { r1(l.X), r1(l.Y), r1(l.Z) }, clearance = clearance, reached_centre_under_mesh = walkUnder }
	end
	-- stand on top: 4 studs above the top centre
	local topPoint = cf:PointToWorldSpace(Vector3.new(0, size.Y / 2 + 4 + standOffset(), 0))
	teleport(CFrame.new(topPoint))
	task.wait(2)
	local feet = root.Position.Y - standOffset() + 0.3
	local above = feet - top
	local l = cf:PointToObjectSpace(root.Position)
	standOn = above >= -1 and above <= 3 and math.abs(l.X) <= size.X / 2 + 1 and math.abs(l.Z) <= size.Z / 2 + 1
	info.stand_on = { feet_above_bbox_top = r1(above), end_local = { r1(l.X), r1(l.Y), r1(l.Z) }, fell_through_to_ground = gCentre ~= nil and feet < gCentre + 1.5 and above < -3 }
	info.walk_under_ok = walkUnder
	info.stand_on_ok = standOn
	local ok
	if walkUnder == false or standOn == false then
		ok = false
	elseif standOn == true then
		ok = true
	end
	set("barn_loft", ok, info)
end

local CHECKS = { stile_over = stileCheck, barn_loft = loftCheck }
local ok, err = pcall(function()
	free()
	local f = CHECKS[PART]
	if not f then
		error("unknown PART " .. tostring(PART))
	end
	local okF, e = pcall(f)
	if not okF then
		set(PART, nil, "check error: " .. tostring(e))
	end
end)
-- restore ---------------------------------------------------------------------------------------------------------------------------------
pcall(function()
	if bind() then
		hum.Jump = false
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
		for _, d in char:GetDescendants() do
			if d:IsA("BasePart") and startAnchored[d.Name] ~= nil then
				d.Anchored = startAnchored[d.Name]
			end
		end
	end
end)
if not ok then
	return finish("probe error: " .. tostring(err))
end
return finish({ part = PART, seconds = r1(os.clock() - t0all), over_budget = os.clock() - t0all > BUDGET, mode = "real character: MoveTo walks, game WalkSpeed / jump settings" })
