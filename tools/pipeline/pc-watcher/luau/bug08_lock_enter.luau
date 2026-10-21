-- Server datamodel: bug probe 8 (ADVISORY), a locked base: the owner walks in, everybody else is kept out (PlotLockGuard + WorldView.enforceLocks,
-- #251). Each plot is a goo jar tower (CONTRACT.md §5.3): jar 1's glass wall (Plot_<i>.Jar: Wall_2..Wall_24 + DoorLintel over the doorway at plot-local
-- -Z) and ONE lock part, LockBarrier.Stopper, that fills the doorway. The REAL test player (the only real Player) owns one plot; the lock is driven
-- through the game's own code:
--   * enforceLocks(world, player) is the real WorldView function. The live `world` is a local of init.server and is not reachable, so a
--     MIRROR pure World (World.new + Sessions.join, as server_steal_sim does) holds the same owner of the player's plot (real PlotIndex) and a
--     fake owner (userId -9001) of a plot the player does not own. The driver calls the real enforceLocks(mirror, player) every physics step
--     (RunService.Stepped), so the group assignment (owner / PlotLeaver / Default) is the shipped code, not a reimplementation.
--   * the lock itself is the plot attribute Locked (what enforceLocks reads; the live 10 Hz updatePlots rewrites it, so the driver re-asserts
--     it every step) and the LockBarrier parts (CanCollide + CollisionGroup PlotLock_<i> exactly as WorldView.setBarrierSolid leaves them; that
--     function is file-local, so it is mirrored). The collision groups PlotLock_<i> / PlotOwner_<i> and the character's group come from the game.
--   * a plot own to the player that the live server has locked right now (join lock, first 45 s) is reported as live_own_panels (the real
--     setBarrierSolid result, read before the driver touches anything).
-- "Inside" is the shipped rule: PlotLockGuard.inside with the jar's inner radius at the character's height (WorldLayout.jarRadius(floorAt(y)));
-- "trapped" adds the doorway passage (WorldLayout.doorway()), as enforceLocks does.
-- The real character is unanchored for the probe (network ownership to the server) and restored: CFrame, Anchored, owner, WalkSpeed.
-- Checks (ok = every non-nil check of the PART true; PART "base" = the first five, each other PART = the one check of that name):
--   owner_passes             own plot locked: the character walks (Humanoid:MoveTo) from 8 studs outside the plot, over the bridge and through the
--                            doorway, to the spawn spot inside the jar (PlotLockGuard.inside)
--   owner_passes_after_respawn  player:LoadCharacter(), the same walk with the new character
--   non_owner_blocked        a locked plot the player does not own: the same walk for 4 s never gets inside; its LockBarrier parts are CanCollide and in a
--                            group that collides with the character's. n/a when the unlocked control walk cannot reach the inside either
--   leaves_freely            the stopper is one-way, nobody is ever moved: teleported (probe setup) onto the spawn spot inside that locked jar the
--                            character gets the PlotLeaver group, walks out through the door (MoveTo, up to 14 s) and ends clear of the jar and the
--                            doorway; every 0.05 s sample moves <= 3 studs (no teleport / throw); then it MoveTos back in for 4 s and never gets inside
--   thrown_slime_not_stuck   a free clone of a real slime body (its size / CollisionGroup, CanCollide forced on) is lobbed from the bridge at the solid
--                            stopper: after 3 s it must not rest suspended in the air next to it (within 1.5 studs of a face) nor inside it
--   leave_on_lock            (shot 222) the character stands on the spawn spot of a free plot, the plot is locked with it inside: the same walk out as
--                            leaves_freely (PlotLeaver, no step > 3 studs, ends clear, flips back, cannot walk back in)
--   owner_door               own plot locked: the OWNER walks through the doorway IN (to 6 studs past it, short of the pads) and back OUT on three lanes (x = 0, +-1.5),
--                            each walk MoveTo up to 5 s; plus carry_clearance: no part that collides with the owner's character group (CanCollide,
--                            RespectCanCollide) inside a 7 x 7 stud box through the doorway (plot-local y 1.5..8.5, the stopper's depth + 2 each side),
--                            i.e. the glass and lintel leave the owner's walk and slime-carry route open; the stopper is in the owner's pass group
-- Real-character wall checks against the locked FOREIGN plot: the real character (unanchored, server-owned, the game's own WalkSpeed 16 and Humanoid jump
-- settings, never raised) tries to get in. Every attempt samples the root every 0.05 s: ever_inside (PlotLockGuard.inside), first_inside_s,
-- max_penetration (studs the root centre got inside the glass's outer surface, the radius measured from the real Wall_* parts; a blocked root stays
-- >= 0.5 outside it), jumped (a position jump > 10 studs: nothing may move the character, so any is reported). An attempt FAILS when ever_inside is true or
-- max_penetration > 0. ok = every attempt stayed out, false = any got in, n/a = geometry not found or no time left (each check is its own PART with a 32 s
-- attempt budget, most important attempts first; attempts end early when the character stalls for 1.5 s). Reset between attempts: teleport, zero
-- velocity, wait 0.3 s. Door attempts aim at the stopper's real CFrame / size; glass spots at the real Wall_* centres (middle) and between two neighbours
-- (joint).
--   door_walk                from the bridge, no jumping: straight at the stopper centre and at both stopper / glass seams (x = +-(half width - 1.6)),
--                            then 45 degree approaches at both seams (from the opening side and from the glass side)
--   door_jump                the same straight lanes jumping every 0.25 s, plus a running jump from 16 studs out
--   glass_push               the glass round the jar, no jumping: a wall middle and a joint on the right side (plot-local angle ~0), the same on the left
--                            (~180) and a middle at the back-left (~150); start 4 studs outside the glass, MoveTo 8 studs inside the jar
--   glass_jump               the same spots, jumping every 0.25 s
-- Everything made is destroyed; the lock attributes / LockBarrier parts are restored; the character ends where it started, with its Anchored states.
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
		WorldLayout = require(RS.Visuals.WorldLayout),
		PlayerData = require(Shared.PlayerData),
		Config = require(Shared.Config),
		Constants = require(Shared.Constants),
	}
