--!strict
-- ItemIcons registry + ItemIconView: every item definition resolves to an icon spec (model, image or
-- a colour + glyph placeholder), no bare-emoji icons, the global live viewport cap, the fallback
-- chain, goal mapping, the ITEM-ICONS-NEEDED.md contract and the Shop rows' icons.
local BatModel = require("../../src/shared/BatModel")
local Config = require("../../src/shared/Config")
local GlyphCheck = require("./GlyphCheck")
local ItemIcons = require("../../src/ui/ItemIcons")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local Remotes = require("../../src/shared/Remotes")
local ShopCatalog = require("../../src/ui/ShopCatalog")
local Shops = require("../../src/shared/Shops")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox") :: any

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local ItemIconView = UiHarness.ui("ItemIconView")
local registry = ItemIcons.build(Config)

-- The same registry without the uploaded pictures: what the UI-drawn fallbacks (ItemIconArt) look like.
local drawnRegistry
do
	local saved = table.clone(ItemIcons.IMAGES)
	table.clear(ItemIcons.IMAGES)
	drawnRegistry = ItemIcons.build(Config)
	for id, image in saved do
		ItemIcons.IMAGES[id] = image
	end
end

-- A registry where three skins are live kit-mesh models (with their pictures as fallback): the model icon path.
local modelRegistry
do
	ItemIcons.MESHES.PlotSkin_mushroom = "plot_skin_mushroom"
	ItemIcons.MESHES.PlotSkin_candy = "plot_skin_candy"
	ItemIcons.MESHES.PlotSkin_crystal = "plot_skin_crystal"
	modelRegistry = ItemIcons.build(Config)
	table.clear(ItemIcons.MESHES)
end

local function find(root: any, name: string): any
	return UiHarness.find(root, name)
end

-- Every item id the game defines, per item table (id -> where it came from).
local function definitions(): { [string]: string }
	local out: { [string]: string } = {}
	for _, item in ShopCatalog.ITEMS do
		out[item.id] = "ShopCatalog.ITEMS"
	end
	for _, u in Config.UPGRADES do
		out[`Upgrade_{u.id}`] = "Config.UPGRADES"
	end
	for code in Config.CODES do
		out[`Code_{code}`] = "Config.CODES"
	end
	for _, g in Config.GOALS do
		out[`Goal_{g.id}`] = "Config.GOALS"
	end
	for _, m in Config.DEX_MILESTONES.species do
		out[`Dex_{m.count}`] = "Config.DEX_MILESTONES.species"
	end
	for _, b in Config.BADGES do
		out[ItemIcons.badge(b.key)] = "Config.BADGES"
	end
	for _, s in Config.PLOT_SKINS do
		out[`PlotSkin_{s.id}`] = "Config.PLOT_SKINS"
	end
	for _, e in Config.ADMIN_EVENTS do
		out[`Event_{e.id}`] = "Config.ADMIN_EVENTS"
	end
	for kind in Config.PET_PASSIVES.KINDS do
		out[`Perk_{kind}`] = "Config.PET_PASSIVES"
	end
	for _, id in { "Lock", "Slap", "Daily", "Rebirth", "Cash", "Gift", "Quest" } do
		out[id] = "gear / misc"
	end
	return out
end

