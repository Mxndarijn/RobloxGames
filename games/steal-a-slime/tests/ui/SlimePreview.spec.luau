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
local TestRunner = require("../TestRunner")
local UiHarness = require("./UiHarness")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect
local Color3, UDim2, Enum = roblox.Color3, roblox.UDim2, roblox.Enum

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
	it("keeps the same viewport model across updates with an unchanged row", function()
		local panel = openDex(1920, 1080, DEX)
		local list = UiHarness.find(panel.frame, "List")
		local world = UiHarness.find(list:FindFirstChild("1:Glow:Spots:Happy"), "World")
		local model = world:GetChildren()[1]
		panel.update({ dex = DEX, dexTotal = TOTAL })
		expect(world:GetChildren()[1]).toBe(model)
	end)
	it(`mounts at most MAX_LIVE previews; later rows keep the swatch`, function()
		local many = {}
		for _, pattern in Config.PATTERNS do
			for _, eyes in Config.EYES do
				table.insert(many, `2:None:{pattern}:{eyes}`)
			end
		end
		expect(#many + Config.MAX_TIER > SlimePreview.MAX_LIVE).toBe(true)
		local panel = openDex(390, 844, many)
		local list = UiHarness.find(panel.frame, "List")
		local live = 0
		for _, row in list:GetChildren() do
			local preview = row:IsA("GuiObject") and UiHarness.find(row, "Preview")
			if preview then
				if preview.Visible then
					live += 1
					expect(row.LayoutOrder <= SlimePreview.MAX_LIVE).toBe(true)
				else
					expect(preview:FindFirstChild("World")).toBeNil()
				end
			end
		end
		expect(live).toBe(SlimePreview.MAX_LIVE)
	end)
end)
