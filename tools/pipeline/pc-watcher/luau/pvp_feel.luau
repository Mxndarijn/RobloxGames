-- Server datamodel (play): PvP feel probe (ADVISORY, FEATURES.PvP items, CONTRACT.md §26 / 26.1). Two stand-in characters = R15 dummies
-- (server-owned, so server physics apply) on a private anchored platform far above the map, so the real map never matters and a "kill plane"
-- fall is unmistakable. The real rule modules are required from ReplicatedStorage.Shared (PvpKnockbackRules.plan / velocity, PvpRules.applyControl /
-- applySlow / clampKnockback, PvpTrapRules, PvpBlasterRules, Config.PVP / PVP_TOOLS) and the real ServerScriptService.Server.Carry
-- (targetWalkSpeed). The shot forces FEATURES.PvP (flags field; flag_on is asserted). The handlers need real Players, so the probe calls the same
-- pure rules they use, replicates server/PvpLaunch.launch on a dummy (PvpKnockbackRules.velocity(push) + PlatformStand for KNOCKBACK_SECONDS)
-- and the same WalkSpeed enforcement rule as WorldView.updatePlayer (WalkSpeed := target) from a Heartbeat loop; `detail.emulated` lists what
-- is emulated. Nothing is changed in the world; every dummy / platform is destroyed.
-- PART picks the check (one shot each, <= 45 s):
--   push      KnockGlove1 and KnockGlove5: horizontal displacement ~1.0 s after the launch must be in [0.5 x push, 1.5 x push], <= KNOCKBACK_MAX_PUSH + 2,
--             vertical rise <= KNOCKBACK_ARC_HEIGHT + 3, dummy alive and above the platform.
--   trap      GooTrap1..3: the dummy's WalkSpeed is 0 for the applied control +- 0.25 s, restored after; it barely moves while held (MoveTo 40 studs away).
--   blaster   GooBlaster1..3: WalkSpeed == base x (1 - slow) for slowSeconds +- 0.25 s, restored after; the dummy really walks slower meanwhile.
--   nonlethal every knockback tier (incl. a push at the platform edge with the map clamp logic) and a Bounce Pad launch: every dummy Humanoid.Health
--             == MaxHealth and alive, nobody below FallenPartsDestroyHeight, edge push stays on the platform.
-- Result: { ok, summary, detail = { checks = {name = {ok, info}}, part_delta, emulated } }.
local PART = %%PART%%
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Shared = RS:FindFirstChild("Shared")
if not Shared then
	return { ok = false, summary = "ReplicatedStorage.Shared missing", detail = {} }
end
local Config = require(Shared.Config)
local PvpRules = require(Shared.PvpRules)
local KR = require(Shared.PvpKnockbackRules)
local BR = require(Shared.PvpBlasterRules)
local PVP = Config.PVP
local EMULATED = {
	"mover = PvpLaunch.launch's steps on a dummy (PvpKnockbackRules.velocity + PlatformStand for KNOCKBACK_SECONDS; it needs a Player)",
	"WalkSpeed enforcement = WorldView.updatePlayer's rule from a Heartbeat loop (no real Player session)",
	"freeze / slow timing = PvpRules.applyControl / applySlow + PvpBlasterRules.factorAt",
}

local flagOn = Config.FEATURES.PvP == true
local Server = game:GetService("ServerScriptService"):FindFirstChild("Server")
local launchMod = Server and Server:FindFirstChild("PvpLaunch")
local made = {}
local function track(i)
	table.insert(made, i)
	return i
end
local function countParts()
	local n = 0
	local wild = workspace:FindFirstChild("WildSlimes")
	for _, d in workspace:GetDescendants() do
		if d:IsA("BasePart") and not (wild and d:IsDescendantOf(wild)) then
			n += 1
		end
	end
	return n
end

-- platform: 100 x 100, top at PY, anchored, far above the map
local PY, HALF = 400, 50
local partsBefore = countParts()
local platform = Instance.new("Part")
platform.Name = "PcwPvpPlatform"
platform.Anchored = true
platform.Size = Vector3.new(HALF * 2, 4, HALF * 2)
platform.Position = Vector3.new(0, PY - 2, 0)
platform.Parent = workspace
track(platform)
local TOP = PY