end)
if not reqOk then
	return { ok = false, summary = "require failed: " .. tostring(mods), detail = {} }
end
local World, Sessions, WorldView, Guard, WL = mods.World, mods.Sessions, mods.WorldView, mods.Guard, mods.WorldLayout
local LOCKED = mods.Constants.PLOT_LOCKED_ATTRIBUTE
-- PART = "base" (the five checks, ~50 s) | "door_walk" | "door_jump" | "glass_push" | "glass_jump" | "owner_door" | "leave_on_lock" (that one check
-- only, 32 s attempt budget): a single execute_luau call must stay well under 60 s, so the checks are split over several calls.
local PART = %%PART%%
local BASE_ORDER = { "owner_passes", "owner_passes_after_respawn", "non_owner_blocked", "leaves_freely", "thrown_slime_not_stuck" }
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
local locks = {} -- plot index -> true: the driver keeps these plots locked + their LockBarrier parts solid
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

-- geometry helpers (Base frame = plot-local, door at -Z) -------------------------------------------------------------------------------------
local DOORWAY = WL.doorway()
local DOOR = { halfWidth = DOORWAY.halfWidth, zOuter = DOORWAY.zOuter }
local SPAWN_Z = WL.SPAWN_SPOT[2]
local function r1(x)
	return math.floor(x * 10 + 0.5) / 10
end
local function r2(v)
	return { r1(v.X), r1(v.Z) }
end
local function frameOf(i)
	local base = plotByIndex[i].Base
	return base.CFrame, base.Size.X / 2, base.Size.Y / 2
end
local function localPos(i)
	local cf = frameOf(i)
	return cf:PointToObjectSpace(root.Position)
end
-- Inner radius of the jar at Base-frame height y (enforceLocks: jarRadius(floorAt(y + Base half height))).
local function radiusAt(i, y)
	local _, _, halfY = frameOf(i)
	return WL.jarRadius(WL.floorAt(y + halfY))
end
local function insideNow(i)
	local p = localPos(i)
	return Guard.inside(p.X, p.Y, p.Z, radiusAt(i, p.Y))
end
local function trappedNow(i)
	local p = localPos(i)
	return Guard.trapped(p.X, p.Y, p.Z, radiusAt(i, p.Y), DOOR)
