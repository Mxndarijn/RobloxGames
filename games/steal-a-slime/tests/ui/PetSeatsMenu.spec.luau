--!strict
-- The Skins menu's Base / Building / Cloud tabs (contract/pet-seats.md): the menu is titled "Skins" and opens on Base;
-- the Cloud tab lists every pet seat with how to unlock it (a line with a bar for Jelly and Rainbow Cloud, a gold
-- Exclusive tag and its price for the rest), Equip asks the server with EquipPetSeat, and Buy on an Exclusive opens
-- Roblox's prompt for Seat_<id>.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local PetSeats = require("../../src/shared/PetSeats")
local PetSeatsView = require("../../src/ui/PetSeatsView")
local PlayerData = require("../../src/shared/PlayerData")
local PlotSkins = require("../../src/shared/PlotSkins")
local Remotes = require("../../src/shared/Remotes")
local SlimeLooks = require("../../src/shared/SlimeLooks")
local SlimeRoster = require("../../src/shared/SlimeRoster")
local SpeciesDex = require("../../src/shared/SpeciesDex")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local UnsoldConfig = require("./UnsoldConfig")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local UDim2 = (require("@lune/roblox") :: any).UDim2

-- State.petSeats for a profile with `merges` merges and the first `found` SlimeDex entries, wearing `equipped`.
local function seats(merges: number, found: number, equipped: string?): { any }
	local data = PlayerData.new()
	data.stats.merges = merges
	for i, entry in SpeciesDex.ENTRIES do
		if i <= found then
			data.found[entry.id] = true
		end
	end
	data.petSeat = equipped or "cloud"
	return PetSeats.view(data)
end

local function ctx(requests: { any }?): any
	return {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		SlimeRoster = SlimeRoster,
		SlimeLooks = SlimeLooks,
		PlotSkins = PlotSkins,
		setName = SpeciesDex.setName,
		actions = Remotes.ACTIONS,
		send = function() end,
		serverNow = function()
			return 1000
		end,
		playerName = function()
			return "Tester"
		end,
		toast = function() end,
		request = function(action: string, _cb: any, ...: any)
			table.insert(requests or {}, { action, ... })
		end,
	}
end

local function openSkins(w: number, h: number, state: any, requests: { any }?, c: any?): (any, Layout.Rect)
	local panel = UiHarness.ui("Panels/Skins").new(UiHarness.root(), c or ctx(requests))
	local raw = Layout.panelFor(Layout.screen(w, h), "Skins")
	local r = Layout.rect(math.floor(raw.x), math.floor(raw.y), math.floor(raw.w), math.floor(raw.h))
	panel.frame.Size = UDim2.fromOffset(r.w, r.h)
	panel.layout(r)
	panel.update(state)
	panel.setOpen(true)
	panel.frame.Visible = true
	return panel, r
end

local function cloudState(merges: number, found: number, equipped: string?): any
	return {
		dex = Fixtures.dex({}),
		plotSkins = PlotSkins.view(PlayerData.new()),
		petSeats = seats(merges, found, equipped),
	}
end