local template
do
	local done = false
	task.spawn(function()
		local ok, m = pcall(function()
			return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
		end)
		if ok and typeof(m) == "Instance" and m:FindFirstChild("HumanoidRootPart") then
			template = m
		end
		done = true
	end)
	local t0 = os.clock()
	while not done and os.clock() - t0 < 6 do
		task.wait(0.1)
	end
	if not template then
		return { ok = false, summary = "no R15 rig", detail = { error = "CreateHumanoidModelFromDescription failed" } }
	end
end
local function dummyAt(x, z)
	local m = template:Clone()
	local root, hum = m.HumanoidRootPart, m:FindFirstChildOfClass("Humanoid")
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = false
		end
	end
	m.PrimaryPart = root
	m:PivotTo(CFrame.new(x, TOP + 3.5, z))
	m.Parent = workspace
	track(m)
	hum.WalkSpeed = 16
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	return hum, root
end
local function xz(v)
	return Vector3.new(v.X, 0, v.Z)
end

-- PvpLaunch.launch for a dummy (it needs a Player): velocity(push) with the default gravity + PlatformStand for KNOCKBACK_SECONDS
local function launch(hum, root, p)
	local v = KR.velocity(p)
	root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, v.Z)
	if hum.Health > 0 and not hum.PlatformStand then
		hum.PlatformStand = true
		task.delay(PVP.KNOCKBACK_SECONDS, function()
			if hum.Parent then
				hum.PlatformStand = false
			end
		end)
	end
	return v
end

local checks, ORDER = {}, {}
local function set(name, ok, info)
	if not checks[name] then
		table.insert(ORDER, name)
	end
	checks[name] = { ok = ok, info = info }
end
local function alive(hum, root)
	return hum.Parent ~= nil and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead and root.Position.Y > TOP - 3
end

-- WalkSpeed enforcement emulation: target(now) every Heartbeat, like WorldView.updatePlayer
local function enforce(hum, targetFn)
	return RunService.Heartbeat:Connect(function()
		local t = targetFn(os.clock())
		if math.abs(hum.WalkSpeed - t) > 0.01 then
			hum.WalkSpeed = t
		end
	end)
end

local function push()
	local jobs = {}
	for _, id in { "KnockGlove1", "KnockGlove5" } do
		local tool = assert(PvpRules.tool(id), id)
		table.insert(jobs, function()
			local idx = if id == "KnockGlove1" then -1 else 1
			local hum, root = dummyAt(idx * 15, 0)
			task.wait(1.5) -- settle on the platform
			local attacker = { X = root.Position.X - 3, Y = root.Position.Y, Z = root.Position.Z }
			local tp = { X = root.Position.X, Y = root.Position.Y, Z = root.Position.Z }
			local bounds = { minX = -HALF - 100, maxX = HALF + 100, minZ = -HALF - 100, maxZ = HALF + 100 } -- platform is far from the map edge
			local _, p = KR.plan(tool, attacker, tp, bounds)
			local start = root.Position
			local v = launch(hum, root, p)
			local t0, maxY, at035 = os.clock(), start.Y, nil
			while os.clock() - t0 < 1.0 do
				task.wait()
				maxY = math.max(maxY, root.Position.Y)
				if not at035 and os.clock() - t0 >= PVP.KNOCKBACK_SECONDS then
					at035 = (xz(root.Position) - xz(start)).Magnitude
				end
			end
			local disp = (xz(root.Position) - xz(start)).Magnitude
			local want = KR.horizontal(p)
			local rise = maxY - start.Y
			local lim = PVP.KNOCKBACK_MAX_PUSH + 2
			local okAll = disp >= 0.5 * want and disp <= 1.5 * want and disp <= lim and rise <= PVP.KNOCKBACK_ARC_HEIGHT + 3 and alive(hum, root)
			set("push_" .. id, okAll, {
				push = want, displacement_1s = disp, displacement_at_launch_end = at035, ratio = disp / math.max(want, 1e-6),
				rise = rise, launch_velocity = { v.X, v.Y, v.Z }, allowed = { 0.5 * want, math.min(1.5 * want, lim) },
				alive = alive(hum, root), health = hum.Health,
			})
		end)
	end
	return jobs
end

