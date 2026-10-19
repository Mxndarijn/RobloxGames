--!strict
-- Kit meshes are drawn whole (RenderFidelity.Precise) and the client preloads
-- every replicated MeshPart, so nothing pops in after the first move.
local fs = require("@lune/fs")

local Preload = require("../src/visuals/client/Preload")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- A plain-table stand-in for an Instance: IsA by class name.
local function fake(className: string): any
	return {
		ClassName = className,
		IsA = function(self, name)
			return self.ClassName == name
		end,
	}
end

-- A Map/Plots stand-in with `children` and a DescendantAdded signal `fire` can trigger.
local function fakeRoot(children: { any }): any
	local root = fake("Model")
	local listeners: { (any) -> () } = {}
	root.GetDescendants = function()
		return children
	end
	root.DescendantAdded = {
		Connect = function(_, fn)
			table.insert(listeners, fn)
			return {
				Disconnect = function()
					table.remove(listeners, table.find(listeners, fn))
				end,
			}
		end,
	}
	root.fire = function(d)
		for _, fn in table.clone(listeners) do
			fn(d)
		end
	end
	root.listeners = listeners
	return root
end

-- Runs Preload.start against fake roots; returns every batch handed to PreloadAsync and the cleanup.
local function run(roots: { [string]: any }): ({ { any } }, () -> ())
	local batches: { { any } } = {}
	local cleanup = Preload.start({
		preload = function(batch)
			table.insert(batches, batch)
		end,
		waitForRoot = function(name)
			return roots[name]
		end,
		spawn = function(fn, ...)
			fn(...)
		end,
	} :: any)
	return batches, cleanup
end

describe("mesh preload", function()
	it("hands PreloadAsync only MeshPart instances, never id strings", function()
		local meshes = {}
		for _ = 1, Preload.BATCH + 5 do
			table.insert(meshes, fake("MeshPart"))
		end
		local mapChildren = table.clone(meshes)
		table.insert(mapChildren, fake("Part"))
		table.insert(mapChildren, fake("Decal"))
		local batches = run({ Map = fakeRoot(mapChildren), Plots = fakeRoot({}) })
		local seen = 0
		for _, batch in batches do
			expect(#batch <= Preload.BATCH).toBe(true)
			for _, item in batch do
				expect(type(item)).toBe("table")
				expect(item.ClassName).toBe("MeshPart")
				seen += 1
			end
		end
		expect(seen).toBe(#meshes)
	end)
	it("preloads MeshParts added later until cleanup", function()
		local map = fakeRoot({})
		local batches, cleanup = run({ Map = map })
		expect(#batches).toBe(0)
		local added = fake("MeshPart")
		map.fire(fake("Part"))
		map.fire(added)
		expect(#batches).toBe(1)
		expect(batches[1][1]).toBe(added)
		cleanup()
		expect(#map.listeners).toBe(0)
		map.fire(fake("MeshPart"))
		expect(#batches).toBe(1)
	end)
	it("does not watch a root that appears after cleanup", function()
		local map = fakeRoot({ fake("MeshPart") })
		local resume: (() -> ())? = nil
		local batches = {}
		local cleanup = Preload.start({
			preload = function(batch)
				table.insert(batches, batch)
			end,
			waitForRoot = function(name)
				return if name == "Map" then map else nil
			end,
			spawn = function(fn, ...)
				local args = table.pack(...)
				if resume == nil then
					resume = function()
						fn(table.unpack(args, 1, args.n))
					end
				else
					fn(table.unpack(args, 1, args.n))
				end
			end,
		} :: any)
		cleanup()
		assert(resume, "the Map watcher was deferred")
		resume()
		expect(#batches).toBe(0)
		expect(#map.listeners).toBe(0)
	end)
	it("leaves no listener when cleanup runs during the first preload", function()
		local map = fakeRoot({ fake("MeshPart") })
		local cleanup: (() -> ())? = nil
		local cleanedDuringPreload = false
		local watchers: { () -> () } = {}
		cleanup = Preload.start({
			preload = function(_batch)
				-- PreloadAsync yields; the client tears down while it is still fetching
				if cleanup and not cleanedDuringPreload then
					cleanedDuringPreload = true
					cleanup()
				end
			end,
			waitForRoot = function(name)
				return if name == "Map" then map else nil
			end,
			spawn = function(fn, ...)
				local args = table.pack(...)
				table.insert(watchers, function()
					fn(table.unpack(args, 1, args.n))
				end)
			end,
		} :: any)
		for _, watch in watchers do
			watch()
		end
		expect(cleanedDuringPreload).toBe(true)
		expect(#map.listeners).toBe(0)
	end)
	it("preloads a MeshPart added while the first preload runs", function()
		local map = fakeRoot({ fake("MeshPart") })
		local late = fake("MeshPart")
		local batches: { { any } } = {}
		Preload.start({
			preload = function(batch)
				table.insert(batches, batch)
				if #batches == 1 then
					map.fire(late) -- added while PreloadAsync is still fetching the snapshot
				end
			end,
			waitForRoot = function(name)
				return if name == "Map" then map else nil
			end,
			spawn = function(fn, ...)
				fn(...)
			end,
		} :: any)
		expect(#batches).toBe(2)
		expect(batches[2][1]).toBe(late)
	end)
	it("skips a root that never appears", function()
		local batches = run({})
		expect(#batches).toBe(0)
	end)
	it("MeshSwap draws every swapped mesh at Precise fidelity", function()
		local src = fs.readFile("src/server/MeshSwap.luau")
		-- via the CreateMeshPartAsync options: a game script writing MeshPart.RenderFidelity throws
		-- (PluginOrOpenCloud only) and left every world slot a primitive
		expect(string.find(src, "{ RenderFidelity = Enum.RenderFidelity.Precise }", 1, true) ~= nil).toBe(true)
		expect(string.find(src, ".RenderFidelity =", 1, true)).toBe(nil)
	end)
	it("VisualsClient starts the preload and the place does not stream", function()
		local init = fs.readFile("src/visuals/client/init.client.luau")
		expect(string.find(init, 'WaitForChild("Preload")', 1, true) ~= nil).toBe(true)
		local project = fs.readFile("default.project.json")
		expect(string.find(project, '"StreamingEnabled": false', 1, true) ~= nil).toBe(true)
	end)
end)
