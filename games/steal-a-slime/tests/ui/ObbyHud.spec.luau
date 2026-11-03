--!strict
-- The Obby on screen (contract/obby.md): the HUD status slot (HudClusters.obby), the portal sign's two lines
-- and the run card (ui/ObbyHud).
local Config = require("../../src/shared/Config")
local HudClusters = require("../../src/ui/HudClusters")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local ObbyHud = require("../../src/ui/ObbyHud")
local TestRunner = require("../TestRunner")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function view(extra: { [string]: any }?): any
	local v: { [string]: any } = { bonus = 0.5, sections = { "Jelly Steps" }, rotatesAt = 1600 }
	for k, x in extra or {} do
		v[k] = x
	end
	return v
end

describe("Obby HUD slot", function()
	it("shows x1.5 with the time left while boosted, and nothing otherwise", function()
		local slot = HudClusters.obby(view({ endsAt = 1300 }), 1000) :: HudClusters.Slot
		expect(slot.id).toBe("Obby")
		expect(slot.icon).toBe("Boost_Obby")
		expect(slot.text).toBe("5:00")
		local tip = HudClusters.tooltip(slot)
		expect(tip.title).toBe("Obby")
		expect(string.find(tip.body, "income for clearing the obby", 1, true) ~= nil).toBe(true)
		expect(HudClusters.obby(view(), 1000)).toBeNil()
		expect(HudClusters.obby(view({ endsAt = 1000 }), 1000)).toBeNil()
		expect(HudClusters.obby(nil, 1000)).toBeNil()
	end)

	it("sits after the Boss Champion slot and before the code boost", function()
		expect(table.find(HudClusters.STATUS_IDS, "Obby")).toBe(table.find(HudClusters.STATUS_IDS, "Mvp") :: number + 1)
		expect(table.concat(Layout.STATUS_SLOTS, ",")).toBe(table.concat(HudClusters.STATUS_IDS, ","))
		local slots = HudClusters.status({
			modifierEnabled = false,
			friendsEnabled = false,
			obby = view({ endsAt = 1300 }),
			codes = { boostMult = 2, boostEndsAt = 1300 },
		}, 1000, 9)
		expect(slots[1].id).toBe("Obby")
		expect(slots[2].id).toBe("Boost")
	end)
end)

describe("Obby portal sign", function()
	it("says what this player gets: ready, boosted, or cooling down", function()
		expect(ObbyHud.statusText(view(), 1000)).toBe("Step in: x1.5 income!")
		expect(ObbyHud.statusText(view({ endsAt = 1192, readyAt = 1492 }), 1000)).toBe("x1.5 income · 3:12 left")
		expect(ObbyHud.statusText(view({ readyAt = 1100 }), 1000)).toBe("Boost ready in 1:40")
		expect(ObbyHud.statusText(nil, 1000)).toBe("Step in to start!")
	end)

	it("keeps the boost status after a clear: the portal lets you in again to beat your time", function()
		expect(ObbyHud.statusText(view({ best = 41.2 }), 1000)).toBe("Step in: x1.5 income!")
		expect(ObbyHud.statusText(view({ best = 41.2, endsAt = 1192, readyAt = 1492 }), 1000)).toBe(
			"x1.5 income · 3:12 left"
		)
	end)

	it("names the course and counts down to the next one", function()
		expect(ObbyHud.courseText(view({ course = 1204 }), 1235)).toBe("Course #1,204 · 6:05 left")
		expect(ObbyHud.courseText(view({ course = 7 }), 1235)).toBe("Course #7 · 6:05 left")
		expect(ObbyHud.courseText(view(), 1235)).toBe("New course in 6:05")
		expect(ObbyHud.courseText(nil, 1235)).toBe(
			`A new course every {math.floor(Config.OBBY.ROTATION_SECONDS / 60 + 0.5)} min`
		)
	end)
end)

