--!nocheck
--[[
	Stand-in player session for Open Cloud Luau Execution (cloud twin of
	tools/livetest/session.luau):

	  python3 /workspace/roblox/live-testing/ci/run.py tools/livetest/cloud/session.luau --version N
	  lune run tools/livetest/cloud-local build.rbxlx tools/livetest/cloud/session.luau   (dry run)

	Luau Execution runs a fresh headless server of the place version with no
	players, no physics and the place Scripts stopped. Like ci/playtest.luau,
	this copies the real ServerScriptService.Server source into a ModuleScript
	(children cloned, top-level locals exported) on DataStoreMode = "Memory",
	so the real boot and Heartbeat loop run. A Player can't be created, so the
	stand-ins are tables (UserId, attributes, Backpack) with an NPC rig as
	Character, and ProximityPrompt.Triggered can't be fired from a script: the
	session calls what the prompt handlers call (Carry.grab, Actions.handle).
	Cash and time come from Server.TestHooks, which only enables on the memory
	store (CONTRACT.md §8.12).

	Scenarios: coil (WalkSpeed before / after buying, while carrying),
	drop (a dropped slime lands on the first collidable surface, real raycasts),
	lockbuy (plot prompts + attributes), claim (FREE PLOT ClaimPrompt), loop (new player -> rebirth 8),
	ui (real State / plot attributes / prompts through the pure src/ui
	modules: BuyUpgrade row, goals, dex, lock / pad buttons, PromptHide,
	Boss banner from State.boss).
	Returns JSON { placeVersion, elapsed, assertions[], diag } for run.py.
]]

local SPAWN_SECONDS = 12
local BOT_ID, NEW_ID = -1101, -1102 -- negative = never a real user

local HttpService = game:GetService("HttpService")
local LogService = game:GetService("LogService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")
local ServerScriptService = game:GetService("ServerScriptService")

local t0 = os.clock()
local function stamp()
	return math.floor((os.clock() - t0) * 10) / 10
end
local function firstLine(s)
	return (string.split(tostring(s), "\n"))[1]
end

local errors, warnings = {}, {}
ScriptContext.Error:Connect(function(message, _, script)
	table.insert(errors, `[{stamp()}] {script and script:GetFullName() or "?"}: {firstLine(message)}`)
end)
LogService.MessageOut:Connect(function(message, kind)
	if kind == Enum.MessageType.MessageError then
		table.insert(errors, `[{stamp()}] {firstLine(message)}`)
	elseif kind == Enum.MessageType.MessageWarning and #warnings < 50 then
		table.insert(warnings, `[{stamp()}] {firstLine(message)}`)
	end
end)

local assertions, diag = {}, {}
local function check(name, pass, detail)
	table.insert(assertions, { name = name, pass = pass == true, detail = tostring(detail or "") })
end
local function scenario(name, fn)
	local ok, err = pcall(fn)
	if not ok then
		check(`{name} (scenario ran)`, false, firstLine(err))
	end
end

---------------------------------------------------------------------------
-- Boot the real server entry as a module
---------------------------------------------------------------------------
workspace:SetAttribute("DataStoreMode", "Memory")
local server = ServerScriptService:FindFirstChild("Server")
local S, bootErr
if server then
	local module = Instance.new("ModuleScript")
	module.Name = "ServerSession"
	module.Source = server.Source
		.. "\n\nreturn { world = world, refreshView = refreshView, Sessions = Sessions, Carry = Carry,"
		.. " WorldView = WorldView, World = World, PlayerData = PlayerData, Actions = Actions, ctx = ctx,"
		.. " Snapshot = Snapshot, Spawner = Spawner }\n"
	for _, child in server:GetChildren() do
		child:Clone().Parent = module
	end
	module.Parent = ServerScriptService
	local done = false
	task.spawn(function()
		local ok, res = pcall(require, module)
		if ok then
			S = res
			S.module = module
		else
			bootErr = firstLine(res)
		end
		done = true
	end)
	local deadline = os.clock() + 15
	while not done and os.clock() < deadline do
		task.wait(0.1)
	end
	bootErr = bootErr or (if done then nil else "require did not return within 15 s")
