--!nocheck
-- The Exclusive Shop's claw shop in the booted server (contract/exclusive-shop.md §7): the stand at its spot, the four
-- kit mesh slots (the glass worn see-through, the hand and arm tagged for the claw show) with a primitive claw shop
-- standing in, the solid Counter with its ShopPrompt and ShopId, the sign, and the prompt -> OpenShop "ExclusiveShop"
-- -> range close round trip. The built Props model is checked under Lune too.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Constants = require("../src/shared/Constants")
local Runtime = require("../tools/livetest/Runtime")
local StaticWorld = require("../scripts/StaticWorld")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local LAYOUT = WorldLayout.EXCLUSIVE_CLAW
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

describe("Props.exclusiveClaw", function()
	local model = Props.exclusiveClaw()
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
	it("carries the four kit mesh slots at the layout scale", function()
		local slots = { Shop = LAYOUT.shop, Glass = LAYOUT.glass, Hand = LAYOUT.hand, Arm = LAYOUT.arm }
		for name, mesh in slots do
			local slot = model[name]
			expect(slot:GetAttribute("MeshAsset")).toBe(mesh)
			local size = WorldLayout.meshSize(mesh, LAYOUT.scale)
			expect(slot.Size.X).toBeCloseTo(size[1], 4)
			expect(slot.Size.Y).toBeCloseTo(size[2], 4)
			expect(slot.Size.Z).toBeCloseTo(size[3], 4)
			expect(slot.Transparency).toBe(1)
			expect(slot.CanCollide).toBe(false)
		end
		expect(bottomOf(model.Shop)).toBeCloseTo(-LAYOUT.groundZ * LAYOUT.scale, 4)
		for name, origin in { Glass = LAYOUT.glassOrigin, Hand = LAYOUT.handOrigin, Arm = LAYOUT.armOrigin } do
			local at = WorldLayout.clawPoint(origin)
			local slot = model[name]
			expect(slot.CFrame.Position.X).toBeCloseTo(at[1], 4)
			expect(slot.CFrame.Position.Z).toBeCloseTo(at[3], 4)
			expect(bottomOf(slot)).toBeCloseTo(at[2], 4)
		end
		-- the claw box stands behind the counter (Props front is -Z), the arm runs from the ceiling hole to the hand
		expect(WorldLayout.clawPoint(LAYOUT.glassOrigin)[3] > WorldLayout.clawPoint(LAYOUT.counter)[3]).toBe(true)
		local arm = model.Arm
		expect(arm.CFrame.Position.Y + arm.Size.Y / 2).toBeCloseTo(WorldLayout.clawPoint(LAYOUT.armRoot)[2], 2)
		expect(bottomOf(arm)).toBeCloseTo(WorldLayout.clawPoint(LAYOUT.handIdle)[2], 2)
	end)
	it("tags the hand and arm pieces for the client's claw show", function()
		local kinds = { Hand = 0, Arm = 0 }
		for _, p in parts(model) do
			local kind = p:GetAttribute(Constants.CLAW_PIECE_ATTRIBUTE)
			if kind ~= nil then
				kinds[kind] += 1
				expect(p.CanCollide).toBe(false)
			end
		end
		expect(model.Hand:GetAttribute(Constants.CLAW_PIECE_ATTRIBUTE)).toBe("Hand")
		expect(model.Arm:GetAttribute(Constants.CLAW_PIECE_ATTRIBUTE)).toBe("Arm")
		expect(kinds.Hand >= 5).toBe(true) -- slot, palm, three fingers
		expect(kinds.Arm >= 2).toBe(true) -- slot, stand-in
	end)
	it("wears the glass mesh see-through", function()
		expect(model.Glass:GetAttribute("MeshMaterial")).toBe(WorldLayout.JAR_GLASS_MATERIAL)
		expect(model.Glass:GetAttribute("MeshTransparency")).toBe(LAYOUT.glassTransparency)
		expect(model.Glass:GetAttribute("MeshCastShadow")).toBe(false)
	end)
	it(
		"stands a clean primitive claw shop in for the meshes: SmoothPlastic, solid body and see-through panes",
		function()
			local standIns = 0
			local meshes = { [LAYOUT.shop] = true, [LAYOUT.glass] = true, [LAYOUT.hand] = true, [LAYOUT.arm] = true }
			for _, p in parts(model) do
				expect(p.Material.Name).toBe("SmoothPlastic")
				local look = p:GetAttribute("MeshStandIn")
				if look ~= nil then
					standIns += 1
					expect(meshes[look]).toBe(true)
					if not p.CanCollide then
						expect(p.CanQuery).toBe(false)
					end
				end
			end
			expect(standIns > 20).toBe(true)
			for _, name in { "GlassFront", "GlassSideL", "GlassSideR" } do
				local pane = model[name]
				expect(pane:GetAttribute("MeshStandIn")).toBe(LAYOUT.glass)
				expect(pane.Transparency).toBeCloseTo(Props.CLAW_GLASS_TRANSPARENCY, 5)
				expect(pane.CanCollide).toBe(true)
			end
			for _, name in { "Body", "BackWall", "Roof", "Chute" } do
				expect(model[name].CanCollide).toBe(true)
				expect(model[name]:GetAttribute("MeshStandIn")).toBe(LAYOUT.shop)
			end
		end
	)
	it("has a solid Counter at the kit's counter top", function()
		local counter = model.Counter
		local top = WorldLayout.clawPoint(LAYOUT.counter)
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
		local face = WorldLayout.clawPoint(LAYOUT.signFace)
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

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-claw-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {
	createMeshPart = function()
		return roblox.Instance.new("MeshPart")
	end,
})
fs.removeFile(path)
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

describe("Exclusive Shop claw shop in the booted server", function()
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
	it("swaps in the uploaded kit meshes and keeps the stand's solid parts colliding under them", function()
		for _, slot in { "Shop", "Glass", "Hand", "Arm" } do
			expect(`{slot} {stand[slot]:FindFirstChild("Mesh") ~= nil}`).toBe(`{slot} true`)
		end
		expect(stand.Body.CanCollide).toBe(true)
		expect(stand.GlassFront.CanCollide).toBe(true)
		expect(stand.Counter.CanCollide).toBe(true)
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
