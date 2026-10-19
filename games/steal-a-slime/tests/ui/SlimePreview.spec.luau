--!strict
-- SlimePreview (src/ui/SlimePreview.luau) under tests/ui/UiHarness.luau: the
-- Ball + eyes builder, locked silhouettes, viewport mount / recycle, and the
-- SlimeDex panel's ViewportFrame previews at every gate viewport.
local roblox = require("@lune/roblox") :: any

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Fixtures = require("../Fixtures")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local Remotes = require("../../src/shared/Remotes")
local SlimeLooks = require("../../src/shared/SlimeLooks")
local SlimeRoster = require("../../src/shared/SlimeRoster")
local SpeciesDex = require("../../src/shared/SpeciesDex")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local Color3, UDim2, Enum, Vector2 = roblox.Color3, roblox.UDim2, roblox.Enum, roblox.Vector2

local SlimePreview = UiHarness.ui("SlimePreview")
local PARTS = { "Body", "EyeWhiteL", "EyeWhiteR", "PupilL", "PupilR" }
local DEX = Fixtures.dex({ "gummy", "mochi", "bumble" })

local function rgb(c: { number }): any
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function ctx(): any
	return {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		SlimeRoster = SlimeRoster,
		SlimeLooks = SlimeLooks,
		actions = Remotes.ACTIONS,
		send = function() end,
		serverNow = function()
			return 0
		end,
		playerName = function()
			return "Tester"
		end,
		toast = function() end,
	}
end

