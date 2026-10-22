--!nocheck
--# selene: allow(incorrect_standard_library_use, shadowing, global_usage)
--[[
	livetest Runtime (Lune-only, not in the Rojo tree)

	A tiny fake Roblox server on top of @lune/roblox, good enough to boot the
	REAL ServerScriptService.Server Script of a built place (build.rbxlx)
	unchanged and watch what it does to workspace:

	  * every Script / ModuleScript runs from its Source through luau.load with
	    a Roblox-like environment (game, workspace, script, require(instance),
	    task, warn, os.clock / os.time on a fake clock, datatypes, Enum);
	  * a virtual clock + coroutine scheduler: task.wait / spawn / defer / delay,
	    RunService.Heartbeat, workspace:GetServerTimeNow(). advance(60) runs a
	    minute of server time in well under a second;
	  * shims for engine APIs Lune lacks: events (Triggered, PlayerAdded,
	    Died, ...), WaitForChild, PivotTo / GetPivot, ScaleTo / GetScale, BasePart.Position,
	    Raycast (axis-aligned boxes, enough for "find the ground"), Players,
	    in-memory DataStores, HttpService GUIDs, InsertService (fails by
	    default, like a place that can't load the mesh asset), Debris.

	What it can NOT tell you: physics, replication, rendering, client
	LocalScripts (no camera / PlayerGui), z-fighting. It is a boot-and-state
	check, not a renderer. See /guides/roblox-live-testing.md.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")

local Instance, CFrame, Vector3, Enum = roblox.Instance, roblox.CFrame, roblox.Vector3, roblox.Enum

local Runtime = {}
Runtime.__index = Runtime

-- One runtime per process: the shims below are global (roblox.implementMethod).
local current = nil

local SERVER_EPOCH = 1_760_000_000 -- fake GetServerTimeNow() at T = 0

-- Minimal Roblox `Random` (Lune has none): deterministic LCG.
local Random = {}
Random.__index = Random
function Random.new(seed)
	return setmetatable({ state = math.floor(seed or os.time()) % 2147483647 + 1 }, Random)
end
function Random:NextNumber(lo, hi)
	self.state = (self.state * 48271) % 2147483647
	local u = self.state / 2147483647
	return if lo then lo + (hi - lo) * u else u
end
function Random:NextInteger(lo, hi)
	return math.min(hi, lo + math.floor(self:NextNumber() * (hi - lo + 1)))
end

---------------------------------------------------------------------------
-- Signals
---------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

local function newSignal(name)
	return setmetatable({ name = name, handlers = {}, waiting = {} }, Signal)
end

function Signal:Connect(fn)
	local handler = { fn = fn, connected = true }
	table.insert(self.handlers, handler)
	return {
		Connected = true,
		Disconnect = function(conn)
			handler.connected = false
			conn.Connected = false
		end,
	}
end

function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end

function Signal:Wait()
	table.insert(self.waiting, coroutine.running())
	return coroutine.yield()
end

function Signal:Fire(...)
	for _, handler in table.clone(self.handlers) do
		if handler.connected then
			current:spawn(handler.fn, ...)
		end
	end
	local waiting = self.waiting
	self.waiting = {}
	for _, co in waiting do
		current:resume(co, ...)
	end
end

-- signals[instance][name]: instance identity is stable in Lune (rawequal).
local signals = {} -- strong keys: a weak table lost OnServerInvoke / signals of instances nothing referenced
local function signalOf(inst, name)
	local byName = signals[inst]
	if not byName then
		byName = {}
		signals[inst] = byName
	end
	if not byName[name] then
		byName[name] = newSignal(name)
	end
	return byName[name]
end
Runtime.signalOf = signalOf

-- Extra per-instance state for properties Lune can't store (callbacks, WorldPivot, ...).
local extra = {}
local function extraOf(inst)
	extra[inst] = extra[inst] or {}
	return extra[inst]
end

---------------------------------------------------------------------------
-- Engine shims
---------------------------------------------------------------------------

local function eventProperty(class, name)
	roblox.implementProperty(class, name, function(inst)
		return signalOf(inst, name)
	end)
end

local function storedProperty(class, name, default)
	roblox.implementProperty(class, name, function(inst)
		local value = extraOf(inst)[name]
		if value == nil then
			return default
		end
		return value
	end, function(inst, value)
		extraOf(inst)[name] = value
	end)
end

local function corners(part)
	local half = part.Size / 2
	local out = {}
	for _, sx in { -1, 1 } do
		for _, sy in { -1, 1 } do
			for _, sz in { -1, 1 } do
				table.insert(out, part.CFrame * Vector3.new(half.X * sx, half.Y * sy, half.Z * sz))
			end
		end
	end
	return out
end

local function bounds(part)
	local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, c in corners(part) do
		lo = Vector3.new(math.min(lo.X, c.X), math.min(lo.Y, c.Y), math.min(lo.Z, c.Z))
		hi = Vector3.new(math.max(hi.X, c.X), math.max(hi.Y, c.Y), math.max(hi.Z, c.Z))
	end
	return lo, hi
end
Runtime.bounds = bounds

local function isExcluded(inst, list)
	for _, ex in list do
		if inst == ex or inst:IsDescendantOf(ex) then
			return true
		end
	end
	return false
end

local function getPivot(inst)
	if inst:IsA("BasePart") then
		return inst.CFrame * inst.PivotOffset
	end
	if inst:IsA("Model") then
		local primary = inst.PrimaryPart
		if primary then
			return primary.CFrame * primary.PivotOffset
		end
		local stored = extraOf(inst).WorldPivot
		if stored then
			return stored
		end
		local ok, pivot = pcall(function()
			return inst.WorldPivot
		end)
		if ok and pivot then
			return pivot
		end
		local first = inst:FindFirstChildWhichIsA("BasePart", true)
		return if first then first.CFrame else CFrame.new()
	end
	return CFrame.new()
end

local function pivotTo(inst, target)
	local delta = target * getPivot(inst):Inverse()
	if inst:IsA("BasePart") then
		inst.CFrame = delta * inst.CFrame
	end
	for _, d in inst:GetDescendants() do
		if d:IsA("BasePart") then
			d.CFrame = delta * d.CFrame
		end
	end
	if inst:IsA("Model") and not inst.PrimaryPart then
		extraOf(inst).WorldPivot = target
	end
end

local shimsInstalled = false
local function installShims()
	if shimsInstalled then
		return
	end
	shimsInstalled = true
	local impl = roblox.implementMethod

	impl("Instance", "WaitForChild", function(self, name, timeout)
		local found = self:FindFirstChild(name)
		if found then
			return found
		end
		local deadline = current.T + (timeout or 5)
		while current.T < deadline do
			current:wait(0.1)
			found = self:FindFirstChild(name)
			if found then
				return found
			end
		end
		current:warn(`Infinite yield possible on '{self:GetFullName()}:WaitForChild("{name}")'`)
		return nil
	end)
	impl("Instance", "GetAttributeChangedSignal", function(self, name)
		return signalOf(self, "Attr:" .. name)
	end)
	impl("Instance", "GetPropertyChangedSignal", function(self, name)
		return signalOf(self, "Prop:" .. name)
	end)
	impl("Model", "PivotTo", pivotTo)
	impl("BasePart", "PivotTo", pivotTo)
	impl("Model", "GetPivot", getPivot)
	-- Model scale (the fighting boss): parts grow about the pivot like Roblox's Model:ScaleTo.
	impl("Model", "GetScale", function(self)
		return extraOf(self).Scale or 1
	end)
	impl("Model", "ScaleTo", function(self, scale)
		local factor = scale / (extraOf(self).Scale or 1)
		local pivot = getPivot(self)
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then
				local offset = pivot:ToObjectSpace(d.CFrame)
				d.Size *= factor
				d.CFrame = pivot * (offset.Rotation + offset.Position * factor)
			end
		end
		extraOf(self).Scale = scale
	end)
	-- Axis-aligned (Roblox orients the box to the pivot; fine for the fake runtime).
	impl("Model", "GetBoundingBox", function(self)
		local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
		for _, d in self:GetDescendants() do
			if d:IsA("BasePart") then
				local a, b = bounds(d)
				lo, hi = lo:Min(a), hi:Max(b)
			end
		end
		if lo.X > hi.X then
			return getPivot(self), Vector3.zero
		end
		return CFrame.new((lo + hi) / 2), hi - lo
	end)
	impl("BasePart", "GetPivot", getPivot)
	storedProperty("Model", "WorldPivot", CFrame.new())
	roblox.implementProperty("BasePart", "Position", function(self)
		return self.CFrame.Position
	end, function(self, value)
		self.CFrame = self.CFrame.Rotation + value
	end)
	storedProperty("BasePart", "AssemblyLinearVelocity", Vector3.zero)
	storedProperty("BasePart", "AssemblyAngularVelocity", Vector3.zero)
	storedProperty("DataModel", "JobId", "00000000-livetest-job")
	storedProperty("DataModel", "PlaceId", 135787188192378)
	storedProperty("DataModel", "GameId", 10770917350)
	storedProperty("DataModel", "PlaceVersion", 0)
	storedProperty("DataModel", "CreatorId", 0)

	for class, names in
		{
			ProximityPrompt = { "Triggered", "PromptShown", "PromptHidden" },
			Players = { "PlayerAdded", "PlayerRemoving" },
			Player = { "CharacterAdded", "CharacterRemoving" },
			Humanoid = { "Died" },
			Tool = { "Activated", "Equipped", "Unequipped" },
			RunService = { "Heartbeat", "Stepped", "RenderStepped" },
			RemoteEvent = { "OnServerEvent", "OnClientEvent" },
			BasePart = { "Touched", "TouchEnded" },
			Instance = {
				"ChildAdded",
				"ChildRemoved",
				"DescendantAdded",
				"DescendantRemoving",
				"AncestryChanged",
				"Destroying",
			},
			CollectionService = {},
			ScriptContext = { "Error" },
			LogService = { "MessageOut" },
		}
	do
		for _, name in names do
			eventProperty(class, name)
		end
	end
	storedProperty("RemoteFunction", "OnServerInvoke", nil)
	storedProperty("RemoteFunction", "OnClientInvoke", nil)
	storedProperty("BindableFunction", "OnInvoke", nil)
	roblox.implementProperty("Player", "Character", function(self)
		return extraOf(self).Character
	end, function(self, value)
		extraOf(self).Character = value
	end)

	impl("RemoteEvent", "FireClient", function(self, player, ...)
		current:record("FireClient", self.Name, player and player.UserId, ...)
	end)
	impl("RemoteEvent", "FireAllClients", function(self, ...)
		current:record("FireAllClients", self.Name, nil, ...)
	end)

	impl("Workspace", "GetServerTimeNow", function()
		return SERVER_EPOCH + current.T
	end)
	impl("Workspace", "Raycast", function(self, origin, direction, params)
		return current:raycast(origin, direction, params)
	end)

	impl("RunService", "IsStudio", function()
		return current.opts.studio == true
	end)
	impl("RunService", "IsServer", function()
		return true
	end)
	impl("RunService", "IsClient", function()
		return false
	end)
	impl("RunService", "IsRunning", function()
		return true
	end)

	impl("Players", "GetPlayers", function()
		return table.clone(current.players)
	end)
	impl("Players", "GetPlayerFromCharacter", function(_, character)
		for _, p in current.players do
			if p.Character == character then
				return p
			end
		end
		return nil
	end)
	impl("Players", "GetPlayerByUserId", function(_, userId)
		for _, p in current.players do
			if p.UserId == userId then
				return p
			end
		end
		return nil
	end)
	impl("Players", "GetNameFromUserIdAsync", function(_, userId)
		return `User{userId}`
	end)
	impl("Player", "Kick", function(self, message)
		current:record("Kick", self.Name, self.UserId, message)
		current:warn(`[livetest] {self.Name} kicked: {message}`)
	end)
	impl("Humanoid", "UnequipTools", function() end)
	impl("Humanoid", "TakeDamage", function(self, amount)
		self.Health -= amount
	end)

	impl("DataModel", "BindToClose", function(_, fn)
		table.insert(current.closeHandlers, fn)
	end)

	impl("HttpService", "GenerateGUID", function(_, braces)
		local hex = string.gsub("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", "[xy]", function(c)
			local v = if c == "x" then current.rng:NextInteger(0, 15) else current.rng:NextInteger(8, 11)
			return string.format("%X", v)
		end)
		return if braces == false then hex else `\{{hex}\}`
	end)
	impl("HttpService", "JSONEncode", function(_, v)
		return require("@lune/serde").encode("json", v)
	end)
	impl("HttpService", "JSONDecode", function(_, s)
		return require("@lune/serde").decode("json", s)
	end)

	impl("InsertService", "LoadAsset", function(_, assetId)
		current:wait(0.5) -- it yields in a live server
		local loader = current.opts.loadAsset
		if loader then
			return loader(assetId)
		end
		error(`livetest: InsertService:LoadAsset({assetId}) not available (pass opts.loadAsset)`)
	end)

	-- MeshSwap: fails (primitive placeholders stay) unless opts.createMeshPart is given.
	impl("AssetService", "CreateMeshPartAsync", function(_, meshId, options)
		local create = current.opts.createMeshPart
		if create then
			return create(meshId, options)
		end
		error(`livetest: AssetService:CreateMeshPartAsync({meshId}) not available (pass opts.createMeshPart)`)
	end)

	impl("Debris", "AddItem", function(_, inst, seconds)
		current:delay(seconds or 10, function()
			inst:Destroy()
		end)
	end)

	impl("CollectionService", "AddTag", function(_, inst, tag)
		inst:AddTag(tag)
	end)
	impl("CollectionService", "RemoveTag", function(_, inst, tag)
		inst:RemoveTag(tag)
	end)
	impl("CollectionService", "HasTag", function(_, inst, tag)
		return inst:HasTag(tag)
	end)
	impl("CollectionService", "GetTagged", function(_, tag)
		local out = {}
		for _, d in current.game:GetDescendants() do
			if d:HasTag(tag) then
				table.insert(out, d)
			end
		end
		return out
	end)
	impl("CollectionService", "GetInstanceAddedSignal", function(self, tag)
		return signalOf(self, "Added:" .. tag)
	end)
	impl("CollectionService", "GetInstanceRemovedSignal", function(self, tag)
		return signalOf(self, "Removed:" .. tag)
	end)

	-- DataStores: in memory, shared by every store object of the same name.
	impl("DataStoreService", "GetDataStore", function(_, name)
		if current.opts.dataStores == "error" then
			error("livetest: DataStore API disabled (opts.dataStores = 'error')")
		end
		return current:dataStore(name, false)
	end)
	impl("DataStoreService", "GetOrderedDataStore", function(_, name)
		return current:dataStore(name, true)
	end)
end

---------------------------------------------------------------------------
-- Runtime
---------------------------------------------------------------------------

function Runtime.new(placePath, opts)
	installShims()
	local self = setmetatable({}, Runtime)
	current = self
	self.opts = opts or {}
	self.T = 0
	self.queue = {} -- { co, at, args }
	self.players = {}
	self.closeHandlers = {}
	self.warnings = {}
	self.prints = {}
	self.errors = {}
	self.records = {}
	self.stores = {}
	self.modules = {}
	self.rng = Random.new(self.opts.seed or 1)
	-- Seeds for the game's own unseeded Random.new() calls: from the run's seed, never the wall clock, so a live
	-- spec replays the same world (the server seeds its generators from Random.new()).
	self.randomSeeds = Random.new((self.opts.seed or 1) + 1)
	self.game = roblox.deserializePlace(fs.readFile(placePath))
	self.workspace = self.game:GetService("Workspace")
	-- Reflected properties without a default: implementProperty can't override them, set values instead.
	for name, value in
		{
			JobId = "00000000-livetest-job",
			PlaceId = 135787188192378,
			GameId = 10770917350,
			PlaceVersion = 0,
			CreatorId = 0,
		}
	do
		pcall(function()
			self.game[name] = value
		end)
	end
	self.runService = self.game:GetService("RunService")
	return self
end

function Runtime:record(kind, name, userId, ...)
	table.insert(self.records, { kind = kind, name = name, userId = userId, args = table.pack(...), t = self.T })
end

function Runtime:warn(...)
	local parts = {}
	for i = 1, select("#", ...) do
		table.insert(parts, tostring((select(i, ...))))
	end
	local line = table.concat(parts, " ")
	table.insert(self.warnings, { t = self.T, text = line })
	if self.opts.verbose then
		print(`[warn t={string.format("%.1f", self.T)}] {line}`)
	end
end

function Runtime:dataStore(name, ordered)
	local key = (if ordered then "O:" else "G:") .. name
	if self.stores[key] then
		return self.stores[key]
	end
	local data = {}
	local store = {}
	function store:UpdateAsync(k, transform)
		local new = transform(data[k])
		if new ~= nil then
			data[k] = new
		end
		return data[k]
	end
	function store:GetAsync(k)
		return data[k]
	end
	function store:SetAsync(k, v)
		data[k] = v
	end
	function store:GetSortedAsync(ascending, pageSize)
		local rows = {}
		for k, v in data do
			table.insert(rows, { key = k, value = v })
		end
		table.sort(rows, function(a, b)
			return if ascending then a.value < b.value else a.value > b.value
		end)
		local page = {}
		for i = 1, math.min(pageSize, #rows) do
			page[i] = rows[i]
		end
		return {
			IsFinished = true,
			GetCurrentPage = function()
				return page
			end,
		}
	end
	self.stores[key] = store
	return store
end

-- Scheduler ----------------------------------------------------------------

function Runtime:resume(co, ...)
	if coroutine.status(co) ~= "suspended" then
		return
	end
	local prev = self.running
	self.running = co
	local ok, err = coroutine.resume(co, ...)
	self.running = prev
	if not ok then
		local trace = debug.traceback(co, tostring(err))
		table.insert(self.errors, { t = self.T, text = trace })
		if self.opts.verbose then
			print(`[error t={string.format("%.1f", self.T)}] {trace}`)
		end
	end
end

function Runtime:spawn(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	self:resume(co, ...)
	return co
end

function Runtime:defer(fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	table.insert(self.queue, { co = co, at = self.T, args = table.pack(...) })
	return co
end

function Runtime:delay(seconds, fn, ...)
	local co = if type(fn) == "thread" then fn else coroutine.create(fn)
	table.insert(self.queue, { co = co, at = self.T + (seconds or 0), args = table.pack(...) })
	return co
end

function Runtime:wait(seconds)
	local co = coroutine.running()
	local start = self.T
	table.insert(self.queue, { co = co, at = self.T + math.max(seconds or 0, 1 / 60), args = nil })
	coroutine.yield()
	return self.T - start
end

function Runtime:cancel(co)
	for i = #self.queue, 1, -1 do
		if self.queue[i].co == co then
			table.remove(self.queue, i)
		end
	end
	pcall(coroutine.close, co)
end

function Runtime:runDue()
	-- Threads woken this frame may queue new zero-delay work; loop until quiet.
	for _ = 1, 1000 do
		local due = {}
		local rest = {}
		for _, item in self.queue do
			table.insert(if item.at <= self.T + 1e-9 then due else rest, item)
		end
		self.queue = rest
		if #due == 0 then
			return
		end
		table.sort(due, function(a, b)
			return a.at < b.at
		end)
		for _, item in due do
			if item.args then
				self:resume(item.co, table.unpack(item.args, 1, item.args.n))
			else
				self:resume(item.co, self.T - item.at)
			end
		end
	end
end

function Runtime:step(dt)
	self.T += dt
	self:runDue()
	signalOf(self.runService, "Stepped"):Fire(self.T, dt)
	signalOf(self.runService, "Heartbeat"):Fire(dt)
	self:runDue()
end

function Runtime:advance(seconds, dt)
	dt = dt or 1 / 30
	local target = self.T + seconds
	while self.T < target - 1e-9 do
		self:step(math.min(dt, target - self.T))
	end
end

-- Raycast: axis-aligned bounds of every CanQuery BasePart (rotated parts get
-- their world AABB, so slopes read a bit high). Enough for "where's the ground".
function Runtime:raycast(origin, direction, params)
	local exclude = {}
	local include = nil
	if params then
		local list = params.FilterDescendantsInstances or {}
		if params.FilterType == Enum.RaycastFilterType.Include then
			include = list
		else
			exclude = list
		end
	end
	-- Like Roblox: CanQuery parts are hit whatever their Transparency; RespectCanCollide skips non-colliders.
	local respect = params and params.RespectCanCollide == true
	local best, bestT = nil, math.huge
	for _, part in self.workspace:GetDescendants() do
		if part:IsA("BasePart") and part.CanQuery and (not respect or part.CanCollide) then
			if (include and not isExcluded(part, include)) or isExcluded(part, exclude) then
				continue
			end
			local lo, hi = bounds(part)
			-- slab test
			local tmin, tmax = 0, 1
			local hit = true
			for _, axis in { "X", "Y", "Z" } do
				local o, d = origin[axis], direction[axis]
				if math.abs(d) < 1e-9 then
					if o < lo[axis] or o > hi[axis] then
						hit = false
						break
					end
				else
					local t1, t2 = (lo[axis] - o) / d, (hi[axis] - o) / d
					if t1 > t2 then
						t1, t2 = t2, t1
					end
					tmin, tmax = math.max(tmin, t1), math.min(tmax, t2)
					if tmin > tmax then
						hit = false
						break
					end
				end
			end
			if hit and tmin < bestT then
				best, bestT = part, tmin
			end
		end
	end
	if not best then
		return nil
	end
	return {
		Instance = best,
		Position = origin + direction * bestT,
		Normal = Vector3.yAxis,
		Distance = (direction * bestT).Magnitude,
		Material = best.Material,
	}
end

-- Script loading -------------------------------------------------------------

local function typeofRoblox(v)
	return typeof(v)
end

function Runtime:env(script)
	local rt = self
	local env = {
		script = script,
		game = self.game,
		workspace = self.workspace,
		Workspace = self.workspace,
		Instance = Instance,
		Vector3 = Vector3,
		Vector2 = roblox.Vector2,
		CFrame = CFrame,
		Color3 = roblox.Color3,
		BrickColor = roblox.BrickColor,
		UDim = roblox.UDim,
		UDim2 = roblox.UDim2,
		Enum = Enum,
		Rect = roblox.Rect,
		Ray = roblox.Ray,
		Region3 = roblox.Region3,
		NumberRange = roblox.NumberRange,
		NumberSequence = roblox.NumberSequence,
		NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
		ColorSequence = roblox.ColorSequence,
		ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
		PhysicalProperties = roblox.PhysicalProperties,
		Font = roblox.Font,
		Random = {
			new = function(seed)
				return Random.new(seed or self.randomSeeds:NextInteger(1, 2147483646))
			end,
		},
		RaycastParams = {
			new = function()
				return {
					FilterType = Enum.RaycastFilterType.Exclude,
					FilterDescendantsInstances = {},
					RespectCanCollide = false,
				}
			end,
		},
		typeof = typeofRoblox,
		__livetest_pos = Runtime.readPosition,
		__livetest_collection = self:collection(),
		warn = function(...)
			rt:warn(...)
		end,
		print = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				table.insert(parts, tostring((select(i, ...))))
			end
			table.insert(rt.prints, { t = rt.T, text = table.concat(parts, " ") })
			if rt.opts.verbose then
				print(`[print t={string.format("%.1f", rt.T)}]`, ...)
			end
		end,
		require = function(module)
			return rt:require(module)
		end,
		tick = function()
			return SERVER_EPOCH + rt.T
		end,
		time = function()
			return rt.T
		end,
		task = {
			wait = function(s)
				return rt:wait(s)
			end,
			spawn = function(fn, ...)
				return rt:spawn(fn, ...)
			end,
			defer = function(fn, ...)
				return rt:defer(fn, ...)
			end,
			delay = function(s, fn, ...)
				return rt:delay(s, fn, ...)
			end,
			cancel = function(co)
				rt:cancel(co)
			end,
		},
		wait = function(s)
			return rt:wait(s)
		end,
		os = setmetatable({
			clock = function()
				return rt.T
			end,
			time = function(t)
				if t then
					return os.time(t)
				end
				return math.floor(SERVER_EPOCH + rt.T)
			end,
		}, { __index = os }),
	}
	return setmetatable(env, { __index = _G })
end

-- Source shims for what implementMethod / implementProperty can't override
-- (Lune's built-ins win and its metatables are locked):
--   * `x.Position` reads -> __livetest_pos(x): BasePart.Position isn't stored in
--     place files or kept in sync with CFrame, so read CFrame.Position instead;
--   * game:GetService("CollectionService") -> a table whose AddTag(inst, tag)
--     etc. take the instance argument (the built-in Instance:AddTag would tag
--     CollectionService itself).
-- Writes (`x.Position = ...`, GUI / Attachment positions) are left alone.
function Runtime.rewrite(source)
	source = string.gsub(source, "([%a_][%w_%.]*)%.Position(%s*=?=?)", function(expr, suffix)
		if string.match(suffix, "^%s*=$") then
			return nil -- assignment: keep
		end
		return `__livetest_pos({expr}){suffix}`
	end)
	source = string.gsub(source, 'game:GetService%("CollectionService"%)', "__livetest_collection")
	return source
end

function Runtime.readPosition(v)
	if typeof(v) == "Instance" and v:IsA("BasePart") then
		return v.CFrame.Position
	end
	return v.Position
end

function Runtime:collection()
	if self.collectionProxy then
		return self.collectionProxy
	end
	local rt = self
	local service = self.game:GetService("CollectionService")
	local proxy = {}
	function proxy:AddTag(inst, tag)
		inst:AddTag(tag)
		signalOf(service, "Added:" .. tag):Fire(inst)
	end
	function proxy:RemoveTag(inst, tag)
		inst:RemoveTag(tag)
		signalOf(service, "Removed:" .. tag):Fire(inst)
	end
	function proxy:HasTag(inst, tag)
		return inst:HasTag(tag)
	end
	function proxy:GetTags(inst)
		return inst:GetTags()
	end
	function proxy:GetTagged(tag)
		local out = {}
		for _, d in rt.game:GetDescendants() do
			if d:HasTag(tag) then
				table.insert(out, d)
			end
		end
		return out
	end
	function proxy:GetInstanceAddedSignal(tag)
		return signalOf(service, "Added:" .. tag)
	end
	function proxy:GetInstanceRemovedSignal(tag)
		return signalOf(service, "Removed:" .. tag)
	end
	self.collectionProxy = proxy
	return proxy
end

function Runtime:load(script)
	local source = Runtime.rewrite(script.Source)
	if self.opts.sourceHook then -- opts.sourceHook(script, source) -> source (e.g. force a Config flag)
		source = self.opts.sourceHook(script, source)
	end
	local chunk = luau.load(source, {
		debugName = script:GetFullName(),
		environment = self:env(script),
	})
	return chunk
end

function Runtime:require(module)
	if type(module) ~= "userdata" or typeof(module) ~= "Instance" then
		error(`livetest: require expects a ModuleScript instance, got {typeof(module)}`)
	end
	local cached = self.modules[module]
	if cached then
		if cached.loading then
			error(`livetest: require cycle on {module:GetFullName()}`)
		end
		return cached.value
	end
	local entry = { loading = true }
	self.modules[module] = entry
	local ok, result = pcall(self.load(self, module))
	entry.loading = false
	if not ok then
		self.modules[module] = nil
		error(`Requested module experienced an error while loading: {module:GetFullName()}: {result}`, 0)
	end
	entry.value = result
	return result
end

-- Runs every Script under ServerScriptService (and Workspace), as the engine would.
function Runtime:boot()
	local scripts = {}
	for _, root in { self.game:GetService("ServerScriptService"), self.workspace } do
		for _, d in root:GetDescendants() do
			if d.ClassName == "Script" and not d.Disabled then
				table.insert(scripts, d)
			end
		end
	end
	for _, script in scripts do
		local chunk = self:load(script)
		self:defer(chunk)
	end
	self:runDue()
	return scripts
end

-- Fake player: Player in Players, Character (Humanoid + HumanoidRootPart) at `position`.
function Runtime:addPlayer(userId, name, position)
	local players = self.game:GetService("Players")
	local player = Instance.new("Player")
	player.Name = name
	player.DisplayName = name
	player.UserId = userId
	Instance.new("Backpack").Parent = player
	player.Parent = players
	table.insert(self.players, player)
	signalOf(players, "PlayerAdded"):Fire(player)
	self:runDue()
	local character = Instance.new("Model")
	character.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.CFrame = CFrame.new(position or Vector3.new(0, 10, 0))
	root.Parent = character
	local humanoid = Instance.new("Humanoid")
	humanoid.Health = 100
	humanoid.WalkSpeed = 16
	humanoid.PlatformStand = false -- a reflected property with no default: PvpLaunch (the Bat knockback) reads it
	humanoid.Parent = character
	character.PrimaryPart = root
	character.Parent = self.workspace
	player.Character = character
	signalOf(player, "CharacterAdded"):Fire(character)
	self:runDue()
	return player
end

function Runtime:close()
	for _, fn in self.closeHandlers do
		self:spawn(fn)
	end
	self:advance(1)
end

return Runtime
