--!strict
--[[
	Loads real src/ui modules (Widgets, Panels/*) under Lune with Roblox
	globals, so tests can build a panel, feed it a State and read the
	resulting Instance properties.

	Instances are thin wrappers: property reads / writes go to a real
	@lune/roblox Instance of the same class (real defaults and type checks),
	the wrapper keeps the Parent / children tree, and events (Activated,
	MouseEnter, ...) are inert signals. No layout engine runs: AbsoluteSize
	is never available, which is exactly the state of a hidden panel.
	`script` / `require` resolve module paths to files under src/.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox") :: any
local task = require("@lune/task")

local UiHarness = {}

-- Count of warn() calls from loaded modules.
UiHarness.warnings = 0

local db = roblox.getReflectionDatabase()

local function isA(className: string, target: string): boolean
	local class = db:GetClass(className)
	while class do
		if class.Name == target then
			return true
		end
		class = if class.Superclass then db:GetClass(class.Superclass) else nil
	end
	return false
end

local signal = table.freeze({
	Connect = function()
		return { Disconnect = function() end }
	end,
	Once = function()
		return { Disconnect = function() end }
	end,
})

export type Mock = any

local Mock = {}
local wrappers: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any

local function unwrap(value: any): any
	return if type(value) == "table" and wrappers[value] then nil else value
end

local methods: { [string]: (any, ...any) -> any } = {}

-- An event that keeps its handlers (instance events, UserInputService.InputBegan); fired by UiHarness.fire.
local eventHandlers: { [any]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any
local function recordingSignal(): any
	local event = { handlers = {} :: { (...any) -> () } }
	function event.Connect(self: any, handler: (...any) -> ())
		table.insert(self.handlers, handler)
		return { Disconnect = function() end }
	end
	event.Once = event.Connect
	return event
end

function methods.GetChildren(self: any): { any }
	return table.clone(rawget(self, "_children"))
end

function methods.FindFirstChild(self: any, name: string): any
	for _, child in rawget(self, "_children") do
		if child.Name == name then
			return child
		end
	end
	return nil
end

function methods.FindFirstChildOfClass(self: any, className: string): any
	for _, child in rawget(self, "_children") do
		if child.ClassName == className then
			return child
		end
	end
	return nil
end

function methods.FindFirstChildWhichIsA(self: any, className: string): any
	for _, child in rawget(self, "_children") do
		if child:IsA(className) then
			return child
		end
	end
	return nil
end

methods.WaitForChild = methods.FindFirstChild

function methods.IsA(self: any, className: string): boolean
	return isA(rawget(self, "_class"), className)
end

function methods.SetAttribute(self: any, name: string, value: any)
	rawget(self, "_attributes")[name] = value
end

function methods.GetAttribute(self: any, name: string): any
	return rawget(self, "_attributes")[name]
end

function methods.GetPropertyChangedSignal(): any
	return signal
end

function methods.GetDescendants(self: any): { any }
	local out = {}
	local function walk(node: any)
		for _, child in rawget(node, "_children") do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(self)
	return out
end

-- Model:GetBoundingBox stand-in: no positions are tracked, so the box is
-- centred at the origin and as big as the largest part on each axis.
function methods.GetBoundingBox(self: any): (any, any)
	local x, y, z = 0, 0, 0
	for _, node in methods.GetDescendants(self) do
		if node:IsA("BasePart") then
			local s = node.Size
			x, y, z = math.max(x, s.X), math.max(y, s.Y), math.max(z, s.Z)
		end
	end
	return roblox.CFrame.new(), roblox.Vector3.new(x, y, z)
end

-- Model / BasePart pivot stand-in: the pose is only remembered (children do not move with it).
local pivots: { [any]: any } = setmetatable({}, { __mode = "k" }) :: any
function methods.PivotTo(self: any, cframe: any)
	pivots[self] = cframe
end

function methods.GetPivot(self: any): any
	return pivots[self] or roblox.CFrame.new()
end

function methods.ClearAllChildren(self: any)
	for _, child in methods.GetChildren(self) do
		child:Destroy()
	end
end

function methods.Destroy(self: any)
	self.Parent = nil
	for _, child in methods.GetChildren(self) do
		child:Destroy()
	end
end

local newInstance: (className: string) -> any

-- Deep copy of the subtree; properties that point into it (e.g.
-- Model.PrimaryPart) are remapped to the copies, as in Roblox.
function methods.Clone(self: any): any
	local copies: { [any]: any } = {}
	local function copy(source: any): any
		local c = newInstance(rawget(source, "_class"))
		copies[source] = c
		rawset(c, "_attributes", table.clone(rawget(source, "_attributes")))
		for _, child in rawget(source, "_children") do
			copy(child).Parent = c
		end
		return c
	end
	local root = copy(self)
	for source, c in copies do
		for key, value in rawget(source, "_props") do
			c[key] = copies[value] or value
		end
	end
	return root
end

local function setParent(self: any, parent: any)
	local old = rawget(self, "_parent")
	if old then
		local siblings = rawget(old, "_children")
		local i = table.find(siblings, self)
		if i then
			table.remove(siblings, i)
		end
	end
	rawset(self, "_parent", parent)
	if parent then
		table.insert(rawget(parent, "_children"), self)
	end
end

Mock.__index = function(self: any, key: string): any
	if key == "Parent" then
		return rawget(self, "_parent")
	elseif key == "ClassName" then
		return rawget(self, "_class")
	elseif methods[key] then
		return methods[key]
	end
	local props = rawget(self, "_props")
	if props[key] ~= nil then
		return props[key]
	end
	local ok, value = pcall(function()
		return rawget(self, "_real")[key]
	end)
	-- A signal table from the real Instance comes from the livetest Runtime's process-wide event shims (a spec that
	-- booted the server ran first); UiHarness.fire can't reach it, so it gets a recording signal like any event.
	-- Those shims stay installed for the rest of `lune run tests` (roblox.implementProperty can't be undone), so UI
	-- specs still run after them; this keeps a mock's events its own either way.
	if ok and not (type(value) == "table" and type(value.Connect) == "function") then
		return value
	end
	-- Not a property: an event (Activated, MouseEnter, Changed, ...). It records its handlers so a spec can
	-- UiHarness.fire it.
	local perInstance = eventHandlers[self]
	if perInstance == nil then
		perInstance = {}
		eventHandlers[self] = perInstance
	end
	local event = perInstance[key]
	if event == nil then
		event = recordingSignal()
		perInstance[key] = event
	end
	return event
end

Mock.__newindex = function(self: any, key: string, value: any)
	if key == "Parent" then
		setParent(self, value)
		return
	end
	local real = rawget(self, "_real")
	local raw = unwrap(value)
	if raw ~= nil then
		real[key] = raw -- type-checks against the real class
	end
	rawget(self, "_props")[key] = value
end

Mock.__tostring = function(self: any): string
	return `{rawget(self, "_class")}:{self.Name}`
end

function newInstance(className: string): any
	local real = roblox.Instance.new(className)
	local self = setmetatable({
		_class = className,
		_real = real,
		_props = {},
		_children = {},
		_attributes = {},
		_parent = nil,
	}, Mock)
	wrappers[self] = true
	return self
end

UiHarness.Instance = table.freeze({ new = newInstance })

-- Module paths: `script`, `script.Parent.X`, ReplicatedStorage.Shared.X.
local Path = {}
Path.__index = function(self: any, key: string): any
	if key == "Parent" then
		local dir = string.match(rawget(self, "path"), "^(.*)/[^/]+$")
		return setmetatable({ path = dir }, Path)
	elseif key == "WaitForChild" or key == "FindFirstChild" then
		return function(this: any, name: string)
			return this[name]
		end
	end
	return setmetatable({ path = `{rawget(self, "path")}/{key}` }, Path)
end

local function pathOf(path: string): any
	return setmetatable({ path = path }, Path)
end

local cache: { [string]: any } = {}
local globals: { [string]: any }

local function fileFor(path: string): string
	if fs.isFile(`{path}.luau`) then
		return `{path}.luau`
	end
	return `{path}/init.luau`
end

local function load(path: string): any
	if cache[path] ~= nil then
		return cache[path]
	end
	local env = table.clone(globals)
	env.script = pathOf(path)
	local chunk = luau.load(fs.readFile(fileFor(path)), { debugName = path, environment = env })
	local result = chunk()
	cache[path] = result
	return result
end

-- Workspace attributes the loaded modules read (RainNextAt, ...); tests set and clear them.
UiHarness.workspaceAttributes = {} :: { [string]: any }

-- `task` for loaded modules: Lune's scheduler, unless UiHarness.virtualTime() is on. Then spawn runs the
-- body at once, wait / delay park the thread on a virtual clock and UiHarness.advance(dt) wakes it
-- (counting every wakeup), so loops like Toasts' 0.25 s sync are measured without real waiting.
type Sleeper = { at: number, thread: thread, interval: number }
local virtual: { now: number, sleepers: { Sleeper }, owned: { [thread]: boolean } }? = nil

local function resume(thread: thread, ...: any)
	local ok, err = coroutine.resume(thread, ...)
	if not ok then
		error(err, 0)
	end
end

UiHarness.task = {
	spawn = function(f: any, ...: any): thread
		if not virtual then
			return task.spawn(f, ...)
		end
		local thread = coroutine.create(f)
		virtual.owned[thread] = true
		resume(thread, ...)
		return thread
	end,
	delay = function(seconds: number, f: any, ...: any): thread
		if not virtual then
			return task.delay(seconds, f, ...)
		end
		local args = table.pack(...)
		local thread = coroutine.create(function()
			f(table.unpack(args, 1, args.n))
		end)
		virtual.owned[thread] = true
		table.insert(virtual.sleepers, { at = virtual.now + seconds, thread = thread, interval = seconds })
		return thread
	end,
	wait = function(seconds: number?): number
		-- Only threads born under this virtual clock sleep on it; a thread left over from an earlier
		-- spec (real scheduler) keeps waiting for real, so it never shows up as a wakeup here.
		if not virtual or not virtual.owned[coroutine.running()] then
			return task.wait(seconds)
		end
		local interval = seconds or 0
		table.insert(
			virtual.sleepers,
			{ at = virtual.now + interval, thread = coroutine.running(), interval = interval }
		)
		coroutine.yield()
		return interval
	end,
	defer = function(f: any, ...: any): thread
		return task.defer(f, ...)
	end,
	cancel = function(thread: thread)
		if not virtual then
			task.cancel(thread)
			return
		end
		for i = #virtual.sleepers, 1, -1 do
			if virtual.sleepers[i].thread == thread then
				table.remove(virtual.sleepers, i)
			end
		end
	end,
}

-- os.clock for loaded modules runs ahead by the virtual seconds advanced so far (never back).
local clockShift = 0

function UiHarness.virtualTime(on: boolean)
	if virtual then
		clockShift += virtual.now
	end
	virtual = if on then { now = 0, sleepers = {}, owned = {} } else nil
end

-- Moves the virtual clock forward, waking sleepers in order.
function UiHarness.advance(seconds: number)
	local v = assert(virtual, "UiHarness.virtualTime(true) first")
	local target = v.now + seconds
	while true do
		local nextIndex: number? = nil
		for i, sleeper in v.sleepers do
			if sleeper.at <= target and (nextIndex == nil or sleeper.at < v.sleepers[nextIndex].at) then
				nextIndex = i
			end
		end
		if not nextIndex then
			break
		end
		local sleeper = table.remove(v.sleepers, nextIndex) :: Sleeper
		v.now = math.max(v.now, sleeper.at)
		UiHarness.stats.wakeups += 1
		resume(sleeper.thread)
	end
	v.now = target
end

-- Parked threads now, by sleep interval ("0.25" -> 1): the live polling loops.
function UiHarness.sleepers(): { [string]: number }
	local out: { [string]: number } = {}
	for _, sleeper in if virtual then virtual.sleepers else {} do
		local key = tostring(sleeper.interval)
		out[key] = (out[key] or 0) + 1
	end
	return out
end

local players = {
	LocalPlayer = nil,
	PlayerRemoving = signal,
	PlayerAdded = signal,
	GetPlayers = function(): { any }
		return {}
	end,
	GetPlayerByUserId = function(): any
		return nil
	end,
}
local services: { [string]: any } = { Players = players }

-- Live counters for tests/ui/PerfMeasure: frame-event connections (connects minus disconnects, per
-- event), TweenService:Create / Play calls and task wakeups. Always on; a counter costs one add.
UiHarness.stats = {
	connects = { RenderStepped = 0, Heartbeat = 0, Stepped = 0 } :: { [string]: number },
	disconnects = { RenderStepped = 0, Heartbeat = 0, Stepped = 0 } :: { [string]: number },
	tweensCreated = 0,
	tweensPlayed = 0,
	tweensCancelled = 0,
	wakeups = 0,
}

-- RunService event with a callback list: Connect counts, the connection's Disconnect counts once.
local function frameEvent(name: string): any
	local callbacks: { [any]: boolean } = {}
	return {
		Connect = function(_self: any, callback: any)
			UiHarness.stats.connects[name] += 1
			local live = true
			callbacks[callback] = true
			return {
				Connected = true,
				Disconnect = function()
					if live then
						live = false
						callbacks[callback] = nil
						UiHarness.stats.disconnects[name] += 1
					end
				end,
			}
		end,
		-- Fires every live callback (tests drive frames by hand).
		Fire = function(_self: any, ...: any)
			for callback in table.clone(callbacks) do
				callback(...)
			end
		end,
	}
end

-- Not Studio here, so the PcwHold test hook in Widgets.holdButton stays off.
services.RunService = {
	IsStudio = function(_self: any): boolean
		return false
	end,
	RenderStepped = frameEvent("RenderStepped"),
	Heartbeat = frameEvent("Heartbeat"),
	Stepped = frameEvent("Stepped"),
}
-- Toasts: no sound playback, tweens are inert.
services.SoundService = {
	PlayLocalSound = function() end,
}
-- InputBegan / GetLastInputType: the status tooltip (Hud) opens on hover, a tap, and closes on a press elsewhere.
UiHarness.inputBegan = recordingSignal()
UiHarness.lastInputType = roblox.Enum.UserInputType.MouseMovement
services.UserInputService = {
	InputChanged = signal,
	InputEnded = signal,
	InputBegan = UiHarness.inputBegan,
	GetLastInputType = function(): any
		return UiHarness.lastInputType
	end,
}
services.GuiService = {
	GetGuiInset = function(): any
		return { X = 0, Y = 0 }
	end,
}
services.TweenService = {
	Create = function()
		UiHarness.stats.tweensCreated += 1
		return {
			Play = function()
				UiHarness.stats.tweensPlayed += 1
			end,
			Cancel = function()
				UiHarness.stats.tweensCancelled += 1
			end,
		}
	end,
}
services.CollectionService = {
	GetInstanceAddedSignal = function()
		return signal
	end,
	GetInstanceRemovedSignal = function()
		return signal
	end,
	GetTagged = function()
		return {}
	end,
}
services.Debris = { AddItem = function() end }
-- ReplicatedStorage:WaitForChild("Shared") -> src/shared, "Visuals" -> src/visuals/shared, "Lib" -> shared/luau/src.
local REPLICATED = {
	Shared = "src/shared",
	Visuals = "src/visuals/shared",
	Lib = "../../shared/luau/src",
}
services.ReplicatedStorage = setmetatable({}, {
	__index = function(_, key: string): any
		if key == "WaitForChild" or key == "FindFirstChild" then
			return function(_this: any, name: string)
				local path = REPLICATED[name]
				assert(path, `ReplicatedStorage.{name} is not mapped`)
				return pathOf(path)
			end
		end
		local path = REPLICATED[key] -- ReplicatedStorage.Shared (the dual require pattern)
		return if path then pathOf(path) else nil
	end,
})

globals = {
	Instance = UiHarness.Instance,
	Enum = roblox.Enum,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	Rect = roblox.Rect,
	task = UiHarness.task,
	os = setmetatable({
		clock = function(): number
			return os.clock() + clockShift + if virtual then virtual.now else 0
		end,
	}, { __index = os }),
	workspace = {
		Terrain = newInstance("Folder"), -- a parent for world attachments (SlimeActor's goo string)
		GetAttribute = function(_self: any, name: string): any
			return UiHarness.workspaceAttributes[name]
		end,
		GetAttributeChangedSignal = function()
			return signal
		end,
		GetServerTimeNow = function()
			return 1000
		end,
	},
	-- @lune/roblox has no TweenInfo; tweens are inert here, so a plain record does.
	TweenInfo = roblox.TweenInfo or table.freeze({
		new = function(...: any): any
			return table.freeze({ ... })
		end,
	}),
	warn = function()
		UiHarness.warnings += 1
	end,
	game = {
		GetService = function(_self: any, name: string): any
			return assert(services[name], `service {name} is not mapped`)
		end,
	},
	require = function(target: any): any
		if type(target) == "table" and rawget(target, "path") then
			return load(rawget(target, "path"))
		end
		error(`UiHarness can only require module paths, got {tostring(target)}`)
	end,
}

-- The src/ui module at `path` (e.g. "Panels/Shop", "Widgets").
function UiHarness.ui(path: string): any
	return load(`src/ui/{path}`)
end

-- A ScreenGui-like root to parent panels to.
-- Runs the handlers connected to `instance.<event>` (Activated, MouseEnter, ...).
function UiHarness.fire(instance: any, event: string, ...: any)
	local perInstance = eventHandlers[instance]
	local recorded = if perInstance then perInstance[event] else nil
	for _, handler in if recorded then table.clone(recorded.handlers) else {} do
		handler(...)
	end
end

-- Runs the UserInputService.InputBegan handlers with a fake press (`kind`: "MouseButton1" | "Touch").
function UiHarness.press(kind: string, x: number, y: number)
	local input = { UserInputType = roblox.Enum.UserInputType[kind], Position = { X = x, Y = y } }
	for _, handler in table.clone(UiHarness.inputBegan.handlers) do
		handler(input)
	end
end

function UiHarness.root(): any
	return newInstance("ScreenGui")
end

-- Every descendant (depth first).
function UiHarness.descendants(root: any): { any }
	local out = {}
	local function walk(node: any)
		for _, child in node:GetChildren() do
			table.insert(out, child)
			walk(child)
		end
	end
	walk(root)
	return out
end

-- Fires one RenderStepped frame (Widgets.holdButton fills on frames; tests drive them by hand).
function UiHarness.renderStep()
	services.RunService.RenderStepped:Fire()
end

-- The first descendant named `name`.
function UiHarness.find(root: any, name: string): any
	for _, node in UiHarness.descendants(root) do
		if node.Name == name then
			return node
		end
	end
	return nil
end

return UiHarness