describe("SlimePreview.build", function()
	it("builds a tinted Ball body with white eyes and dark pupils", function()
		local model = SlimePreview.build({ 255, 120, 40 })
		expect(model.ClassName).toBe("Model")
		expect(#model:GetChildren()).toBe(#PARTS)
		for _, name in PARTS do
			local part = model:FindFirstChild(name)
			expect(part ~= nil).toBe(true)
			expect(part.Shape).toBe(Enum.PartType.Ball)
			expect(part.Anchored).toBe(true)
			expect(part.CanCollide).toBe(false)
		end
		local body = model:FindFirstChild("Body")
		expect(model.PrimaryPart).toBe(body) -- remapped to the clone, not the template
		expect(body.Color).toBe(Color3.fromRGB(255, 120, 40))
		expect(model:FindFirstChild("EyeWhiteL").Color).toBe(Color3.fromRGB(245, 248, 255))
		expect(model:FindFirstChild("PupilR").Color).toBe(Color3.fromRGB(20, 22, 30))
		expect(model:FindFirstChild("EyeWhiteL").Position.Z > 0).toBe(true) -- faces the camera
	end)
	it("clones from a shared template: each build is independent", function()
		local a = SlimePreview.build({ 10, 20, 30 })
		local b = SlimePreview.build({ 200, 100, 0 })
		expect(a ~= b).toBe(true)
		expect(a:FindFirstChild("Body").Color).toBe(Color3.fromRGB(10, 20, 30))
		expect(b:FindFirstChild("Body").Color).toBe(Color3.fromRGB(200, 100, 0))
	end)
	it("clamps bad colour channels", function()
		local body = SlimePreview.build({ 300, -5 }):FindFirstChild("Body")
		expect(body.Color).toBe(Color3.fromRGB(255, 0, 0))
	end)
	it("locked: dark silhouette body whatever the colour, dim half-transparent eyes", function()
		local model = SlimePreview.build({ 255, 255, 0 }, { locked = true })
		expect(model:GetAttribute("Locked")).toBe(true)
		expect(model:FindFirstChild("Body").Color).toBe(SlimePreview.SILHOUETTE)
		for _, name in { "EyeWhiteL", "EyeWhiteR", "PupilL", "PupilR" } do
			local part = model:FindFirstChild(name)
			expect(part.Transparency > 0).toBe(true)
			expect(part.Color ~= Color3.fromRGB(245, 248, 255)).toBe(true)
		end
		expect(SlimePreview.build({ 1, 2, 3 }):GetAttribute("Locked")).toBe(false)
	end)
end)

describe("SlimePreview.mount", function()
	it("adds a WorldModel with the slime and a framed camera", function()
		local vf = UiHarness.Instance.new("ViewportFrame")
		expect(SlimePreview.mount(vf, { 1, 2, 3 })).toBe(true)
		local world = vf:FindFirstChild("World")
		expect(world.ClassName).toBe("WorldModel")
		expect(#world:GetChildren()).toBe(1)
		local cam = vf:FindFirstChild("PreviewCamera")
		expect(vf.CurrentCamera).toBe(cam)
		expect(cam.CFrame.Position.Z > 0).toBe(true)
	end)
	it("recycles the WorldModel and camera on remount, swapping only the model", function()
		local vf = UiHarness.Instance.new("ViewportFrame")
		SlimePreview.mount(vf, { 1, 2, 3 })
		local world, cam = vf:FindFirstChild("World"), vf:FindFirstChild("PreviewCamera")
		SlimePreview.mount(vf, { 9, 9, 9 }, { locked = true })
		expect(vf:FindFirstChild("World")).toBe(world)
		expect(vf:FindFirstChild("PreviewCamera")).toBe(cam)
		expect(#world:GetChildren()).toBe(1)
		expect(world:GetChildren()[1].Name).toBe("SlimePreviewLocked")
		SlimePreview.unmount(vf)
		expect(#vf:GetChildren()).toBe(0)
	end)
	it("returns false, warns and leaves nothing behind when the target is not a viewport", function()
		local frame = UiHarness.Instance.new("Frame")
		local before = UiHarness.warnings
		expect(SlimePreview.mount(frame, { 1, 2, 3 })).toBe(false)
		expect(UiHarness.warnings).toBe(before + 1)
		expect(#frame:GetChildren()).toBe(0)
	end)
end)

local function openDex(w: number, h: number, dex: any, extra: { [string]: any }?): any
	local panel = UiHarness.ui("Panels/Dex").new(UiHarness.root(), (extra or ctx()) :: any)
	local r = Layout.panelFor(Layout.screen(w, h), "Dex")
	panel.frame.Size = UDim2.fromOffset(math.floor(r.w), math.floor(r.h))
	panel.layout(Layout.rect(math.floor(r.x), math.floor(r.y), math.floor(r.w), math.floor(r.h)))
	panel.setOpen(true)
	panel.update({ dex = dex })
	return panel
end

-- A card by species id (cards sit inside their grid line).
local function cardIn(panel: any, id: string): any
	return UiHarness.find(UiHarness.find(panel.frame, "List"), id)
end

-- Scrolls the list so `id`'s line is at the top and refreshes the previews.
local function scrollTo(panel: any, id: string)
	local list = UiHarness.find(panel.frame, "List")
	list.CanvasPosition = Vector2.new(0, cardIn(panel, id).Parent.Position.Y.Offset - 4)
	panel.refreshPreviews()
end

describe("SlimeDex panel previews", function()
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(`{vp.name}: a ViewportFrame per card fills the square preview box inside the card`, function()
			local panel = openDex(vp.w, vp.h, DEX)
			for _, id in { "gummy", "pebble" } do
				local card = cardIn(panel, id)
				local image = card:FindFirstChild("Image")
				local preview = image:FindFirstChild("Preview")
				expect(preview.ClassName).toBe("ViewportFrame")
				expect(preview.Visible).toBe(true)
				expect(preview.Size).toBe(UDim2.fromScale(1, 1))
				expect(image.Size.X.Offset).toBe(image.Size.Y.Offset)
				expect(image.Size.Y.Offset <= card.Size.Y.Offset).toBe(true)
				expect(image.Size.X.Offset <= card.Size.X.Offset).toBe(true)
			end
			-- No species mesh builder here: the blob in the species colour, black for an unfound species.
			local found = UiHarness.find(cardIn(panel, "gummy"), "World"):GetChildren()[1]
			expect(found:FindFirstChild("Body").Color).toBe(rgb(SlimeLooks.get("gummy").color))
			local silhouette = UiHarness.find(cardIn(panel, "pebble"), "World"):GetChildren()[1]
			expect(silhouette:FindFirstChild("Body").Color).toBe(SlimePreview.SILHOUETTE)
		end)
	end
	it("mounts the species mesh from ctx.buildSpecies, painted black when not found", function()
		local built: { string } = {}
		local c = ctx()
		c.SlimeRoster = SlimeRoster
		c.SlimeLooks = SlimeLooks
		c.buildSpecies = function(id: string)
			table.insert(built, id)
			local model = UiHarness.Instance.new("Model")
			local part = UiHarness.Instance.new("Part")
			part.Name = "Mesh"
			part.Color = Color3.new(1, 1, 1)
			part.Parent = model
			return model
		end
		local panel = openDex(1920, 1080, DEX, c)
		expect(table.find(built, "gummy") ~= nil).toBe(true)
		local found = UiHarness.find(cardIn(panel, "gummy"), "World"):GetChildren()[1]
		expect(found:FindFirstChild("Mesh").Color).toBe(Color3.new(1, 1, 1))
		local silhouette = UiHarness.find(cardIn(panel, "pebble"), "World"):GetChildren()[1]
		expect(silhouette:FindFirstChild("Mesh").Color).toBe(SlimePreview.SILHOUETTE)
		expect(cardIn(panel, "pebble"):FindFirstChild("Image"):FindFirstChild("Glyph").Visible).toBe(false)
	end)
	it("remounts a card's preview when it gets found", function()
		local c = ctx()
		c.SlimeLooks = SlimeLooks
		local panel = openDex(1920, 1080, DEX, c)
		local world = UiHarness.find(cardIn(panel, "pebble"), "World")
		expect(world:GetChildren()[1]:FindFirstChild("Body").Color).toBe(SlimePreview.SILHOUETTE)
		panel.update({ dex = Fixtures.dex({ "gummy", "mochi", "pebble" }) })
		expect(world:GetChildren()[1]:FindFirstChild("Body").Color).toBe(rgb(SlimeLooks.get("pebble").color))
	end)
	it("keeps the same viewport model across updates with an unchanged card", function()
		local panel = openDex(1920, 1080, DEX)
		local world = UiHarness.find(cardIn(panel, "gummy"), "World")
		local model = world:GetChildren()[1]
		panel.update({ dex = DEX })
		expect(world:GetChildren()[1]).toBe(model)
	end)
	it("mounts at most MAX_LIVE previews, for the cards in the scroll window only", function()
		expect(SpeciesDex.TOTAL > SlimePreview.MAX_LIVE).toBe(true)
		local panel = openDex(390, 844, DEX)
		local first = cardIn(panel, SpeciesDex.ENTRIES[1].id)
		local last = cardIn(panel, SpeciesDex.BONUS[#SpeciesDex.BONUS].id)
		expect(UiHarness.find(first, "Preview").Visible).toBe(true)
		expect(UiHarness.find(last, "Preview").Visible).toBe(false)
		expect(UiHarness.find(last, "World")).toBeNil()
		local live = panel.liveCount()
		expect(live > 0 and live <= SlimePreview.MAX_LIVE).toBe(true)
		scrollTo(panel, SpeciesDex.BONUS[#SpeciesDex.BONUS].id)
		expect(UiHarness.find(last, "Preview").Visible).toBe(true)
		expect(UiHarness.find(first, "World")).toBeNil()
		expect(panel.liveCount() <= SlimePreview.MAX_LIVE).toBe(true)
	end)
end)

describe("SlimeDex previews rebuild only while open", function()
	local MORE = Fixtures.dex({ "gummy", "mochi", "bumble", "moo" })

	local function closedDex(): any
		local panel = UiHarness.ui("Panels/Dex").new(UiHarness.root(), ctx())
		local r = Layout.panelFor(Layout.screen(1920, 1080), "Dex")
		panel.frame.Size = UDim2.fromOffset(math.floor(r.w), math.floor(r.h))
		return panel
	end

	it("does not rebuild while closed: the update only marks the list dirty", function()
		local panel = closedDex()
		panel.update({ dex = DEX })
		expect(panel.builds()).toBe(0)
		expect(UiHarness.find(panel.frame, "Preview")).toBeNil()
		-- Built once, then closed: a later update leaves the list alone.
		panel.setOpen(true)
		panel.setOpen(false)
		panel.update({ dex = MORE })
		expect(panel.builds()).toBe(1)
		expect(cardIn(panel, "moo"):GetAttribute("Found")).toBe(false)
		expect(UiHarness.find(panel.frame, "Count").Text).toBe(`Species 4/{SpeciesDex.TOTAL}`) -- header still live
	end)
	it("rebuilds on open when dirty (never built, or changed while closed)", function()
		local panel = closedDex()
		panel.update({ dex = DEX })
		panel.setOpen(true)
		expect(panel.builds()).toBe(1)
		panel.setOpen(false)
		panel.update({ dex = MORE })
		panel.setOpen(true)
		expect(panel.builds()).toBe(2)
		expect(cardIn(panel, "moo"):GetAttribute("Found")).toBe(true)
	end)
	it("rebuilds while open when an update makes it dirty", function()
		local panel = closedDex()
		panel.setOpen(true)
		expect(panel.builds()).toBe(0) -- nothing to build before the first state
		panel.update({ dex = DEX })
		expect(panel.builds()).toBe(1)
		panel.update({ dex = MORE })
		expect(panel.builds()).toBe(2)
		expect(cardIn(panel, "moo"):GetAttribute("Found")).toBe(true)
	end)
	it("does not rebuild redundantly on open, or on an unchanged update, when clean", function()
		local panel = closedDex()
		panel.update({ dex = DEX })
		panel.setOpen(true)
		local world = UiHarness.find(cardIn(panel, "gummy"), "World")
		local model = world:GetChildren()[1]
		panel.setOpen(false)
		panel.update({ dex = Fixtures.dex({ "gummy", "mochi", "bumble" }) }) -- same cards: stays clean
		panel.setOpen(true)
		panel.update({ dex = DEX }) -- init.client updates right after opening
		expect(panel.builds()).toBe(1)
		expect(world:GetChildren()[1]).toBe(model)
	end)
end)
