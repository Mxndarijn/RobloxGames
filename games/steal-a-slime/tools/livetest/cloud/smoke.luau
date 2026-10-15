--!nocheck
--[[
	Open Cloud Luau Execution smoke test for Steal a Slime (runs inside a real
	Roblox server for the published place version; see tools/livetest/cloud/run.sh).

	Facts about that environment (create.roblox.com/docs/cloud/reference/features/luau-execution):
	  * the place's own Scripts do NOT start, so this script drives the server
	    modules itself; no players, no physics; changes are discarded afterwards;
	  * DataStores are REAL: this script never touches DataService / saves;
	  * 5 min max run time; the return value comes back as JSON in `output`.

	Checks (all pcall'd, so one failure doesn't hide the rest):
	  1. modules: require every ModuleScript under ServerScriptService.Server,
	     ReplicatedStorage.Shared and ReplicatedStorage.Visuals; report errors
	     (catches "Shared is not a valid member of ServerScriptService").
	  2. world: Map / Plots / HubSpawn present, every plot Sign and every
	     TextLabel under workspace (empty text = what players see as blank signs).
	  3. boot: WorldView.setup + WorldProps.place + a World driven by
	     GameLoop.step / WorldView.reconcile for SIM_SECONDS of real time, then
	     counts workspace.WildSlimes models (0 = "no slimes spawned").
]]

local SIM_SECONDS = 20

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local report = { modules = { failed = {}, loaded = 0 }, world = {}, boot = {}, ok = true }

local function firstLine(err)
	return (string.split(tostring(err), "\n"))[1]
end

local function fail(section, message)
	report.ok = false
	report[section].errors = report[section].errors or {}
	table.insert(report[section].errors, message)
	print(`FAIL [{section}] {message}`)
end

-- 1. Module load sweep --------------------------------------------------------
local roots = {
	ServerScriptService:FindFirstChild("Server"),
	ReplicatedStorage:FindFirstChild("Shared"),
	ReplicatedStorage:FindFirstChild("Visuals"),
}
for _, root in roots do
	if root then
		for _, module in root:GetDescendants() do
			if module:IsA("ModuleScript") then
				local ok, err = pcall(require, module)
				if ok then
					report.modules.loaded += 1
				else
					report.ok = false
					table.insert(report.modules.failed, `{module:GetFullName()}: {firstLine(err)}`)
					print(`FAIL [modules] {module:GetFullName()}: {firstLine(err)}`)
				end
			end
		end
	end
end

-- 2. Static world + sign text ------------------------------------------------------
local function textReport()
	local labels, empty, blankSigns = 0, {}, {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("TextLabel") or d:IsA("TextButton") then
			labels += 1
			if d.Text == "" or d.Text == "Label" then
				table.insert(empty, d:GetFullName())
			end
		elseif d:IsA("BasePart") and string.find(d.Name, "Sign") then
			local hasText = false
			for _, g in d:GetDescendants() do
				if (g:IsA("TextLabel") or g:IsA("TextButton")) and g.Text ~= "" then
					hasText = true
				end
			end
			if not hasText then
				table.insert(blankSigns, d:GetFullName())
			end
		end
	end
	return { labels = labels, empty = empty, blankSigns = blankSigns }
end

for _, name in { "Map", "Plots", "HubSpawn" } do
	report.world[name] = workspace:FindFirstChild(name) ~= nil
	if not report.world[name] then
		fail("world", `workspace.{name} missing`)
	end
end
report.world.textBeforeBoot = textReport()

-- 3. Boot the server modules (no DataStores, no players) -----------------------------
local ok, err = pcall(function()
	local Server = ServerScriptService.Server
	local Config = require(ReplicatedStorage.Shared.Config)
	local World = require(Server.World)
	local GameLoop = require(Server.GameLoop)
	local WorldView = require(Server.WorldView)
	local WorldProps = require(Server.WorldProps)

	WorldView.setup()
	report.boot.slimeLook = workspace:GetAttribute("SlimeLook")
	local placed = WorldProps.place()
	report.boot.props = {}
	for name in placed do
		table.insert(report.boot.props, name)
	end
	pcall(WorldProps.fillBoard, nil)

	local now = workspace:GetServerTimeNow()
	local world = World.new({
		now = now,
		seed = os.time(),
		newId = function()
			return HttpService:GenerateGUID(false)
		end,
		plotCount = Config.PLOT_COUNT,
	})
	local deadline = os.clock() + SIM_SECONDS
	while os.clock() < deadline do
		local t = workspace:GetServerTimeNow()
		GameLoop.step(world, t)
		WorldView.reconcile(world, t, function() end)
		World.drain(world)
		task.wait(0.1)
	end
	local wildCount = 0
	for _ in world.wild do
		wildCount += 1
	end
	local folder = workspace:FindFirstChild("WildSlimes")
	report.boot.worldWild = wildCount
	report.boot.wildModels = if folder then #folder:GetChildren() else 0
	if report.boot.wildModels == 0 then
		fail("boot", `0 slime models in workspace.WildSlimes after {SIM_SECONDS} s (World has {wildCount} wild)`)
	end
end)
if not ok then
	fail("boot", `server boot error: {firstLine(err)}`)
end
report.world.textAfterBoot = textReport()
if #report.world.textAfterBoot.empty > 0 then
	fail("world", `{#report.world.textAfterBoot.empty} empty TextLabel(s)`)
end
if #report.world.textAfterBoot.blankSigns > 0 then
	fail("world", `{#report.world.textAfterBoot.blankSigns} sign part(s) with no text`)
end

print(if report.ok then "PASS all checks" else "FAIL see report")
return report
