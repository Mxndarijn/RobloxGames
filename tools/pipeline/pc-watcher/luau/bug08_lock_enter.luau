-- Server datamodel: bug probe 8 (ADVISORY), a locked base: the owner walks in, everybody else is kept out (PlotLockGuard + WorldView.enforceLocks,
-- #251). The REAL test player (the only real Player) owns one plot; the lock is driven through the game's own code:
--   * enforceLocks(world, player) is the real WorldView function. The live `world` is a local of init.server and is not reachable, so a
--     MIRROR pure World (World.new + Sessions.join, as server_steal_sim does) holds the same owner of the player's plot (real PlotIndex) and a
--     fake owner (userId -9001) of a plot the player does not own. The driver calls the real enforceLocks(mirror, player) every physics step
--     (RunService.Stepped), so the group assignment and the eject loop are the shipped code, not a reimplementation.
--   * the lock itself is the plot attribute Locked (what enforceLocks reads; the live 10 Hz updatePlots rewrites it, so the driver re-asserts
--     it every step) and the LockBarrier panels (CanCollide + CollisionGroup PlotLock_<i> exactly as WorldView.setBarrierSolid leaves them; that
--     function is file-local, so it is mirrored). The collision groups PlotLock_<i> / PlotOwner_<i> and the character's group come from the game.
--   * a plot own to the player that the live server has locked right now (join lock, first 45 s) is reported as live_own_panels (the real
--     setBarrierSolid result, read before the driver touches anything).
-- The real character is unanchored for the probe (network ownership to the server) and restored: CFrame, Anchored, owner, WalkSpeed.
-- Checks (ok = every non-nil check of the PART true; PART "base" = the first five, each other PART = the one wall check of that name):
--   owner_passes             own plot locked: the character walks (Humanoid:MoveTo) from 8 studs outside the entrance to inside (PlotLockGuard.inside)
--   owner_passes_after_respawn  player:LoadCharacter(), the same walk with the new character
--   non_owner_blocked        a locked plot the player does not own: MoveTo from outside for 4 s never gets inside; its panels are CanCollide and in a
--                            group that collides with the character's. n/a when the unlocked control walk cannot reach the inside either
--   eject_once               teleported into that locked plot, sampled every 0.05 s for 4 s: ends outside, exactly ONE position jump (> 10 studs), never
--                            back inside
--   thrown_slime_not_stuck   a free clone of a real slime body (its size / CollisionGroup, CanCollide forced on) is launched at a solid panel: after
--                            3 s it must not rest suspended in the air next to a panel (within 1.5 studs of a face) nor inside the panel
-- Real-character wall checks (#277 removed the invisible Wall* blocks: the fence meshes are the only barrier besides the LockBarrier panels). Against the
-- locked FOREIGN plot, the real character (unanchored, server-owned, the game's own WalkSpeed 16 and Humanoid jump settings, never raised) tries to get in.
-- Every attempt samples the root every 0.05 s: ever_inside (PlotLockGuard.inside), first_inside_s, max_penetration (studs past the fence plane, plot-local),
-- ejected (a position jump > 10 studs). An attempt FAILS when ever_inside is true (getting in and being ejected still counts). The fence is found by the
-- attribute FenceCollider or the names ranch_fence_20 / phoenix_fence_segment / phoenix_corner_post (and GatePost / GatePostL / GatePostR) among the plot's
-- descendants; the fence lines, panel middles / joints, gate seams and corners are computed from their real CFrames and sizes in the Base's frame. ok = every
-- attempt stayed outside, false = any got inside, n/a = geometry not found or no time left (each check is its own PART with a 32 s attempt budget, most
-- important attempts first; attempts end early when the character stalls for 1.5 s). Reset between attempts: teleport outside, zero velocity, wait 0.3 s.
--   fence_jump_over          back + one side fence line: start 6 studs outside, MoveTo 10 studs inside for 4 s with hum.Jump every 0.25 s; plus a running start from 16 studs
--   fence_push_through       back and both side lines at a panel middle AND a panel joint, plus both gate-side phoenix_fence_segments: MoveTo straight in, no jumping
--   gate_post_squeeze        at the gate: FIRST the strict jumps (fail on max_penetration > 0, i.e. any root past the front fence line, not only ever_inside) from
--                            plot-local (post.x ~ 10.8, front - 6 ~ -45.5) at the gate-side phoenix_corner_post and its mirror at the left gate segment post
--                            (x ~ -10.8), then the seams between the LockBarrier front panel / gate posts / phoenix_corner_post, straight (no jump, jumping) and 45 degree approaches
--   corner_squeeze           the four plot corners, where the fence meshes meet the thin LockBarrier panels (no jumping): per corner a 45 degree
--                            approach at the fence corner, then straight in on both sides at the seam (the end of the fence mesh nearest the corner,
--                            else 0.8 studs in from the corner), then a diagonal at the panel corner when it sits > 0.75 studs from the fence corner;
--                            info.junctions has the fence corner, the panel corner and the fence-end / panel-end gap per corner
--   corner_jump              the same corner attempts, jumping every 0.25 s
-- Everything made is destroyed; the lock attributes / panels are restored; the character ends where it started, with its Anchored states.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")
local Server = game:GetService("ServerScriptService"):FindFirstChild("Server")
if not Server then
	return { ok = false, summary = "ServerScriptService.Server missing", detail = {} }
end
local reqOk, mods = pcall(function()
	local Shared = RS.Shared
	return {
		World = require(Server.World),
		Sessions = require(Server.Sessions),
		WorldView = require(Server.WorldView),
		Guard = require(Server.PlotLockGuard),
		PlayerData = require(Shared.PlayerData),
		Config = require(Shared.Config),
		Constants = require(Shared.Constants),
	}
end)
if not reqOk then
	return { ok = false, summary = "require failed: " .. tostring(mods), detail = {} }
end
local World, Sessions, WorldView, Guard = mods.World, mods.Sessions, mods.WorldView, mods.Guard
local LOCKED = mods.Constants.PLOT_LOCKED_ATTRIBUTE
-- PART = "base" (the five old checks, ~50 s) | "fence_jump_over" | "fence_push_through" | "gate_post_squeeze" | "corner_squeeze" | "corner_jump" (that one wall check
-- only, 32 s attempt budget): a single execute_luau call must stay well under 60 s, so the checks are split over several calls.
local PART = %%PART%%
local BASE_ORDER = { "owner_passes", "owner_passes_after_respawn", "non_owner_blocked", "eject_once", "thrown_slime_not_stuck" }
local ORDER = if PART == "base" then BASE_ORDER else { PART }
local ATTEMPT_BUDGET = 32
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

local player = Players:GetPlayers()[1]
if not player then
	return finish("no real Player in the server")
end
local plotsFolder = workspace:FindFirstChild(mods.Constants.PLOTS_FOLDER)
if not plotsFolder then
	return finish("workspace.Plots missing")
end

-- plots -------------------------------------------------------------------------------------------------------------------------------------
local plotByIndex = {}
for _, p in plotsFolder:GetChildren() do
	local i = p:GetAttribute(mods.Constants.PLOT_INDEX_ATTRIBUTE)
	if p:IsA("Model") and type(i) == "number" and p:FindFirstChild("LockBarrier") and p:FindFirstChild("Base") then
		plotByIndex[i] = p
	end
end
local ownIndex, foreignIndex
for i, p in plotByIndex do
	if p:GetAttribute("OwnerUserId") == player.UserId then
		ownIndex = i
	end
end
for i = 1, mods.Config.PLOT_COUNT do
	local p = plotByIndex[i]
	local o = p and p:GetAttribute("OwnerUserId")
	if p and i ~= ownIndex and (o == 0 or o == nil) and p:GetAttribute(LOCKED) ~= true then
		foreignIndex = i
		break
	end
end

-- state to restore -------------------------------------------------------------------------------------------------------------------------
local saved = { attr = {}, panels = {} }
local made = {}
local alive = true
local locks = {} -- plot index -> true: the driver keeps these plots locked + their panels solid
local driver
local function register(i)
	local lock, owner = Guard.lockGroup(i), Guard.ownerGroup(i)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(lock)
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup(owner)
	end)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable(lock, owner, false)
	end)
end
local function remember(i)
	local plot = plotByIndex[i]
	if saved.attr[i] ~= nil then
		return
	end
	saved.attr[i] = { locked = plot:GetAttribute(LOCKED) }
	for _, panel in plot.LockBarrier:GetChildren() do
		if panel:IsA("BasePart") then
			saved.panels[panel] = { can = panel.CanCollide, group = panel.CollisionGroup }
		end
	end
end
local function setPanels(i, solid)
	for _, panel in plotByIndex[i].LockBarrier:GetChildren() do
		if panel:IsA("BasePart") then
			panel.CanCollide = solid
			pcall(function()
				panel.CollisionGroup = Guard.lockGroup(i)
			end)
		end
	end
end
local function lockPlot(i, on)
	remember(i)
	register(i)
	locks[i] = on or nil
	if not on then
		plotByIndex[i]:SetAttribute(LOCKED, false)
		setPanels(i, false)
	end
end

-- mirror world -------------------------------------------------------------------------------------------------------------------------------
local now = os.time()
local mirror = World.new({ now = now, seed = 11, plotCount = mods.Config.PLOT_COUNT })
local function joinAs(userId, index, name)
	local s = Sessions.join(mirror, userId, name, mods.PlayerData.new(), now)
	if s then
		mirror.plots[s.plotIndex] = nil
		s.plotIndex = index
		mirror.plots[index] = userId
	end
	return s
end
if ownIndex then
	joinAs(player.UserId, ownIndex, player.Name)
end
local FAKE_OWNER = -9001
if foreignIndex then
	joinAs(FAKE_OWNER, foreignIndex, "PCW Lock Owner")
end
driver = RunService.Stepped:Connect(function()
	if not alive then
		return
	end
	for i in locks do
		local plot = plotByIndex[i]
		plot:SetAttribute(LOCKED, true)
		setPanels(i, true)
	end
	pcall(WorldView.enforceLocks, mirror, player)
end)

-- character -------------------------------------------------------------------------------------------------------------------------------
local char, hum, root
local function bind()
	char = player.Character
	hum = char and char:FindFirstChildOfClass("Humanoid")
	root = char and char:FindFirstChild("HumanoidRootPart")
	return root ~= nil and hum ~= nil
end
if not bind() then
	driver:Disconnect()
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

-- geometry helpers --------------------------------------------------------------------------------------------------------------------------
local function frameOf(i)
	local base = plotByIndex[i].Base
	return base.CFrame, base.Size.X / 2
end
local function localPos(i)
	local cf = frameOf(i)
	local p = cf:PointToObjectSpace(root.Position)
	return p
end
local function insideNow(i)
	local _, half = frameOf(i)
	local p = localPos(i)
	return Guard.inside(p.X, p.Y, p.Z, half)
end
local function placeOutside(i)
	local cf, half = frameOf(i)
	teleport(cf * CFrame.new(0, 4, -(half + 8)) * CFrame.Angles(0, math.pi, 0))
	task.wait(0.4)
end
-- Walk from outside the entrance towards the plot interior. Returns {inside, ever_inside, secs}.
local function walkIn(i, secs, stopWhenInside)
	local cf, half = frameOf(i)
	local target = cf:PointToWorldSpace(Vector3.new(0, 4, -(half - 8)))
	local t0 = os.clock()
	local ever = false
	while os.clock() - t0 < secs do
		hum:MoveTo(target)
		task.wait(0.05)
		if not root.Parent then
			break
		end
		if insideNow(i) then
			ever = true
			if stopWhenInside then
				break
			end
		end
	end
	return { inside = insideNow(i), ever_inside = ever, secs = os.clock() - t0, group = root.CollisionGroup }
end

-- real-character wall checks -------------------------------------------------------------------------------------------------------------
local FENCE_NAMES = { ranch_fence_20 = true, phoenix_fence_segment = true, phoenix_corner_post = true }
local SEARCHED = "attribute FenceCollider, names ranch_fence_20 / phoenix_fence_segment / phoenix_corner_post / GatePost"
local SIDE_N = { back = Vector3.new(0, 0, -1), front = Vector3.new(0, 0, 1), left = Vector3.new(1, 0, 0), right = Vector3.new(-1, 0, 0) } -- inward normals
local function r1(x)
	return math.floor(x * 10 + 0.5) / 10
end
local function r2(v)
	return { r1(v.X), r1(v.Z) }
end
-- Fence geometry of plot i in the Base frame: segments per side {s, len, line, name}, posts, gate stand-ins.
local function fenceGeometry(i)
	local plot = plotByIndex[i]
	local cf, half = frameOf(i)
	local sides = { back = {}, front = {}, left = {}, right = {} }
	local posts, stubs, count = {}, {}, 0
	for _, d in plot:GetDescendants() do
		if d:IsA("BasePart") and d:FindFirstAncestor("LockBarrier") == nil then
			local isPost = d.Name == "phoenix_corner_post" or d.Name == "GatePost"
			if d.Name == "GatePostL" or d.Name == "GatePostR" then
				local rel = cf:ToObjectSpace(d.CFrame)
				local ex = math.abs(rel.RightVector.X) * d.Size.X / 2 + math.abs(rel.LookVector.X) * d.Size.Z / 2
				table.insert(stubs, { x = rel.Position.X, z = rel.Position.Z, ex = ex })
			elseif isPost or d:GetAttribute("FenceCollider") or FENCE_NAMES[d.Name] then
				local rel = cf:ToObjectSpace(d.CFrame)
				local sz = d.Size
				local ex = math.abs(rel.RightVector.X) * sz.X / 2 + math.abs(rel.UpVector.X) * sz.Y / 2 + math.abs(rel.LookVector.X) * sz.Z / 2
				local ez = math.abs(rel.RightVector.Z) * sz.X / 2 + math.abs(rel.UpVector.Z) * sz.Y / 2 + math.abs(rel.LookVector.Z) * sz.Z / 2
				local c = rel.Position
				if isPost or math.max(ex, ez) < 3 then
					local dup = false
					for _, p in posts do
						dup = dup or (math.abs(p.x - c.X) < 1.5 and math.abs(p.z - c.Z) < 1.5)
					end
					if not dup then
						table.insert(posts, { x = c.X, z = c.Z, ex = ex, ez = ez })
					end
				elseif d.Size.Y > 2 or d:GetAttribute("FenceCollider") then
					local alongX = ex >= ez
					local side = if alongX then (if c.Z > 0 then "back" else "front") else (if c.X < 0 then "left" else "right")
					local s, line, len = if alongX then c.X else c.Z, if alongX then c.Z else c.X, 2 * (if alongX then ex else ez)
					local dup = false
					for _, o in sides[side] do
						dup = dup or (math.abs(o.s - s) < 1.5 and math.abs(o.line - line) < 1.5)
					end
					if not dup then
						count += 1
						table.insert(sides[side], { s = s, len = len, line = line, name = d.Name })
					end
				end
			end
		end
	end
	local lines = {}
	for side, list in sides do
		table.sort(list, function(a, b)
			return a.s < b.s
		end)
		if #list > 0 then
			local sum = 0
			for _, sg in list do
				sum += sg.line
			end
			lines[side] = sum / #list
		else
			lines[side] = (if side == "back" or side == "right" then 1 else -1) * (half - 0.5)
		end
	end
	-- LockBarrier panels in the Base frame: side -> { line, lo, hi } (Front / Back along X at -z / +z, Left / Right along Z at -x / +x)
	local panels = {}
	local barrier = plot:FindFirstChild("LockBarrier")
	if barrier then
		for _, pnl in barrier:GetChildren() do
			if pnl:IsA("BasePart") then
				local rel = cf:ToObjectSpace(pnl.CFrame)
				local sz = pnl.Size
				local ex = math.abs(rel.RightVector.X) * sz.X / 2 + math.abs(rel.UpVector.X) * sz.Y / 2 + math.abs(rel.LookVector.X) * sz.Z / 2
				local ez = math.abs(rel.RightVector.Z) * sz.X / 2 + math.abs(rel.UpVector.Z) * sz.Y / 2 + math.abs(rel.LookVector.Z) * sz.Z / 2
				local c = rel.Position
				if ex >= ez then
					panels[if c.Z > 0 then "back" else "front"] = { line = c.Z, lo = c.X - ex, hi = c.X + ex, thick = 2 * ez }
				else
					panels[if c.X < 0 then "left" else "right"] = { line = c.X, lo = c.Z - ez, hi = c.Z + ez, thick = 2 * ex }
				end
			end
		end
	end
	return { sides = sides, lines = lines, posts = posts, stubs = stubs, count = count, half = half, cf = cf, panels = panels }
end
-- plot-local point of a side: tangent coordinate s, `out` studs outside the fence centre plane
local function sidePoint(g, side, s, out)
	local n = SIDE_N[side]
	local alongX = side == "back" or side == "front"
	local p = if alongX then Vector3.new(s, 0, g.lines[side]) else Vector3.new(g.lines[side], 0, s)
	return p - n * out
end
local function sidePlane(g, side)
	local n = SIDE_N[side]
	return { n = n, d = n:Dot(sidePoint(g, side, 0, 0)) }
end

local checkStart
-- One attempt: from startL to targetL (plot-local x, z), MoveTo for up to 4 s. planes = {{n, d}} measure penetration (min over the planes).
local function attempt(i, label, startL, targetL, jump, planes)
	local cf = frameOf(i)
	local y = 4
	teleport(cf * CFrame.lookAt(Vector3.new(startL.X, y, startL.Z), Vector3.new(targetL.X, y, targetL.Z)))
	hum.Jump = false
	task.wait(0.3)
	local target = cf:PointToWorldSpace(Vector3.new(targetL.X, y, targetL.Z))
	local rec = { label = label, start = r2(startL), target = r2(targetL), jump = jump, ever_inside = false, ejected = false, max_penetration = -99 }
	local t0, lastJump = os.clock(), -1
	local last, movePos, moveT = nil, nil, 0
	local insideAt
	while true do
		local t = os.clock() - t0
		if not root.Parent then
			break
		end
		hum:MoveTo(target)
		if jump and t - lastJump >= 0.25 then
			hum.Jump = true
			lastJump = t
		end
		task.wait(0.05)
		t = os.clock() - t0
		local pos = root.Position
		if last and (pos - last).Magnitude > 10 then
			rec.ejected = true
		end
		last = pos
		local lp = cf:PointToObjectSpace(pos)
		local pen = math.huge
		for _, pl in planes do
			pen = math.min(pen, pl.n:Dot(lp) - pl.d)
		end
		rec.max_penetration = math.max(rec.max_penetration, pen)
		if insideNow(i) and not rec.ever_inside then
			rec.ever_inside, rec.first_inside_s, insideAt = true, r1(t), t
		end
		local flatPos = Vector3.new(pos.X, 0, pos.Z)
		if not movePos or (flatPos - movePos).Magnitude > 0.5 then
			movePos, moveT = flatPos, t
		end
		if t >= 4 or (insideAt and t - insideAt >= 0.5) or (t >= 2 and t - moveT >= 1.5) then
			rec.secs = r1(t)
			break
		end
	end
	hum.Jump = false
	rec.max_penetration = r1(rec.max_penetration)
	rec.end_local = r2(cf:PointToObjectSpace(root.Position))
	if insideNow(i) then
		rec.ended_inside = true
	end
	return rec
end
-- Runs the attempt list builder for one check and sets the result. Attempts (sorted by pri, then build order) that do not fit the budget are skipped.
local cornerJunctions -- set by the corner builders: per-corner fence / panel geometry for the report
local function runCheck(name, i, build)
	checkStart = os.clock()
	local deadline = checkStart + ATTEMPT_BUDGET
	local okG, g = pcall(fenceGeometry, i)
	if not okG or g.count == 0 then
		set(name, nil, "no fence parts found under the plot (searched: " .. SEARCHED .. ")" .. (if okG then "" else " " .. tostring(g)))
		return
	end
	local list = build(g)
	for k, a in list do
		a.idx = k
		a.pri = a.pri or 5
	end
	table.sort(list, function(x, y)
		if x.pri ~= y.pri then
			return x.pri < y.pri
		end
		return x.idx < y.idx
	end)
	if #list == 0 then
		set(name, nil, "fence geometry incomplete (needed sides / gate posts not found); fence parts: " .. tostring(g.count))
		return
	end
	local recs, skipped, anyIn = {}, 0, false
	for _, a in list do
		if os.clock() + 4.7 > deadline then -- an attempt takes up to 0.3 + 4 s plus the reset
			skipped += 1
		else
			local okA, rec = pcall(attempt, i, a.label, a.start, a.target, a.jump, a.planes)
			if okA then
				table.insert(recs, rec)
				rec.strict = a.strict
				anyIn = anyIn or rec.ever_inside or (a.strict and rec.max_penetration > 0)
				if rec.ever_inside or rec.ended_inside then
					local cf, half = frameOf(i)
					teleport(cf * CFrame.new(0, 4, -(half + 8)))
				end
			else
				table.insert(recs, { label = a.label, error = tostring(rec) })
			end
		end
	end
	local ran = 0
	for _, r in recs do
		ran += if r.error then 0 else 1
	end
	local info = { attempts = recs, skipped_for_time = skipped, fence_parts = g.count, seconds = r1(os.clock() - checkStart) }
	if cornerJunctions then
		info.junctions = cornerJunctions
	end
	if skipped > 0 then
		info.note = skipped .. " attempt(s) did not fit the " .. ATTEMPT_BUDGET .. " s budget (n/a)"
	end
	set(name, if anyIn then false elseif ran > 0 then true else nil, info)
	local cf, half = frameOf(i)
	teleport(cf * CFrame.new(0, 4, -(half + 8)))
end

local function jumpOverList(g)
	local list = {}
	local sides = { "back" }
	for _, side in { "left", "right" } do
		if #g.sides[side] > 0 and #sides < 2 then
			table.insert(sides, side)
		end
	end
	for k, side in sides do
		if #g.sides[side] > 0 then
			local pl = { sidePlane(g, side) }
			local target = sidePoint(g, side, 0, -10)
			table.insert(list, { label = side .. " jump 6 out", start = sidePoint(g, side, 0, 6), target = target, jump = true, planes = pl })
			if k == 1 then
				table.insert(list, { label = side .. " running jump 16 out", start = sidePoint(g, side, 0, 16), target = target, jump = true, planes = pl })
			end
		end
	end
	return list
end
local function pushList(g)
	local list = {}
	for _, side in { "back", "left", "right" } do
		local segs = g.sides[side]
		if #segs > 0 then
			local pl = { sidePlane(g, side) }
			local mid = segs[1]
			for _, sg in segs do
				if sg.len > mid.len + 0.5 then
					mid = sg
				end
			end
			local jointS, jointD = nil, math.huge
			for k = 1, #segs - 1 do
				local b = (segs[k].s + segs[k].len / 2 + segs[k + 1].s - segs[k + 1].len / 2) / 2
				if math.abs(b) < jointD then
					jointS, jointD = b, math.abs(b)
				end
			end
			local function add(label, s, pri)
				table.insert(list, { label = label, start = sidePoint(g, side, s, 4), target = sidePoint(g, side, s, -8), jump = false, planes = pl, pri = pri })
			end
			add(side .. " panel middle (" .. mid.name .. ")", mid.s, 3)
			if jointS then
				add(side .. " joint", jointS, 1) -- panel joints first
			end
		end
	end
	local front = g.sides.front
	local pl = { sidePlane(g, "front") }
	for _, sign in { -1, 1 } do
		local best
		for _, sg in front do
			if sg.s * sign > 0 and (not best or math.abs(sg.s) < math.abs(best.s)) then
				best = sg
			end
		end
		if best then
			table.insert(list, {
				label = "gate-side segment " .. (if sign < 0 then "left" else "right") .. " (" .. best.name .. ")",
				start = sidePoint(g, "front", best.s, 4), target = sidePoint(g, "front", best.s, -8), jump = false, planes = pl, pri = 2, -- gate-side segments second
			})
		end
	end
	return list
end
local function squeezeList(g)
	local list = {}
	local front = g.lines.front
	local pl = { sidePlane(g, "front") }
	local inner, outerX = {}, {}
	for _, st in g.stubs do
		local sign = if st.x < 0 then -1 else 1
		inner[sign] = math.abs(st.x) - st.ex
		outerX[sign] = math.abs(st.x) + st.ex
	end
	for _, sign in { -1, 1 } do
		if not inner[sign] then -- no GatePost stand-ins: the fence segments' inner ends are the opening
			local best
			for _, sg in g.sides.front do
				if sg.s * sign > 0 and (not best or math.abs(sg.s) < math.abs(best.s)) then
					best = sg
				end
			end
			if best then
				inner[sign] = math.abs(best.s) - best.len / 2
			end
		end
	end
	for _, sign in { -1, 1 } do
		local nm = if sign < 0 then "left" else "right"
		if inner[sign] then
			local x = sign * inner[sign]
			local function add(label, from, to, jump, pri)
				table.insert(list, { label = label, start = from, target = to, jump = jump, planes = pl, pri = pri })
			end
			for _, jump in { false, true } do
				local tag = if jump then " jump" else ""
				add("gate " .. nm .. " post inner edge straight" .. tag, Vector3.new(x, 0, front - 6), Vector3.new(x, 0, front + 10), jump, if jump then 2 else 1) -- both seams straight, then jumping
				for _, from in { -1, 1 } do -- 45 degrees, coming from the opening side (from = sign * -1) or from the post side
					local d = Vector3.new(from, 0, 1).Unit
					local aim = Vector3.new(x, 0, front)
					add("gate " .. nm .. " post inner edge diag from " .. (if from == -sign then "opening" else "post") .. tag, aim - d * (6 / d.Z), aim + d * 10, jump, if jump then 5 else 4)
				end
			end
		end
	end
	-- Bug #8 follow-up (shot 189): the jump from (post.x, front - 6) at the gate-side phoenix_corner_post got +1.7 past the front fence line (the thin
	-- LockBarrier panel was pierced by the post). FIRST in the list and STRICT: it fails on any root past the fence line (max_penetration > 0), not
	-- only on ever_inside. The mirror (x = -post.x, the left gate segment's post) goes right after it.
	for _, post in g.posts do
		if math.abs(post.z - front) < 4 and post.x > 0 then
			for k, x in { post.x, -post.x } do
				table.insert(list, {
					label = (if k == 1 then "phoenix_corner_post jump" else "left gate segment post jump (mirror)") .. " x=" .. r1(x),
					start = Vector3.new(x, 0, front - 6), target = Vector3.new(x, 0, front + 10), jump = true, planes = pl, pri = 0, strict = true,
				})
			end
		end
	end
	for _, post in g.posts do
		if math.abs(post.z - front) < 4 then
			table.insert(list, {
				label = "phoenix_corner_post straight", start = Vector3.new(post.x, 0, front - 6),
				target = Vector3.new(post.x, 0, front + 10), jump = false, planes = pl, pri = 2,
			})
		end
	end
	return list
end
-- Corner attempts (#277 + LockBarrier panels): where the fence meshes meet the thin panels, at all four corners.
local CORNERS = { { "back", "left" }, { "back", "right" }, { "front", "left" }, { "front", "right" } }
local function seamS(g, side, cornerS) -- tangent coordinate of the fence end on `side` nearest the corner at tangent cornerS
	local best, bestD = nil, math.huge
	for _, sg in g.sides[side] do
		for _, e in { sg.s - sg.len / 2, sg.s + sg.len / 2 } do
			local d = math.abs(e - cornerS)
			if d < bestD then
				best, bestD = e, d
			end
		end
	end
	if best and bestD <= 4 then
		return best
	end
	return cornerS - (if cornerS > 0 then 1 else -1) * 0.8
end
local function cornerAttempts(g, jump)
	local list = {}
	cornerJunctions = {}
	local tag = if jump then " jump" else ""
	for _, v in CORNERS do
		local a, b = v[1], v[2] -- a along X (back / front), b along Z (left / right)
		local corner = Vector3.new(g.lines[b], 0, g.lines[a])
		local inward = (SIDE_N[a] + SIDE_N[b]).Unit
		local planes = { sidePlane(g, a), sidePlane(g, b) }
		local cname = a .. "-" .. b
		table.insert(list, { pri = 1, label = cname .. " corner diag" .. tag, start = corner - inward * 5, target = corner + inward * 10, jump = jump, planes = planes })
		local sa, sb = seamS(g, a, corner.X), seamS(g, b, corner.Z)
		table.insert(list, { pri = 2, label = cname .. " seam on " .. a .. " at s=" .. r1(sa) .. tag, start = sidePoint(g, a, sa, 4), target = sidePoint(g, a, sa, -8), jump = jump, planes = planes })
		table.insert(list, { pri = 2, label = cname .. " seam on " .. b .. " at s=" .. r1(sb) .. tag, start = sidePoint(g, b, sb, 4), target = sidePoint(g, b, sb, -8), jump = jump, planes = planes })
		local pa, pb = g.panels[a], g.panels[b]
		local j = { fence_corner = r2(corner), fence_end_on = { [a] = r1(sa), [b] = r1(sb) } }
		if pa and pb then
			local pc = Vector3.new(pb.line, 0, pa.line)
			j.panel_corner = r2(pc)
			-- gap between the panel's end and the fence end it should meet, along each side (negative = overlap)
			local endA = if corner.X > 0 then pa.hi else pa.lo
			local endB = if corner.Z > 0 then pb.hi else pb.lo
			j.panel_end_vs_fence_end = { [a] = r1(math.abs(sa) - math.abs(endA)), [b] = r1(math.abs(sb) - math.abs(endB)) }
			j.panel_vs_fence_line = { [a] = r1(pa.line - g.lines[a]), [b] = r1(pb.line - g.lines[b]) }
			if (pc - corner).Magnitude > 0.75 then
				table.insert(list, { pri = 3, label = cname .. " panel-corner diag" .. tag, start = pc - inward * 5, target = pc + inward * 10, jump = jump, planes = planes })
			end
		else
			j.panel_corner = "no LockBarrier panels on " .. a .. " / " .. b
		end
		cornerJunctions[cname] = j
	end
	return list
end
local function cornerList(g)
	return cornerAttempts(g, false)
end
local function cornerJumpList(g)
	return cornerAttempts(g, true)
end

local function charChecks(i)
	local builders = { fence_jump_over = jumpOverList, fence_push_through = pushList, gate_post_squeeze = squeezeList, corner_squeeze = cornerList, corner_jump = cornerJumpList }
	runCheck(PART, i, builders[PART])
end

local function runWall()
	free()
	if not foreignIndex then
		set(PART, nil, "no unowned, unlocked plot with a LockBarrier to use as the foreign plot")
		return
	end
	lockPlot(foreignIndex, true)
	placeOutside(foreignIndex)
	charChecks(foreignIndex)
	lockPlot(foreignIndex, false)
end

local function run()
	if PART ~= "base" then
		runWall()
		return
	end
	free()
	-- ---- a) owner passes ----
	if ownIndex then
		local live = plotByIndex[ownIndex]
		local liveInfo
		if live:GetAttribute(LOCKED) == true then
			local solid, grp = 0, nil
			for _, panel in live.LockBarrier:GetChildren() do
				if panel:IsA("BasePart") then
					solid += if panel.CanCollide then 1 else 0
					grp = panel.CollisionGroup
				end
			end
			liveInfo = { live_locked = true, panels_solid = solid, panel_group = grp }
		end
		lockPlot(ownIndex, true)
		placeOutside(ownIndex)
		local r = walkIn(ownIndex, 4, true)
		r.live_own_panels = liveInfo
		r.expected_group = Guard.ownerGroup(ownIndex)
		if r.inside then
			set("owner_passes", true, r)
		else
			lockPlot(ownIndex, false)
			placeOutside(ownIndex)
			r.control_unlocked = walkIn(ownIndex, 4, true).inside
			lockPlot(ownIndex, true)
			set("owner_passes", if r.control_unlocked then false else nil, r)
		end
		lockPlot(ownIndex, false)
	else
		set("owner_passes", nil, "the test player owns no plot (no OwnerUserId match)")
		set("owner_passes_after_respawn", nil, "the test player owns no plot")
	end
	-- ---- c) non-owner blocked ----
	local panelsInfo
	if foreignIndex then
		lockPlot(foreignIndex, true)
		placeOutside(foreignIndex)
		local r = walkIn(foreignIndex, 4, false)
		task.wait(0.1)
		panelsInfo = {}
		local allSolid = true
		for _, panel in plotByIndex[foreignIndex].LockBarrier:GetChildren() do
			if panel:IsA("BasePart") then
				local collides = PhysicsService:CollisionGroupsAreCollidable(panel.CollisionGroup, root.CollisionGroup)
				panelsInfo[panel.Name] = { can_collide = panel.CanCollide, group = panel.CollisionGroup, collides_with_character = collides }
				allSolid = allSolid and panel.CanCollide and collides
			end
		end
		r.panels = panelsInfo
		r.panels_solid = allSolid
		local blocked = not r.ever_inside and allSolid
		if blocked then
			lockPlot(foreignIndex, false)
			placeOutside(foreignIndex)
			r.control_unlocked_reaches_inside = walkIn(foreignIndex, 4, true).inside
			lockPlot(foreignIndex, true)
			if not r.control_unlocked_reaches_inside then
				set("non_owner_blocked", nil, r) -- the unlocked plot cannot be entered either: the walk proves nothing
			else
				set("non_owner_blocked", true, r)
			end
		else
			set("non_owner_blocked", false, r)
		end
		-- ---- d) eject once ----
		local cf, half = frameOf(foreignIndex)
		local samples, jumps, last, inAfter = 0, 0, nil, false
		local jumped = false
		teleport(cf * CFrame.new(0, 4, 0))
		local t0 = os.clock()
		while true do
			local pos = root.Position
			if last and (pos - last).Magnitude > 10 then
				jumps += 1
				jumped = true
			end
			if jumped and insideNow(foreignIndex) then
				inAfter = true
			end
			last = pos
			samples += 1
			if os.clock() - t0 >= 4 then
				break
			end
			task.wait(0.05)
		end
		local outside = not insideNow(foreignIndex)
		local lp = localPos(foreignIndex)
		set("eject_once", outside and jumps == 1 and not inAfter, {
			outside = outside, jumps = jumps, back_inside_after_jump = inAfter, samples = samples,
			end_local = { lp.X, lp.Y, lp.Z }, half = half,
		})
		-- ---- e) thrown slime ----
		local body
		for _, folder in { workspace:FindFirstChild(mods.Constants.WILD_FOLDER), plotsFolder } do
			if folder then
				for _, m in folder:GetDescendants() do
					if m:IsA("Model") and m.PrimaryPart and m:FindFirstChild(mods.Constants.GRAB_PROMPT_NAME or "GrabPrompt", true) then
						body = m.PrimaryPart
						break
					end
				end
			end
			if body then
				break
			end
		end
		local how = if body then "clone of a real slime body (size + CollisionGroup), unanchored, CanCollide on" else "plain 3-stud ball (no slime found)"
		local slime = Instance.new("Part")
		slime.Name = "PcwBugSlime"
		slime.Size = if body then Vector3.new(math.min(body.Size.X, 6), math.min(body.Size.Y, 6), math.min(body.Size.Z, 6)) else Vector3.new(3, 3, 3)
		slime.Shape = Enum.PartType.Ball
		slime.CanCollide = true
		if body then
			pcall(function()
				slime.CollisionGroup = body.CollisionGroup
			end)
			slime.Material = body.Material
		end
		slime.CustomPhysicalProperties = PhysicalProperties.new(0.7, 0.3, 0.1, 1, 1)
		teleport(cf * CFrame.new(0, 4, -(half + 40))) -- the character out of the way
		slime.CFrame = cf * CFrame.new(-6, 6, -(half + 12))
		slime.Parent = workspace
		table.insert(made, slime)
		slime.AssemblyLinearVelocity = cf:VectorToWorldSpace(Vector3.new(4, 12, 38)) -- lobbed at the entrance panel
		task.wait(3)
		local bestGap, bestPanel = math.huge, nil
		local radius = slime.Size.Y / 2
		for _, panel in plotByIndex[foreignIndex].LockBarrier:GetChildren() do
			if panel:IsA("BasePart") then
				local l = panel.CFrame:PointToObjectSpace(slime.Position)
				local h = panel.Size / 2
				local out = Vector3.new(math.max(math.abs(l.X) - h.X, 0), math.max(math.abs(l.Y) - h.Y, 0), math.max(math.abs(l.Z) - h.Z, 0))
				local inside = math.abs(l.X) < h.X and math.abs(l.Y) < h.Y and math.abs(l.Z) < h.Z
				local gap = if inside then -1 else out.Magnitude - radius
				if gap < bestGap then
					bestGap, bestPanel = gap, panel.Name
				end
			end
		end
		local ground = workspace:Raycast(slime.Position, Vector3.new(0, -60, 0), (function()
			local p = RaycastParams.new()
			p.FilterType = Enum.RaycastFilterType.Exclude
			p.FilterDescendantsInstances = { slime, char, plotByIndex[foreignIndex].LockBarrier }
			return p
		end)())
		local height = if ground then slime.Position.Y - radius - ground.Position.Y else 1e6
		local speed = slime.AssemblyLinearVelocity.Magnitude
		local atRest = speed < 1
		local suspended = height > 0.75
		local stuck = bestGap < 0 or (atRest and bestGap <= 1.5 and suspended)
		set("thrown_slime_not_stuck", not stuck, {
			how = how, nearest_panel = bestPanel, gap_to_face = if bestGap == math.huge then nil else bestGap, height_above_ground = height, speed = speed,
			resting_on_ground_against_wall = atRest and bestGap <= 1.5 and not suspended,
			note = "no slime throw exists in src/server (slimes are anchored or welded to the carrier; PvpKnockback only launches characters)",
		})
		lockPlot(foreignIndex, false)
	else
		for _, n in { "non_owner_blocked", "eject_once", "thrown_slime_not_stuck" } do
			set(n, nil, "no unowned, unlocked plot with a LockBarrier to use as the foreign plot")
		end
	end
	-- ---- b) owner passes after respawn (last: it replaces the character) ----
	if ownIndex then
		lockPlot(ownIndex, true)
		local okLoad, err = pcall(function()
			player:LoadCharacter()
		end)
		if not okLoad then
			set("owner_passes_after_respawn", nil, "LoadCharacter failed: " .. tostring(err))
		else
			local t0 = os.clock()
			while os.clock() - t0 < 6 and not (bind() and root:IsDescendantOf(workspace)) do
				task.wait(0.1)
			end
			if not (root and hum) then
				set("owner_passes_after_respawn", false, "no character after LoadCharacter")
			else
				free()
				task.wait(0.3)
				placeOutside(ownIndex)
				local r = walkIn(ownIndex, 4, true)
				r.expected_group = Guard.ownerGroup(ownIndex)
				set("owner_passes_after_respawn", r.inside, r)
			end
		end
		lockPlot(ownIndex, false)
	end
end

local ok, err = pcall(run)
-- restore ---------------------------------------------------------------------------------------------------------------------------------
alive = false
driver:Disconnect()
for _, o in made do
	pcall(function()
		o:Destroy()
	end)
end
for panel, s in saved.panels do
	pcall(function()
		panel.CanCollide = s.can
		panel.CollisionGroup = s.group
	end)
end
for i, s in saved.attr do
	pcall(function()
		plotByIndex[i]:SetAttribute(LOCKED, s.locked)
	end)
end
pcall(function()
	if bind() then
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
return finish({
	part = PART,
	mode = "mirror World driven through the real WorldView.enforceLocks; lock = plot attribute + mirrored setBarrierSolid",
	own_plot = ownIndex,
	foreign_plot = foreignIndex,
})
