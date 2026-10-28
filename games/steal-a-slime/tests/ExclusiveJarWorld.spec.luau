--!nocheck
-- The Exclusive Shop's jar in the booted server with FEATURES.ExclusiveShop on (contract/exclusive-shop.md §7): the
-- stand at its spot, the two kit mesh slots (the glass worn see-through) with a primitive jar standing in, the solid
-- Counter with its ShopPrompt and ShopId, the sign, and the prompt -> OpenShop "ExclusiveShop" -> range close round
-- trip. The built Props model is checked under Lune too.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Constants = require("../src/shared/Constants")
local Runtime = require("../tools/livetest/Runtime")
local StaticWorld = require("../scripts/StaticWorld")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local LAYOUT = WorldLayout.EXCLUSIVE_JAR
local Props = StaticWorld.visual("Props")

local function parts(root): { any }
	local out = {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(out, d)
		end
	end
	return out
end

local function bottomOf(p): number
	local cf, half = p.CFrame, p.Size / 2
	return cf.Position.Y
		- (math.abs(cf.XVector.Y) * half.X + math.abs(cf.YVector.Y) * half.Y + math.abs(cf.ZVector.Y) * half.Z)
end

describe("Props.exclusiveJar", function()
	local model = Props.exclusiveJar()
	it("is the ExclusiveShopStand with the Counter as its PrimaryPart and its pivot on the ground", function()
		expect(model.Name).toBe(Constants.SHOP_STAND_EXCLUSIVE)
		expect(model.PrimaryPart.Name).toBe("Counter")
		expect(model:GetPivot().Position.Magnitude).toBeCloseTo(0, 4)
		local lowest = math.huge
		for _, p in parts(model) do
			expect(p.Anchored).toBe(true)
			if p.Transparency < 1 then
				lowest = math.min(lowest, bottomOf(p))
			end
		end
		expect(lowest).toBeCloseTo(0, 3)
	end)
	it("carries both kit mesh slots at the layout scale, the shop's bottom groundZ under the grass", function()
		local shop, glass = model.Shop, model.Glass
		expect(shop:GetAttribute("MeshAsset")).toBe(LAYOUT.shop)
		expect(glass:GetAttribute("MeshAsset")).toBe(LAYOUT.glass)
		for slot, mesh in { [shop] = LAYOUT.shop, [glass] = LAYOUT.glass } do
			local size = WorldLayout.meshSize(mesh, LAYOUT.scale)
			expect(slot.Size.X).toBeCloseTo(size[1], 4)
			expect(slot.Size.Y).toBeCloseTo(size[2], 4)
			expect(slot.Size.Z).toBeCloseTo(size[3], 4)
			expect(slot.Transparency).toBe(1)
			expect(slot.CanCollide).toBe(false)
		end
		expect(bottomOf(shop)).toBeCloseTo(-LAYOUT.groundZ * LAYOUT.scale, 4)
		expect(shop.CFrame.Position.X).toBeCloseTo(0, 4)
		expect(shop.CFrame.Position.Z).toBeCloseTo(0, 4)
		local axis = WorldLayout.jarPoint(LAYOUT.glassOrigin)
		expect(glass.CFrame.Position.X).toBeCloseTo(axis[1], 4)
		expect(glass.CFrame.Position.Z).toBeCloseTo(axis[3], 4)
		expect(bottomOf(glass)).toBeCloseTo(axis[2], 4)
		-- the jar's axis stands behind the counter (Props front is -Z)
		expect(axis[3] > WorldLayout.jarPoint(LAYOUT.counter)[3]).toBe(true)
	end)
	it("wears the glass mesh see-through like the goo jar tower's glass", function()
		expect(model.Glass:GetAttribute("MeshMaterial")).toBe(WorldLayout.JAR_GLASS_MATERIAL)
		expect(model.Glass:GetAttribute("MeshTransparency")).toBe(WorldLayout.JAR_GLASS_MESH_TRANSPARENCY)
		expect(model.Glass:GetAttribute("MeshCastShadow")).toBe(false)
	end)
	it("stands a clean primitive jar in for the meshes: SmoothPlastic, the glass light and see-through", function()
		local standIns = 0
		for _, p in parts(model) do
			expect(p.Material.Name).toBe("SmoothPlastic")
			local look = p:GetAttribute("MeshStandIn")
			if look ~= nil then
				standIns += 1
				expect(look == LAYOUT.shop or look == LAYOUT.glass).toBe(true)
				if not p.CanCollide then
					expect(p.CanQuery).toBe(false)
				end
			end
		end
		expect(standIns > 20).toBe(true)
		local pane = model.GlassWall
		expect(pane:GetAttribute("MeshStandIn")).toBe(LAYOUT.glass)
		expect(pane.Transparency).toBeCloseTo(Props.JAR_GLASS_TRANSPARENCY, 5)
		expect(pane.CanCollide).toBe(true)
		expect(pane.Size.Y).toBeCloseTo(model.Glass.Size.X, 4) -- the glass mesh's width
		expect(model.Plinth.CanCollide).toBe(true)
		expect(model.Plinth:GetAttribute("MeshStandIn")).toBe(LAYOUT.shop)
	end)
	it("has a solid Counter at the kit's counter top", function()
		local counter = model.Counter
		local top = WorldLayout.jarPoint(LAYOUT.counter)
		expect(counter.CanCollide).toBe(true)
		expect(counter:GetAttribute("MeshStandIn")).toBe(LAYOUT.shop)
		expect(counter.CFrame.Position.X).toBeCloseTo(top[1], 4)
		expect(counter.CFrame.Position.Z).toBeCloseTo(top[3], 4)
		expect(counter.CFrame.Position.Y + counter.Size.Y / 2).toBeCloseTo(top[2], 4)
		expect(counter.Size.X).toBeCloseTo(LAYOUT.counterSize[1] * LAYOUT.scale, 4)
		expect(counter.Size.Z).toBeCloseTo(LAYOUT.counterSize[2] * LAYOUT.scale, 4)
	end)
	it("puts the EXCLUSIVE sign just in front of the kit's sign face", function()
		local sign = model.Sign
		local face = WorldLayout.jarPoint(LAYOUT.signFace)
		expect(sign.Transparency).toBe(1)
		expect(sign.CanCollide).toBe(false)
		expect(sign:GetAttribute("MeshStandIn")).toBeNil() -- stays when the mesh loads
		expect(sign.CFrame.Position.X).toBeCloseTo(face[1], 4)
		expect(sign.CFrame.Position.Y).toBeCloseTo(face[2], 4)
		local front = sign.CFrame.Position.Z - sign.Size.Z / 2
		expect(front < face[3] and front > face[3] - 0.1).toBe(true)
		expect(sign.Size.X).toBeCloseTo(LAYOUT.signSize[1] * LAYOUT.scale, 4)
		local gui = sign:FindFirstChild("SignGui")
		expect(gui ~= nil and gui.Face.Name).toBe("Front")
		local text = gui:FindFirstChild("Text", true)
		expect(text.Text).toBe("EXCLUSIVE")
	end)
end)

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-jar-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {
	createMeshPart = function()
		return roblox.Instance.new("MeshPart")
	end,
})
fs.removeFile(path)
local config = rt.game:GetService("ReplicatedStorage").Shared.Config
local patched, n = string.gsub(config.Source, "ExclusiveShop = %a+,", "ExclusiveShop = true,")
assert(n == 1, "FEATURES.ExclusiveShop line not found in Config")
config.Source = patched
rt:boot()
rt:advance(2)
local map = rt.workspace.Map
local stand = map:FindFirstChild(Constants.SHOP_STAND_EXCLUSIVE)

