--!strict
-- The Skins menu's Pet tab: Auto (the favourite slime, as before), then every SlimeDex species that has a kit, in
-- Dex order; found ones can be equipped with SetPetSpecies (Auto sends ""), the rest are grey and say to find them
-- first. Only the rows near the scroll window show a live preview.
local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local KitRequest = require("../../src/shared/KitRequest")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local PetSpeciesView = require("../../src/ui/PetSpeciesView")
local PlayerData = require("../../src/shared/PlayerData")
local PlotSkins = require("../../src/shared/PlotSkins")
local Remotes = require("../../src/shared/Remotes")
local SlimeDex = require("../../src/ui/SlimeDex")
local SlimeLooks = require("../../src/shared/SlimeLooks")
local SlimeRoster = require("../../src/shared/SlimeRoster")
local SpeciesDex = require("../../src/shared/SpeciesDex")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local SlimePreview = UiHarness.ui("SlimePreview")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local UDim2 = (require("@lune/roblox") :: any).UDim2

local FOUND = { SpeciesDex.ENTRIES[1].id, SpeciesDex.ENTRIES[2].id, SpeciesDex.ENTRIES[3].id }

local function cards(found: { string }): { SlimeDex.Card }
	return SlimeDex.cards(Fixtures.dex(found), Config, function(id: string)
		local entry = SlimeRoster.get(id)
		local look = SlimeLooks.get(id)
		return if entry then entry.name else nil, if look then look.color else nil, nil
	end)
end

