--!strict
-- SlimePreview (src/ui/SlimePreview.luau) under tests/ui/UiHarness.luau: the
-- Ball + eyes builder, locked silhouettes, viewport mount / recycle, and the
-- SlimeDex panel's ViewportFrame previews at every gate viewport.
local roblox = require("@lune/roblox") :: any

local Config = require("../../src/shared/Config")
local Constants = require("../../src/shared/Constants")
local Genome = require("../../src/shared/Genome")
local Layout = require("../../src/ui/Layout")
local LayoutAssert = require("./LayoutAssert")
local Remotes = require("../../src/shared/Remotes")
local SlimeDex = require("../../src/ui/SlimeDex")
local SlimeRoster = require("../../src/shared/SlimeRoster")
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local Color3, UDim2, Enum, Vector2 = roblox.Color3, roblox.UDim2, roblox.Enum, roblox.Vector2

local SlimePreview = UiHarness.ui("SlimePreview")
local PARTS = { "Body", "EyeWhiteL", "EyeWhiteR", "PupilL", "PupilR" }
local TOTAL = Config.MAX_TIER * (#Config.MUTATIONS + 1) * #Config.PATTERNS * #Config.EYES
local DEX = { "2:None:Plain:Round", "1:Glow:Spots:Happy", "1:None:Plain:Round" }

local function rgb(c: { number }): any
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function ctx(): any
	return {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
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

describe("SlimePreview mutation finishes", function()
	it("covers every Config mutation (v28 Rainbow / Crystal / Eclipse included)", function()
		for _, m in Config.MUTATIONS do
			expect(SlimePreview.FINISHES[m.name] ~= nil).toBe(true)
			expect((SlimeDex.MUTATION_COLORS :: any)[m.name] ~= nil).toBe(true)
		end
		for _, m in SlimeRoster.NEW_MUTATIONS do
			local finish = SlimePreview.FINISHES[m.name]
			expect(finish.material ~= nil or finish.accents ~= nil).toBe(true) -- more than a tint
		end
	end)
	it("Rainbow gets three bands, Crystal a glass body + shard, Eclipse a bright corona", function()
		local rainbow = SlimePreview.build(SlimeDex.MUTATION_COLORS.Rainbow, { mutation = "Rainbow" })
		expect(rainbow:GetAttribute("Mutation")).toBe("Rainbow")
		for _, name in { "BandRed", "BandYellow", "BandBlue" } do
			local band = rainbow:FindFirstChild(name)
			expect(band.Shape).toBe(Enum.PartType.Cylinder)
			expect(band.CFrame.Position.Z < 0).toBe(true) -- behind the body, eyes stay visible
		end
		local crystal = SlimePreview.build(SlimeDex.MUTATION_COLORS.Crystal, { mutation = "Crystal" })
		expect(crystal:FindFirstChild("Body").Material).toBe(Enum.Material.Glass)
		expect(crystal:FindFirstChild("Body").Transparency > 0).toBe(true)
		expect(crystal:FindFirstChild("Shard").CFrame.Position.Y > 0.9).toBe(true)
		local eclipse = SlimePreview.build(SlimeDex.MUTATION_COLORS.Eclipse, { mutation = "Eclipse" })
		expect(eclipse:FindFirstChild("Body").Color).toBe(rgb(SlimeDex.MUTATION_COLORS.Eclipse))
		expect(eclipse:FindFirstChild("Corona").Material).toBe(Enum.Material.Neon)
		expect(eclipse:GetAttribute("Locked")).toBe(false) -- dark, but not the locked look
		for _, model in { rainbow, crystal, eclipse } do
			for _, name in PARTS do
				expect(model:FindFirstChild(name) ~= nil).toBe(true)
			end
		end
	end)
	it("locked rows and unknown / None mutations use the plain look", function()
		local locked = SlimePreview.build({ 1, 2, 3 }, { locked = true, mutation = "Eclipse" })
		expect(locked:FindFirstChild("Corona")).toBeNil()
		expect(locked:GetAttribute("Mutation")).toBeNil()
		for _, mutation in { "None", "Nope" } do
			local model = SlimePreview.build({ 1, 2, 3 }, { mutation = mutation })
			expect(#model:GetChildren()).toBe(#PARTS)
			expect(model:GetAttribute("Mutation")).toBeNil()
		end
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

local function openDex(w: number, h: number, dex: { string }): any
	local panel = UiHarness.ui("Panels/Dex").new(UiHarness.root(), ctx())
	local r = Layout.panelFor(Layout.screen(w, h), "Dex")
	panel.frame.Size = UDim2.fromOffset(math.floor(r.w), math.floor(r.h))
	panel.setOpen(true)
	panel.update({ dex = dex, dexTotal = TOTAL })
	return panel
end

describe("SlimeDex panel previews", function()
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(`{vp.name}: a ViewportFrame per row fills the square image box inside the row`, function()
			local panel = openDex(vp.w, vp.h, DEX)
			local list = UiHarness.find(panel.frame, "List")
			for _, key in { "1:Glow:Spots:Happy", "locked:1" } do
				local row = list:FindFirstChild(key)
				local image = row:FindFirstChild("Image")
				local preview = image:FindFirstChild("Preview")
				expect(preview.ClassName).toBe("ViewportFrame")
				expect(preview.Visible).toBe(true)
				expect(preview.Size).toBe(UDim2.fromScale(1, 1))
				expect(image.Size.X.Offset).toBe(image.Size.Y.Offset)
				expect(image.Size.Y.Offset <= row.Size.Y.Offset).toBe(true)
				expect(image.Size.X.Offset < panel.frame.Size.X.Offset).toBe(true)
				expect(preview.ZIndex < image:FindFirstChild("Glyph").ZIndex).toBe(true)
			end
			local glow = list:FindFirstChild("1:Glow:Spots:Happy"):FindFirstChild("Image")
			local model = glow:FindFirstChild("Preview"):FindFirstChild("World"):GetChildren()[1]
			expect(model:FindFirstChild("Body").Color).toBe(rgb(SlimeDex.MUTATION_COLORS.Glow))
			local locked = list:FindFirstChild("locked:1"):FindFirstChild("Image")
			local blob = locked:FindFirstChild("Preview"):FindFirstChild("World"):GetChildren()[1]
			expect(blob:FindFirstChild("Body").Color).toBe(SlimePreview.SILHOUETTE)
			expect(locked:FindFirstChild("Glyph").Visible).toBe(true) -- ? over the silhouette
		end)
	end
	local NEW_ROWS = {
		"5:Rainbow:Plain:Round",
		"6:Crystal:Spots:Happy",
		"6:Eclipse:Plain:Round",
		"4:Lava:Spots:Happy", -- old save id, shows as Syrup
	}
	for _, vp in LayoutAssert.GATE_VIEWPORTS do
		it(`{vp.name}: v28 mutation rows (and Lava/Syrup) get a finished ViewportFrame preview`, function()
			local panel = openDex(vp.w, vp.h, NEW_ROWS)
			local list = UiHarness.find(panel.frame, "List")
			local accent = { Rainbow = "BandRed", Crystal = "Shard", Eclipse = "Corona", Lava = nil }
			for _, key in NEW_ROWS do
				local mutation = string.match(key, "^%d+:([^:]+)") :: string
				local row = list:FindFirstChild(key)
				list.CanvasPosition = Vector2.new(0, row.Position.Y.Offset - 4) -- previews follow the scroll window
				panel.refreshPreviews()
				local image = row:FindFirstChild("Image")
				local preview = image:FindFirstChild("Preview")
				expect(preview.ClassName).toBe("ViewportFrame")
				expect(preview.Visible).toBe(true)
				expect(image.Size.Y.Offset <= row.Size.Y.Offset).toBe(true)
				local model = preview:FindFirstChild("World"):GetChildren()[1]
				expect(model:GetAttribute("Mutation")).toBe(mutation)
				expect(model:FindFirstChild("Body").Color).toBe(rgb((SlimeDex.MUTATION_COLORS :: any)[mutation]))
				if accent[mutation] then
					expect(model:FindFirstChild(accent[mutation]) ~= nil).toBe(true)
				end
				local title = row:FindFirstChild("Title").Text
				expect(string.find(string.lower(title), "lava", 1, true)).toBeNil()
			end
			expect(list:FindFirstChild("4:Lava:Spots:Happy"):FindFirstChild("Title").Text).toBe(
				"Epic · Syrup · Spots · Happy"
			)
		end)
	end
	it("remounts a row's preview when only its mutation finish changes", function()
		local panel = openDex(1920, 1080, { "6:Crystal:Plain:Round" })
		local list = UiHarness.find(panel.frame, "List")
		local world = UiHarness.find(list:FindFirstChild("6:Crystal:Plain:Round"), "World")
		expect(world:GetChildren()[1]:GetAttribute("Mutation")).toBe("Crystal")
		panel.update({ dex = { "6:Crystal:Plain:Round" }, dexTotal = TOTAL })
		expect(world:GetChildren()[1]:FindFirstChild("Shard") ~= nil).toBe(true)
	end)
	it("keeps the same viewport model across updates with an unchanged row", function()
		local panel = openDex(1920, 1080, DEX)
		local list = UiHarness.find(panel.frame, "List")
		local world = UiHarness.find(list:FindFirstChild("1:Glow:Spots:Happy"), "World")
		local model = world:GetChildren()[1]
		panel.update({ dex = DEX, dexTotal = TOTAL })
		expect(world:GetChildren()[1]).toBe(model)
	end)
	it(`mounts at most MAX_LIVE previews, for the rows in the scroll window only`, function()
		local many = {}
		for _, pattern in Config.PATTERNS do
			for _, eyes in Config.EYES do
				table.insert(many, `2:None:{pattern}:{eyes}`)
			end
		end
		expect(#many + Config.MAX_TIER > SlimePreview.MAX_LIVE).toBe(true)
		local panel = openDex(390, 844, many)
		local list = UiHarness.find(panel.frame, "List")
		local live, first, last = 0, false, false
		for _, row in list:GetChildren() do
			local preview = row:IsA("GuiObject") and UiHarness.find(row, "Preview")
			if preview then
				if preview.Visible then
					live += 1
					first = first or row.LayoutOrder == 1
				else
					expect(preview:FindFirstChild("World")).toBeNil()
					last = last or row.LayoutOrder == #many + Config.MAX_TIER
				end
			end
		end
		expect(first).toBe(true)
		expect(last).toBe(true)
		expect(live > 0 and live <= SlimePreview.MAX_LIVE).toBe(true)
		expect(panel.liveCount()).toBe(live)
	end)
end)

describe("SlimeDex previews rebuild only while open", function()
	local NEW = "3:None:Plain:Round"
	local MORE = { DEX[1], DEX[2], DEX[3], NEW }

	local function closedDex(): any
		local panel = UiHarness.ui("Panels/Dex").new(UiHarness.root(), ctx())
		local r = Layout.panelFor(Layout.screen(1920, 1080), "Dex")
		panel.frame.Size = UDim2.fromOffset(math.floor(r.w), math.floor(r.h))
		return panel
	end

	it("does not rebuild while closed: the update only marks the list dirty", function()
		local panel = closedDex()
		panel.update({ dex = DEX, dexTotal = TOTAL })
		expect(panel.builds()).toBe(0)
		expect(UiHarness.find(panel.frame, "Preview")).toBeNil()
		-- Built once, then closed: a later update leaves the list alone.
		panel.setOpen(true)
		panel.setOpen(false)
		panel.update({ dex = MORE, dexTotal = TOTAL })
		expect(panel.builds()).toBe(1)
		expect(UiHarness.find(panel.frame, "List"):FindFirstChild(NEW)).toBeNil()
		expect(UiHarness.find(panel.frame, "Count").Text).toBe("Discovered 4 / " .. TOTAL) -- header still live
	end)
	it("rebuilds on open when dirty (never built, or changed while closed)", function()
		local panel = closedDex()
		panel.update({ dex = DEX, dexTotal = TOTAL })
		panel.setOpen(true)
		expect(panel.builds()).toBe(1)
		local list = UiHarness.find(panel.frame, "List")
		expect(UiHarness.find(list:FindFirstChild(DEX[2]), "World") ~= nil).toBe(true)
		panel.setOpen(false)
		panel.update({ dex = MORE, dexTotal = TOTAL })
		panel.setOpen(true)
		expect(panel.builds()).toBe(2)
		expect(UiHarness.find(list:FindFirstChild(NEW), "World") ~= nil).toBe(true)
	end)
	it("rebuilds while open when an update makes it dirty", function()
		local panel = closedDex()
		panel.setOpen(true)
		expect(panel.builds()).toBe(0) -- nothing to build before the first state
		panel.update({ dex = DEX, dexTotal = TOTAL })
		expect(panel.builds()).toBe(1)
		panel.update({ dex = MORE, dexTotal = TOTAL })
		expect(panel.builds()).toBe(2)
		local list = UiHarness.find(panel.frame, "List")
		expect(UiHarness.find(list:FindFirstChild(NEW), "World") ~= nil).toBe(true)
	end)
	it("does not rebuild redundantly on open, or on an unchanged update, when clean", function()
		local panel = closedDex()
		panel.update({ dex = DEX, dexTotal = TOTAL })
		panel.setOpen(true)
		local world = UiHarness.find(UiHarness.find(panel.frame, "List"):FindFirstChild(DEX[2]), "World")
		local model = world:GetChildren()[1]
		panel.setOpen(false)
		panel.update({ dex = table.clone(DEX), dexTotal = TOTAL }) -- same rows: stays clean
		panel.setOpen(true)
		panel.update({ dex = DEX, dexTotal = TOTAL }) -- init.client updates right after opening
		expect(panel.builds()).toBe(1)
		expect(world:GetChildren()[1]).toBe(model)
	end)
end)