else
	bootErr = "ServerScriptService.Server missing"
end
check("server boots (real init.server.luau)", S ~= nil and type(S.world) == "table", bootErr or "ok")

local function now()
	return workspace:GetServerTimeNow()
end

-- A stand-in Player: what WorldView.updatePlayer touches, no real Player needed.
local stash = Instance.new("Folder")
stash.Name = "SessionStandIns"
stash.Parent = game:GetService("ServerStorage")
local function standIn(userId, name)
	local attributes = {}
	local backpack = Instance.new("Backpack")
	backpack.Parent = stash
	local rig
	local okRig = pcall(function()
		rig = Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15)
	end)
	if not okRig or not rig then
		rig = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "HumanoidRootPart"
		root.Size = Vector3.new(2, 2, 1)
		root.Anchored = true
		root.Parent = rig
		Instance.new("Humanoid").Parent = rig
		rig.PrimaryPart = root
	end
	rig.Name = name
	rig.Parent = workspace
	local p = { UserId = userId, Name = name, DisplayName = name, Character = rig, Parent = Players }
	function p:GetAttribute(k)
		return attributes[k]
	end
	function p:SetAttribute(k, v)
		attributes[k] = v
	end
	function p:FindFirstChildOfClass(class)
		return if class == "Backpack" then backpack else nil
	end
	function p:FindFirstChild(n)
		return if n == "Backpack" then backpack else nil
	end
	return p, rig, backpack
end

local world = S and S.world
local TestHooks = S and require(S.module:FindFirstChild("TestHooks"))
local Shared = ReplicatedStorage:FindFirstChild("Shared")
local Economy = require(Shared.Economy)
local Merge = require(Shared.Merge)
local Steal = require(Shared.Steal)

local bot, botRig, botPack, session
if world then
	check("TestHooks enable on DataStoreMode = Memory", TestHooks.enable(world), "memory store")
	bot, botRig, botPack = standIn(BOT_ID, "Session Bot")
	session = assert(S.Sessions.join(world, BOT_ID, bot.DisplayName, S.PlayerData.new(), now()))
	botRig:PivotTo(S.WorldView.plotSpawn(session.plotIndex) + Vector3.new(0, 3, 0))
end
task.wait(SPAWN_SECONDS)

local function act(userId, action, ...)
	local s = world.sessions[userId]
	s.limiter = {} -- the per-action rate limit is for clients, not this script
	local res = S.Actions.handle(world, userId, action, table.pack(...), now(), S.ctx)
	S.refreshView(now())
	return res
end
local function settledWild()
	for id, wild in world.wild do
		if not world.carriedBy[id] and wild.spawnedAt < now() - 1.5 and not wild.boss then
			return id
		end
	end
	return nil
end
local function grab(userId)
	local id = settledWild()
	local deadline = os.clock() + 12
	while not id and os.clock() < deadline do
		task.wait(0.5) -- the volcano drops one every SPAWN_INTERVAL
		id = settledWild()
	end
	assert(id, "no settled wild slime")
	TestHooks.grantCash(world, userId, world.wild[id].price)
	local ok, why = S.Carry.grab(world, userId, id, 0, now())
	assert(ok, `grab: {why}`)
	S.refreshView(now())
	return id
end

---------------------------------------------------------------------------
-- coil
---------------------------------------------------------------------------
scenario("coil", function()
	local humanoid = botRig:FindFirstChildOfClass("Humanoid")
	S.WorldView.updatePlayer(bot, session, now())
	local before = humanoid.WalkSpeed
	TestHooks.grantCash(world, BOT_ID, 1500)
	local res = act(BOT_ID, "BuySpeedCoil")
	S.WorldView.updatePlayer(bot, session, now())
	local after = humanoid.WalkSpeed
	check(
		"coil: buying raises the rig's WalkSpeed",
		res.ok and after > before + 4,
		`ok={res.ok} {res.message or ""}; WalkSpeed {before} -> {after}; tool={botPack:FindFirstChild("SpeedCoil") ~= nil}`
	)
	local id = grab(BOT_ID)
	S.WorldView.updatePlayer(bot, session, now())
	local noCoil = Steal.walkSpeed(session.carry.timer, now())
	check(
		"coil: still faster while carrying",
		humanoid.WalkSpeed > noCoil + 1,
		`carrying WalkSpeed {humanoid.WalkSpeed} vs {noCoil} without the coil`
	)
	diag.coilCarryId = id
end)