end
local function outsidePoint(i, x)
	local cf, half = frameOf(i)
	return cf * CFrame.new(x or 0, 4, -(half + 8)) * CFrame.Angles(0, math.pi, 0)
end
local function placeOutside(i)
	teleport(outsidePoint(i))
	task.wait(0.4)
end
-- Walk from outside the plot, over the bridge and through the doorway, to the spawn spot. Returns {inside, ever_inside, secs}.
local function walkIn(i, secs, stopWhenInside)
	local cf = frameOf(i)
	local target = cf:PointToWorldSpace(Vector3.new(0, 4, SPAWN_Z))
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
local SEARCHED = "Plot_<i>.Jar Wall_* / DoorLintel and LockBarrier.Stopper"
local function polar(r, deg)
	local a = math.rad(deg)
	return Vector3.new(r * math.cos(a), 0, r * math.sin(a))
end
local function angleOf(v)
	return math.deg(math.atan2(v.Z, v.X))
end
local function angleDiff(a, b)
	return (a - b + 180) % 360 - 180
end
-- Jar 1 of plot i in the Base frame, from the real parts: walls {name, angle, radius, can_collide}, the glass outer radius, the stopper box.
local function jarGeometry(i)
	local plot = plotByIndex[i]
	local cf = frameOf(i)
	local jar = plot:FindFirstChild("Jar")
	local walls, outer, n = {}, 0, 0
	if jar then
		for _, w in jar:GetChildren() do
			if w:IsA("BasePart") and (string.match(w.Name, "^Wall_%d+$") or w.Name == "DoorLintel") then
				local rel = cf:ToObjectSpace(w.CFrame)
				local c = Vector3.new(rel.Position.X, 0, rel.Position.Z)
				local thick = math.min(w.Size.X, w.Size.Z)
				table.insert(walls, { name = w.Name, angle = angleOf(c), radius = c.Magnitude, can_collide = w.CanCollide, lintel = w.Name == "DoorLintel" })
				outer += c.Magnitude + thick / 2
				n += 1
			end
		end
	end
	table.sort(walls, function(a, b)
		return a.angle < b.angle
	end)
	local stopper
	local s = plot.LockBarrier:FindFirstChild("Stopper")
	if s and s:IsA("BasePart") then
		local rel = cf:ToObjectSpace(s.CFrame)
		local ex = math.abs(rel.RightVector.X) * s.Size.X / 2 + math.abs(rel.UpVector.X) * s.Size.Y / 2 + math.abs(rel.LookVector.X) * s.Size.Z / 2
		local ez = math.abs(rel.RightVector.Z) * s.Size.X / 2 + math.abs(rel.UpVector.Z) * s.Size.Y / 2 + math.abs(rel.LookVector.Z) * s.Size.Z / 2
		stopper = { x = rel.Position.X, half = ex, zOuter = rel.Position.Z - ez, zInner = rel.Position.Z + ez }
	end
	return {
		walls = walls,
		count = n,
		glassOuter = if n > 0 then outer / n else WL.jarRadius(1) + WL.JAR_WALL,
		inner = WL.jarRadius(1),
		stopper = stopper,
	}
end
-- Wall nearest plot-local angle `deg` (DoorLintel excluded) and, for a joint, its neighbour on the side of `deg`.
local function wallSpot(g, deg, joint)
	local best, bestK, bestD = nil, nil, math.huge
	for k, w in g.walls do
		local d = math.abs(angleDiff(w.angle, deg))
		if not w.lintel and d < bestD then
			best, bestK, bestD = w, k, d
		end
	end
	if not best then
		return nil
	end
	if not joint then
		return best.angle, best.name
	end
	local m = #g.walls
	local side = if angleDiff(deg, best.angle) >= 0 then 1 else -1
	local nb = g.walls[(bestK - 1 + side) % m + 1]
	if not nb or nb.lintel then
		return nil
	end
	return best.angle + angleDiff(nb.angle, best.angle) / 2, best.name .. "|" .. nb.name
end