describe("PetSeatsView.rows", function()
	it("is empty without State.petSeats", function()
		expect(#PetSeatsView.rows(nil, Config)).toBe(0)
		expect(#PetSeatsView.rows("junk", Config)).toBe(0)
	end)
	it("one row per seat: the cloud equipped, Jelly and Rainbow Cloud with a line and a count", function()
		local rows = PetSeatsView.rows(seats(136, 26), Config)
		expect(#rows).toBe(#Config.PET_SEATS)
		expect(rows[1].key).toBe("seat:cloud")
		expect(rows[1].title).toBe("Fluffy")
		expect(rows[1].state).toBe("equipped")
		expect(rows[1].line).toBe("")
		expect(rows[2].title).toBe("Jelly")
		expect(rows[2].line).toBe("Merge 200 slimes.")
		expect(rows[2].count).toBe("136/200")
		expect(rows[2].fraction).toBeCloseTo(136 / 200)
		expect(rows[2].exclusive).toBe(false)
		expect(rows[3].title).toBe("Rainbow cloud")
		expect(rows[3].line).toBe("Complete 80% of the SlimeDex.")
		expect(rows[3].count).toBe(`{math.floor(26 * 100 / SpeciesDex.TOTAL)}%/80%`)
		expect(PetSeatsView.summary(rows)).toBe(`1/{#rows} unlocked`)
	end)
	it("every other seat is Exclusive: its price, no line or count, never 'Coming soon'", function()
		for i, row in PetSeatsView.rows(seats(0, 0), Config) do
			if i > 3 then
				expect(row.exclusive).toBe(true)
				expect(row.price).toBe(`R${Config.EXCLUSIVE_SHOP.products[`Seat_{row.id}`].robux}`)
				expect(row.line).toBe("")
				expect(row.count).toBe("")
			else
				expect(row.price).toBe("")
			end
			expect(string.find(string.lower(row.line), "coming soon", 1, true)).toBeNil()
		end
	end)
	it("an earned seat is unlocked, the worn one equipped", function()
		local rows = PetSeatsView.rows(seats(200, 0, "jelly"), Config)
		expect(rows[1].state).toBe("unlocked")
		expect(rows[2].state).toBe("equipped")
		expect(rows[2].line).toBe("")
		expect(PetSeatsView.firstSelected(rows)).toBe("jelly")
	end)
end)

describe("PetSeatsView.detail", function()
	it("a free unlock says how to unlock it and what is still missing", function()
		local jelly = PetSeatsView.detail(seats(136, 0), "jelly") :: PetSeatsView.Detail
		expect(jelly.heading).toBe("How to unlock")
		expect(jelly.line).toBe("Merge 200 slimes.")
		expect(jelly.count).toBe("136/200")
		expect(jelly.action).toBe("Merge 64 more slimes")
		local rainbow = PetSeatsView.detail(seats(0, 26), "rainbow_cloud") :: PetSeatsView.Detail
		local have = math.floor(26 * 100 / SpeciesDex.TOTAL)
		expect(rainbow.action).toBe(`{80 - have}% more of the SlimeDex`)
	end)
	it("an Exclusive says where to get it and sells Seat_<id>; not on sale it opens the shop", function()
		local storm = PetSeatsView.detail(seats(0, 0), "storm_cloud", Config) :: PetSeatsView.Detail
		local product = Config.EXCLUSIVE_SHOP.products.Seat_storm_cloud
		expect(storm.exclusive).toBe(true)
		expect(storm.heading).toBe("How to get it")
		expect(storm.line).toBe("Buy it here or in the Exclusive shop.")
		expect(storm.count).toBeNil()
		expect(storm.action).toBe(`Buy · R${product.robux}`)
		expect(storm.purchase).toEqual({ kind = "product", id = product.productId })
		expect(storm.shopKey).toBe("seat:storm_cloud")
		local unsold = PetSeatsView.detail(seats(0, 0), "storm_cloud", UnsoldConfig) :: PetSeatsView.Detail
		expect(unsold.action).toBe("Exclusive shop")
		expect(unsold.purchase).toBeNil()
		expect(unsold.shopKey).toBe("seat:storm_cloud")
	end)
	it("Equip once unlocked, Equipped once worn; nil for an unknown seat", function()
		expect((PetSeatsView.detail(seats(200, 0), "jelly") :: any).action).toBe("Equip")
		expect((PetSeatsView.detail(seats(0, 0), "cloud") :: any).action).toBe("Equipped")
		expect(PetSeatsView.detail(seats(0, 0), "nope")).toBeNil()
		expect(PetSeatsView.detail(nil, "cloud")).toBeNil()
	end)
end)

describe("Skins menu tabs", function()
	it("is titled Skins and opens on the Base tab with the plot skins", function()
		local panel = openSkins(1920, 1080, cloudState(0, 0))
		expect(UiHarness.find(panel.frame, "Title").Text).toBe("Skins")
		expect(panel.tab()).toBe("base")
		expect(UiHarness.find(panel.frame, "Tab_base"):GetAttribute("Selected")).toBe(true)
		expect(UiHarness.find(panel.frame, "Tab_cloud"):GetAttribute("Selected")).toBe(false)
		expect(UiHarness.find(panel.frame, "List").Visible).toBe(true)
		expect(UiHarness.find(panel.frame, "SeatList").Visible).toBe(false)
	end)
	it("tapping Cloud lists the seats, with its own unlocked count", function()
		local panel = openSkins(1920, 1080, cloudState(200, 0))
		UiHarness.fire(UiHarness.find(panel.frame, "Tab_cloud"), "Activated")
		expect(panel.tab()).toBe("cloud")
		expect(UiHarness.find(panel.frame, "List").Visible).toBe(false)
		local list = UiHarness.find(panel.frame, "SeatList")
		expect(list.Visible).toBe(true)
		expect(UiHarness.find(list, "seat:cloud") ~= nil).toBe(true)
		expect(UiHarness.find(list, "seat:hoverboard") ~= nil).toBe(true)
		expect(UiHarness.find(panel.frame, "Summary").Text).toBe(`2/{#Config.PET_SEATS} unlocked`)
	end)
	it("opens on Base again after closing on Cloud", function()
		local panel = openSkins(1920, 1080, cloudState(0, 0))
		panel.setTab("cloud")
		panel.setOpen(false)
		panel.setOpen(true)
		expect(panel.tab()).toBe("base")
	end)
	it("a locked row shows its line and bar; an Exclusive row its gold tag and no bar", function()
		local panel = openSkins(1920, 1080, cloudState(136, 0))
		panel.setTab("cloud")
		local list = UiHarness.find(panel.frame, "SeatList")
		local jelly = UiHarness.find(list, "seat:jelly")
		expect(UiHarness.find(jelly, "Line").Text).toBe("Merge 200 slimes.")
		expect(UiHarness.find(jelly, "Progress").Visible).toBe(true)
		expect(UiHarness.find(jelly, "Count").Text).toBe("136/200")
		expect(UiHarness.find(jelly, "Exclusive").Visible).toBe(false)
		local storm = UiHarness.find(list, "seat:storm_cloud")
		expect(UiHarness.find(storm, "Exclusive").Visible).toBe(true)
		expect(UiHarness.find(storm, "Price").Visible).toBe(true)
		expect(UiHarness.find(storm, "Price").Text).toBe(`R${Config.EXCLUSIVE_SHOP.products.Seat_storm_cloud.robux}`)
		expect(UiHarness.find(storm, "Line").Visible).toBe(false)
		expect(UiHarness.find(storm, "Progress").Visible).toBe(false)
		expect(UiHarness.find(jelly, "Price").Visible).toBe(false)
		local cloud = UiHarness.find(list, "seat:cloud")
		expect(UiHarness.find(cloud, "State").Text).toBe("Equipped")
		expect(UiHarness.find(cloud, "Line").Visible).toBe(false)
	end)
	it("picking an Exclusive shows how to get it and Buy, which opens Roblox's prompt for Seat_<id>", function()
		local prompts = {}
		local c = ctx()
		c.purchase = {
			prompt = function(p: any): boolean
				table.insert(prompts, p)
				return true
			end,
		}
		local panel = openSkins(1920, 1080, cloudState(0, 0), nil, c)
		panel.setTab("cloud")
		UiHarness.fire(UiHarness.find(UiHarness.find(panel.frame, "SeatList"), "seat:storm_cloud"), "Activated")
		expect(panel.selected()).toBe("storm_cloud")
		local pane = UiHarness.find(panel.frame, "Pane")
		local product = Config.EXCLUSIVE_SHOP.products.Seat_storm_cloud
		expect(UiHarness.find(pane, "PaneTitle").Text).toBe("Storm cloud")
		expect(UiHarness.find(pane, "Exclusive").Visible).toBe(true)
		expect(UiHarness.find(UiHarness.find(pane, "How"), "Heading").Text).toBe("How to get it")
		expect(UiHarness.find(pane, "Equip").Visible).toBe(false)
		expect(UiHarness.find(pane, "Well").Visible).toBe(false)
		local buy = UiHarness.find(pane, "Buy")
		expect(buy.Visible).toBe(true)
		expect(buy.Text).toBe(`Buy · R${product.robux}`)
		UiHarness.fire(buy, "Activated")
		expect(prompts).toEqual({ { kind = "product", id = product.productId } })
		expect(UiHarness.find(pane, "Slime1")).toBeNil()
	end)
	it("an Exclusive not on sale yet opens the Exclusive shop on that seat instead", function()
		local opened = {}
		local c = ctx()
		c.Config = UnsoldConfig
		c.purchase = {
			prompt = function(): boolean
				return true
			end,
		}
		c.openExclusiveShop = function(key: string?)
			table.insert(opened, key)
		end
		local state = cloudState(0, 0)
		state.exclusiveShop = {}
		local panel = openSkins(1920, 1080, state, nil, c)
		panel.setTab("cloud")
		panel.select("storm_cloud")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "Buy").Visible).toBe(false)
		local shop = UiHarness.find(pane, "ExclusiveShop")
		expect(shop.Visible).toBe(true)
		UiHarness.fire(shop, "Activated")
		expect(opened).toEqual({ "seat:storm_cloud" })
	end)
	it("Equip on an unlocked seat asks the server with EquipPetSeat(seatId)", function()
		local requests = {}
		local panel = openSkins(1920, 1080, cloudState(200, 0), requests)
		panel.setTab("cloud")
		panel.select("jelly")
		local equip = UiHarness.find(UiHarness.find(panel.frame, "Pane"), "Equip")
		expect(equip.Visible).toBe(true)
		UiHarness.fire(equip, "Activated")
		expect(#requests).toBe(1)
		expect(requests[1][1]).toBe("EquipPetSeat")
		expect(requests[1][2]).toBe("jelly")
	end)
	it("back on Base the pane shows the skin again, without the seat's box or tag", function()
		local panel = openSkins(1920, 1080, cloudState(0, 0))
		panel.setTab("cloud")
		panel.select("storm_cloud")
		panel.setTab("base")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "How").Visible).toBe(false)
		expect(UiHarness.find(pane, "Exclusive").Visible).toBe(false)
		expect(UiHarness.find(pane, "PaneTitle").Text).toBe("Classic ranch")
	end)
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(`{vp.name}: tabs, seat rows and the seat pane stay inside the body`, function()
			local panel, r = openSkins(vp.w, vp.h, cloudState(136, 26))
			panel.setTab("cloud")
			panel.select("rainbow_cloud")
			local body = Layout.panelBody(r)
			local list = UiHarness.find(panel.frame, "SeatList")
			local pane = UiHarness.find(panel.frame, "Pane")
			local cloudTab = UiHarness.find(panel.frame, "Tab_cloud")
			expect(cloudTab.Position.X.Offset + cloudTab.Size.X.Offset <= body.w).toBe(true)
			expect(list.Position.Y.Offset >= cloudTab.Size.Y.Offset).toBe(true)
			expect(list.Size.X.Offset <= pane.Position.X.Offset).toBe(true)
			expect(pane.Position.X.Offset + pane.Size.X.Offset <= body.w + 1e-6).toBe(true)
			for _, row in list:GetChildren() do
				local line = UiHarness.find(row, "Line")
				if line and line.Visible then
					expect(line.Position.Y.Offset + line.Size.Y.Offset <= row.Size.Y.Offset).toBe(true)
				end
			end
			for _, child in pane:GetChildren() do
				if child:IsA("GuiObject") and child.Visible then
					local w = child.Size.X.Scale * pane.Size.X.Offset + child.Size.X.Offset
					local x = child.Position.X.Scale * pane.Size.X.Offset + child.Position.X.Offset
					local left = x - child.AnchorPoint.X * w
					expect(left >= 0).toBe(true)
					expect(left + w <= pane.Size.X.Offset + 1e-6).toBe(true)
				end
			end
		end)
	end
end)
