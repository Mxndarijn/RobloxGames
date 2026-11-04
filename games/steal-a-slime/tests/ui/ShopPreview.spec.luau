--!strict
-- ShopPreview (src/ui/ShopPreview.luau): what the Exclusive shop's stage shows for the selected item.
local Config = require("../../src/shared/Config")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ShopPreview = UiHarness.ui("ShopPreview")
local SHOP = Config.EXCLUSIVE_SHOP

local function detail(kind: string, id: string): any
	return { kind = kind, id = id }
end

describe("ShopPreview.of", function()
	it("turns every Exclusive cloud on the stage with its seat height", function()
		for _, seat in Config.PET_SEATS do
			if seat.unlock.kind == "exclusive" then
				local p = ShopPreview.of(detail("seat", seat.id), Config)
				expect(p).toBeTruthy()
				expect(p.kind).toBe("model")
				expect(p.pose).toBe("seat")
				expect(p.mesh).toBe(seat.mesh)
				expect(p.folder).toBe(ShopPreview.FOLDERS.seat)
				expect(p.seat).toBe(seat.seat)
			end
		end
	end)
	it("shows hats on a slime, and lock styles, Bat skins and base-skin decor on their own", function()
		for _, def in SHOP.hats do
			local p = ShopPreview.of(detail("hat", def.id), Config)
			expect(p.pose).toBe("hat")
			expect(p.mesh).toBe(def.mesh)
			expect(p.folder).toBe(ShopPreview.FOLDERS.hat)
		end
		for _, def in SHOP.lockStyles do
			local p = ShopPreview.of(detail("lockStyle", def.id), Config)
			expect(p.pose).toBe("stopper")
			expect(p.folder).toBeNil() -- no published template: loaded by mesh id
		end
		for _, def in SHOP.batSkins do
			expect(ShopPreview.of(detail("batSkin", def.id), Config).mesh).toBe(def.mesh)
		end
		for _, skin in Config.PLOT_SKINS do
			if skin.exclusive then
				local p = ShopPreview.of(detail("plotSkin", skin.id), Config)
				expect(p.pose).toBe("decor")
				expect(p.mesh).toBe(skin.decor)
			end
		end
	end)
	it("lists a bundle's items as icons, and keeps the icon for bases, trails, passes and boosts", function()
		local sky = ShopPreview.of(detail("product", "SkyBundle"), Config)
		expect(sky.kind).toBe("items")
		expect(#sky.items).toBe(4)
		expect(sky.items[1]).toBe("PetSeat_storm_cloud")
		local starter = ShopPreview.of(detail("product", "StarterBundle"), Config)
		expect(starter.items[1]).toBe("PetSeat_leaf")
		expect(starter.items[2]).toBe("Boost_Code")
		local boutique = ShopPreview.of(detail("product", "BoutiqueBundle"), Config)
		expect(table.find(boutique.items, "PetSeat_magic_carpet") ~= nil).toBe(true)
		expect(table.find(boutique.items, "PlotSkin_fairground") ~= nil).toBe(true)
		expect(ShopPreview.of(detail("plotBase", "rocket"), Config)).toBeNil()
		expect(ShopPreview.of(detail("trail", "sparkle"), Config)).toBeNil()
		expect(ShopPreview.of(detail("pass", "VIP"), Config)).toBeNil()
		expect(ShopPreview.of(detail("product", "SlimeRain"), Config)).toBeNil()
		expect(ShopPreview.of(detail("seat", "nope"), Config)).toBeNil()
		expect(ShopPreview.of(nil, Config)).toBeNil()
	end)
	it("gives every preview a distinct key, so a new item rebuilds the stage", function()
		local a = ShopPreview.of(detail("hat", "party"), Config)
		local b = ShopPreview.of(detail("hat", "bow"), Config)
		expect(a.key ~= b.key).toBe(true)
	end)
end)

describe("ShopPreview framing", function()
	it("seats the rider on the seat height, partly sunk in", function()
		local diameter, centre = ShopPreview.rider({ 3.3, 1.2, 2.4 }, 1.22)
		expect(math.abs(diameter - 3.3 * ShopPreview.STYLE.riderShare) < 1e-9).toBe(true)
		expect(centre > 1.22 and centre < 1.22 + diameter / 2).toBe(true)
	end)
	it("backs the camera off further for a wider or taller model", function()
		local near = ShopPreview.distance(1, 1, 1.5)
		expect(ShopPreview.distance(2, 1, 1.5) > near).toBe(true)
		expect(ShopPreview.distance(1, 4, 1.5) > near).toBe(true)
		expect(ShopPreview.distance(1, 1, 0.5) > near).toBe(true) -- a narrow stage
	end)
end)