local function trapJob()
	local jobs = {}
	for n, id in { "GooTrap1", "GooTrap2", "GooTrap3" } do
		local tool = assert(PvpRules.tool(id), id)
		table.insert(jobs, function()
			local hum, root = dummyAt((n - 2) * 20, 0)
			task.wait(1.5)
			local state = PvpRules.newState()
			local base = 16
			local now = os.clock()
			local applied = PvpRules.applyControl(state, tool.control or 0, now)
			local frozenUntil = now + applied
			local conn = enforce(hum, function(t)
				return if t < frozenUntil then 0 else base
			end)
			local start = root.Position
			local tgt = start + Vector3.new(0, 0, 40)
			local firstZero, lastZero, atEndPos
			local t0 = os.clock()
			while os.clock() - t0 < applied + 1.2 do
				hum:MoveTo(tgt)
				task.wait()
				local rel = os.clock() - t0
				if hum.WalkSpeed == 0 then
					firstZero = firstZero or rel
					lastZero = rel
				end
				if not atEndPos and os.clock() >= frozenUntil then
					atEndPos = (xz(root.Position) - xz(start)).Magnitude
				end
			end
			conn:Disconnect()
			local held = if firstZero and lastZero then lastZero - firstZero else 0
			local restored = hum.WalkSpeed == base
			local moved = (xz(root.Position) - xz(start)).Magnitude
			set("trap_" .. id, firstZero ~= nil and math.abs(held - applied) <= 0.25 and restored and (atEndPos or 99) <= 1.5 and moved > 1.5 and alive(hum, root), {
				control = tool.control, applied = applied, zero_seconds = held, restored = restored, walkspeed_after = hum.WalkSpeed,
				moved_during_hold = atEndPos, moved_after_release = moved, health = hum.Health,
			})
		end)
	end
	return jobs
end

local function blasterJob()
	local jobs = {}
	for n, id in { "GooBlaster1", "GooBlaster2", "GooBlaster3" } do
		local tool = assert(PvpRules.tool(id), id)
		table.insert(jobs, function()
			local hum, root = dummyAt((n - 2) * 20, 0)
			task.wait(1.5)
			local state = PvpRules.newState()
			local factor = BR.slowFactor(tool)
			local base = 16
			local now = os.clock()
			local applied = PvpRules.applySlow(state, tool.slowSeconds or 0, now)
			local untilTime = now + applied
			local conn = enforce(hum, function(t)
				return base * BR.factorAt(factor, untilTime, t)
			end)
			local expect = base * (1 - (tool.slow or 0))
			local firstSlow, lastSlow, wrong = nil, nil, 0
			local posAtStart, posAtEnd
			local t0 = os.clock()
			local dir = Vector3.new(0, 0, 1)
			while os.clock() - t0 < applied + 1.2 do
				hum:Move(dir, false)
				task.wait()
				local rel = os.clock() - t0
				if math.abs(hum.WalkSpeed - expect) <= 0.01 then
					firstSlow = firstSlow or rel
					lastSlow = rel
					posAtStart = posAtStart or root.Position
					posAtEnd = root.Position
				elseif rel < applied - 0.1 and rel > 0.1 then
					wrong += 1
				end
			end
			conn:Disconnect()
			local held = if firstSlow and lastSlow then lastSlow - firstSlow else 0
			local restored = math.abs(hum.WalkSpeed - base) <= 0.01
			local slowSpeed = if posAtStart and posAtEnd and held > 0.3 then (xz(posAtEnd) - xz(posAtStart)).Magnitude / held else nil
			set("blaster_" .. id, firstSlow ~= nil and math.abs(held - applied) <= 0.25 and restored and wrong == 0 and alive(hum, root), {
				slow = tool.slow, slowSeconds = tool.slowSeconds, applied = applied, expected_walkspeed = expect, slow_seconds_seen = held,
				restored = restored, walkspeed_after = hum.WalkSpeed, wrong_samples = wrong, measured_speed_while_slow = slowSpeed, health = hum.Health,
			})
		end)
	end
	return jobs
end

