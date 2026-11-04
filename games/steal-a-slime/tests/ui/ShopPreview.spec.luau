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
	it("lists a bundle's items as icons, and keeps the icon for passes and boosts", function()
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

describe("ShopPreview bases", function()
	local MeshAssets = require("../../src/shared/MeshAssets")
	it("builds every Exclusive base whole, with all floors", function()
		for _, base in Config.PLOT_BASES do
			if base.exclusive then
				local p = ShopPreview.of(detail("plotBase", base.id), Config)
				expect(p.kind).toBe("base")
				expect(p.base).toBe(base.id)
				expect(p.floors).toBe(#Config.BASE_FLOORS)
				local pieces = ShopPreview.basePieces(base.id, p.floors)
				expect(`{base.id}: {#pieces >= 8}`).toBe(`{base.id}: true`)
				local top = 0
				for _, piece in pieces do
					expect(MeshAssets.meshId(piece.mesh) ~= nil).toBe(true) -- only uploaded meshes
					top = math.max(top, piece.pos[2] + piece.size[2] / 2)
				end
				-- four floors stand higher than one
				local one = 0
				for _, piece in ShopPreview.basePieces(base.id, 1) do
					one = math.max(one, piece.pos[2] + piece.size[2] / 2)
				end
				expect(`{base.id}: {top > one}`).toBe(`{base.id}: true`)
			end
		end
		expect(ShopPreview.of(detail("plotBase", "jar"), Config)).toBeNil() -- free, never in the shop
		expect(ShopPreview.of(detail("plotBase", "nope"), Config)).toBeNil()
	end)
	it("shows a roof piece only on the top floor, and leaves the shut door out", function()
		for _, piece in ShopPreview.basePieces("factory", 4) do
			if piece.mesh == "factory_roof" then
				expect(piece.pos[2] > 40).toBe(true)
			end
			expect(piece.mesh ~= "factory_shutter_shut").toBe(true)
		end
	end)
	it("tints role pieces in the classic skin and keeps glass see-through", function()
		local tinted, glass = 0, 0
		for _, piece in ShopPreview.basePieces("factory", 4) do
			if piece.rgb then
				tinted += 1
			end
			if piece.glass then
				glass += 1
				expect(piece.rgb).toBeNil()
			end
		end
		expect(tinted > 0).toBe(true)
		expect(glass > 0).toBe(true)
	end)
end)

describe("ShopPreview trails", function()
	local CarryTrail = require("../../src/visuals/shared/CarryTrail")
	local TRAIL = ShopPreview.TRAIL
	it("previews every trail", function()
		for _, def in SHOP.trails do
			local p = ShopPreview.of(detail("trail", def.id), Config)
			expect(p.kind).toBe("trail")
			expect(p.trail).toBe(def.id)
		end
		expect(ShopPreview.of(detail("trail", "nope"), Config)).toBeNil()
	end)
	it("streams the ribbon behind the runner in the trail's colours, with live particles", function()
		for _, def in SHOP.trails do
			local look = CarryTrail.look(def :: any)
			for _, t in { 0.4, 2.3, 7.9 } do
				local f = ShopPreview.trailFrame(look, t)
				expect(#f.ribbon).toBe(TRAIL.segments)
				-- the ribbon starts at the runner
				expect(math.abs(f.ribbon[1].a[1] - f.slime[1]) < 1e-6).toBe(true)
				expect(math.abs(f.ribbon[1].a[3] - f.slime[3]) < 1e-6).toBe(true)
				-- the newest piece wears the trail's first colour (it takes the colour one step along)
				expect(math.abs(f.ribbon[1].rgb[1] - look.trail.colors[1].rgb[1]) < 24).toBe(true)
				-- never more particles than the stage keeps cards for
				expect(#f.particles <= math.ceil(CarryTrail.alive(look.particles)) + 2).toBe(true)
				for _, part in f.particles do
					expect(part.size > 0).toBe(true)
					-- stays near the circle, inside what the camera frames
					local r = math.sqrt(part.pos[1] ^ 2 + part.pos[3] ^ 2)
					expect(r < TRAIL.radius + TRAIL.slime + TRAIL.camera + 1).toBe(true)
				end
			end
			expect(#ShopPreview.trailFrame(look, TRAIL.restTime).particles > 0).toBe(true) -- the still frame shows some
		end
	end)
	it("draws the same frame for the same time", function()
		local look = CarryTrail.look(SHOP.trails[1] :: any)
		local a = ShopPreview.trailFrame(look, 3.21)
		local b = ShopPreview.trailFrame(look, 3.21)
		expect(#a.particles).toBe(#b.particles)
		expect(a.particles[1].pos[1]).toBe(b.particles[1].pos[1])
	end)
end)

describe("ShopPreview framing", function()
	it("seats the rider on the seat height, partly sunk in", function()
		local diameter, centre = ShopPreview.rider({ 3.3, 1.2, 2.4 }, 1.22)
		expect(math.abs(diameter - 3.3 * ShopPreview.STYLE.riderShare) < 1e-9).toBe(true)
		expect(centre > 1.22 and centre < 1.22 + diameter / 2).toBe(true)
	end)
	it("sizes a hat to hatShare of the slime and sinks it into the slime's top", function()
		local scale, up = ShopPreview.hat(2, { 1, 2, 1 })
		expect(math.abs(scale - 2 * ShopPreview.STYLE.hatShare) < 1e-9).toBe(true)
		local hatH = 2 * scale
		expect(math.abs(up - (1 - 2 * ShopPreview.STYLE.hatSink + hatH / 2)) < 1e-9).toBe(true)
	end)
	it("backs the camera off further for a wider or taller model", function()
		local near = ShopPreview.distance(1, 1, 1.5)
		expect(ShopPreview.distance(2, 1, 1.5) > near).toBe(true)
		expect(ShopPreview.distance(1, 4, 1.5) > near).toBe(true)
		expect(ShopPreview.distance(1, 1, 0.5) > near).toBe(true) -- a narrow stage
	end)
end)