local checkStart
-- One attempt: from startL to targetL (plot-local x, z), MoveTo for up to 4 s. Penetration = studs the root centre is inside the glass's outer surface.
local function attempt(i, g, label, startL, targetL, jump)
	local cf = frameOf(i)
	local y = 4
	teleport(cf * CFrame.lookAt(Vector3.new(startL.X, y, startL.Z), Vector3.new(targetL.X, y, targetL.Z)))
	hum.Jump = false
	task.wait(0.3)
	local target = cf:PointToWorldSpace(Vector3.new(targetL.X, y, targetL.Z))
	local rec = { label = label, start = r2(startL), target = r2(targetL), jump = jump, ever_inside = false, jumped = false, max_penetration = -99 }
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
			rec.jumped = true
		end
		last = pos
		local lp = cf:PointToObjectSpace(pos)
		rec.max_penetration = math.max(rec.max_penetration, g.glassOuter - Vector3.new(lp.X, 0, lp.Z).Magnitude)
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
local function runCheck(name, i, build)
	checkStart = os.clock()
	local deadline = checkStart + ATTEMPT_BUDGET
	local okG, g = pcall(jarGeometry, i)
	if not okG or g.count == 0 or not g.stopper then
		set(name, nil, "jar geometry not found under the plot (searched: " .. SEARCHED .. ")" .. (if okG then "" else " " .. tostring(g)))
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
		set(name, nil, "jar geometry incomplete (no glass spot found); glass parts: " .. tostring(g.count))
		return
	end
	local recs, skipped, anyIn = {}, 0, false
	for _, a in list do
		if os.clock() + 4.7 > deadline then -- an attempt takes up to 0.3 + 4 s plus the reset
			skipped += 1
		else
			local okA, rec = pcall(attempt, i, g, a.label, a.start, a.target, a.jump)
			if okA then
				rec.wall = a.wall
				table.insert(recs, rec)
				anyIn = anyIn or rec.ever_inside or rec.max_penetration > 0
				if rec.ever_inside or rec.ended_inside then
					teleport(outsidePoint(i))
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
	local solid = 0
	for _, w in g.walls do
		solid += if w.can_collide then 1 else 0
	end
	local info = {
		attempts = recs,
		skipped_for_time = skipped,
		glass_parts = g.count,
		glass_colliding = solid,
		glass_outer_radius = r1(g.glassOuter),
		stopper = { x = r1(g.stopper.x), half_width = r1(g.stopper.half), z_outer = r1(g.stopper.zOuter), z_inner = r1(g.stopper.zInner) },
		seconds = r1(os.clock() - checkStart),
	}
	if skipped > 0 then
		info.note = skipped .. " attempt(s) did not fit the " .. ATTEMPT_BUDGET .. " s budget (n/a)"
	end
	set(name, if anyIn then false elseif ran > 0 then true else nil, info)
	teleport(outsidePoint(i))
end

-- The doorway from the bridge: straight lanes at the stopper centre and its two seams with the glass, 45 degree approaches at the seams.
local function doorList(g, jump)
	local st = g.stopper
	local list = {}
	local tag = if jump then " jump" else ""
	local seam = math.max(st.half - 1.6, 0)
	local zStart, zIn = st.zOuter - 4, st.zInner + 12
	for k, x in { st.x, st.x - seam, st.x + seam } do
		local nm = if k == 1 then "centre" elseif k == 2 then "left seam" else "right seam"
		table.insert(list, { label = "door " .. nm .. " straight" .. tag, start = Vector3.new(x, 0, zStart), target = Vector3.new(x, 0, zIn), jump = jump, pri = if k == 1 then 1 else 2 })
	end
	if jump then
		table.insert(list, { label = "door running jump 16 out", start = Vector3.new(st.x, 0, st.zOuter - 16), target = Vector3.new(st.x, 0, zIn), jump = true, pri = 1 })
	else
		for _, sign in { -1, 1 } do
			local aim = Vector3.new(st.x + sign * seam, 0, st.zOuter)
			for _, from in { -1, 1 } do -- from = -sign: coming from the opening side; from = sign: from the glass side
				local d = Vector3.new(-from, 0, 1).Unit
				table.insert(list, {
					label = "door " .. (if sign < 0 then "left" else "right") .. " seam diag from " .. (if from == -sign then "opening" else "glass"),
					start = aim - d * (4 / d.Z), target = aim + d * 12, jump = false, pri = 3,
				})
			end
		end
	end
	return list
