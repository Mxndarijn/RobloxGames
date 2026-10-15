--!nocheck
--[[
	Open Cloud Luau Execution: live-state inspection of the published place
	(primary PoC; run with tools/livetest/cloud/run.sh tools/livetest/cloud/live.luau).

	The task runs in a fresh headless Roblox server for the place version, with
	NO players. Phases:
	  1. passive: poll up to BOOT_WAIT s for the server to boot on its own
	     (ReplicatedStorage.Remotes, workspace.DataStoreStatus, WildSlimes),
	     then snapshot the world as a player would find it.
	  2. boot (BOOT): place Scripts and physics never run in Luau Execution
	     (re-enabling ServerScriptService.Server does nothing either), so this
	     sets workspace.DataStoreMode = "Memory", requires the Server modules
	     and replays init.server.luau's boot + Heartbeat body for BOOT_SECONDS,
	     then snapshots again (report.boot). If WorldView fails to require
	     (v10: SlimeMesh path), it retries on a clone with that path shimmed
	     (report.boot.shim = true). Errors land in `errors` / boot.steps.
	Returns one JSON-able table (output.results[1] on the task).
]]

local BOOT_WAIT = 10 -- passive: does anything boot on its own? (it never does here)
local BOOT = true
local BOOT_SECONDS = 60 -- real seconds of GameLoop after the module boot
local LIST_CAP = 150
local HUGE = 2048