---------------------------------------------------------------------------
-- drop (real Roblox raycasts against the real map)
---------------------------------------------------------------------------
local function groundY(position, exclude)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(position + Vector3.new(0, 4, 0), Vector3.new(0, -200, 0), params)
	return hit and hit.Position.Y, hit and hit.Instance:GetFullName()
end

scenario("drop", function()
	local exclude = { workspace:FindFirstChild("WildSlimes"), botRig }
	for _, plot in workspace.Plots:GetChildren() do
		table.insert(exclude, plot:FindFirstChild("Slimes"))
	end
	local crater = workspace.Map.Volcano.Crater.Position
	local spots = { { "volcano ring", Vector3.new(crater.X + 45, 0, crater.Z + 5) } }
	local stand = workspace.Map:FindFirstChild("ShopStand")
	if stand then
		table.insert(spots, { "beside ShopStand", stand:GetPivot().Position + Vector3.new(6, 0, 6) })
	end
	local other = S.WorldView.plot(if session.plotIndex == 1 then 2 else 1)
	if other and other:FindFirstChild("Base") then
		table.insert(spots, { "another plot's Base", other.Base.Position })
	end
	botRig:PivotTo(CFrame.new(0, 500, 3000)) -- out of the way: it's not a real character
	for i, spot in spots do
		local label, at = spot[1], spot[2]
		local id = if i == 1
				and diag.coilCarryId
				and world.carriedBy[diag.coilCarryId] == BOT_ID
			then diag.coilCarryId
			else grab(BOT_ID)
		local floorY = groundY(Vector3.new(at.X, 150, at.Z), exclude) or 0
		local rootPos = Vector3.new(at.X, floorY + 3, at.Z) -- where a standing carrier's root would be
		S.Carry.release(world, BOT_ID, now(), rootPos, "drop")
		S.refreshView(now())
		task.wait(0.8)
		local body = S.WorldView.slimeBody(id)
		local pivotY = body and body.Parent:GetPivot().Position.Y
		local expectY, surface = groundY(rootPos, exclude)
		check(
			`drop: lands on the ground ({label})`,
			pivotY ~= nil and expectY ~= nil and math.abs(pivotY - expectY) < 0.3 and pivotY <= rootPos.Y - 2.9,
			`slime bottom y={pivotY}, collidable ground y={expectY} ({surface}), carrier root y={rootPos.Y}`
		)
		world.wild[id] = nil
	end
	botRig:PivotTo(S.WorldView.plotSpawn(session.plotIndex) + Vector3.new(0, 3, 0))
end)

---------------------------------------------------------------------------
-- lockbuy (prompt texts + attributes; actions as the prompt handlers call them)
---------------------------------------------------------------------------
scenario("lockbuy", function()
	local plot = S.WorldView.plot(session.plotIndex)
	session.lockUntil = now() - 1
	S.refreshView(now())
	local lock = plot.LockButton:FindFirstChild("LockPrompt")
	local openText = lock and `"{lock.ActionText}" / "{lock.ObjectText}"`
	TestHooks.grantCash(world, BOT_ID, 1e4)
	local res = act(BOT_ID, "Lock")
	check(
		"lockbuy: LockPrompt reads OPEN, then LOCKED after a lock",
		lock ~= nil
			and string.find(openText, "OPEN", 1, true) ~= nil
			and res.ok
			and plot:GetAttribute("Locked") == true
			and string.find(lock.ObjectText, "LOCKED", 1, true) ~= nil
			and lock:GetAttribute("ShowOnlyToUserId") == BOT_ID,
		`{openText} -> "{lock and lock.ActionText}" / "{lock and lock.ObjectText}"`
	)
	local buy = plot:FindFirstChild("BuyPadPrompt", true)
	local pads = session.data.padsUnlocked
	local before = buy and buy.Parent
	local res2 = act(BOT_ID, "BuyPad")
	check(
		"lockbuy: BuyPadPrompt buys the next pad and moves on",
		buy ~= nil
			and res2.ok
			and session.data.padsUnlocked == pads + 1
			and before:GetAttribute("Unlocked") == true
			and buy.Parent ~= before,
		buy
				and `"{buy.ActionText}" / "{buy.ObjectText}" now on {buy.Parent.Name}; PadsUnlocked={plot:GetAttribute(
					"PadsUnlocked"
				)}`
			or "no BuyPadPrompt"
	)
end)