end
local function doorWalkList(g)
	return doorList(g, false)
end
local function doorJumpList(g)
	return doorList(g, true)
end
-- The glass round the jar: a wall middle and a joint on each side, a middle at the back-left; start 4 studs outside, aim 8 studs inside.
local GLASS_SPOTS = { { 0, false, 1 }, { 0, true, 1 }, { 180, false, 2 }, { 180, true, 2 }, { 150, false, 3 } }
local function glassList(g, jump)
	local list = {}
	local tag = if jump then " jump" else ""
	for _, spot in GLASS_SPOTS do
		local deg, name = wallSpot(g, spot[1], spot[2])
		if deg then
			table.insert(list, {
				label = "glass " .. (if spot[2] then "joint" else "middle") .. " at " .. r1(deg % 360) .. " deg" .. tag,
				wall = name,
				start = polar(g.glassOuter + 4, deg),
				target = polar(g.inner - 8, deg),
				jump = jump,
				pri = spot[3],
			})
		end
	end
	return list
end
local function glassPushList(g)
	return glassList(g, false)
end
local function glassJumpList(g)
	return glassList(g, true)
end

local function runWall()
	free()
	if not foreignIndex then
		set(PART, nil, "no unowned, unlocked plot with a LockBarrier to use as the foreign plot")
		return
	end
	lockPlot(foreignIndex, true)
	placeOutside(foreignIndex)
	local builders = { door_walk = doorWalkList, door_jump = doorJumpList, glass_push = glassPushList, glass_jump = glassJumpList }
	runCheck(PART, foreignIndex, builders[PART])
	lockPlot(foreignIndex, false)
end

-- owner_door: the owner through the locked doorway both ways + carry clearance in the doorway -----------------------------------------------
local function walkTo(i, xL, zL, secs)
	local cf = frameOf(i)
	local target = cf:PointToWorldSpace(Vector3.new(xL, 4, zL))
	local t0 = os.clock()
	while os.clock() - t0 < secs do
		hum:MoveTo(target)
		task.wait(0.05)
		if not root.Parent then
			break
		end
		local l = cf:PointToObjectSpace(root.Position)
		if Vector3.new(l.X - xL, 0, l.Z - zL).Magnitude <= 2 then
			break
		end
	end
	local l = cf:PointToObjectSpace(root.Position)
	return { end_local = { r1(l.X), r1(l.Z) }, secs = r1(os.clock() - t0) }
