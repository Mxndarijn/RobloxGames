-- Server datamodel (play): default Bat probe (LIVE, not behind FEATURES.PvP; CONTRACT.md §26 "Bat"). PART picks the check (one shot each, <= 45 s):
--   hit   An owner bats a carrying thief and the slime returns home. Two R15 dummies (server-owned, so server physics apply) on a private anchored
--         platform far above the map stand in for the two characters; the REAL Server modules run on a private World (World.new, Sessions.join,
--         Carry.grab, StealService, BatTool.swing with the real BatRules.pickTarget): the thief carries the owner's "gem", the owner swings once,
--         then checks: hit, the thief's carry is nil, world.escaping.gem set (bounces home), StealService.step clears it after
--         ESCAPE_BOUNCE_SECONDS and the owner still has the slime, a knockback was planned away from the owner within Config.BAT.PUSH /
--         PVP.KNOCKBACK_MAX_PUSH and (replicating PvpLaunch.launch on the dummy) the thief really moved away and kept full health; a swing at
--         nothing / a non-carrier returns "nothing in reach" without spending the slap cooldown; a second hit inside SLAP_COOLDOWN is refused.
--   tool  The real player's Bat: exactly one Tool "Bat" across Backpack + Character, CanBeDropped false, single Handle, no collision / query / touch.
-- The live BatTool env is swapped for the probe's and restored (BatTool.getEnv). Result: { ok, summary, detail = { checks, part_delta, emulated } }.
local PART = %%PART%%
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local SSS = game:GetService("ServerScriptService")
local Shared = RS:FindFirstChild("Shared")
local Server = SSS:FindFirstChild("Server")
if not Shared or not Server then
	return { ok = false, summary = "Shared / Server missing", detail = {} }
end
local Config = require(Shared.Config)
local KR = require(Shared.PvpKnockbackRules)
local BatTool = require(Server.BatTool)
local EMULATED = { "mover = PvpLaunch.launch's steps on a dummy (PvpKnockbackRules.velocity + PlatformStand; it needs a real Player)", "the two sessions live in a private World, not the running game" }

local checks, ORDER, errors = {}, {}, {}
local function set(name, ok, info)
	if not checks[name] then
		table.insert(ORDER, name)
	end
	checks[name] = { ok = ok, info = info }
end
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
local partsBefore = countParts()