local function ctx(requests: { any }?): any
	return {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		SlimeRoster = SlimeRoster,
		SlimeLooks = SlimeLooks,
		PlotSkins = PlotSkins,
		KitRequest = KitRequest,
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

local function petState(petSpecies: string?): any
	return {
		dex = Fixtures.dex(FOUND),
		plotSkins = PlotSkins.view(PlayerData.new()),
		petSpecies = petSpecies,
	}
end

local function openPet(w: number, h: number, state: any, requests: { any }?): (any, Layout.Rect)
	local panel = UiHarness.ui("Panels/Skins").new(UiHarness.root(), ctx(requests))
	local raw = Layout.panelFor(Layout.screen(w, h), "Skins")
	local r = Layout.rect(math.floor(raw.x), math.floor(raw.y), math.floor(raw.w), math.floor(raw.h))
	panel.frame.Size = UDim2.fromOffset(r.w, r.h)
	panel.layout(r)
	panel.update(state)
	panel.setOpen(true)
	panel.frame.Visible = true
	panel.setTab("pet")
	return panel, r
end

describe("PetSpeciesView", function()
	it("Auto first, then one row per Dex card with a kit; Auto is equipped without a pick", function()
		local rows = PetSpeciesView.rows(cards(FOUND), nil)
		expect(rows[1].key).toBe("pet:auto")
		expect(rows[1].id).toBe("")
		expect(rows[1].state).toBe("equipped")
		expect(#rows).toBe(1 + #cards(FOUND))
		expect(rows[2].id).toBe(FOUND[1])
		expect(rows[2].state).toBe("unlocked")
		local last = rows[#rows]
		expect(last.found).toBe(false)
		expect(last.state).toBe("locked")
		expect(PetSpeciesView.summary(rows)).toBe(`3/{#rows - 1} found`)
	end)
	it("lists the found species before the unfound ones", function()
		local all = cards({ "octo" }) -- one found species, deep in the Dex
		local rows = PetSpeciesView.rows(all, nil)
		expect(rows[2].id).toBe("octo")
		local seenLocked = false
		for i = 2, #rows do
			if rows[i].found then
				expect(seenLocked).toBe(false)
			else
				seenLocked = true
			end
		end
	end)
	it("species without a kit are left out", function()
		local rows = PetSpeciesView.rows(cards(FOUND), nil, function(id: string)
			return id == FOUND[2]
		end)
		expect(#rows).toBe(2)
		expect(rows[2].id).toBe(FOUND[2])
	end)
	it("the picked species is equipped and shown first; an empty pick is Auto", function()
		local rows = PetSpeciesView.rows(cards(FOUND), FOUND[2])
		expect(rows[1].state).toBe("unlocked")
		expect(rows[3].state).toBe("equipped")
		expect(PetSpeciesView.firstSelected(rows)).toBe(FOUND[2])
		expect(PetSpeciesView.rows(cards(FOUND), "")[1].state).toBe("equipped")
	end)
	it("the pane says Equip, Equipped, or to find the slime first", function()
		local rows = PetSpeciesView.rows(cards(FOUND), FOUND[1])
		expect((PetSpeciesView.detail(rows, FOUND[1]) :: any).action).toBe("Equipped")
		expect((PetSpeciesView.detail(rows, FOUND[2]) :: any).action).toBe("Equip")
		expect((PetSpeciesView.detail(rows, "") :: any).action).toBe("Equip")
		expect((PetSpeciesView.detail(rows, "") :: any).line).toBe(PetSpeciesView.AUTO_LINE)
		local locked = PetSpeciesView.detail(rows, rows[#rows].id) :: any
		expect(locked.action).toBe(PetSpeciesView.LOCKED_ACTION)
		expect(locked.state).toBe("locked")
		expect(PetSpeciesView.detail(rows, "nope")).toBeNil()
	end)
end)

describe("Skins menu Pet tab", function()
	it("has four tabs and still opens on Base", function()
		local panel = openPet(1920, 1080, petState(nil))
		expect(UiHarness.find(panel.frame, "Tab_pet") ~= nil).toBe(true)
		panel.setOpen(false)
		panel.setOpen(true)
		expect(panel.tab()).toBe("base")
	end)
	it("lists Auto and the species, with the found count in the band", function()
		local panel = openPet(1920, 1080, petState(nil))
		expect(panel.tab()).toBe("pet")
		local list = UiHarness.find(panel.frame, "PetList")
		expect(list.Visible).toBe(true)
		expect(UiHarness.find(panel.frame, "SeatList").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "List").Visible).toBe(false)
		local auto = UiHarness.find(list, "pet:auto")
		expect(UiHarness.find(auto, "State").Text).toBe("Equipped")
		expect(UiHarness.find(auto, "Glyph").Text).toBe("\u{2728}")
		expect(UiHarness.find(list, `pet:{FOUND[1]}`) ~= nil).toBe(true)
		local species = 0
		for _, child in list:GetChildren() do
			if string.sub(child.Name, 1, 4) == "pet:" and child.Name ~= "pet:auto" then
				species += 1
			end
		end
		expect(UiHarness.find(panel.frame, "Summary").Text).toBe(`3/{species} found`)
		expect(UiHarness.find(UiHarness.find(panel.frame, "Pane"), "BigPreview").Visible).toBe(true)
		expect(UiHarness.find(UiHarness.find(panel.frame, "Pane"), "BigIcon").Visible).toBe(false)
	end)
	it("Equip on a found species sends SetPetSpecies(id); on Auto it sends an empty id", function()
		local requests = {}
		local panel = openPet(1920, 1080, petState(FOUND[1]), requests)
		panel.select(FOUND[2])
		local pane = UiHarness.find(panel.frame, "Pane")
		local equip = UiHarness.find(pane, "Equip")
		expect(equip.Visible).toBe(true)
		UiHarness.fire(equip, "Activated")
		panel.select("")
		UiHarness.fire(UiHarness.find(pane, "Equip"), "Activated")
		expect(requests).toEqual({ { "SetPetSpecies", FOUND[2] }, { "SetPetSpecies", "" } })
	end)
	it("a species not found yet has no Equip, only a well saying to find it", function()
		local requests = {}
		local panel = openPet(1920, 1080, petState(nil), requests)
		local rows = PetSpeciesView.rows(cards(FOUND), nil, function(id: string)
			return KitRequest.kitOf(id) ~= nil
		end)
		local lockedId = rows[#rows].id
		UiHarness.fire(UiHarness.find(UiHarness.find(panel.frame, "PetList"), `pet:{lockedId}`), "Activated")
		expect(panel.selected()).toBe(lockedId)
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "Equip").Visible).toBe(false)
		local well = UiHarness.find(pane, "Well")
		expect(well.Visible).toBe(true)
		expect(well.Text).toBe(PetSpeciesView.LOCKED_ACTION)
		expect(#requests).toBe(0)
	end)
	it("back on Base the skin pane comes back and the pet previews are emptied", function()
		local panel = openPet(1920, 1080, petState(nil))
		panel.setTab("base")
		local pane = UiHarness.find(panel.frame, "Pane")
		expect(UiHarness.find(pane, "BigIcon").Visible).toBe(true)
		expect(UiHarness.find(pane, "BigPreview").Visible).toBe(false)
		expect(UiHarness.find(panel.frame, "PetList").Visible).toBe(false)
		for _, row in UiHarness.find(panel.frame, "PetList"):GetChildren() do
			local preview = UiHarness.find(row, "Preview")
			if preview then
				expect(preview:GetAttribute("Look")).toBeNil()
			end
		end
	end)
	it(`mounts at most {SlimePreview.MAX_LIVE} previews`, function()
		local panel = openPet(1920, 1080, petState(nil))
		local live = 0
		for _, inst in panel.frame:GetDescendants() do
			if inst.Name == "Preview" and inst:GetAttribute("Look") ~= nil then
				live += 1
			end
		end
		expect(live <= SlimePreview.MAX_LIVE).toBe(true)
	end)
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(`{vp.name}: four tabs, pet rows and the pet pane stay inside the body`, function()
			local panel, r = openPet(vp.w, vp.h, petState(FOUND[1]))
			panel.select(FOUND[2])
			local body = Layout.panelBody(r)
			local list = UiHarness.find(panel.frame, "PetList")
			local pane = UiHarness.find(panel.frame, "Pane")
			local petTab = UiHarness.find(panel.frame, "Tab_pet")
			expect(petTab.Position.X.Offset + petTab.Size.X.Offset <= body.w).toBe(true)
			expect(petTab.Size.Y.Offset >= Layout.MIN_TOUCH_DESIGN).toBe(true)
			expect(list.Position.Y.Offset >= petTab.Size.Y.Offset).toBe(true)
			expect(list.Size.X.Offset <= pane.Position.X.Offset).toBe(true)
			expect(pane.Position.X.Offset + pane.Size.X.Offset <= body.w + 1e-6).toBe(true)
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
