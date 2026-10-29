--!strict
-- The owner's steal cards in the top banner stack (src/ui/StealCardsLogic.luau).
local StealCardsLogic = require("../../src/ui/StealCardsLogic")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local function view(id: string, stolenBy: number?)
	return { slime = { id = id }, stolenBy = stolenBy }
end

local function kinds(cards: { StealCardsLogic.Card }): string
	local parts = {}
	for _, card in cards do
		table.insert(parts, `{card.kind}:{card.thief or card.name or ""}`)
	end
	return table.concat(parts, ",")
end

describe("StealCardsLogic", function()
	it("shows nothing while nobody steals", function()
		local m = StealCardsLogic.observe(StealCardsLogic.new(), { slimes = { view("a"), view("b") } }, 0)
		local cards, hidden = StealCardsLogic.cards(m, 0)
		expect(#cards).toBe(0)
		expect(hidden).toBe(0)
	end)

	it("shows a stealing card for one thief", function()
		local m = StealCardsLogic.observe(StealCardsLogic.new(), { slimes = { view("a", 7), view("b") } }, 0)
		local cards, hidden = StealCardsLogic.cards(m, 0)
		expect(kinds(cards)).toBe("stealing:7")
		expect(hidden).toBe(0)
		expect(StealCardsLogic.title(cards[1], "Ann")).toBe("Ann is stealing your slime!")
	end)

	it("puts every thief on one card", function()
		local m =
			StealCardsLogic.observe(StealCardsLogic.new(), { slimes = { view("a", 9), view("b", 7), view("c", 8) } }, 0)
		local cards, hidden = StealCardsLogic.cards(m, 0)
		expect(kinds(cards)).toBe("stealing:7")
		expect(table.concat(cards[1].thieves :: { number }, ",")).toBe("7,8,9")
		expect(hidden).toBe(0)
		expect(StealCardsLogic.thievesText("Ann", nil, 1)).toBe("Ann is stealing your slime!")
		expect(StealCardsLogic.thievesText("Ann", "Bo", 2)).toBe("Ann and Bo are stealing your slimes!")
		expect(StealCardsLogic.thievesText("Ann", "Bo", 3)).toBe("Ann and 2 others are stealing your slimes!")
	end)

	it("counts what does not fit for the more chip", function()
		local m = StealCardsLogic.observe(StealCardsLogic.new(), { slimes = { view("a", 7), view("b", 8) } }, 0)
		m = StealCardsLogic.observe(m, { slimes = {} }, 1) -- both got away with theirs
		local cards, hidden = StealCardsLogic.cards(m, 1)
		expect(kinds(cards)).toBe("stolen:8,stolen:7")
		expect(hidden).toBe(0)
		m = StealCardsLogic.observe(m, { slimes = { view("c", 9) } }, 1.5)
		m = StealCardsLogic.observe(m, { slimes = {} }, 2)
		cards, hidden = StealCardsLogic.cards(m, 2)
		expect(#cards).toBe(StealCardsLogic.MAX_CARDS)
		expect(hidden).toBe(1)
		expect(StealCardsLogic.moreText(hidden)).toBe("+1 more")
		expect(StealCardsLogic.moreText(0)).toBeNil()
	end)

	it("turns a carried slime that leaves the plot into a stolen card for a few seconds", function()
		local m = StealCardsLogic.observe(StealCardsLogic.new(), { slimes = { view("a", 7), view("b") } }, 0)
		m = StealCardsLogic.observe(m, { slimes = { view("b") } }, 10)
		local cards = StealCardsLogic.cards(m, 10)
		expect(kinds(cards)).toBe("stolen:7")
		expect(StealCardsLogic.title(cards[1], "Ann")).toBe("Ann has stolen one of your slimes")
		expect(#StealCardsLogic.cards(m, 10 + StealCardsLogic.STOLEN_SECONDS - 0.1)).toBe(1)
		expect(#StealCardsLogic.cards(m, 10 + StealCardsLogic.STOLEN_SECONDS)).toBe(0)
		m = StealCardsLogic.observe(m, { slimes = { view("b") } }, 10 + StealCardsLogic.STOLEN_SECONDS)
		expect(#m.timed).toBe(0)
	end)

	it("shows no stolen card when the slime escapes home", function()
		local m = StealCardsLogic.observe(StealCardsLogic.new(), { slimes = { view("a", 7) } }, 0)
		m = StealCardsLogic.observe(m, { slimes = { view("a") } }, 1)
		expect(#StealCardsLogic.cards(m, 1)).toBe(0)
	end)

	it("puts live thieves before stolen cards, newest steal first", function()
		local m =
			StealCardsLogic.observe(StealCardsLogic.new(), { slimes = { view("a", 7), view("b", 8), view("c", 9) } }, 0)
		m = StealCardsLogic.observe(m, { slimes = { view("c", 9) } }, 1) -- 7 and 8 got home with theirs
		local cards, hidden = StealCardsLogic.cards(m, 1)
		expect(kinds(cards)).toBe("stealing:9,stolen:8")
		expect(hidden).toBe(1)
	end)

	it("turns each notice into one timed card, shown once", function()
		local notices = {
			{ id = "Bonked", at = 10 },
			{ id = "SlimeHome", at = 10, name = "Ann" },
		}
		local m = StealCardsLogic.observe(StealCardsLogic.new(), { slimes = {}, notices = notices }, 10)
		local cards = StealCardsLogic.cards(m, 10)
		expect(kinds(cards)).toBe("home:Ann,bonked:")
		expect(StealCardsLogic.title(cards[1], "Ann")).toBe("Your slime is back home")
		expect(StealCardsLogic.subtitle(cards[1], "Ann", 10)).toBe("It escaped from Ann")
		expect(StealCardsLogic.title(cards[2], "")).toBe("You got bonked!")
		expect(StealCardsLogic.subtitle(cards[2], "", 10)).toBe("The slime bounced home")
		-- the same notices again (the next State push) add nothing
		m = StealCardsLogic.observe(m, { slimes = {}, notices = notices }, 11)
		expect(#m.timed).toBe(2)
		expect(#StealCardsLogic.cards(m, 13)).toBe(0)
	end)

	it("skips a notice that is already over when it arrives", function()
		local m =
			StealCardsLogic.observe(StealCardsLogic.new(), { slimes = {}, notices = { { id = "Bonked", at = 0 } } }, 9)
		expect(#StealCardsLogic.cards(m, 9)).toBe(0)
	end)

	it("counts down to when a locked base opens", function()
		local notices = { { id = "BaseLocked", at = 10, opensAt = 34.2 } }
		local m = StealCardsLogic.observe(StealCardsLogic.new(), { slimes = {}, notices = notices }, 10)
		local card = StealCardsLogic.cards(m, 10)[1]
		expect(StealCardsLogic.title(card, "")).toBe("This base is locked")
		expect(StealCardsLogic.subtitle(card, "", 10)).toBe("Opens in 0:25")
		expect(StealCardsLogic.subtitle(card, "", 40)).toBe("Opens in 0:00")
	end)
end)

describe("StealCardsLogic.strip", function()
	local NAMES: { [number]: string } = { [7] = "Ann", [8] = "Bo", [9] = "Cy" }
	local function nameOf(id: number): string
		return NAMES[id] or "?"
	end

	it("says nothing while nobody steals", function()
		local m = StealCardsLogic.observe(StealCardsLogic.new(), { slimes = { view("a") } }, 0)
		expect(StealCardsLogic.strip(m, 0, nameOf)).toBeNil()
	end)

	it("puts every live thief in one line, however many", function()
		local one = StealCardsLogic.observe(StealCardsLogic.new(), { slimes = { view("a", 7) } }, 0)
		local strip = StealCardsLogic.strip(one, 0, nameOf) :: StealCardsLogic.Strip
		expect(strip.kind).toBe("stealing")
		expect(strip.text).toBe("Ann is stealing your slime!")
		expect(strip.hint).toBe("Chase them")
		local two = StealCardsLogic.observe(StealCardsLogic.new(), { slimes = { view("a", 8), view("b", 7) } }, 0)
		expect((StealCardsLogic.strip(two, 0, nameOf) :: any).text).toBe("Ann and Bo are stealing your slimes!")
		local three = StealCardsLogic.observe(
			StealCardsLogic.new(),
			{ slimes = { view("a", 9), view("b", 7), view("c", 8), view("d", 7) } },
			0
		)
		expect((StealCardsLogic.strip(three, 0, nameOf) :: any).text).toBe("Ann and 2 others are stealing your slimes!")
	end)

	it("shows the newest timed card when nobody is stealing", function()
		local m = StealCardsLogic.observe(StealCardsLogic.new(), { slimes = { view("a", 7) } }, 0)
		m = StealCardsLogic.observe(m, { slimes = {} }, 1)
		local strip = StealCardsLogic.strip(m, 1, nameOf) :: StealCardsLogic.Strip
		expect(strip.kind).toBe("stolen")
		expect(strip.text).toBe("Ann has stolen one of your slimes")
		expect(strip.hint).toBe("Lock your base")
		local locked = StealCardsLogic.observe(
			StealCardsLogic.new(),
			{ slimes = {}, notices = { { id = "BaseLocked", at = 10, opensAt = 34.2 } } },
			10
		)
		local lockStrip = StealCardsLogic.strip(locked, 10, nameOf) :: StealCardsLogic.Strip
		expect(lockStrip.text).toBe("This base is locked")
		expect(lockStrip.hint).toBe("Opens in 0:25")
	end)
end)

describe("StealCards widget", function()
	local NAMES: { [number]: string } = { [7] = "Ann", [8] = "Bo", [9] = "Cy" }
	local function mount(): (any, any)
		local root = UiHarness.root()
		local cards = UiHarness.ui("StealCards").new(root, {
			serverNow = function()
				return 0
			end,
			playerName = function(id: number): string
				return NAMES[id] or "someone"
			end,
		}, 1)
		return cards, cards.frame
	end
	local robbed = { slimes = { view("a", 9), view("b", 7), view("c", 8) } }

	it("puts every thief on one card", function()
		local cards, frame = mount()
		cards.update(robbed, 0)
		expect(frame.Visible).toBe(true)
		local title = UiHarness.find(frame, "Title").Text
		expect(string.find(title, "Ann", 1, true) ~= nil).toBe(true)
		expect(string.find(title, "and 2 others are stealing your slimes!", 1, true) ~= nil).toBe(true)
		expect((cards.strip(0) :: any).text).toBe("Ann and 2 others are stealing your slimes!")
	end)

	it("hides while folded into the boss card and comes back after", function()
		local cards, frame = mount()
		cards.update(robbed, 0)
		cards.setFolded(true)
		expect(frame.Visible).toBe(false)
		cards.tick(1)
		expect(frame.Visible).toBe(false)
		cards.setFolded(false)
		expect(frame.Visible).toBe(true)
	end)
end)