describe("ItemIcons registry", function()
	it("every item definition in every item table resolves to a real spec (not the unknown tile)", function()
		local n = 0
		for id, from in definitions() do
			n += 1
			local spec = registry.get(id)
			expect(`{id} ({from}): {if spec then "ok" else "missing"}`).toBe(`{id} ({from}): ok`)
			expect(spec.id).toBe(id)
			expect(registry.resolve(id)).toBe(spec)
			expect(
				spec.source == "model"
					or spec.source == "image"
					or spec.source == "drawn"
					or spec.source == "placeholder"
			).toBe(true)
		end
		expect(n > 40).toBe(true)
	end)

	it("every spec carries a colour and an allowlisted glyph: never a bare emoji box", function()
		for _, id in registry.order do
			local spec = registry.byId[id]
			expect(#spec.color).toBe(3)
			for _, ch in spec.color do
				expect(ch >= 0 and ch <= 255).toBe(true)
			end
			expect(#spec.glyph > 0).toBe(true)
			expect(`{id}: {table.concat(GlyphCheck.bad(spec.glyph), ",")}`).toBe(`{id}: `)
			expect(#spec.brief > 10).toBe(true)
		end
	end)

	it("the unknown tile still has colour + glyph; resolve never returns nil", function()
		for _, bad in { "nope", 5, false } do
			local spec = registry.resolve(bad)
			expect(spec.source).toBe("placeholder")
			expect(#spec.glyph > 0 and #spec.color == 3).toBe(true)
		end
		expect(registry.resolve(nil).glyph).toBe("?")
	end)

	it("covers every id the other surfaces use: shop upgrades, goals, badges", function()
		for _, u in Config.UPGRADES do
			expect(registry.get(`Upgrade_{u.id}`) ~= nil).toBe(true)
		end
		for _, id in { "FillPads", "AllPads", "Daily", "BestTier", "Rebirth", "Dex", "SpeedCoil", "Catch" } do
			expect(registry.byId[ItemIcons.forGoal(registry, id)] ~= nil).toBe(true)
		end
		expect(ItemIcons.forGoal(registry, "Catch")).toBe("Goal_Catch")
		expect(ItemIcons.forGoal(registry, "Daily")).toBe("Daily")
		expect(ItemIcons.forGoal(registry, "whatever")).toBe("Quest")
	end)

	it("plot skins show their tower pictures; a kit-mesh item is a model; drawn without pictures", function()
		expect(registry.byId.PlotSkin_candy.source).toBe("image")
		expect(modelRegistry.byId.PlotSkin_candy.model.kind).toBe("mesh")
		expect(registry.byId.PlotSkin_classic.source).toBe("image")
		expect(registry.byId.SpeedCoil.source).toBe("image")
		expect(drawnRegistry.byId.PlotSkin_classic.source).toBe("drawn")
		expect(drawnRegistry.byId.SpeedCoil.source).toBe("drawn")
	end)
end)

describe("drawn icons (every group)", function()
	local ItemIconArt = UiHarness.ui("ItemIconArt")

	it("no item resolves to the placeholder unless listed FOR ARCHER", function()
		for _, id in drawnRegistry.order do
			local spec = drawnRegistry.byId[id]
			if table.find(ItemIcons.FOR_ARCHER, id) == nil then
				expect(`{id}: {spec.source ~= "placeholder"}`).toBe(`{id}: true`)
				if spec.source == "drawn" then
					expect(`{id}: {ItemIconArt.has(id)}`).toBe(`{id}: true`)
				end
			end
		end
		expect(#ItemIcons.needsArt(drawnRegistry)).toBe(#ItemIcons.FOR_ARCHER)
		local doc = fs.readFile("ITEM-ICONS-NEEDED.md")
		expect(string.find(doc, "## FOR ARCHER", 1, true) ~= nil).toBe(true)
		expect(string.find(doc, "## FOR ARCHER", 1, true) < string.find(doc, "| id |", 1, true)).toBe(true)
	end)

	it("goals, Dex trophies, badges and plot skins all have recipes (drawn when there is no picture)", function()
		local n = 0
		for _, id in drawnRegistry.order do
			local spec = drawnRegistry.byId[id]
			if spec.group == "goal" or spec.group == "badge" or spec.group == "skin" then
				n += 1
				expect(`{id}: {ItemIconArt.has(id)}`).toBe(`{id}: true`)
			end
		end
		expect(n >= 25).toBe(true)
		-- Without its picture a skin shows its drawn scene, not the tile.
		local icon = ItemIconView.new({ Id = "PlotSkin_candy", Size = 36, Parent = UiHarness.root() }, drawnRegistry)
		icon.setActive(true)
		expect(icon.source).toBe("drawn")
		expect(icon.art.Visible).toBe(true)
		icon.destroy()
	end)

	it("every recipe builds static frames only (no viewport, outside the live cap), glyphs on the allowlist", function()
		ItemIconView.resetLive()
		for _, id in drawnRegistry.order do
			local spec = drawnRegistry.byId[id]
			if spec.source ~= "drawn" then
				continue
			end
			local icon = ItemIconView.new({ Id = id, Size = 36, Parent = UiHarness.root() }, drawnRegistry)
			icon.setActive(true)
			expect(icon.source).toBe("drawn")
			expect(icon.art.Visible).toBe(true)
			expect(icon.glyph.Visible).toBe(false)
			expect(icon.viewport.Visible).toBe(false)
			expect(#icon.art:GetChildren() >= 4).toBe(true)
			for _, d in icon.art:GetDescendants() do
				expect(d.ClassName ~= "ViewportFrame" and d.ClassName ~= "MeshPart" and d.ClassName ~= "ImageLabel").toBe(
					true
				)
				if d.ClassName == "TextLabel" then
					expect(#GlyphCheck.bad(d.Text)).toBe(0)
				end
			end
			icon.destroy()
		end
		expect(ItemIconView.liveCount()).toBe(0)
	end)

	it("an uploaded image still wins over the drawn icon", function()
		local was_Cash = ItemIcons.IMAGES.Cash
		ItemIcons.IMAGES.Cash = 555
		local withImage = ItemIcons.build(Config)
		ItemIcons.IMAGES.Cash = was_Cash
		local icon = ItemIconView.new({ Id = "Cash", Size = 36, Parent = UiHarness.root() }, withImage)
		expect(withImage.byId.Cash.source).toBe("image")
		expect(icon.source).toBe("image")
		expect(icon.art.Visible).toBe(false)
		icon.destroy()
	end)
end)

describe("uploaded item icon images", function()
	it("every id of a drawn group has a positive integer image", function()
		local n = 0
		for _, id in registry.order do
			local spec = registry.byId[id]
			if ItemIcons.DRAWN_GROUPS[spec.group] and table.find(ItemIcons.AWAITING_UPLOAD, id) == nil then
				n += 1
				local image = ItemIcons.IMAGES[id]
				expect(`{id}: {type(image) == "number" and image > 0 and image == math.floor(image)}`).toBe(
					`{id}: true`
				)
			end
		end
		expect(n).toBe(49)
	end)
	it("ids awaiting an upload are real drawn-group ids with a UI-drawn scene", function()
		local ItemIconArt = UiHarness.ui("ItemIconArt")
		for _, id in ItemIcons.AWAITING_UPLOAD do
			local spec = registry.byId[id]
			expect(`{id}: {spec ~= nil and ItemIcons.DRAWN_GROUPS[spec.group] == true}`).toBe(`{id}: true`)
			expect(`{id}: {spec and spec.source}`).toBe(`{id}: drawn`)
			expect(`{id}: {ItemIconArt.has(id)}`).toBe(`{id}: true`)
		end
	end)

	it("IMAGES holds no stale ids and no duplicate asset ids", function()
		local seen: { [number]: string } = {}
		-- ids the shop UI looks up through shopIconId (Consumable_/Pvp_) may predate their registry entries
		local shopIds: { [string]: boolean } = {}
		for _, shop in Shops.SHOPS do
			for _, item in shop.items do
				shopIds[ItemIcons.shopIconId(item)] = true
			end
		end
		-- held tools wired as their own Tool (ItemIcons.HELD_TOOLS), not a shop or registry row
		local heldToolIds: { [string]: boolean } = {}
		for _, id in ItemIcons.HELD_TOOLS do
			heldToolIds[id] = true
		end
		expect(`Bat icon: {BatModel.ICON_ID}`).toBe(
			`Bat icon: rbxassetid://{ItemIcons.IMAGES[ItemIcons.HELD_TOOLS.Bat]}`
		)
		for id, image in ItemIcons.IMAGES do
			expect(`{id}: {registry.byId[id] ~= nil or shopIds[id] == true or heldToolIds[id] == true}`).toBe(
				`{id}: true`
			)
			expect(`{id}: {seen[image] == nil}`).toBe(`{id}: true`)
			seen[image] = id
		end
	end)

	it("image specs resolve to source image; kit-mesh items stay models with the image as fallback", function()
		for _, id in registry.order do
			local spec = registry.byId[id]
			if ItemIcons.DRAWN_GROUPS[spec.group] and table.find(ItemIcons.AWAITING_UPLOAD, id) == nil then
				expect(spec.image).toBe(ItemIcons.IMAGES[id])
				expect(`{id}: {spec.source}`).toBe(`{id}: {if spec.model then "model" else "image"}`)
			end
		end
		for _, id in { "PlotSkin_mushroom", "PlotSkin_candy", "PlotSkin_crystal" } do
			expect(modelRegistry.byId[id].source).toBe("model")
			expect(modelRegistry.byId[id].image ~= nil).toBe(true)
		end
	end)

	it("ItemIconView shows the picture (Fit, transparent) with no tile behind it, and no drawn scene", function()
		ItemIconView.resetLive()
		for _, id in { "Lock", "Dex_50", "Badge_Millionaire", "PlotSkin_classic", "Code_WELCOME" } do
			local icon = ItemIconView.new({ Id = id, Size = 36, Parent = UiHarness.root() }, registry)
			icon.setActive(true)
			expect(icon.source).toBe("image")
			local picture = find(icon.instance, "Picture")
			expect(picture.Visible).toBe(true)
			expect(picture.Image).toBe(`rbxassetid://{ItemIcons.IMAGES[id]}`)
			expect(picture.ScaleType).toBe(roblox.Enum.ScaleType.Fit)
			expect(picture.BackgroundTransparency).toBe(1)
			expect(icon.art.Visible).toBe(false)
			expect(icon.glyph.Visible).toBe(false)
			expect(icon.tile.BackgroundTransparency).toBe(1)
			expect(icon.tile:FindFirstChildOfClass("UIStroke").Transparency).toBe(1)
			icon.destroy()
		end
	end)

	it("a kit-mesh item shows its image (not the drawn scene) while the mesh is missing", function()
		local icon = ItemIconView.new({ Id = "PlotSkin_mushroom", Size = 36, Parent = UiHarness.root() }, modelRegistry)
		icon.setActive(true)
		expect(icon.source).toBe("image")
		expect(icon.art.Visible).toBe(false)
		expect(find(icon.instance, "Picture").Visible).toBe(true)
		icon.destroy()
	end)
end)

describe("ItemIcons.of", function()
	it("builds once per ctx", function()
		local ctx: any = { Config = Config }
		expect(ItemIcons.of(ctx)).toBe(ItemIcons.of(ctx))
	end)
end)

describe("ItemIconView", function()
	it("draws the placeholder tile: gradient in the item colour, stroke, bold glyph", function()
		for _, id in registry.order do
			local icon = ItemIconView.new({ Id = id, Size = 40, Parent = UiHarness.root() }, registry)
			local tile = find(icon.instance, "Tile")
			expect(tile ~= nil).toBe(true)
			expect(#tile:GetChildren() >= 3).toBe(true) -- corner, gradient, stroke (+ glyph)
			local classes = {}
			for _, child in tile:GetChildren() do
				classes[child.ClassName] = true
			end
			expect(classes.UIGradient and classes.UIStroke and classes.UICorner and classes.TextLabel).toBe(true)
			local glyph = find(icon.instance, "Glyph")
			expect(glyph.Text).toBe(registry.byId[id].glyph)
			expect(glyph.Font).toBe(UiHarness.ui("Widgets").Theme.Font)
			expect(icon.instance:GetAttribute("ItemId")).toBe(id)
			icon.destroy()
		end
	end)

	it("live model viewports are lazy and capped across all icons; extras keep the tile", function()
		ItemIconView.resetLive()
		local mounts = 0
		local saved = ItemIconView.builders.mesh
		ItemIconView.builders.mesh = function()
			mounts += 1
			return true
		end
		local icons = {}
		for i = 1, ItemIconView.MAX_LIVE + 10 do
			icons[i] = ItemIconView.new({ Id = "PlotSkin_candy", Size = 36, Parent = UiHarness.root() }, modelRegistry)
		end
		expect(mounts).toBe(0) -- lazy: nothing renders until the owner says the icon is on screen
		expect(ItemIconView.liveCount()).toBe(0)
		for _, icon in icons do
			icon.setActive(true)
		end
		expect(ItemIconView.liveCount()).toBe(ItemIconView.MAX_LIVE)
		expect(mounts).toBe(ItemIconView.MAX_LIVE)
		expect(icons[1].source).toBe("model")
		expect(icons[ItemIconView.MAX_LIVE + 1].source).toBe("image")
		expect(find(icons[ItemIconView.MAX_LIVE + 1].instance, "Picture").Visible).toBe(true)
		-- Hiding releases (recycle): the waiting icons take the freed slots on their next activation.
		icons[1].setActive(false)
		expect(ItemIconView.liveCount()).toBe(ItemIconView.MAX_LIVE - 1)
		icons[ItemIconView.MAX_LIVE + 1].setActive(false)
		icons[ItemIconView.MAX_LIVE + 1].setActive(true)
		expect(ItemIconView.liveCount()).toBe(ItemIconView.MAX_LIVE)
		expect(icons[ItemIconView.MAX_LIVE + 1].source).toBe("model")
		for _, icon in icons do
			icon.destroy()
		end
		expect(ItemIconView.liveCount()).toBe(0)
		ItemIconView.builders.mesh = saved
	end)

	it("fallback chain: model fails -> uploaded image", function()
		ItemIconView.resetLive()
		local saved = ItemIconView.builders.mesh
		ItemIconView.builders.mesh = function()
			return false
		end
		local plain = ItemIconView.new({ Id = "PlotSkin_candy", Parent = UiHarness.root() }, modelRegistry)
		plain.setActive(true)
		expect(plain.source).toBe("image")
		expect(ItemIconView.liveCount()).toBe(0)

		local was_PlotSkin_candy = ItemIcons.IMAGES.PlotSkin_candy
		ItemIcons.IMAGES.PlotSkin_candy = 12345
		local withImage = ItemIcons.build(Config)
		expect(withImage.byId.PlotSkin_candy.image).toBe(12345)
		local icon = ItemIconView.new({ Id = "PlotSkin_candy", Parent = UiHarness.root() }, withImage)
		icon.setActive(true)
		expect(icon.source).toBe("image")
		expect(find(icon.instance, "Picture").Visible).toBe(true)
		expect(find(icon.instance, "Picture").Image).toBe("rbxassetid://12345")
		ItemIcons.IMAGES.PlotSkin_candy = was_PlotSkin_candy

		-- An image-only item (no model) uses the picture without any viewport.
		local was_SpeedCoil = ItemIcons.IMAGES.SpeedCoil
		ItemIcons.IMAGES.SpeedCoil = 777
		local coil = ItemIcons.build(Config)
		expect(coil.byId.SpeedCoil.source).toBe("image")
		ItemIcons.IMAGES.SpeedCoil = was_SpeedCoil
		ItemIconView.builders.mesh = saved
	end)

	it("a mesh builder with no uploaded mesh falls back", function()
		ItemIconView.resetLive()
		local builder = ItemIconView.meshBuilder({
			meshId = function()
				return nil
			end,
		}, {})
		expect(builder(UiHarness.root(), { model = { kind = "mesh", mesh = "plot_skin_candy" } })).toBe(false)
		local icon = ItemIconView.new({ Id = "PlotSkin_candy", Parent = UiHarness.root() }, drawnRegistry)
		icon.setActive(true)
		expect(icon.source).toBe("drawn") -- default mesh builder: not wired under Lune, so the diorama shows
	end)

	it("a changed id releases the old viewport", function()
		ItemIconView.resetLive()
		local saved = ItemIconView.builders.mesh
		ItemIconView.builders.mesh = function()
			return true
		end
		local icon = ItemIconView.new({ Id = "PlotSkin_candy", Parent = UiHarness.root() }, modelRegistry)
		icon.setActive(true)
		expect(ItemIconView.liveCount()).toBe(1)
		icon.set("SpeedCoil")
		expect(ItemIconView.liveCount()).toBe(0)
		icon.destroy()
		ItemIconView.builders.mesh = saved
	end)
end)

describe("item icons on the surfaces", function()
	local function ctx(): any
		return {
			Config = Config,
			actions = Remotes.ACTIONS,
			send = function() end,
			serverNow = function()
				return 0
			end,
		}
	end

	it("Codes, Goals and the Daily popup draw item icons", function()
		local codes = UiHarness.ui("Panels/Codes").new(UiHarness.root(), ctx())
		expect(find(codes.frame, "BoostIcon"):GetAttribute("ItemId")).toBe("Boost_Code")
		local daily = UiHarness.ui("Panels/DailyPopup").new(UiHarness.root(), ctx())
		expect(find(daily.frame, "Day1Icon"):GetAttribute("ItemId")).toBe("Cash")
		local goals = UiHarness.ui("Panels/Goals").new(UiHarness.root(), ctx())
		goals.update({ slimes = {}, padsUnlocked = 4, padsMax = 8, cash = 0 })
		local found = 0
		for _, inst in UiHarness.descendants(goals.frame) do
			if inst.Name == "Icon" and inst:GetAttribute("ItemId") then
				found += 1
			end
		end
		expect(found > 0).toBe(true)
	end)
end)

describe("item icons: server ids, Dex skins, gear", function()
	local function ctx(): any
		return {
			Config = Config,
			actions = Remotes.ACTIONS,
			send = function() end,
			serverNow = function()
				return 0
			end,
		}
	end

	it("every Plot skins row draws its PlotSkin_ item icon", function()
		local dex = UiHarness.ui("Panels/Skins").new(UiHarness.root(), ctx())
		dex.setOpen(true)
		dex.update({
			dex = {},
			dexTotal = 10,
			plotSkins = {
				{ id = "classic", name = "Classic", unlocked = true, equipped = true, owned = 0, needed = 0 },
				{ id = "candy", name = "Candy", unlocked = false, equipped = false, owned = 1, needed = 5 },
			},
		})
		local seen = {}
		for _, inst in UiHarness.descendants(dex.frame) do
			if inst.Name == "SkinIcon" then
				seen[inst:GetAttribute("ItemId")] = true
			end
		end
		expect(seen.PlotSkin_classic and seen.PlotSkin_candy).toBe(true)
	end)

	it("every server Notify that names an item passes its id, and each id resolves in the registry", function()
		local ids = {}
		for _, file in { "Actions", "MysteryEgg", "Rebirth", "StealService" } do
			local src = fs.readFile(`src/server/{file}.luau`)
			for id in string.gmatch(src, '"(%a+)"%s*%)') do
				if registry.byId[id] then
					ids[id] = true
				end
			end
		end
		for _, id in { "Daily", "Gift", "SpeedCoil", "MysteryEgg", "Rebirth", "Lock", "Slap" } do
			expect(`{id}: {ids[id] == true}`).toBe(`{id}: true`)
		end
	end)
end)

describe("ITEM-ICONS-NEEDED.md", function()
	it("lists every item without a 3D model or image, and nothing that has one", function()
		local doc = fs.readFile("ITEM-ICONS-NEEDED.md")
		local needed = ItemIcons.needsArt(registry)
		expect(#needed).toBe(#ItemIcons.FOR_ARCHER)
		for _, spec in needed do
			expect(string.find(doc, string.format("| `%s` |", spec.id), 1, true) ~= nil).toBe(true)
		end
		for _, id in registry.order do
			local spec = registry.byId[id]
			if spec.source ~= "placeholder" then
				expect(string.find(doc, string.format("| `%s` |", id), 1, true)).toBe(nil)
			end
		end
		expect(string.find(doc, "ItemIcons.IMAGES", 1, true) ~= nil).toBe(true)
	end)
end)

describe("item icon layout (LayoutAssert at the 5 gate viewports)", function()
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(`Goals rows keep their text fitting beside the icon at {vp.name}`, function()
			local screen = Layout.screen(vp.w, vp.h)
			local check = LayoutAssert.new(vp.name, screen)
			local panel = Layout.panelFor(screen, "Goals")
			-- Panels/Goals ROW: pad 10, ICON 50, gap 12; the reward top-right, "Next" right of the meta line.
			local rowW = panel.w - Layout.PANEL_CHROME.pad * 2 - 10
			local textW = rowW - (10 + 50 + 12) - 10
			local nextW = math.ceil(Layout.lineWidth("Next: $1.0B", 12)) + 2 + 6
			local rewardW = math.ceil(Layout.lineWidth("+$12.5K", 15, true)) + 2 + 8
			for _, g in Config.GOALS do
				check.text({
					name = `Goal {g.id} meta`,
					text = "999.9K/1.0M · Stage 5 of 5",
					size = 12,
					w = textW - nextW,
					h = 14,
				})
			end
			check.text({
				name = "Goal title",
				text = "Lock your base 100 times",
				size = 17,
				bold = true,
				w = textW - rewardW,
				h = 20,
			})
			expect(check.report()).toBe("")
		end)
	end
end)