---------------------------------------------------------------------------
-- claim: FREE PLOT stand ClaimPrompt (CONTRACT.md §9.1); calls what its handler calls
---------------------------------------------------------------------------
scenario("claim", function()
	local PlotClaim = require(S.module:FindFirstChild("PlotClaim"))
	local freeIndex = nil
	for index = 1, world.plotCount do
		if world.plots[index] == nil then
			freeIndex = index
			break
		end
	end
	local stand = S.WorldView.plot(freeIndex):FindFirstChild("BuyStand")
	local prompt = stand and stand.Counter:FindFirstChild("ClaimPrompt")
	local own = S.WorldView.plot(session.plotIndex).BuyStand.Counter:FindFirstChild("ClaimPrompt")
	check(
		"claim: free plot's BuyStand has an enabled ClaimPrompt, own plot's is off",
		prompt ~= nil and prompt.Enabled and prompt.ActionText == "Claim plot" and own ~= nil and not own.Enabled,
		prompt and `Plot_{freeIndex}: "{prompt.ActionText}" / "{prompt.ObjectText}"` or "missing"
	)
	botRig:PivotTo(stand.Counter.CFrame + Vector3.new(0, 3, -3))
	local outcome, home = PlotClaim.claim(world, BOT_ID, freeIndex)
	local moved = outcome == "home" and S.WorldView.sendHome(bot, home)
	S.refreshView(now())
	check(
		"claim: sends a player who has a plot home",
		outcome == "home"
			and home == session.plotIndex
			and moved
			and S.WorldView.inHomeZone(bot, session.plotIndex)
			and world.plots[freeIndex] == nil,
		`{outcome} -> Plot {home}, inHomeZone={S.WorldView.inHomeZone(bot, session.plotIndex)}`
	)
end)

