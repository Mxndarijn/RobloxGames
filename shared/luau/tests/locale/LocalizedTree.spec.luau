--!strict
local Localize = require("../../src/locale/Localize")
local LocalizedTree = require("../../src/locale/LocalizedTree")
local T = require("../../testing/TestRunner")
local describe, it, expect = T.describe, T.it, T.expect

local catalog = Localize.catalog({ { ["plot.lock"] = "Lock base", ["plot.owner"] = "{name}'s base" } })

-- JSON stand-in: messages here are flat, so a key|name=value encoding is enough.
local function encode(m: any): string
	local parts = { m.key }
	for k, v in m.args or {} do
		table.insert(parts, `{k}={v}`)
	end
	return table.concat(parts, "|")
end
local function decode(s: string): any
	local parts = string.split(s, "|")
	local args = {}
	for i = 2, #parts do
		local k, v = string.match(parts[i], "^(.-)=(.*)$")
		args[k :: string] = v
	end
	return Localize.msg(parts[1], args)
end

local function signal()
	local s = { handlers = {} :: { any } }
	function s.Connect(self: any, fn: any)
		table.insert(self.handlers, fn)
		return {
			Disconnect = function()
				table.remove(self.handlers, table.find(self.handlers, fn))
			end,
		}
	end
	function s.Fire(self: any, ...: any)
		for _, fn in table.clone(self.handlers) do
			fn(...)
		end
	end
	return s
end

local function fakeInstance(): any
	local attrs, tags, propSignals = {}, {}, {}
	local inst: any = { AutoLocalize = true, ActionText = "", ObjectText = "" }
	inst.AttributeChanged = signal()
	function inst.GetAttribute(_, n)
		return attrs[n]
	end
	function inst.SetAttribute(self, n, v)
		attrs[n] = v
		self.AttributeChanged:Fire(n)
	end
	function inst.GetAttributes()
		return table.clone(attrs)
	end
	function inst.HasTag(_, t)
		return tags[t] == true
	end
	function inst.GetPropertyChangedSignal(_, p)
		propSignals[p] = propSignals[p] or signal()
		return propSignals[p]
	end
	inst._tags = tags
	inst._set = function(p: string, v: any)
		inst[p] = v
		if propSignals[p] then
			propSignals[p]:Fire()
		end
	end
	return inst
end

local serverDeps: LocalizedTree.ServerDeps = {
	english = function(m)
		return Localize.english(catalog, m)
	end,
	encode = encode,
	addTag = function(inst, tag)
		inst._tags[tag] = true
	end,
}

describe("LocalizedTree", function()
	it("writes English, the message attribute and the tag on the server", function()
		local inst = fakeInstance()
		LocalizedTree.set(inst, "ObjectText", Localize.msg("plot.owner", { name = "Ana" }), serverDeps)
		expect(inst.ObjectText).toBe("Ana's base")
		expect(inst:HasTag(LocalizedTree.TAG)).toBe(true)
		expect(LocalizedTree.properties(inst)[1]).toBe("ObjectText")
	end)

	it("translates tagged instances on the client and follows server updates", function()
		local inst = fakeInstance()
		LocalizedTree.set(inst, "ActionText", Localize.msg("plot.lock"), serverDeps)
		local added, removed = signal(), signal()
		local collection = {
			GetInstanceAddedSignal = function()
				return added
			end,
			GetInstanceRemovedSignal = function()
				return removed
			end,
			GetTagged = function()
				return { inst }
			end,
		}
		local translator = {
			text = function(m: any): string
				return Localize.text(catalog, function(e)
					return ({ ["plot.lock"] = "Bloquear base", ["plot.owner"] = "Base de {name}" })[e.key]
				end, m)
			end,
		}
		local handle = LocalizedTree.watch(translator, { collection = collection, decode = decode })
		expect(inst.ActionText).toBe("Bloquear base")
		expect(inst.AutoLocalize).toBe(false)
		-- A server update: the attribute changes, then the English property replicates.
		LocalizedTree.set(inst, "ObjectText", Localize.msg("plot.owner", { name = "Bo" }), serverDeps)
		inst._set("ObjectText", "Bo's base")
		expect(inst.ObjectText).toBe("Base de Bo")
		handle.destroy()
		inst._set("ActionText", "Lock base")
		expect(inst.ActionText).toBe("Lock base")
	end)
end)
