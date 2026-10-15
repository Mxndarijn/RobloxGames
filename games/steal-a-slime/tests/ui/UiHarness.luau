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
	if ok then
		return value
	end
	-- Not a property: an event (Activated, MouseEnter, Changed, ...).
	return signal
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

local function newInstance(className: string): any
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

local players = { LocalPlayer = nil }
local services: { [string]: any } = { Players = players }
-- ReplicatedStorage:WaitForChild("Shared") -> src/shared.
services.ReplicatedStorage = setmetatable({}, {
	__index = function(_, key: string): any
		if key == "WaitForChild" or key == "FindFirstChild" then
			return function(_this: any, name: string)
				assert(name == "Shared", `ReplicatedStorage.{name} is not mapped`)
				return pathOf("src/shared")
			end
		end
		return nil
	end,
})

globals = {
	Instance = UiHarness.Instance,
	Enum = roblox.Enum,
	UDim = roblox.UDim,
	UDim2 = roblox.UDim2,
	Vector2 = roblox.Vector2,
	Vector3 = roblox.Vector3,
	Color3 = roblox.Color3,
	ColorSequence = roblox.ColorSequence,
	ColorSequenceKeypoint = roblox.ColorSequenceKeypoint,
	NumberSequence = roblox.NumberSequence,
	NumberSequenceKeypoint = roblox.NumberSequenceKeypoint,
	NumberRange = roblox.NumberRange,
	Rect = roblox.Rect,
	task = task,
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