---------------------------------------------------------------------------
-- loop: brand-new player -> rebirth 8
---------------------------------------------------------------------------
scenario("loop", function()
	local newbie, newRig = standIn(NEW_ID, "Session Newbie")
	local me = assert(S.Sessions.join(world, NEW_ID, newbie.DisplayName, S.PlayerData.new(), now()))
	newRig:PivotTo(S.WorldView.plotSpawn(me.plotIndex) + Vector3.new(0, 3, 0))
	local TutorialProgress = require(Shared.TutorialProgress)
	local steps = { TutorialProgress.currentId(me.data) }
	local function note()
		local id = TutorialProgress.currentId(me.data) or "done"
		if steps[#steps] ~= id then
			table.insert(steps, id)
		end
	end
	local function catch()
		grab(NEW_ID)
		note()
		assert(S.Carry.deposit(world, NEW_ID))
		note()
	end
	catch()
	me.lockUntil = 0
	TestHooks.grantCash(world, NEW_ID, 1e4)
	act(NEW_ID, "Lock")
	note()
	act(NEW_ID, "BuyPad")
	note()
	for _ = 1, 12 do
		local a = Merge.findPair(me.data.slimes, S.World.busySet(world), me.data.favoriteId)
		if a then
			break
		end
		catch()
	end
	local a, b = Merge.findPair(me.data.slimes, S.World.busySet(world), me.data.favoriteId)
	act(NEW_ID, "Merge", a, b)
	note()
	session.lockUntil = 0
	if #session.data.slimes == 0 then -- the bot's catches were dropped in the drop scenario
		local Genome = require(Shared.Genome)
		S.PlayerData.addSlime(session.data, Genome.generate(world.rng, { id = "session-victim", tier = 1 }))
		S.refreshView(now())
	end
	local victim = session.data.slimes[1]
	local stole = victim and S.Carry.grab(world, NEW_ID, victim.id, 0, now())
	note()
	act(NEW_ID, "Drop")
	check(
		"loop: tutorial walks every step",
		table.concat(steps, ",") == "Grab,Deposit,Lock,BuyPad,Merge,Steal,Rebirth" and stole == true,
		table.concat(steps, " -> ")
	)
	local cash = me.data.cash
	TestHooks.skipTime(world, 600)
	check("loop: skipTime pays plot income", me.data.cash > cash, `cash {cash} -> {me.data.cash}`)
	local titles, failures = {}, {}
	for _ = 1, 8 do
		TestHooks.grantCash(world, NEW_ID, Economy.rebirthCost(me.data.rebirths))
		local res = act(NEW_ID, "Rebirth")
		if not res.ok then
			table.insert(failures, res.message or "?")
		end
		S.WorldView.updatePlayer(newbie, me, now())
		table.insert(titles, newbie:GetAttribute("RebirthTitle"))
		for _, id in { "Income", "CarrySpeed", "OfflineCap", "Luck" } do
			TestHooks.grantCash(world, NEW_ID, 1e7)
			act(NEW_ID, "BuyUpgrade", id)
		end
		catch()
	end
	note()
	check(
		"loop: rebirth 8 with new ranks, tutorial done",
		me.data.rebirths == 8 and #failures == 0 and titles[8] == "Ooze Overlord" and steps[#steps] == "done",
		`rebirths {me.data.rebirths}; {table.concat(titles, " > ")}; failures {table.concat(failures, ", ")}`
	)
	local goals = 0
	for _, stage in me.data.goals do
		goals += stage
	end
	check(
		"loop: upgrades bought, goals paid, 2+ slimes kept",
		(me.data.upgrades.Luck or 0) > 0 and goals >= 5 and #me.data.slimes >= 2,
		`upgrades Income={me.data.upgrades.Income} CarrySpeed={me.data.upgrades.CarrySpeed} OfflineCap={me.data.upgrades.OfflineCap} Luck={me.data.upgrades.Luck}; goal stages paid {goals}; slimes {#me.data.slimes}`
	)
end)

---------------------------------------------------------------------------
-- ui: real State / attributes / prompts through the pure src/ui modules
---------------------------------------------------------------------------
scenario("ui", function()
	local UI = game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("UI")
	local ShopCatalog = require(UI.ShopCatalog)
	local Goals = require(UI.Goals)
	local Progress = require(UI.Progress)
	local Nav = require(UI.Nav)
	local LockHud = require(UI.LockHud)
	local PromptHide = require(UI.PromptHide)
	local RareAnnounce = require(UI.RareAnnounce)
	local Config = require(Shared.Config)
	local Remotes = require(Shared.Remotes)
	local plot = S.WorldView.plot(session.plotIndex)
	local function state()
		S.refreshView(now())
		return S.Snapshot.build(world, session, now())
	end
	local function incomeRow(st)
		for _, row in ShopCatalog.upgradeViews(st, Remotes.ACTIONS) do
			if row.item.id == "Upgrade_Income" then
				return row
			end
		end
		return nil
	end
	TestHooks.grantCash(world, BOT_ID, 1e6)
	local level = session.data.upgrades.Income or 0
	local row = incomeRow(state())
	local res = row and act(BOT_ID, row.item.action, table.unpack(row.item.args))
	local after = incomeRow(state())
	check(
		"ui: Shop upgrade row buys Income via BuyUpgrade",
		row ~= nil and row.enabled and res.ok and (session.data.upgrades.Income or 0) == level + 1 and after ~= nil,
		row and `"{row.buttonText}" {row.levelText} -> {after and after.levelText}` or "no row"
	)
	local st = state()
	local goals = Goals.fromServer(st.goals)
	check(
		"ui: Goals panel lists every server goal",
		goals ~= nil and #goals == #Config.GOALS,
		goals and `{#goals} goals; summary "{Goals.summary(goals)}"` or "no goals"
	)
	local dexRewards = Progress.dexRewards(st)
	local badges = Nav.badges(st)
	check(
		"ui: SlimeDex panel, nav badge and plot Dex attributes agree",
		dexRewards.next ~= nil
			and badges.Dex ~= nil
			and plot:GetAttribute("DexCount") == #st.dex
			and plot:GetAttribute("DexTotal") == 720
			and type(plot:GetAttribute("DexTierMask")) == "number"
			and plot:GetAttribute("PlotPrice") == nil,
		`DexCount={plot:GetAttribute("DexCount")}/{plot:GetAttribute("DexTotal")} mask={plot:GetAttribute("DexTierMask")}; "{dexRewards.next}"`
	)
	session.lockUntil = now() - 1
	st = state()
	local lockButton = LockHud.lockButton(st, now(), Config.LOCK_MAX_REMAINING)
	local padButton = LockHud.padButton(st)
	local lockPrompt = plot.LockButton:FindFirstChild("LockPrompt")
	local buyPad = plot:FindFirstChild("BuyPadPrompt", true)
	check(
		"ui: Lock / Buy-pad HUD buttons match the plot prompts",
		string.find(lockButton.text, "Lock", 1, true) ~= nil
			and string.find(lockPrompt.ActionText, "Lock base", 1, true) == 1
			and plot:GetAttribute("LockCost") == st.lockCost
			and (st.nextPadCost == nil) == (padButton.visible == false),
		`"{(lockButton.text:gsub("\n", " "))}" / "{lockPrompt.ActionText}"; "{(padButton.text:gsub("\n", " "))}" / "{buyPad and buyPad.ActionText}"`
	)
	local function reason(userId, p)
		return tostring(PromptHide.reason({
			root = workspace,
			localUserId = userId,
			attribute = "HideFromUserId",
			ownerAttribute = "ShowOnlyToUserId",
		}, p))
	end
	local mine, theirs = {}, {}
	for _, p in { lockPrompt, buyPad, plot.MergeVat:FindFirstChild("MergePrompt") } do
		table.insert(mine, reason(BOT_ID, p))
		table.insert(theirs, reason(NEW_ID, p))
	end
	check(
		"ui: PromptHide shows owner prompts only to the owner",
		table.concat(mine, ",") == "nil,nil,nil" and table.concat(theirs, ",") == "owner,owner,owner",
		`owner {table.concat(mine, ",")}; other {table.concat(theirs, ",")}`
	)
	local id = S.Spawner.spawnBoss(world, now())
	st = state()
	local body = S.WorldView.slimeBody(id)
	local name = body and RareAnnounce.nameFromObjectText(body.GrabPrompt.ObjectText)
	local banner = st.boss.active and RareAnnounce.banner({ name = name, expiresAt = st.boss.endsAt }, nil, now())
	world.wild[id].expiresAt = now()
	S.Spawner.step(world, now())
	local cleared = state().boss
	check(
		"ui: State.boss drives the boss banner and clears on expiry",
		banner ~= nil and banner.kind == "boss" and cleared.active == false and cleared.endsAt == nil,
		`banner "{banner and banner.text}"; after expiry active={cleared.active}`
	)
end)

task.wait(0.5)
check(
	"no errors in LogService / ScriptContext",
	#errors == 0,
	if #errors > 0 then table.concat(errors, " | ") else "0 errors"
)
diag.warnings = warnings
diag.errors = errors
return HttpService:JSONEncode({
	placeVersion = game.PlaceVersion,
	elapsed = stamp(),
	assertions = assertions,
	diag = diag,
})