local function nonlethalJob()
	local dummies, jobs = {}, {}
	for n = 1, 5 do
		local id = "KnockGlove" .. n
		local tool = assert(PvpRules.tool(id), id)
		table.insert(jobs, function()
			local hum, root = dummyAt(-40 + n * 14, 0)
			table.insert(dummies, { id = id, hum = hum, root = root })
			task.wait(1.5)
			local p0 = root.Position
			local _, p = KR.plan(tool, { X = p0.X - 3, Y = p0.Y, Z = p0.Z }, { X = p0.X, Y = p0.Y, Z = p0.Z })
			launch(hum, root, p)
			task.wait(1.5)
		end)
	end
	-- edge: dummy 2 studs inside the platform edge pushed outward; the platform plays the part of the map, plan clamps to bounds minus margin
	table.insert(jobs, function()
		local hum, root = dummyAt(0, HALF - 2)
		table.insert(dummies, { id = "edge", hum = hum, root = root })
		task.wait(1.5)
		local box = { minX = -HALF, maxX = HALF, minZ = -HALF, maxZ = HALF }
		local p0 = root.Position
		local landing, p = KR.plan(PvpRules.tool("KnockGlove5"), { X = p0.X, Y = p0.Y, Z = p0.Z - 3 }, { X = p0.X, Y = p0.Y, Z = p0.Z }, box)
		launch(hum, root, p)
		task.wait(1.5)
		set("edge_clamp", landing.Z <= HALF - PVP.KNOCKBACK_BOUNDS_MARGIN + 1e-6 and math.abs(root.Position.Z) < HALF, {
			planned_landing_z = landing.Z, limit = HALF - PVP.KNOCKBACK_BOUNDS_MARGIN, final_z = root.Position.Z,
		})
	end)
	-- the real map edge through the pure clamp (nobody is pushed there)
	local mb = PVP.MAP_BOUNDS
	local landing = KR.plan(PvpRules.tool("KnockGlove5"), { X = mb.maxX - 6, Y = 5, Z = 0 }, { X = mb.maxX - 3, Y = 5, Z = 0 })
	set("map_edge_clamp", landing.X <= mb.maxX - PVP.KNOCKBACK_BOUNDS_MARGIN + 1e-6, { landing_x = landing.X, limit = mb.maxX - PVP.KNOCKBACK_BOUNDS_MARGIN })
	-- Bounce Pad launch (FunBouncePad height, control): straight up
	table.insert(jobs, function()
		local tool = assert(PvpRules.tool("FunBouncePad"))
		local hum, root = dummyAt(-30, -30)
		table.insert(dummies, { id = "bounce", hum = hum, root = root })
		task.wait(1.5)
		launch(hum, root, { X = 0, Y = tool.height or 0, Z = 0 })
		local maxY, t0 = root.Position.Y, os.clock()
		while os.clock() - t0 < 3 do
			task.wait()
			maxY = math.max(maxY, root.Position.Y)
		end
		set("bounce_pad_rise", true, { height = tool.height, apex_rise = maxY - (TOP + 3.5) })
	end)
	return jobs, dummies
end

set("flag_on", flagOn, { PvP = Config.FEATURES.PvP, PvpLaunch_module = launchMod ~= nil })
local jobs, dummies = {}, nil
if PART == "push" then
	jobs = push()
elseif PART == "trap" then
	jobs = trapJob()
elseif PART == "blaster" then
	jobs = blasterJob()
elseif PART == "nonlethal" then
	jobs, dummies = nonlethalJob()
else
	return { ok = false, summary = "unknown PART " .. tostring(PART), detail = {} }
end

local pending = #jobs
local errors = {}
for _, job in jobs do
	task.spawn(function()
		local ok, err = pcall(job)
		if not ok then
			table.insert(errors, tostring(err))
		end
		pending -= 1
	end)
end
local t0 = os.clock()
while pending > 0 and os.clock() - t0 < 30 do
	task.wait(0.1)
end

if PART == "nonlethal" then
	local list, bad = {}, 0
	local kill = workspace.FallenPartsDestroyHeight
	for _, d in dummies do
		local hum = d.hum
		local good = hum.Parent ~= nil and hum.Health == hum.MaxHealth and hum.Health > 0 and hum:GetState() ~= Enum.HumanoidStateType.Dead and d.root.Position.Y > kill
		if not good then
			bad += 1
		end
		table.insert(list, { id = d.id, health = hum.Health, max = hum.MaxHealth, y = d.root.Position.Y, ok = good })
	end
	set("nonlethal", bad == 0 and #list == 7, { dummies = list, kill_plane_y = kill })
end

for _, i in made do
	pcall(function()
		i:Destroy()
	end)
end
task.wait(0.2)
local delta = countParts() - partsBefore
set("part_delta", delta == 0, { delta = delta })

local parts, allOk = {}, true
for _, name in ORDER do
	local c = checks[name]
	table.insert(parts, name .. " " .. (if c.ok == true then "PASS" elseif c.ok == false then "FAIL" else "n/a"))
	if c.ok == false then
		allOk = false
	end
end
if #errors > 0 then
	allOk = false
	table.insert(parts, "errors: " .. table.concat(errors, "; "):sub(1, 200))
end
return { ok = allOk, summary = table.concat(parts, ", "), detail = { checks = checks, part = PART, emulated = EMULATED, errors = errors } }