local function toolCheck()
	local player = Players:GetPlayers()[1]
	if not player then
		set("player", false, "no player in the playtest")
		return
	end
	local found = {}
	for _, container in { player:FindFirstChildOfClass("Backpack"), player.Character } do
		if container then
			for _, c in container:GetChildren() do
				if c.Name == Config.BAT.TOOL_NAME and c:IsA("Tool") then
					table.insert(found, c)
				end
			end
		end
	end
	set("one_bat", #found == 1, { count = #found })
	local bat = found[1]
	if bat then
		local handle = bat:FindFirstChild("Handle")
		set("not_droppable", bat.CanBeDropped == false, { CanBeDropped = bat.CanBeDropped })
		set("handle_inert", handle ~= nil and handle.CanCollide == false and handle.CanTouch == false and handle.CanQuery == false, handle and { CanCollide = handle.CanCollide, CanTouch = handle.CanTouch, CanQuery = handle.CanQuery } or "no Handle")
		local parts = 0
		for _, d in bat:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		set("few_parts", parts >= 1 and parts <= 3, { parts = parts })
	end
end

local function hitCheck()
	local World = require(Server.World)
	local Sessions = require(Server.Sessions)
	local Carry = require(Server.Carry)
	local StealService = require(Server.StealService)
	local PlayerData = require(Shared.PlayerData)
	local PVP = Config.PVP

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
			set("rig", false, "CreateHumanoidModelFromDescription failed")
			return
		end
	end
	local PY = 400
	local platform = Instance.new("Part")
	platform.Name = "PcwBatPlatform"
	platform.Anchored = true
	platform.Size = Vector3.new(100, 4, 100)
	platform.Position = Vector3.new(0, PY - 2, 0)
	platform.Parent = workspace
	track(platform)
	local function dummyAt(x, z)
		local m = template:Clone()
		local root, hum = m.HumanoidRootPart, m:FindFirstChildOfClass("Humanoid")
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = false
			end
		end
		m.PrimaryPart = root
		-- facing +X (LookVector = -Z of the CFrame, so rotate -90 degrees about Y)
		m:PivotTo(CFrame.new(x, PY + 3.5, z) * CFrame.Angles(0, -math.pi / 2, 0))
		m.Parent = workspace
		track(m)
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
		return hum, root
	end
	local ownerHum, ownerRoot = dummyAt(-6, 0)
	local thiefHum, thiefRoot = dummyAt(-1, 0) -- 5 studs in front of the owner
	task.wait(1) -- settle on the platform

	local T = 1_700_000_000
	local world = World.new({ now = T, seed = 7 })
	local function joinWith(userId, slimes)
		local data = PlayerData.new()
		data.padsUnlocked = Config.PADS_MAX
		for _, s in slimes do
			PlayerData.addSlime(data, s)
		end
		return Sessions.join(world, userId, "P" .. userId, data, T)
	end
	local gem = { id = "gem", name = "Blorp", tier = 3, color = { 200, 50, 100 }, size = 1, pattern = "Plain", eyes = "Round", mouth = "Smile", mutation = "None" }
	local owner = joinWith(9001, { gem })
	local thief = joinWith(9002, {})
	local bystander = joinWith(9003, {})
	if not owner or not thief or not bystander then
		set("sessions", false, "Sessions.join failed")
		return
	end
	owner.lockUntil = 0
	local roots = { [9001] = ownerRoot, [9002] = thiefRoot, [9003] = ownerRoot }
	local planned, moved
	local previous = BatTool.getEnv()
	BatTool.setEnv({
		pose = function(userId)
			local root = roots[userId]
			if not root then
				return nil, nil
			end
			local p, look = root.Position, root.CFrame.LookVector
			return { X = p.X, Y = p.Y, Z = p.Z }, { X = look.X, Y = 0, Z = look.Z }
		end,
		mover = function(userId, push)
			local root = roots[userId]
			planned = { userId = userId, X = push.X, Y = push.Y, Z = push.Z }
			local v = KR.velocity(push)
			root.AssemblyLinearVelocity = Vector3.new(v.X, v.Y, v.Z)
			local hum = if userId == 9002 then thiefHum else ownerHum
			hum.PlatformStand = true
			task.delay(PVP.KNOCKBACK_SECONDS, function()
				if hum.Parent then
					hum.PlatformStand = false
				end
			end)
			moved = true
			return true
		end,
	})

	-- 1. nothing to hit: the bystander shares the owner's spot and carries nothing; the thief has not stolen yet
	local hit0, why0 = BatTool.swing(world, owner, T + 100)
	set("whiff_is_harmless", hit0 == false and why0 == "nothing in reach" and owner.lastSlapAt < T, { hit = hit0, why = why0 })
	-- 2. steal, then bat
	local grabbed, grabWhy = Carry.grab(world, 9002, "gem", 1, T + 101)
	set("thief_carries", grabbed == true and thief.carry ~= nil, { ok = grabbed, why = grabWhy })
	local start = thiefRoot.Position
	local hit, why = BatTool.swing(world, owner, T + 102)
	set("bat_hit", hit == true, { hit = hit, why = why })
	set("slime_dropped", thief.carry == nil, nil)
	set("bounces_home", world.escaping.gem ~= nil, { escaping = world.escaping.gem })
	StealService.step(world, T + 102 + World.ESCAPE_BOUNCE_SECONDS + 0.5)
	local mine = PlayerData.findSlime(owner.data, "gem")
	set("slime_back_home", world.escaping.gem == nil and mine ~= nil and world.carriedBy.gem == nil, { has_slime = mine ~= nil })
	set("shares_slap_cooldown", owner.lastSlapAt == T + 102, { lastSlapAt = owner.lastSlapAt - T })
	-- 3. knockback: planned within the limits, away from the owner, and the dummy really moved without losing health
	local pushLen = planned and math.sqrt(planned.X * planned.X + planned.Z * planned.Z) or 0
	set("knockback_planned", planned ~= nil and planned.userId == 9002 and planned.X > 0 and pushLen > 0 and pushLen <= math.min(Config.BAT.PUSH, PVP.KNOCKBACK_MAX_PUSH) + 1e-6, { push = planned, len = pushLen })
	task.wait(1.0)
	local d = Vector3.new(thiefRoot.Position.X - start.X, 0, thiefRoot.Position.Z - start.Z)
	set("thief_pushed_away", moved == true and d.X > 0.5 * pushLen and d.Magnitude <= PVP.KNOCKBACK_MAX_PUSH + 2 and thiefRoot.Position.Y > PY - 3, { displacement = d.Magnitude, planned = pushLen })
	set("nonlethal", thiefHum.Health == thiefHum.MaxHealth and thiefHum.Health > 0, { health = thiefHum.Health })
	-- 4. cooldown: steal again, a second hit inside SLAP_COOLDOWN is refused
	local ok2 = Carry.grab(world, 9002, "gem", 1, T + 103)
	local again, againWhy = BatTool.swing(world, owner, T + 102 + Config.SLAP_COOLDOWN - 0.5)
	set("cooldown_enforced", ok2 == true and again == false and againWhy == "slap on cooldown" and thief.carry ~= nil, { regrabbed = ok2, hit = again, why = againWhy })
	BatTool.setEnv(previous)
end

if PART == "tool" then
	toolCheck()
elseif PART == "hit" then
	local ok, err = pcall(hitCheck)
	if not ok then
		table.insert(errors, tostring(err))
	end
else
	return { ok = false, summary = "unknown PART " .. tostring(PART), detail = {} }
end

for _, i in made do
	pcall(function()
		i:Destroy()
	end)
end
task.wait(0.2)
set("part_delta", countParts() - partsBefore == 0, { delta = countParts() - partsBefore })

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