describe("Obby course board: my line", function()
	it("tints my row when I'm in the top 10, else shows the You line, nothing without a time", function()
		local size = Config.OBBY.BOARD.SIZE
		expect(ObbyHud.boardYou(view({ best = 44.9, rank = 6 }), size).row).toBe(6)
		local you = ObbyHud.boardYou(view({ best = 51.4, rank = 23 }), size)
		expect(you.row).toBeNil()
		expect(you.name).toBe("You #23")
		expect(you.value).toBe("0:51.4")
		expect(ObbyHud.boardYou(view({ best = 51.4, rank = 101 }), size).name).toBe("You #100+")
		expect(ObbyHud.boardYou(view({ best = 51.4 }), size).name).toBe("You")
		expect(ObbyHud.boardYou(view(), size).name).toBeNil()
		expect(ObbyHud.boardYou(nil, size).row).toBeNil()
	end)
end)

describe("Obby run card", function()
	it("shows the furthest section and the run clock only while running", function()
		expect(ObbyHud.runText(view(), 1000)).toBeNil()
		local title, clock = ObbyHud.runText(view({ run = { section = 0, of = 6, startedAt = 990 } }), 1000)
		expect(title).toBe("Start")
		expect(clock).toBe("0:10.0")
		title, clock = ObbyHud.runText(view({ run = { section = 2, of = 6, startedAt = 900 } }), 1003.5)
		expect(title).toBe("Section 2/6")
		expect(clock).toBe("1:43.5")
	end)

	it("shows my best and rank on this course once I have a time on it", function()
		local best, rank = ObbyHud.bestText(view({ best = 51.4, rank = 23 }))
		expect(best).toBe("Best 0:51.4")
		expect(rank).toBe("#23")
		best, rank = ObbyHud.bestText(view({ best = 61.0 }))
		expect(best).toBe("Best 1:01.0")
		expect(rank).toBeNil()
		expect(ObbyHud.bestText(view())).toBeNil()
	end)

	it("draws one pip per section: passed, the furthest reached, still to come", function()
		expect(#ObbyHud.pips(view())).toBe(0)
		local pips = ObbyHud.pips(view({ run = { section = 3, of = 6, startedAt = 0 } }))
		expect(table.concat(pips, ",")).toBe("done,done,here,ahead,ahead,ahead")
		pips = ObbyHud.pips(view({ run = { section = 0, of = 6, startedAt = 0 } }))
		expect(table.concat(pips, ",")).toBe("ahead,ahead,ahead,ahead,ahead,ahead")
		pips = ObbyHud.pips(view({ run = { section = 6, of = 6, startedAt = 0 } }))
		expect(table.concat(pips, ",")).toBe("done,done,done,done,done,here")
	end)

	it("counts the base lock down at the run's lock rate from the last lockUntil it saw", function()
		-- seen at 1000 with 100 s left; 10 s later at half speed: 95 s left
		expect(ObbyHud.lockLeft(1100, 1000, 1010, 0.5)).toBe(95)
		expect(ObbyHud.lockLeft(1100, 1000, 1010, 1)).toBe(90)
		expect(ObbyHud.lockLeft(1100, 1000, 1300, 0.5)).toBe(0) -- ran out
		expect(ObbyHud.lockLeft(nil, 1000, 1010, 0.5)).toBe(0)
		expect(ObbyHud.lockLeft(900, 1000, 1010, 0.5)).toBe(0) -- ended before it was seen
		-- a fresh lockUntil a little later than the estimate never steps the countdown back up; a new lock does
		expect(ObbyHud.lockLeft(1100, 1000, 1000, 0.5, 99.5)).toBe(99.5)
		expect(ObbyHud.lockLeft(1200, 1000, 1000, 0.5, 40)).toBe(200)
	end)

	it("reads the lock rate off the run, held within 0..1", function()
		expect(ObbyHud.lockRate(view({ run = { section = 1, of = 6, startedAt = 0, lockRate = 0.5 } }))).toBe(0.5)
		expect(ObbyHud.lockRate(view({ run = { section = 1, of = 6, startedAt = 0 } }))).toBe(1)
		expect(ObbyHud.lockRate(view({ run = { section = 1, of = 6, startedAt = 0, lockRate = 3 } }))).toBe(1)
		expect(ObbyHud.lockRate(nil)).toBe(1)
	end)

	it("says the lock's time left and how much slower it runs, or that the base is open", function()
		local time, note = ObbyHud.lockText(102, 0.5)
		expect(time).toBe("🔒 1:42")
		expect(note).toBe("50% slower locks")
		time, note = ObbyHud.lockText(102, 1)
		expect(time).toBe("🔒 1:42")
		expect(note).toBeNil()
		time, note = ObbyHud.lockText(0, 0.5)
		expect(time).toBe("🔓 Base open")
		expect(note).toBeNil()
	end)
end)

-- Layout gate for the run card: the six gate viewports, raw and under the 58 px top bar, with and without touch.
describe("Obby run card layout", function()
	local C = Layout.OBBY_CARD
	local sizes = {}
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		table.insert(sizes, vp)
		table.insert(sizes, { name = `{vp.w}x{vp.h - 58}`, w = vp.w, h = vp.h - 58 })
	end
	for _, vp in sizes do
		for _, touch in { false, true } do
			local label = `{vp.name}{if touch then " touch" else ""}`
			it(`{label}: on screen, clear of the nav, hotbar, clusters and jump button, text fits`, function()
				local s = Layout.screen(vp.w, vp.h, { touch = touch })
				local check = LayoutAssert.new(label, s)
				-- under the tallest banner stack the card can meet (one notice card)
				local split = ObbyHud.lockSplit(Layout.obbyCard(s).w)
				local r = Layout.obbyCard(
					s,
					s.banners.y + Layout.NOTICE_CARD.icon + Layout.NOTICE_CARD.pad * 2 + Layout.GAP,
					true, -- with the best-time row: the tallest card
					split
				)
				check.onScreen("ObbyRunCard", r, Layout.MARGIN)
				check.noOverlap("ObbyRunCard", r, "Nav", s.nav)
				check.noOverlap("ObbyRunCard", r, "Hotbar", s.hotbar)
				check.noOverlap("ObbyRunCard", r, "Money", s.money.rect)
				check.noOverlap("ObbyRunCard", r, "Status", s.status.rect)
				if touch then
					local j = Layout.jumpRect(vp.w, vp.h)
					local jump = Layout.rect(j.x / s.scale, j.y / s.scale, j.w / s.scale, j.h / s.scale)
					check.noOverlap("ObbyRunCard", r, "JumpButton", jump)
				end
				local inner = r.w - C.pad * 2
				local _, clockText = ObbyHud.runText(view({ run = { section = 6, of = 6, startedAt = 0 } }), 3599.9)
				local titleW = Layout.lineWidth("Section 6/6", C.titleSize, true)
				local clockW = Layout.lineWidth(clockText :: string, C.clockSize, true)
				if titleW + clockW + C.gap > inner then
					check.fail(`head row needs {titleW + clockW + C.gap} px, has {inner}`)
				end
				local of = #Config.OBBY.ORDER
				local pipsW = of * C.pip + (of - 1) * C.pipGap
				if pipsW > inner then
					check.fail(`{of} pips need {pipsW} px, have {inner}`)
				end
				local time, note = ObbyHud.lockText(Config.LOCK_MAX_SECONDS, Config.OBBY.LOCK_RATE)
				-- side by side, or one chip per line on a split card
				local timeW = Layout.lineWidth(time, C.lockSize, true) + C.chipPad * 2
				local noteW = Layout.lineWidth(note or "", C.noteSize, true) + C.chipPad * 2
				local lockW = if split then math.max(timeW, noteW) else timeW + noteW + C.gap
				if lockW > inner then
					check.fail(`lock row needs {lockW} px, has {inner}`)
				end
				local best, rank = ObbyHud.bestText(view({ best = 3599.9, rank = Config.OBBY.BOARD.RANK_DEPTH + 1 }))
				local bestW = Layout.lineWidth(best :: string, C.bestSize, true)
					+ Layout.lineWidth(rank :: string, C.bestSize, true)
					+ C.chipPad * 2
					+ C.gap
				if bestW > inner then
					check.fail(`best row needs {bestW} px, has {inner}`)
				end
				for _, size in { C.titleSize, C.clockSize, C.pipText, C.lockSize, C.noteSize, C.bestSize } do
					if size < Layout.MIN_TEXT then
						check.fail(`text size {size} < MIN_TEXT {Layout.MIN_TEXT}`)
					end
				end
				expect(check.report()).toBe("")
			end)
		end
	end
end)
