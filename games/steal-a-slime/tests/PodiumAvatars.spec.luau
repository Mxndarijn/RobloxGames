--!strict

local PodiumAvatars = require("../src/server/PodiumAvatars")
local TestRunner = require("./TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- A recording fake adapter; rigs are tables { id, desc, kind, text }.
local function fake(opts: { failFetch: { [number]: number }?, failBuild: boolean? }?)
	local o = opts or {}
	local failFetch = o.failFetch or {}
	local log = { fetches = {}, built = 0, destroyed = {}, mounted = {}, labels = {}, timers = {}, warns = 0 }
	local nextId = 0
	local function rig(kind: string, desc: any?)
		nextId += 1
		return { id = nextId, kind = kind, desc = desc, text = "" }
	end
	local adapter: PodiumAvatars.Adapter = {
		fetchDescription = function(userId)
			log.fetches[userId] = (log.fetches[userId] or 0) + 1
			if (failFetch[userId] or 0) >= log.fetches[userId] then
				error("HTTP 500")
			end
			return `desc{userId}`
		end,
		buildRig = function(desc)
			if o.failBuild then
				error("asset failure")
			end
			log.built += 1
			return rig(if desc then "avatar" else "default", desc)
		end,
		placeholder = function()
			return rig("placeholder")
		end,
		displayName = function(_, fallback)
			return fallback
		end,
		mount = function(rank, r, text)
			r.text = text
			log.mounted[rank] = r
		end,
		setLabel = function(r, text)
			r.text = text
			table.insert(log.labels, text)
		end,
		destroy = function(r)
			table.insert(log.destroyed, r.id)
		end,
		delay = function(_, fn)
			table.insert(log.timers, fn)
		end,
		warn = function()
			log.warns += 1
		end,
	}
	return adapter, log
end

local function board(...: any): any
	local entries = {}
	for i, pair in { ... } do
		entries[i] = { rank = i, userId = pair[1], name = `N{pair[1]}`, value = pair[2] }
	end
	return { stat = "TotalEarned", entries = entries }
end

describe("PodiumAvatars", function()
	it("labels a rig with display name and formatted stat, or no text for an empty slot", function()
		expect(PodiumAvatars.labelText("Merijn", 1500)).toBe("Merijn\n$1.5K")
		expect(PodiumAvatars.labelText(nil, nil)).toBe("")
	end)
	it("mounts avatar rigs for the top three and placeholders for empty slots", function()
		local adapter, log = fake()
		PodiumAvatars.new(adapter):apply(board({ 10, 500 }, { 20, 300 }))
		expect(log.mounted[1].kind).toBe("avatar")
		expect(log.mounted[1].desc).toBe("desc10")
		expect(log.mounted[1].text).toBe("N10\n$500")
		expect(log.mounted[2].desc).toBe("desc20")
		expect(log.mounted[3].kind).toBe("placeholder")
		expect(log.mounted[3].text).toBe("")
	end)
	it("caches descriptions per userId across rebuilds", function()
		local adapter, log = fake()
		local podiums = PodiumAvatars.new(adapter)
		podiums:apply(board({ 10, 500 }, { 20, 300 }))
		podiums:apply(board({ 20, 600 }, { 10, 550 }))
		expect(log.fetches[10]).toBe(1)
		expect(log.fetches[20]).toBe(1)
		expect(log.mounted[1].desc).toBe("desc20")
	end)
	it("retries a failed fetch once, then falls back to the default rig and retries later", function()
		local adapter, log = fake({ failFetch = { [10] = 2 } })
		local podiums = PodiumAvatars.new(adapter)
		podiums:apply(board({ 10, 500 }))
		expect(log.fetches[10]).toBe(2)
		expect(log.mounted[1].kind).toBe("default")
		expect(log.warns).toBe(1)
		-- same board: the fallback slot retries, the fetch now works
		podiums:apply(board({ 10, 500 }))
		expect(log.fetches[10]).toBe(3)
		expect(log.mounted[1].kind).toBe("avatar")
	end)
	it("uses the placeholder when building any rig fails", function()
		local adapter, log = fake({ failBuild = true })
		PodiumAvatars.new(adapter):apply(board({ 10, 500 }))
		expect(log.mounted[1].kind).toBe("placeholder")
		expect(log.mounted[1].text).toBe("N10\n$500")
	end)
	it("rebuilds only slots whose player changed, destroying the old rig", function()
		local adapter, log = fake()
		local podiums = PodiumAvatars.new(adapter)
		podiums:apply(board({ 10, 500 }, { 20, 300 }, { 30, 100 }))
		local first, third = log.mounted[1].id, log.mounted[3].id
		podiums:apply(board({ 10, 500 }, { 20, 300 }, { 30, 100 }))
		expect(log.built).toBe(3)
		expect(#log.destroyed).toBe(0)
		podiums:apply(board({ 10, 500 }, { 20, 300 }, { 40, 200 }))
		expect(log.built).toBe(4)
		expect(log.destroyed).toEqual({ third })
		expect(log.mounted[1].id).toBe(first)
	end)
	it("rewrites only the label when a podium player's stat changes", function()
		local adapter, log = fake()
		local podiums = PodiumAvatars.new(adapter)
		podiums:apply(board({ 10, 500 }))
		podiums:apply(board({ 10, 2500 }))
		expect(log.built).toBe(1)
		expect(log.labels).toEqual({ "N10\n$2.5K" })
	end)
	it("clears a slot to the placeholder when the board shrinks", function()
		local adapter, log = fake()
		local podiums = PodiumAvatars.new(adapter)
		podiums:apply(board({ 10, 500 }, { 20, 300 }))
		local second = log.mounted[2].id
		podiums:apply(board({ 10, 500 }))
		expect(log.destroyed).toEqual({ second })
		expect(log.mounted[2].kind).toBe("placeholder")
	end)
	it("debounces requests: one timer, the latest board wins", function()
		local adapter, log = fake()
		local podiums = PodiumAvatars.new(adapter)
		podiums:request(board({ 10, 500 }))
		podiums:request(board({ 20, 900 }))
		expect(#log.timers).toBe(1)
		expect(log.built).toBe(0)
		log.timers[1]()
		expect(log.mounted[1].desc).toBe("desc20")
		expect(log.fetches[10]).toBeNil()
		podiums:request(board({ 20, 900 }))
		expect(#log.timers).toBe(2)
	end)
end)