end
local function runOwnerDoor()
	free()
	if not ownIndex then
		set("owner_door", nil, "the test player owns no plot (no OwnerUserId match)")
		return
	end
	local i = ownIndex
	local cf, half = frameOf(i)
	lockPlot(i, true)
	task.wait(0.2)
	local lanes, allOk, info = {}, true, { plot = i, owner_group = nil }
	for _, x in { 0, -1.5, 1.5 } do
		teleport(outsidePoint(i, x))
		task.wait(0.4)
		info.owner_group = root.CollisionGroup
		local rin = walkTo(i, x, DOORWAY.zInner + 6, 5) -- inside the jar, short of the pad ring
		rin.inside = insideNow(i)
		local rout = walkTo(i, x, -(half + 8), 5)
		local lz = localPos(i).Z
		rout.outside = (not trappedNow(i)) and lz < DOOR.zOuter - 2
		lanes["x=" .. x] = { walk_in = rin, walk_out = rout }
		allOk = allOk and rin.inside and rout.outside
	end
	info.lanes = lanes
	-- carry clearance: parts colliding with the owner's character group in the doorway
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { char }
	op.RespectCanCollide = true
	op.CollisionGroup = root.CollisionGroup
	local depth = DOORWAY.zInner - DOORWAY.zOuter + 4
	local box = cf * CFrame.new(0, 4.5, (DOORWAY.zOuter + DOORWAY.zInner) / 2)
	local hits = {}
	for _, part in workspace:GetPartBoundsInBox(box, Vector3.new(7, 7, depth), op) do
		if part.CanCollide and PhysicsService:CollisionGroupsAreCollidable(part.CollisionGroup, root.CollisionGroup) then
			table.insert(hits, part:GetFullName() .. " [" .. part.CollisionGroup .. "]")
		end
	end
	info.carry_clearance = {
		blocking = hits,
		box = string.format("7 x 7 x %.1f studs through the doorway (plot-local x -3.5..3.5, y 1.5..8.5, z %.1f..%.1f)", depth, DOORWAY.zOuter - 2, DOORWAY.zInner + 2),
	}
	lockPlot(i, false)
	set("owner_door", allOk and #hits == 0, info)
end

-- leave_on_lock / leaves_freely: the stopper is one-way and nobody is ever moved. The character stands on the spawn spot inside jar i (probe setup
-- teleport, or it was there when the owner locked: `lockAfter`), has the PlotLeaver group, walks out through the door and ends clear of the jar and
-- the doorway with no sample step > 3 studs (a teleport / throw would be 10+), then walks back in and is blocked (never trapped again).
local function leaveWalk(i, lockAfter)
	local cf = frameOf(i)
	lockPlot(i, not lockAfter)
	teleport(cf * CFrame.new(0, 4, SPAWN_Z)) -- probe setup: the character is in the jar
	task.wait(0.4)
	local startedInside = trappedNow(i)
	if lockAfter then
		lockPlot(i, true) -- the owner locks while the character stands inside
		task.wait(0.4)
	end
	local groupInside = root.CollisionGroup
	local out = cf:PointToWorldSpace(Vector3.new(0, 4, DOOR.zOuter - 10))
	local t0, last, maxStep, samples = os.clock(), root.Position, 0, 0
	while os.clock() - t0 < 14 and trappedNow(i) do
		hum:MoveTo(out)
		task.wait(0.05)
		maxStep = math.max(maxStep, (root.Position - last).Magnitude)
		last = root.Position
		samples += 1
	end
	local walkSecs = os.clock() - t0
	local outside = not trappedNow(i)
	t0 = os.clock()
	while os.clock() - t0 < 1 do -- settle past the exit margin so the group flips back
		hum:MoveTo(out)
		task.wait(0.05)
		maxStep = math.max(maxStep, (root.Position - last).Magnitude)
		last = root.Position
	end
	local groupOutside = root.CollisionGroup
	local back = walkIn(i, 4, false)
	local okAll = startedInside and groupInside == Guard.LEAVER_GROUP and outside and maxStep <= 3 and not back.ever_inside and not trappedNow(i)
	return okAll, {
		started_inside = startedInside, group_inside = groupInside, group_outside = groupOutside, outside = outside, max_step = r1(maxStep),
		samples = samples, walk_secs = r1(walkSecs), reentered = back.ever_inside, locked_after_entering = lockAfter, jar_radius = WL.jarRadius(1),
		door_z_outer = r1(DOOR.zOuter),
	}
end
local function runLeaveOnLock()
	free()
	if not foreignIndex then
		set("leave_on_lock", nil, "no unowned, unlocked plot with a LockBarrier to use as the foreign plot")
		return
	end
	local okAll, info = leaveWalk(foreignIndex, true)
	lockPlot(foreignIndex, false)
	set("leave_on_lock", okAll, info)
end

local function run()
	if PART == "leave_on_lock" then
		runLeaveOnLock()
		return
	end
	if PART == "owner_door" then
		runOwnerDoor()
		return
	end
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
		local cf = frameOf(foreignIndex)
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
		-- ---- d) leaves freely (one-way stopper, never moved) ----
		local lfOk, lfInfo = leaveWalk(foreignIndex, false)
		set("leaves_freely", lfOk, lfInfo)
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
		local _, half = frameOf(foreignIndex)
		teleport(cf * CFrame.new(0, 4, -(half + 40))) -- the character out of the way
		slime.CFrame = cf * CFrame.new(0, 6, DOOR.zOuter - 14)
		slime.Parent = workspace
		table.insert(made, slime)
		slime.AssemblyLinearVelocity = cf:VectorToWorldSpace(Vector3.new(0, 28, 50)) -- lobbed from the bridge at the stopper, ~mid height
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
		for _, n in { "non_owner_blocked", "leaves_freely", "thrown_slime_not_stuck" } do
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