local CollectionService = game:GetService("CollectionService")
local LogService = game:GetService("LogService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local ServerScriptService = game:GetService("ServerScriptService")

local t0 = os.clock()
local errors = {}
pcall(function() -- pcall: the Lune dry run (cloud-local) has no ScriptContext.Error
	ScriptContext.Error:Connect(function(message, trace, script)
		table.insert(errors, {
			t = math.floor((os.clock() - t0) * 10) / 10,
			message = message,
			script = script and script:GetFullName() or nil,
			trace = trace,
		})
	end)
end)
local logs = {}
pcall(function()
	LogService.MessageOut:Connect(function(message, kind)
		if kind ~= Enum.MessageType.MessageOutput then
			table.insert(logs, { t = math.floor((os.clock() - t0) * 10) / 10, kind = kind.Name, message = message })
		end
	end)
end)

local function push(list, value)
	if #list < LIST_CAP then
		table.insert(list, value)
	end
end

local function isBad(n)
	return n ~= n or math.abs(n) > HUGE
end

local function vec(v)
	return { math.floor(v.X * 100) / 100, math.floor(v.Y * 100) / 100, math.floor(v.Z * 100) / 100 }
end

local function badVec(v)
	return isBad(v.X) or isBad(v.Y) or isBad(v.Z)
end

local function serverState()
	local server = ServerScriptService:FindFirstChild("Server")
	return {
		present = server ~= nil,
		class = server and server.ClassName or nil,
		enabled = server and server:IsA("BaseScript") and server.Enabled or nil,
		runContext = server and server:IsA("BaseScript") and server.RunContext.Name or nil,
	}
end

local function booted()
	return ReplicatedStorage:FindFirstChild("Remotes") ~= nil
		or workspace:GetAttribute("DataStoreStatus") ~= nil
		or workspace:FindFirstChild("WildSlimes") ~= nil
end

local function waitBoot(seconds)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		if booted() then
			return true, math.floor((os.clock() - t0) * 10) / 10
		end
		task.wait(1)
	end
	return booted(), nil
end

-- A slime = tagged "Slime", or a Model under a WildSlimes / plot Slimes folder.
local function slimeRoot(inst)
	local node = inst
	while node and node ~= workspace do
		if CollectionService:HasTag(node, "Slime") then
			return node
		end
		local parent = node.Parent
		if parent and node:IsA("Model") and (parent.Name == "WildSlimes" or parent.Name == "Slimes") then
			return node
		end
		node = parent
	end
	return nil
end

local function snapshot()
	local s = {}

	-- Slimes ---------------------------------------------------------------
	local slimes = { tagged = 0, taggedInWorkspace = 0, folders = {}, examples = {} }
	for _, inst in CollectionService:GetTagged("Slime") do
		slimes.tagged += 1
		if inst:IsDescendantOf(workspace) then
			slimes.taggedInWorkspace += 1
		end
		push(slimes.examples, inst:GetFullName())
	end
	for _, folder in workspace:GetDescendants() do
		if folder.Name == "Slimes" or folder.Name == "WildSlimes" then
			if not folder:IsA("BasePart") then
				local n = 0
				for _, child in folder:GetChildren() do
					if child:IsA("Model") or child:IsA("BasePart") then
						n += 1
					end
				end
				s[folder.Name] = (s[folder.Name] or 0) + n
				push(slimes.folders, { path = folder:GetFullName(), children = n })
			end
		end
	end
	slimes.workspaceSlimes = workspace:FindFirstChild("Slimes") and #workspace.Slimes:GetChildren() or nil
	slimes.wildSlimes = workspace:FindFirstChild("WildSlimes") and #workspace.WildSlimes:GetChildren() or nil
	-- Where wild slimes sit: pivot, radius from the volcano axis, anchored body.
	slimes.wildSamples = {}
	local wildFolder = workspace:FindFirstChild("WildSlimes")
	if wildFolder then
		for _, model in wildFolder:GetChildren() do
			if model:IsA("Model") and #slimes.wildSamples < 25 then
				local pOk, pivot = pcall(function()
					return model:GetPivot().Position
				end)
				local body = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
				table.insert(slimes.wildSamples, {
					name = model.Name,
					pivot = if pOk then vec(pivot) else nil,
					radius = if pOk then math.floor(Vector3.new(pivot.X, 0, pivot.Z).Magnitude * 10) / 10 else nil,
					anchored = body and body.Anchored or nil,
					parts = #model:GetDescendants(),
				})
			end
		end
	end
	s.slimes = slimes

	-- Texts on SurfaceGui / BillboardGui ------------------------------------
	local texts = { total = 0, empty = 0, emptyPaths = {}, nonEmptyExamples = {}, templatesEmpty = {} }
	local function scanTexts(root, inWorkspace)
		for _, label in root:GetDescendants() do
			if label:IsA("TextLabel") or label:IsA("TextButton") then
				local gui = label:FindFirstAncestorWhichIsA("SurfaceGui")
					or label:FindFirstAncestorWhichIsA("BillboardGui")
				if gui then
					local empty = string.match(label.Text, "^%s*$") ~= nil
					if inWorkspace then
						texts.total += 1
						if empty then
							texts.empty += 1
							push(texts.emptyPaths, label:GetFullName())
						else
							if #texts.nonEmptyExamples < 15 then
								table.insert(
									texts.nonEmptyExamples,
									`{label:GetFullName()} = {string.sub(label.Text, 1, 40)}`
								)
							end
						end
					elseif empty then
						push(texts.templatesEmpty, label:GetFullName())
					end
				end
			end
		end
	end
	scanTexts(workspace, true)
	scanTexts(ReplicatedStorage, false)
	scanTexts(game:GetService("ServerStorage"), false)
	scanTexts(game:GetService("StarterGui"), false)
	-- Signs that have no text object at all (a sign part with nothing to show).
	texts.plotSigns = {}
	local plots = workspace:FindFirstChild("Plots")
	if plots then
		for _, plot in plots:GetChildren() do
			local sign = plot:FindFirstChild("Sign", true)
			if sign then
				local labels, filled = 0, 0
				for _, d in sign:GetDescendants() do
					if d:IsA("TextLabel") or d:IsA("TextButton") then
						labels += 1
						if not string.match(d.Text, "^%s*$") then
							filled += 1
						end
					end
				end
				table.insert(
					texts.plotSigns,
					{ plot = plot.Name, sign = sign:GetFullName(), labels = labels, filled = filled }
				)
			end
		end
	end
	s.texts = texts

	-- Physics: unanchored non-slime parts and parts below the floor ---------
	local map = workspace:FindFirstChild("Map")
	local ground = map and map:FindFirstChild("Ground")
	local floorY = if ground and ground:IsA("BasePart") then ground.Position.Y + ground.Size.Y / 2 else 0
	local phys = {
		floorY = floorY,
		parts = 0,
		unanchored = 0,
		unanchoredPaths = {},
		belowFloor = 0,
		belowFloorPaths = {},
		badNumbers = {},
	}
	for _, part in workspace:GetDescendants() do
		if part:IsA("BasePart") and not part:IsA("Terrain") then
			phys.parts += 1
			local slime = slimeRoot(part) ~= nil
			local character = part:FindFirstAncestorWhichIsA("Model")
				and part:FindFirstAncestorWhichIsA("Model"):FindFirstChildOfClass("Humanoid") ~= nil
			if not part.Anchored and not slime and not character then
				phys.unanchored += 1
				push(phys.unanchoredPaths, `{part:GetFullName()} @ {table.concat(vec(part.Position), ",")}`)
			end
			-- "below floor": the whole part sits under the ground top by more than 1 stud
			local top = part.Position.Y + part.Size.Y / 2
			if part ~= ground and top < floorY - 1 then
				phys.belowFloor += 1
				push(
					phys.belowFloorPaths,
					`{part:GetFullName()} top={math.floor(top * 10) / 10}{if slime then " (slime)" else ""}`
				)
			end
			if badVec(part.Size) or badVec(part.Position) then
				push(
					phys.badNumbers,
					`{part:GetFullName()} size={table.concat(vec(part.Size), ",")} pos={table.concat(
						vec(part.Position),
						","
					)}`
				)
			end
		end
	end
	s.physics = phys

	-- Volcano ----------------------------------------------------------------
	local volcano = map and map:FindFirstChild("Volcano")
	local v = { present = volcano ~= nil, parts = {}, effects = {}, anomalies = {} }
	local function effectCount(root, into)
		for _, d in root:GetDescendants() do
			if
				d:IsA("ParticleEmitter")
				or d:IsA("Fire")
				or d:IsA("Smoke")
				or d:IsA("Sparkles")
				or d:IsA("Light")
				or d:IsA("Beam")
				or d:IsA("Trail")
				or d:IsA("Explosion")
			then
				into[d.ClassName] = (into[d.ClassName] or 0) + 1
			end
		end
	end
	if volcano then
		v.class = volcano.ClassName
		v.primaryPart = volcano:IsA("Model") and volcano.PrimaryPart and volcano.PrimaryPart.Name or nil
		local pivotOk, pivot = pcall(function()
			return volcano:GetPivot().Position
		end)
		v.pivot = pivotOk and vec(pivot) or nil
		for _, part in volcano:GetDescendants() do
			if part:IsA("BasePart") then
				local entry = {
					path = string.gsub(part:GetFullName(), "^Workspace%.Map%.Volcano%.", ""),
					class = part.ClassName,
					anchored = part.Anchored,
					canCollide = part.CanCollide,
					transparency = part.Transparency,
					material = part.Material.Name,
					color = part.Color:ToHex(),
					size = vec(part.Size),
					position = vec(part.Position),
					orientation = (function()
						local okO, o = pcall(function()
							return vec(part.Orientation)
						end)
						return if okO then o else nil -- Lune dry run lacks Orientation
					end)(),
				}
				if part:IsA("MeshPart") then
					entry.meshId = part.MeshId
				end
				local fx = {}
				effectCount(part, fx)
				if next(fx) then
					entry.effects = fx
				end
				push(v.parts, entry)
				if badVec(part.Size) or badVec(part.Position) then
					push(v.anomalies, `NaN/huge: {entry.path}`)
				end
				if not part.Anchored then
					push(v.anomalies, `unanchored: {entry.path}`)
				end
			end
		end
		effectCount(volcano, v.effects)
		-- Same-name siblings = something built the volcano twice (z-fighting flicker).
		local seen = {}
		for _, child in volcano:GetChildren() do
			seen[child.Name] = (seen[child.Name] or 0) + 1
		end
		for name, n in seen do
			if n > 1 then
				push(v.anomalies, `duplicate x{n}: {name}`)
			end
		end
		v.partCount = #v.parts
	end
	local volcanoes = 0
	for _, d in workspace:GetDescendants() do
		if d.Name == "Volcano" then
			volcanoes += 1
		end
	end
	v.volcanoCount = volcanoes
	-- Everything volcano-adjacent outside the Volcano model (lava cracks, chute, crater fx).
	v.otherLavaParts = {}
	if map then
		for _, part in map:GetDescendants() do
			if
				part:IsA("BasePart")
				and not (volcano and part:IsDescendantOf(volcano))
				and (
					string.find(part.Name, "Lava")
					or string.find(part.Name, "Chute")
					or string.find(part.Name, "Crater")
				)
			then
				push(v.otherLavaParts, {
					path = part:GetFullName(),
					anchored = part.Anchored,
					transparency = part.Transparency,
					material = part.Material.Name,
					size = vec(part.Size),
					position = vec(part.Position),
				})
			end
		end
	end
	v.workspaceEffects = {}
	effectCount(workspace, v.workspaceEffects)
	s.volcano = v

	-- Attributes / services ----------------------------------------------------
	s.attributes = {
		DataStoreStatus = workspace:GetAttribute("DataStoreStatus"),
		DataStoreMode = workspace:GetAttribute("DataStoreMode"),
		SlimeLook = workspace:GetAttribute("SlimeLook"),
		SlimeRain = workspace:GetAttribute("SlimeRain"),
		RainActive = workspace:GetAttribute("RainActive"),
		RainEndsAt = workspace:GetAttribute("RainEndsAt"),
		RainNextAt = workspace:GetAttribute("RainNextAt"),
		all = {},
	}
	for name, value in workspace:GetAttributes() do
		s.attributes.all[name] = if type(value) == "number"
				or type(value) == "boolean"
				or type(value) == "string"
			then value
			else tostring(value)
	end
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	s.remotes = remotes and #remotes:GetChildren() or 0
	s.workspaceChildren = {}
	for _, child in workspace:GetChildren() do
		table.insert(s.workspaceChildren, `{child.Name}:{child.ClassName}`)
	end
	return s
end

local report = {
	placeVersion = game.PlaceVersion,
	placeId = game.PlaceId,
	jobId = game.JobId,
	isServer = RunService:IsServer(),
	isRunning = RunService:IsRunning(),
	players = #game:GetService("Players"):GetPlayers(),
	server = (function()
		local okState, state = pcall(serverState)
		return if okState then state else { error = tostring(state) }
	end)(),
}

local ok, at = waitBoot(BOOT_WAIT)
report.passive = { booted = ok, bootedAt = at, waited = BOOT_WAIT }
local snapOk, snap = pcall(snapshot)
report.passive.snapshot = if snapOk then snap else { error = tostring(snap) }

-- Phase 2: boot the server modules ourselves (place Scripts never start here). ----
-- Mirrors ServerScriptService.Server (init.server.luau) minus players, prompts'
-- player callbacks and DataStores: Remotes.setup, WorldView.setup, WorldProps.place,
-- fillBoard, a World driven by GameLoop.step + the rain attribute + refreshView,
-- and the memory-mode leaderboard refresh. Every step is pcall'd and recorded.
local boot = { steps = {}, requireErrors = {}, shim = false }
report.boot = boot

local function firstLine(err)
	return (string.split(tostring(err), "\n"))[1]
end

local function step(name, fn, ...)
	local okStep, res = pcall(fn, ...)
	table.insert(boot.steps, { step = name, ok = okStep, err = if okStep then nil else firstLine(res) })
	return okStep, res
end

-- Require every server module from `root`; returns name -> module (nil on error).
local function requireAll(root, label)
	local mods = {}
	for _, child in root:GetChildren() do
		if child:IsA("ModuleScript") then
			local okReq, mod = pcall(require, child)
			if okReq then
				mods[child.Name] = mod
			else
				table.insert(boot.requireErrors, `{label}.{child.Name}: {firstLine(mod)}`)
			end
		end
	end
	return mods
end

if BOOT then
	workspace:SetAttribute("DataStoreMode", "Memory") -- never touch real DataStores
	local server = ServerScriptService:FindFirstChild("Server")
	local mods = if server then requireAll(server, "Server") else {}
	if server and not mods.WorldView then
		-- v10 SlimeMesh requires script.Parent.Parent.Shared (= ServerScriptService.Shared).
		-- Retry once on fresh clones with that path satisfied, so the rest of the boot
		-- (signs, spawner, volcano drops) can still be observed. Reported as boot.shim.
		boot.shim = true
		if not ServerScriptService:FindFirstChild("Shared") then
			ReplicatedStorage.Shared:Clone().Parent = ServerScriptService
		end
		local clone = server:Clone()
		clone.Name = "ServerBootClone"
		pcall(function()
			clone.Enabled = false
		end)
		clone.Parent = ServerScriptService
		mods = requireAll(clone, "ServerBootClone")
	end
	boot.modules = {}
	for name in mods do
		table.insert(boot.modules, name)
	end
	table.sort(boot.modules)

	local Shared = ReplicatedStorage:FindFirstChild("Shared")
	local Config = require(Shared.Config)
	local Remotes = require(Shared.Remotes)
	local World, GameLoop, Spawner, WorldView, WorldProps, Leaderboard =
		mods.World, mods.GameLoop, mods.Spawner, mods.WorldView, mods.WorldProps, mods.Leaderboard

	local heartbeats = 0
	local hb = RunService.Heartbeat:Connect(function()
		heartbeats += 1
	end)

	step("Remotes.setup", Remotes.setup)
	if WorldView then
		step("WorldView.setup", WorldView.setup)
	end
	if WorldProps then
		step("WorldProps.place", WorldProps.place)
		step("WorldProps.addShopPrompts", WorldProps.addShopPrompts, function() end)
		step("WorldProps.fillBoard(nil)", WorldProps.fillBoard, nil)
	end
	local now = function()
		return workspace:GetServerTimeNow()
	end
	local world
	if World then
		step("World.new", function()
			world = World.new({
				now = now(),
				seed = math.floor(os.clock() * 1e6) + os.time(),
				newId = function()
					return game:GetService("HttpService"):GenerateGUID(false)
				end,
				plotCount = Config.PLOT_COUNT,
			})
		end)
	end
	if world and Leaderboard and WorldProps then
		step("leaderboard refresh (memory)", function()
			WorldProps.fillBoard(Leaderboard.fromPage(Leaderboard.pageFromSessions(world.sessions), function(id)
				return `Player {id}`
			end))
		end)
	end

	-- The server's Heartbeat body, driven by task.wait (no players to step).
	local loopErrors, ticks, wasRaining, rainStarts = {}, 0, nil, 0
	local deadline = os.clock() + BOOT_SECONDS
	local function tick()
		local t = now()
		GameLoop.step(world, t)
		if world.raining ~= wasRaining then
			wasRaining = world.raining
			if world.raining then
				rainStarts += 1
			end
			WorldView.setRain(Spawner.rain(world, t))
		end
		WorldView.reconcile(world, t, function() end)
		WorldView.updatePlots(world)
		World.drain(world)
	end
	if world and GameLoop and WorldView and Spawner then
		while os.clock() < deadline do
			ticks += 1
			local okTick, err = pcall(tick)
			if not okTick and #loopErrors < 10 then
				table.insert(loopErrors, firstLine(err))
			end
			task.wait(0.1)
		end
		local wild = 0
		for _ in world.wild do
			wild += 1
		end
		boot.worldWild = wild
		boot.rainStarts = rainStarts
		if Spawner.forceRain then
			-- Force one rain so the SlimeRain attribute path is exercised too.
			step("Spawner.forceRain", function()
				Spawner.forceRain(world, now())
				for _ = 1, 30 do
					pcall(tick)
					task.wait(0.1)
				end
			end)
		end
	end
	hb:Disconnect()
	boot.ticks, boot.loopErrors, boot.heartbeats = ticks, loopErrors, heartbeats
	local sOk, s2 = pcall(snapshot)
	boot.snapshot = if sOk then s2 else { error = tostring(s2) }
end

report.errors = errors
report.logs = logs
local history = {}
pcall(function()
	for _, entry in LogService:GetLogHistory() do
		if entry.messageType ~= Enum.MessageType.MessageOutput then
			push(history, `{entry.messageType.Name}: {entry.message}`)
		end
	end
end)
report.logHistory = history
report.elapsed = math.floor((os.clock() - t0) * 10) / 10

-- Publish gate (tools/livetest/gate.sh): slimes > 0, no empty plot-sign texts, no
-- boot errors. Slimes seen only thanks to the shim count as 0: the real server
-- would have crashed before spawning them. report.ok drives run.sh's exit code.
local gate = { slimes = 0, shimmedSlimes = 0, signs = 0, emptySigns = 0, emptySignPaths = {}, bootErrors = {} }
local snapBoot = boot.snapshot
if type(snapBoot) == "table" and snapBoot.slimes then
	local count = snapBoot.slimes.wildSlimes or 0
	for _, folder in snapBoot.slimes.folders or {} do
		if string.match(folder.path, "%.Slimes$") then
			count += folder.children
		end
	end
	if boot.shim then
		gate.shimmedSlimes = count
	else
		gate.slimes = count
	end
	for _, sign in (snapBoot.texts and snapBoot.texts.plotSigns) or {} do
		gate.signs += 1
		-- A sign with no labels shows nothing: count it as one empty text.
		local empty = if sign.labels == 0 then 1 else sign.labels - sign.filled
		if empty > 0 then
			gate.emptySigns += empty
			table.insert(gate.emptySignPaths, sign.sign)
		end
	end
elseif BOOT then
	table.insert(gate.bootErrors, `snapshot: {snapBoot and snapBoot.error or "missing"}`)
end
for _, e in boot.requireErrors do
	table.insert(gate.bootErrors, `require {e}`)
end
for _, s in boot.steps do
	if not s.ok then
		table.insert(gate.bootErrors, `step {s.step}: {s.err}`)
	end
end
for _, e in boot.loopErrors or {} do
	table.insert(gate.bootErrors, `loop {e}`)
end
for _, e in errors do
	table.insert(gate.bootErrors, `script {e.script or "?"}: {firstLine(e.message)}`)
end
gate.ok = BOOT and gate.slimes > 0 and gate.signs > 0 and gate.emptySigns == 0 and #gate.bootErrors == 0
report.gate = gate
report.ok = gate.ok
-- JSON string: the runner decodes it; avoids Luau-table -> output conversion quirks.
return game:GetService("HttpService"):JSONEncode(report)