-- The live steps run while the spec loads, like the other *Live specs: the runner loads every spec before it
-- runs any test, so a runtime driven from inside `it` would run long after its boot.
local seen: { [string]: any } = {}
if stand then
	local counter = stand.Counter.CFrame.Position
	local near = rt:addPlayer(3001, "Collector")
	local far = rt:addPlayer(3002, "Faraway")
	rt:advance(3)
	near.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(counter.X, counter.Y + 3, counter.Z)
	far.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(0, 5, 0)
	stand.Counter.ShopPrompt.Triggered:Fire(near)
	stand.Counter.ShopPrompt.Triggered:Fire(far)
	rt:advance(0.1)
	seen.nearOpen = near:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE)
	seen.farOpen = far:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE)
	near.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(0, 5, 0)
	rt:advance(3)
	seen.nearAfterWalk = near:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE)
end

describe("Exclusive Shop jar in the booted server", function()
	it("boots clean and places the stand at its layout spot, facing the fountain", function()
		expect(#rt.errors).toBe(0)
		expect(stand ~= nil).toBe(true)
		local spot = WorldLayout.PROP_SPOTS[Constants.SHOP_STAND_EXCLUSIVE]
		local pivot = stand:GetPivot()
		expect(pivot.Position.X).toBeCloseTo(spot.pos[1], 2)
		expect(pivot.Position.Y).toBeCloseTo(spot.pos[2], 2)
		expect(pivot.Position.Z).toBeCloseTo(spot.pos[3], 2)
		local front = pivot.LookVector -- Props front is -Z
		local fx, fz = -spot.pos[1], -spot.pos[3]
		local len = math.sqrt(fx * fx + fz * fz)
		expect((front.X * fx + front.Z * fz) / len > 0.999).toBe(true)
	end)
	it("tags the stand ExclusiveShop and puts one ShopPrompt on the Counter", function()
		expect(stand:GetAttribute(Constants.SHOP_ID_ATTRIBUTE)).toBe(Constants.EXCLUSIVE_SHOP_ID)
		local prompts = {}
		for _, d in stand:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				table.insert(prompts, d)
			end
		end
		expect(#prompts).toBe(1)
		local prompt = prompts[1]
		expect(prompt.Parent).toBe(stand.Counter)
		expect(prompt.Name).toBe(Constants.SHOP_PROMPT_NAME)
		expect(prompt.ObjectText).toBe("Exclusive Shop")
		expect(prompt.KeyboardKeyCode.Name).toBe("E")
		expect(prompt.HoldDuration).toBe(0)
		expect(prompt.MaxActivationDistance).toBe(12)
	end)
	it("keeps the primitive jar while the kit meshes are not uploaded", function()
		expect(stand.Shop:FindFirstChild("Mesh")).toBeNil()
		expect(stand.Glass:FindFirstChild("Mesh")).toBeNil()
		expect(stand.Plinth.Transparency < 1).toBe(true)
		expect(stand.GlassWall.Transparency < 1).toBe(true)
	end)
	it("opens the Exclusive Shop from the prompt and closes it when the player walks away", function()
		expect(seen.nearOpen).toBe(Constants.EXCLUSIVE_SHOP_ID)
		expect(seen.nearAfterWalk).toBeNil()
	end)
	it("does not open from far away", function()
		expect(seen.farOpen).toBeNil()
	end)
	it("still boots clean after the players", function()
		expect(#rt.errors).toBe(0)
	end)
end)
