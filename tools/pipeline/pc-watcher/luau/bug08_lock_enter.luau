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
-- Checks (ok = every non-nil check true):
--   owner_passes             own plot locked: the character walks (Humanoid:MoveTo) from 8 studs outside the entrance to inside (PlotLockGuard.inside)
--   owner_passes_after_respawn  player:LoadCharacter(), the same walk with the new character
--   non_owner_blocked        a locked plot the player does not own: MoveTo from outside for 4 s never gets inside; its panels are CanCollide and in a
--                            group that collides with the character's. n/a when the unlocked control walk cannot reach the inside either
--   eject_once               teleported into that locked plot, sampled every 0.05 s for 4 s: ends outside, exactly ONE position jump (> 10 studs), never
--                            back inside
--   thrown_slime_not_stuck   a free clone of a real slime body (its size / CollisionGroup, CanCollide forced on) is launched at a solid panel: after
--                            3 s it must not rest suspended in the air next to a panel (within 1.5 studs of a face) nor inside the panel
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
local ORDER = { "owner_passes", "owner_passes_after_respawn", "non_owner_blocked", "eject_once", "thrown_slime_not_stuck" }
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
	hum.WalkSpeed = 16
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

local function run()
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
	mode = "mirror World driven through the real WorldView.enforceLocks; lock = plot attribute + mirrored setBarrierSolid",
	own_plot = ownIndex,
	foreign_plot = foreignIndex,
})
