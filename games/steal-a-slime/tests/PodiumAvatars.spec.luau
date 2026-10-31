--!strict

local PlayerSettings = require("../src/shared/PlayerSettings")
local PodiumAvatars = require("../src/server/PodiumAvatars")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

-- A recording fake adapter; rigs are tables { id, desc, kind, text }.
local function fake(opts: { failFetch: { [number]: number }?, failBuild: boolean?, failPlaceholder: boolean? }?)
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
			if o.failPlaceholder then
				error("no placeholder")
			end
			return rig("placeholder")
		end,
		displayName = function(_, fallback)
			return fallback
		end,
		mount = function(rank, r, text)
			r.text = text
			log.mounted[rank] = r
		end,
		setLabel = function(rank, text)
			table.insert(log.labels, `{rank}:{text}`)
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
	it("splits a label into the name for the board's band and the stat under it", function()
		local name, stat = PodiumAvatars.splitLabel(PodiumAvatars.labelText("Merijn", 1500))
		expect(name).toBe("Merijn")
		expect(stat).toBe("$1.5K")
		local only, none = PodiumAvatars.splitLabel("Solo")
		expect(only).toBe("Solo")
		expect(none).toBe("")
	end)
	it("stands a rig on its feet, not on an accessory that hangs below them", function()
		-- Podium top at 5, feet at 1, a cape reaching down to 0.2: the feet land on the top.
		expect(PodiumAvatars.standLift(5, 1, 0.2)).toBe(4)
		-- No feet (the placeholder): the bounding-box bottom lands on the top.
		expect(PodiumAvatars.standLift(5, nil, 0.2)).toBe(4.8)
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
	it("still writes the plate when no rig can be built at all", function()
		local adapter, log = fake({ failBuild = true, failPlaceholder = true })
		PodiumAvatars.new(adapter):apply(board({ 10, 500 }))
		expect(log.mounted[1]).toBeNil()
		expect(log.labels).toEqual({ "1:N10\n$500", "2:", "3:" })
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
		expect(log.labels).toEqual({ "1:N10\n$2.5K" })
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
	it("stands a hidden player on the podium as the default rig, without looking them up", function()
		local adapter, log = fake()
		local names = 0
		adapter.displayName = function(_, fallback)
			names += 1
			return fallback
		end
		local podiums = PodiumAvatars.new(adapter)
		local hidden = {
			stat = "TotalEarned",
			entries = {
				{ rank = 1, userId = 0, name = PlayerSettings.HIDDEN_NAME, value = 900, hidden = true },
				{ rank = 2, userId = 0, name = "N0", value = 500 },
			},
		} :: any
		podiums:apply(hidden)
		expect(next(log.fetches)).toBeNil()
		expect(names).toBe(0)
		expect(log.mounted[1].kind).toBe("default")
		expect(log.mounted[1].text).toBe(PlayerSettings.HIDDEN_NAME .. "\n$900")
		expect(log.mounted[2].kind).toBe("default") -- userId 0 alone also counts as hidden
		expect(log.mounted[2].text).toBe(PlayerSettings.HIDDEN_NAME .. "\n$500")
		-- not a fallback: the next refresh keeps the rig
		podiums:apply(hidden)
		expect(log.built).toBe(2)
		expect(#log.destroyed).toBe(0)
	end)
end)

describe("WorldLayout.podiumTopCentre", function()
	it("finds each podium's flat top where Studio measured it on the placed slots", function()
		-- slot size (x, z) and the top's centre (x, z) in slot studs, probed straight down in a Studio playtest
		local measured = {
			{ 6.246, 6.006, -0.31, -0.19 },
			{ 5.797, 5.594, -0.29, -0.21 },
			{ 5.535, 5.31, -0.31, -0.2 },
		}
		for rank, m in measured do
			local x, z = WorldLayout.podiumTopCentre(rank, m[1], m[2])
			expect(math.abs(x - m[3]) < 0.05).toBe(true)
			expect(math.abs(z - m[4]) < 0.05).toBe(true)
		end
	end)
	it("leaves an unknown podium at its slot's centre", function()
		local x, z = WorldLayout.podiumTopCentre(4, 6, 6)
		expect(x).toBe(0)
		expect(z).toBe(0)
	end)
end)

describe("WorldLayout.podiumPlate", function()
	-- the placed slots (Studio playtest) at the plaza's 0.7 scale, and the model's numbers (_phoenix_podium.py)
	local slots = { { 6.246, 5.034, 6.006 }, { 5.797, 3.639, 5.594 }, { 5.535, 2.865, 5.31 } }
	local SCALE = 0.7
	local P, T = WorldLayout.PODIUM_PLATE, WorldLayout.PODIUM_TOPS
	it("fits each plate between the corner posts, over the plinth and under the red band", function()
		for rank, s in slots do
			local plate = assert(WorldLayout.podiumPlate(rank, s[1], s[2], s[3])).plate
			local w, top = T.column[rank] * SCALE, P.height[rank] * SCALE
			expect(plate.w < w - 0.9 * SCALE).toBe(true) -- inside the posts' inner faces
			expect(plate.y - plate.h / 2 + s[2] / 2 > 0.8 * SCALE).toBe(true) -- above the plinth and step
			expect(plate.y + plate.h / 2 + s[2] / 2 < top - 1.25 * SCALE).toBe(true) -- under the band
			expect(plate.h > 1).toBe(true) -- two lines of text fit even on podium 3
		end
	end)
	it("mounts the plate over the modelled numeral and the medallion over the star", function()
		for rank, s in slots do
			local boxes = assert(WorldLayout.podiumPlate(rank, s[1], s[2], s[3]))
			local _, cz = WorldLayout.podiumTopCentre(rank, s[1], s[3])
			local half = T.column[rank] / 2 * SCALE
			local plateFront = boxes.plate.z + boxes.plate.d / 2 - cz
			local medalFront = boxes.medal.z + boxes.medal.d / 2 - cz
			expect(plateFront > half + 0.53 * SCALE).toBe(true) -- in front of the numeral's face
			expect(medalFront > half + 0.45 * SCALE).toBe(true) -- in front of the star
			expect(medalFront > plateFront).toBe(true) -- the medallion overlaps the plate's top edge
			expect(boxes.medal.y > boxes.plate.y + boxes.plate.h / 2 - boxes.medal.h / 2).toBe(true)
			expect(math.abs(boxes.medal.w - boxes.medal.h) < 1e-6).toBe(true) -- a round disc
		end
	end)
	it("has no plate for an unknown podium", function()
		expect(WorldLayout.podiumPlate(4, 6, 6, 6)).toBeNil()
	end)
end)
