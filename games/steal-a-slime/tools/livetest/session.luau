--!nocheck
--[[
	Scripted stand-in player session (Lune, no Studio, no network):

	  rojo build -o build.rbxlx
	  lune run tools/livetest/session build.rbxlx [--verbose] [--json out.json]

	Boots the real ServerScriptService.Server from the place in the fake
	runtime (Runtime.luau) on the in-memory store, joins one player with a
	character and plays through the Request remote and the world
	ProximityPrompts like a client would. The only shortcut is
	Server.TestHooks (grant cash / skip time), which refuses to run unless
	DataStoreMode = "Memory" (CONTRACT.md §8.12). Scenarios:

	  coil   buy the Speed Coil, measure Humanoid.WalkSpeed before / after,
	         while carrying and after a respawn
	  drop   a dropped slime lands on the first collidable surface
	  lockbuy / rare / loop   plot prompts, Legendary+ drops,
	         first grab -> rebirth 8
	  ui     the real State / attributes / prompts through the pure src/ui
	         modules: BuyUpgrade row, goals, dex, lock / pad buttons,
	         PromptHide, Boss banner (State.boss)

	Prints PASS / FAIL per check and exits 1 on any FAIL. The cloud twin is
	tools/livetest/cloud/session.luau (Luau Execution, ci/run.py).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Runtime = require("./Runtime")

local CFrame, Vector3, Instance = roblox.CFrame, roblox.Vector3, roblox.Instance

local path, verbose, jsonOut = "build.rbxlx", false, nil
do
	local i = 1
	while i <= #process.args do
		local arg = process.args[i]
		if arg == "--verbose" then
			verbose = true
		elseif arg == "--json" then
			i += 1
			jsonOut = process.args[i]
		else
			path = arg
		end
		i += 1
	end
end

local USER_ID = 4242
local rt = Runtime.new(path, { verbose = verbose })
rt.workspace:SetAttribute("DataStoreMode", "Memory")

-- Expose the server's top-level state to this session (in memory only, like ci/playtest.luau).
local server = rt.game:GetService("ServerScriptService"):FindFirstChild("Server")
assert(server, "ServerScriptService.Server missing")
server.Source = server.Source
	.. "\n_G.__session = { world = world, refreshView = refreshView, WorldView = WorldView, Carry = Carry, World = World }\n"
rt:boot()
rt:advance(1)
local S = _G.__session
assert(S and S.world, "server did not export its world")
local world = S.world
local TestHooks = rt:require(server:FindFirstChild("TestHooks"))
local Remotes = rt.game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
local request = Remotes:FindFirstChild("Request")

local checks = {}
local function check(name, ok, detail)
	table.insert(checks, { name = name, ok = ok == true, detail = tostring(detail or "") })
	print(`{if ok then "PASS" else "FAIL"}  {name}: {detail or ""}`)
end

local player = rt:addPlayer(USER_ID, "StandIn", Vector3.new(0, 10, 0))
rt:advance(1)
local session = world.sessions[USER_ID]
assert(session, "stand-in player did not get a session")
check("TestHooks enable on DataStoreMode = Memory", TestHooks.enable(world), "memory store")

local function humanoid()
	return player.Character and player.Character:FindFirstChildOfClass("Humanoid")
end
local function root()
	return player.Character and player.Character:FindFirstChild("HumanoidRootPart")
end
local function invoke(action, ...)
	local res = request.OnServerInvoke(player, action, ...)
	rt:advance(0.3)
	return res
end
local function moveTo(position)
	root().CFrame = CFrame.new(position)
	rt:advance(0.2)
end
local function plotPart(name)
	local plot = S.WorldView.plot(session.plotIndex)
	return plot and plot:FindFirstChild(name)
end
local function respawn()
	local old = player.Character
	if old then
		old:Destroy()
	end
	local character = Instance.new("Model")
	character.Name = player.Name
	local part = Instance.new("Part")
	part.Name = "HumanoidRootPart"
	part.Size = Vector3.new(2, 2, 1)
	part.CFrame = CFrame.new(0, 10, 0)
	part.Parent = character
	local hum = Instance.new("Humanoid")
	hum.Health = 100
	hum.WalkSpeed = 16
	hum.Parent = character
	character.PrimaryPart = part
	character.Parent = rt.workspace
	player.Character = character
	player.CharacterAdded:Fire(character)
	rt:advance(0.5)
end
local function nearestWild()
	local best, bestD = nil, math.huge
	for id in world.wild do
		local settled = world.wild[id].spawnedAt < rt.workspace:GetServerTimeNow() - 1.5 -- volcano arc done
		if not world.carriedBy[id] and settled then
			local pos = S.WorldView.slimePosition(id)
			if pos then
				local d = (pos - root().CFrame.Position).Magnitude
				if d < bestD then
					best, bestD = id, d
				end
			end
		end
	end
	return best
end
local function grabWild()
	rt:advance(5) -- let the volcano drop something
	local id = nearestWild()
	assert(id, "no wild slime")
	TestHooks.grantCash(world, USER_ID, world.wild[id].price) -- afford a "Buy $" drop
	local body = S.WorldView.slimeBody(id)
	moveTo(body.CFrame.Position + Vector3.new(2, 2, 0))
	body:FindFirstChild("GrabPrompt").Triggered:Fire(player)
	rt:advance(0.3)
	if world.carriedBy[id] ~= USER_ID then
		local last = rt.records[#rt.records]
		local why = last and last.name == "Notify" and last.args[1] or "?"
		error(`grab of {id} failed (price {world.wild[id] and world.wild[id].price}): {why}`)
	end
	return id
end
local function scenario(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		check(`{name} (scenario ran)`, false, err)
	end
end

---------------------------------------------------------------------------
-- coil: buy the Speed Coil and measure the speed change
---------------------------------------------------------------------------
scenario("coil", function()
	local before = humanoid().WalkSpeed
	TestHooks.grantCash(world, USER_ID, 1500)
	local res = invoke("BuySpeedCoil")
	rt:advance(0.5)
	local after = humanoid().WalkSpeed
	check(
		"coil: buying raises WalkSpeed",
		res.ok and after > before + 4,
		`Request ok={res.ok} {res.message or ""}; WalkSpeed {before} -> {after}, TargetWalkSpeed={player:GetAttribute(
			"TargetWalkSpeed"
		)}`
	)
	local backpack = player:FindFirstChildOfClass("Backpack")
	check(
		"coil: SpeedCoil tool granted",
		backpack and backpack:FindFirstChild("SpeedCoil") ~= nil,
		"Backpack.SpeedCoil"
	)
	-- A speed the server didn't set itself (v12 then left it alone forever).
	humanoid().WalkSpeed = 19
	rt:advance(0.3)
	check(
		"coil: server re-applies a foreign WalkSpeed",
		math.abs(humanoid().WalkSpeed - after) < 0.01,
		`19 -> {humanoid().WalkSpeed}`
	)
	respawn()
	check(
		"coil: kept after respawn",
		math.abs(humanoid().WalkSpeed - after) < 0.01,
		`new character WalkSpeed {humanoid().WalkSpeed}`
	)
	local id = grabWild()
	local carrying = humanoid().WalkSpeed
	local Steal = rt:require(rt.game:GetService("ReplicatedStorage").Shared.Steal)
	local noCoil = Steal.walkSpeed(session.carry.timer, rt.workspace:GetServerTimeNow())
	check(
		"coil: carrying with the coil beats carrying without it",
		world.carriedBy[id] == USER_ID and carrying > noCoil + 1 and carrying < after,
		`carry WalkSpeed {carrying}, same carry without the coil {noCoil}`
	)
	invoke("Drop")
	check("coil: speed back after drop", math.abs(humanoid().WalkSpeed - after) < 0.01, `{humanoid().WalkSpeed}`)
end)

---------------------------------------------------------------------------
-- drop: a dropped wild slime lands on the first collidable surface
---------------------------------------------------------------------------
local function collidableGroundY(position)
	local exclude = { player.Character }
	for _, name in { "WildSlimes" } do
		table.insert(exclude, rt.workspace:FindFirstChild(name))
	end
	for _, plot in rt.workspace.Plots:GetChildren() do
		local slimes = plot:FindFirstChild("Slimes")
		if slimes then
			table.insert(exclude, slimes)
		end
	end
	local hit = rt:raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -200, 0), {
		FilterType = roblox.Enum.RaycastFilterType.Exclude,
		FilterDescendantsInstances = exclude,
		RespectCanCollide = true,
	})
	return hit and hit.Position.Y, hit and hit.Instance:GetFullName()
end

scenario("drop", function()
	local spots = {}
	local Visuals = rt.game:GetService("ReplicatedStorage"):FindFirstChild("Visuals")
	local layout = rt:require(Visuals.WorldLayout)
	local crater = rt.workspace.Map.Volcano.Crater.CFrame.Position
	table.insert(spots, { "open ground by the volcano", Vector3.new(crater.X + 45, 0, crater.Z) })
	for _, name in { "ItemShopStand", "UpgradeShopStand", "LeaderboardBoard" } do
		local spot = layout.PROP_SPOTS and layout.PROP_SPOTS[name]
		if spot then
			table.insert(spots, { `next to {name}`, Vector3.new(spot.pos[1] + 2, 0, spot.pos[3] + 4) })
		end
	end
	local other = S.WorldView.plot(if session.plotIndex == 1 then 2 else 1)
	local base = other and other:FindFirstChild("Base")
	if base then
		table.insert(spots, { "on another plot's Base", base.CFrame.Position })
	end
	for _, spot in spots do
		local label, at = spot[1], spot[2]
		local id = grabWild()
		local groundY = collidableGroundY(Vector3.new(at.X, 150, at.Z)) or 0
		moveTo(Vector3.new(at.X, groundY + 3, at.Z)) -- root 3 studs up, like a standing R15
		local res = invoke("Drop")
		rt:advance(1)
		local body = S.WorldView.slimeBody(id)
		local model = body and body.Parent
		local pivotY = model and model:GetPivot().Position.Y
		local expectY, surface = collidableGroundY(root().CFrame.Position)
		-- Independent of the ray: never above the carrier's feet (v12 put it on the carrier's root / head).
		local feetY = root().CFrame.Position.Y - 3
		local ok = res.ok
			and pivotY ~= nil
			and expectY ~= nil
			and math.abs(pivotY - expectY) < 0.3
			and pivotY <= feetY + 0.05
		check(
			`drop: lands on the ground ({label})`,
			ok,
			`Drop ok={res.ok}; slime bottom y={pivotY}, collidable ground y={expectY} ({surface}), carrier root y={root().CFrame.Position.Y}`
		)
		world.wild[id] = nil -- clear it so the next grab picks a fresh slime
		rt:advance(0.3)
	end
	-- Over the void (nothing collidable below): back to its volcano landing spot, not mid-air.
	local id = grabWild()
	moveTo(Vector3.new(3000, 3, 3000))
	invoke("Drop")
	rt:advance(1)
	local model = S.WorldView.slimeBody(id).Parent
	local p = model:GetPivot().Position
	local d = Vector3.new(p.X - crater.X, 0, p.Z - crater.Z).Magnitude
	local groundY = collidableGroundY(Vector3.new(p.X, 150, p.Z))
	check(
		"drop: over the void it goes back to the volcano ring",
		d < 80 and groundY ~= nil and math.abs(p.Y - groundY) < 0.3,
		`landed at ({math.floor(p.X)}, {p.Y}, {math.floor(p.Z)}), {math.floor(d)} studs from the crater, ground y={groundY}`
	)
	world.wild[id] = nil
	rt:advance(0.3)
end)

---------------------------------------------------------------------------
-- lockbuy: lock and pad buying through the plot prompts, tutorial steps
---------------------------------------------------------------------------
scenario("lockbuy", function()
	local plot = S.WorldView.plot(session.plotIndex)
	local lockPrompt = plotPart("LockButton"):FindFirstChild("LockPrompt")
	check(
		"lockbuy: LockPrompt for the owner only",
		lockPrompt ~= nil and lockPrompt.Enabled and lockPrompt:GetAttribute("ShowOnlyToUserId") == USER_ID,
		lockPrompt and `"{lockPrompt.ActionText}" / "{lockPrompt.ObjectText}"` or "missing"
	)
	-- Wait out the join lock, so the prompt says OPEN / Lock base.
	session.lockUntil = rt.workspace:GetServerTimeNow() - 1
	rt:advance(0.3)
	local openText, openAction = lockPrompt.ObjectText, lockPrompt.ActionText
	check(
		"lockbuy: open plot reads OPEN / Lock base $",
		plot:GetAttribute("Locked") == false
			and string.find(openText, "OPEN", 1, true) ~= nil
			and string.find(openAction, "Lock base $", 1, true) == 1,
		`Locked={plot:GetAttribute("Locked")} "{openAction}" / "{openText}"`
	)
	session.data.tutorialStep = 3 -- at the Lock step
	TestHooks.grantCash(world, USER_ID, plot:GetAttribute("LockCost"))
	moveTo(plotPart("LockButton").CFrame.Position + Vector3.new(0, 3, 3))
	lockPrompt.Triggered:Fire(player)
	rt:advance(0.5)
	check(
		"lockbuy: LockPrompt locks the base",
		plot:GetAttribute("Locked") == true
			and string.find(lockPrompt.ObjectText, "LOCKED", 1, true) ~= nil
			and string.find(lockPrompt.ActionText, "Extend lock", 1, true) == 1,
		`Locked={plot:GetAttribute("Locked")} "{lockPrompt.ActionText}" / "{lockPrompt.ObjectText}"`
	)
	check(
		"lockbuy: tutorial moves Lock -> BuyPad",
		player:GetAttribute("TutorialStepId") == "BuyPad" and player:GetAttribute("TutorialStep") == 4,
		`TutorialStepId={player:GetAttribute("TutorialStepId")} TutorialStep={player:GetAttribute("TutorialStep")}`
	)
	local pads = session.data.padsUnlocked
	local buyPad = plot:FindFirstChild("BuyPadPrompt", true)
	local padPart = buyPad and buyPad.Parent
	check(
		"lockbuy: BuyPadPrompt sits on the lowest locked pad",
		buyPad ~= nil
			and padPart:GetAttribute("PadIndex") == pads + 1
			and padPart:GetAttribute("Unlocked") == false
			and buyPad:GetAttribute("ShowOnlyToUserId") == USER_ID,
		buyPad and `"{buyPad.ActionText}" / "{buyPad.ObjectText}" on {padPart.Name}` or "missing"
	)
	TestHooks.grantCash(world, USER_ID, plot:GetAttribute("NextPadCost"))
	buyPad.Triggered:Fire(player)
	rt:advance(0.5)
	check(
		"lockbuy: BuyPadPrompt buys the pad and moves on",
		session.data.padsUnlocked == pads + 1
			and padPart:GetAttribute("Unlocked") == true
			and buyPad.Parent ~= padPart
			and plot:GetAttribute("PadsUnlocked") == pads + 1,
		`pads {pads} -> {session.data.padsUnlocked}, prompt now on {buyPad.Parent.Name}: "{buyPad.ActionText}"`
	)
	check(
		"lockbuy: tutorial moves BuyPad -> Merge",
		player:GetAttribute("TutorialStepId") == "Merge",
		`TutorialStepId={player:GetAttribute("TutorialStepId")}`
	)
	-- Another player's prompt is refused server-side.
	local other = rt:addPlayer(5151, "Neighbour", Vector3.new(0, 10, 0))
	rt:advance(0.5)
	local before = session.lockUntil
	lockPrompt.Triggered:Fire(other)
	rt:advance(0.3)
	local last = rt.records[#rt.records]
	check(
		"lockbuy: a neighbour can't use your LockPrompt",
		session.lockUntil == before and last.name == "Notify" and last.userId == 5151,
		`lockUntil unchanged={session.lockUntil == before}; neighbour got "{last.args[1]}"`
	)
	rt.game:GetService("Players").PlayerRemoving:Fire(other) -- leave like a real client
	rt:advance(0.3)
	table.remove(rt.players, table.find(rt.players, other))
	other:Destroy()
	rt:advance(0.3)
end)

---------------------------------------------------------------------------
-- loop: a brand-new player goes from first grab to rebirth 6+ (cash via TestHooks)
---------------------------------------------------------------------------
scenario("loop", function()
	local NEW_ID = 7070
	local newbie = rt:addPlayer(NEW_ID, "Newbie", Vector3.new(0, 10, 0))
	rt:advance(1)
	local me = world.sessions[NEW_ID]
	assert(me, "newbie has no session")
	local function nroot()
		return newbie.Character:FindFirstChild("HumanoidRootPart")
	end
	local function ninvoke(action, ...)
		local res = request.OnServerInvoke(newbie, action, ...)
		rt:advance(0.6) -- past the per-action rate limit
		return res
	end
	local function nmove(position)
		nroot().CFrame = CFrame.new(position)
		rt:advance(0.3)
	end
	local function nplot(name)
		return S.WorldView.plot(me.plotIndex):FindFirstChild(name)
	end
	local function lastState()
		for i = #rt.records, 1, -1 do
			local r = rt.records[i]
			if r.kind == "FireClient" and r.name == "State" and r.userId == NEW_ID then
				return r.args[1]
			end
		end
		return nil
	end
	local function toasts(from)
		local out = {}
		for i = from + 1, #rt.records do
			local r = rt.records[i]
			if r.name == "Notify" and (r.userId == NEW_ID or r.kind == "FireAllClients") then
				table.insert(out, `{r.args[3] or "-"}: {r.args[1]}`)
			end
		end
		return out
	end
	local steps = {}
	local function stepId()
		return newbie:GetAttribute("TutorialStepId") or "done"
	end
	table.insert(steps, stepId())
	local start = #rt.records

	-- 1-2: grab a wild slime with its prompt and carry it into the HomeZone.
	local function grabAndBringHome()
		rt:advance(4)
		local best, bestD = nil, math.huge
		for id, wild in world.wild do
			if not world.carriedBy[id] and wild.spawnedAt < rt.workspace:GetServerTimeNow() - 1.5 then
				local pos = S.WorldView.slimePosition(id)
				local d = pos and (pos - nroot().CFrame.Position).Magnitude or math.huge
				if d < bestD then
					best, bestD = id, d
				end
			end
		end
		assert(best, "no wild slime")
		TestHooks.grantCash(world, NEW_ID, world.wild[best].price)
		local body = S.WorldView.slimeBody(best)
		nmove(body.CFrame.Position + Vector3.new(2, 2, 0))
		body:FindFirstChild("GrabPrompt").Triggered:Fire(newbie)
		rt:advance(0.3)
		assert(world.carriedBy[best] == NEW_ID, "grab failed")
		if steps[#steps] ~= stepId() then
			table.insert(steps, stepId()) -- Grab -> Deposit happens mid-carry
		end
		nmove(nplot("HomeZone").CFrame.Position)
		rt:advance(0.5)
		assert(world.carriedBy[best] == nil, "deposit failed")
		return best
	end
	grabAndBringHome()
	table.insert(steps, stepId())
	steps = { steps[1], steps[2], steps[#steps] }
	-- 3: lock with the LockPrompt.
	me.lockUntil = rt.workspace:GetServerTimeNow() - 1
	rt:advance(0.3)
	TestHooks.grantCash(world, NEW_ID, 1000)
	nplot("LockButton"):FindFirstChild("LockPrompt").Triggered:Fire(newbie)
	rt:advance(0.6)
	table.insert(steps, stepId())
	-- 4: buy a pad with the BuyPadPrompt.
	TestHooks.grantCash(world, NEW_ID, 1000)
	S.WorldView.plot(me.plotIndex):FindFirstChild("BuyPadPrompt", true).Triggered:Fire(newbie)
	rt:advance(0.6)
	table.insert(steps, stepId())
	-- 5: catch until two slimes share a rarity, then use the MergePrompt.
	for _ = 1, 12 do
		local tiers = {}
		local pair = false
		for _, slime in me.data.slimes do
			pair = pair or tiers[slime.tier] == true
			tiers[slime.tier] = true
		end
		if pair then
			break
		end
		grabAndBringHome()
	end
	nplot("MergeVat"):FindFirstChild("MergePrompt").Triggered:Fire(newbie)
	rt:advance(0.6)
	table.insert(steps, stepId())
	-- 6: steal from the other stand-in's unlocked plot, then drop it (it escapes home).
	session.lockUntil = 0
	if #session.data.slimes == 0 then
		local Genome = rt:require(rt.game:GetService("ReplicatedStorage").Shared.Genome)
		local PlayerData = rt:require(rt.game:GetService("ReplicatedStorage").Shared.PlayerData)
		PlayerData.addSlime(session.data, Genome.generate(world.rng, { id = "victim-slime", tier = 1 }))
	end
	rt:advance(0.5)
	local victim = session.data.slimes[1]
	local vbody = S.WorldView.slimeBody(victim.id)
	nmove(vbody.CFrame.Position + Vector3.new(2, 2, 0))
	vbody:FindFirstChild("GrabPrompt").Triggered:Fire(newbie)
	rt:advance(0.3)
	local stole = world.carriedBy[victim.id] == NEW_ID
	ninvoke("Drop")
	rt:advance(2)
	table.insert(steps, stepId())
	check(
		"loop: tutorial walks Grab -> Deposit -> Lock -> BuyPad -> Merge -> Steal -> Rebirth",
		table.concat(steps, ",") == "Grab,Deposit,Lock,BuyPad,Merge,Steal,Rebirth" and stole,
		`steps {table.concat(steps, " -> ")}; steal started={stole}`
	)

	-- Income for a while, then rebirth 8 times (cash topped up to each rebirth cost).
	local cashBefore = me.data.cash
	TestHooks.skipTime(world, 600)
	rt:advance(1.2)
	check(
		"loop: skipTime pays plot income",
		me.data.cash > cashBefore,
		`cash {cashBefore} -> {me.data.cash} over 10 min`
	)
	local Economy = rt:require(rt.game:GetService("ReplicatedStorage").Shared.Economy)
	local titles, failures = {}, {}
	for _ = 1, 8 do
		TestHooks.grantCash(world, NEW_ID, Economy.rebirthCost(me.data.rebirths))
		local res = ninvoke("Rebirth")
		if not res.ok then
			table.insert(failures, res.message or "?")
		end
		table.insert(titles, newbie:GetAttribute("RebirthTitle"))
		-- Spend on upgrades as they unlock, like a player would.
		for _, id in { "Income", "CarrySpeed", "OfflineCap", "Luck" } do
			TestHooks.grantCash(world, NEW_ID, 1e7)
			ninvoke("BuyUpgrade", id)
		end
		grabAndBringHome() -- something to keep through the next rebirth
	end
	rt:advance(1.5)
	local state = lastState() or {}
	local log = toasts(start)
	local function has(pattern)
		for _, line in log do
			if string.find(line, pattern, 1, true) then
				return true
			end
		end
		return false
	end
	check(
		"loop: reaches rebirth 6+ with new ranks",
		me.data.rebirths >= 6 and #failures == 0 and newbie:GetAttribute("RebirthTitle") == "Ooze Overlord",
		`rebirths {me.data.rebirths}; titles {table.concat(titles, " > ")}; failures {table.concat(failures, ", ")}`
	)
	check(
		"loop: tutorial finished by the rebirth",
		newbie:GetAttribute("TutorialStepId") == nil and has("Tutorial complete"),
		`TutorialStepId={newbie:GetAttribute("TutorialStepId")}`
	)
	local levels = {}
	for _, u in state.upgrades or {} do
		table.insert(levels, `{u.id}={u.level}`)
	end
	check(
		"loop: upgrades unlock with rebirths and are bought",
		(me.data.upgrades.Income or 0) > 0 and (me.data.upgrades.Luck or 0) > 0 and #(state.upgrades or {}) == 4,
		`State.upgrades {table.concat(levels, " ")}`
	)
	local goalsPaid = 0
	for _, line in log do
		if string.sub(line, 1, 5) == "Goal:" then
			goalsPaid += 1
		end
	end
	check(
		"loop: goals pay out (Notify Goal) and State carries v13 fields",
		goalsPaid >= 5
			and state.rebirthTitle == "Ooze Overlord"
			and state.nextRebirthTier ~= nil
			and state.incomeMultiplier ~= nil
			and state.stats ~= nil
			and state.stats.rebirths == me.data.rebirths,
		`{goalsPaid} goal toasts; incomeMultiplier={state.incomeMultiplier}; next rank={state.nextRebirthTier and state.nextRebirthTier.title}`
	)
	check(
		"loop: Goo Tycoon keeps 2 slimes on rebirth",
		has("New rank: Goo Tycoon") and #me.data.slimes >= 2,
		`slimes on plot after the last rebirth + catch: {#me.data.slimes}`
	)
	_G.__loopLog = log
end)

---------------------------------------------------------------------------
-- ui: the server's real State / attributes / prompts through Jolt's pure UI
-- modules (src/ui): BuyUpgrade shop rows, server goals, SlimeDex, lock / pad
-- buttons, owner-only prompt hiding, Boss Slime banner (State.boss)
---------------------------------------------------------------------------
scenario("ui", function()
	local RS = rt.game:GetService("ReplicatedStorage")
	local UI = rt.game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"):FindFirstChild("UI")
	local function ui(name)
		return rt:require(UI:FindFirstChild(name))
	end
	local ShopCatalog, Goals, Progress, Nav = ui("ShopCatalog"), ui("Goals"), ui("Progress"), ui("Nav")
	local LockHud, PromptHide, RareAnnounce = ui("LockHud"), ui("PromptHide"), ui("RareAnnounce")
	local Config = rt:require(RS.Shared.Config)
	local Remotes = rt:require(RS.Shared.Remotes)
	local function now()
		return rt.workspace:GetServerTimeNow()
	end
	local function lastState()
		for i = #rt.records, 1, -1 do
			local r = rt.records[i]
			if r.kind == "FireClient" and r.name == "State" and r.userId == USER_ID then
				return r.args[1]
			end
		end
		return nil
	end
	local plot = S.WorldView.plot(session.plotIndex)
	invoke("Sync")
	local state = lastState()
	assert(state, "no State pushed to the stand-in")

	-- BuyUpgrade: the Shop panel's upgrade row drives the Request.
	local function incomeRow(st)
		for _, row in ShopCatalog.upgradeViews(st, Remotes.ACTIONS) do
			if row.item.id == "Upgrade_Income" then
				return row
			end
		end
		return nil
	end
	TestHooks.grantCash(world, USER_ID, 1e6)
	invoke("Sync")
	local row = incomeRow(lastState())
	local level = session.data.upgrades.Income or 0
	local res = row and invoke(row.item.action, table.unpack(row.item.args))
	local after = incomeRow(lastState())
	check(
		"ui: Shop upgrade row buys Income via BuyUpgrade",
		row ~= nil
			and row.enabled
			and res.ok
			and (session.data.upgrades.Income or 0) == level + 1
			and after ~= nil
			and string.find(after.levelText, `Lv {level + 1}/`, 1, true) == 1,
		row and `"{row.buttonText}" {row.levelText} -> {after and after.levelText}; Request ok={res and res.ok}`
			or "no row"
	)

	-- Goals panel from State.goals.
	state = lastState()
	local goals = Goals.fromServer(state.goals)
	local catch
	for _, g in goals or {} do
		if g.id == "Catch" then
			catch = g
		end
	end
	check(
		"ui: Goals panel lists every server goal",
		goals ~= nil and #goals == #Config.GOALS and catch ~= nil and #catch.title > 0 and #catch.detail > 0,
		catch and `{#goals} goals; Catch: "{catch.title}" / "{catch.detail}"; summary "{Goals.summary(goals)}"`
			or "no goals"
	)

	-- SlimeDex: panel text, nav badge and the plot DexBoard attributes agree.
	local dexRewards = Progress.dexRewards(state)
	local badges = Nav.badges(state)
	check(
		"ui: SlimeDex panel, nav badge and plot DexCount/DexTotal/DexTierMask agree",
		dexRewards.next ~= nil
			and badges.Dex ~= nil
			and plot:GetAttribute("DexCount") == #state.dex
			and plot:GetAttribute("DexTotal") == state.dexTotal
			and state.dexTotal == 1152
			and (plot:GetAttribute("DexTierMask") or 0) > 0
			and plot:GetAttribute("PlotPrice") == nil,
		`DexCount={plot:GetAttribute("DexCount")}/{plot:GetAttribute("DexTotal")} mask={plot:GetAttribute("DexTierMask")} badge={badges.Dex}; "{dexRewards.next}"`
	)

	-- Lock / pad HUD buttons match the plot prompts.
	session.lockUntil = now() - 1
	invoke("Sync")
	state = lastState()
	local lockButton = LockHud.lockButton(state, now(), Config.LOCK_MAX_REMAINING)
	local padButton = LockHud.padButton(state)
	local lockPrompt = plotPart("LockButton"):FindFirstChild("LockPrompt")
	local buyPad = plot:FindFirstChild("BuyPadPrompt", true)
	local padCost = state.nextPadCost
	check(
		"ui: Lock / Buy-pad HUD buttons match LockPrompt / BuyPadPrompt",
		string.find(lockButton.text, "Lock", 1, true) ~= nil
			and string.find(lockPrompt.ActionText, "Lock base", 1, true) == 1
			and plot:GetAttribute("LockCost") == state.lockCost
			and (padCost == nil) == (padButton.visible == false)
			and (padCost == nil or plot:GetAttribute("NextPadCost") == padCost)
			and (padCost == nil or buyPad.Enabled),
		`HUD "{lockButton.text:gsub("\n", " ")}" / prompt "{lockPrompt.ActionText}"; HUD "{padButton.text:gsub(
			"\n",
			" "
		)}" / prompt "{buyPad and buyPad.ActionText}"`
	)

	-- PromptHide: owner keeps the owner-only prompts, a neighbour hides them.
	local function opts(userId)
		return {
			root = rt.workspace,
			localUserId = userId,
			attribute = "HideFromUserId",
			ownerAttribute = "ShowOnlyToUserId",
		}
	end
	local prompts = { lockPrompt, buyPad, plotPart("MergeVat"):FindFirstChild("MergePrompt") }
	local mine, theirs = {}, {}
	for _, p in prompts do
		table.insert(mine, tostring(PromptHide.reason(opts(USER_ID), p)))
		table.insert(theirs, tostring(PromptHide.reason(opts(USER_ID + 1), p)))
	end
	check(
		"ui: PromptHide shows Lock/BuyPad/Merge prompts only to the owner",
		table.concat(mine, ",") == "nil,nil,nil" and table.concat(theirs, ",") == "owner,owner,owner",
		`owner {table.concat(mine, ",")}; neighbour {table.concat(theirs, ",")}`
	)

	-- Boss Slime: State.boss drives the banner; it clears on expiry.
	local Spawner = rt:require(server:FindFirstChild("Spawner"))
	local before = lastState().boss
	local id = Spawner.spawnBoss(world, now())
	rt:advance(0.5)
	state = lastState()
	local body = S.WorldView.slimeBody(id)
	local name = body and RareAnnounce.nameFromObjectText(body:FindFirstChild("GrabPrompt").ObjectText)
	local banner = state.boss.active and RareAnnounce.banner({ name = name, expiresAt = state.boss.endsAt }, nil, now())
	check(
		"ui: State.boss active -> boss banner with countdown",
		before.active == false
			and state.boss.active == true
			and math.abs(state.boss.endsAt - world.wild[id].expiresAt) < 0.01
			and banner ~= nil
			and banner.kind == "boss"
			and body.Parent:GetAttribute("Boss") == true,
		`boss {before.active} -> {state.boss.active}, endsAt in {state.boss.endsAt and math.floor(
			state.boss.endsAt - now()
		)}s; banner "{banner and banner.text}"`
	)
	world.wild[id].expiresAt = now()
	rt:advance(0.5)
	state = lastState()
	check(
		"ui: State.boss clears when the boss expires",
		state.boss.active == false and state.boss.endsAt == nil and S.WorldView.slimeBody(id) == nil,
		`boss.active={state.boss.active}`
	)
end)

---------------------------------------------------------------------------
-- Report
---------------------------------------------------------------------------
local failed = 0
for _, c in checks do
	if not c.ok then
		failed += 1
	end
end
for _, w in rt.warnings do
	if verbose then
		print(`warn: {if type(w) == "table" then w.text or w[1] else w}`)
	end
end
if #rt.errors > 0 then
	failed += 1
	print(`FAIL  script errors: {#rt.errors}`)
	for _, e in rt.errors do
		print(`  t={e.t} {e.text}`)
	end
end
if verbose and _G.__loopLog then
	print("loop toasts:")
	for _, line in _G.__loopLog do
		print(`  {line}`)
	end
end
if jsonOut then
	fs.writeFile(
		jsonOut,
		serde.encode("json", { place = path, failed = failed, checks = checks, errors = rt.errors }, true)
	)
end
print(`{failed} check(s) failed, {#checks} run`)
process.exit(if failed > 0 then 1 else 0)
