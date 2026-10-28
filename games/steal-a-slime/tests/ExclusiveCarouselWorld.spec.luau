--!nocheck
-- The Exclusive Shop carousel in the booted server with FEATURES.ExclusiveShop on (contract/exclusive-shop.md §7):
-- the stand at its spot, the two kit mesh slots with a primitive carousel standing in, the spin part and everything
-- on it never colliding, the flat deck collider, the kiosk Counter with its ShopPrompt and ShopId, and the prompt ->
-- OpenShop "ExclusiveShop" -> range close round trip. The built Props model is checked under Lune too.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Constants = require("../src/shared/Constants")
local Runtime = require("../tools/livetest/Runtime")
local StaticWorld = require("../scripts/StaticWorld")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local LAYOUT = WorldLayout.EXCLUSIVE_CAROUSEL
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

describe("Props.exclusiveCarousel", function()
	local model = Props.exclusiveCarousel()
	it("is the ExclusiveShopStand with the kiosk Counter as its PrimaryPart and its pivot on the ground", function()
		expect(model.Name).toBe(Constants.SHOP_STAND_EXCLUSIVE)
		expect(model.PrimaryPart.Name).toBe("Counter")
		expect(model:GetPivot().Position.Magnitude).toBeCloseTo(0, 4)
		local lowest = math.huge
		for _, p in parts(model) do
			expect(p.Anchored).toBe(true)
			if p.Transparency < 1 then
				local cf, half = p.CFrame, p.Size / 2
				local down = math.abs(cf.XVector.Y) * half.X
					+ math.abs(cf.YVector.Y) * half.Y
					+ math.abs(cf.ZVector.Y) * half.Z
				lowest = math.min(lowest, cf.Position.Y - down)
			end
		end
		expect(lowest).toBeCloseTo(0, 3)
	end)
	it("carries both kit mesh slots at the layout scale, the spin slot on the kit's spin axis", function()
		local static = model.Static
		expect(static:GetAttribute("MeshAsset")).toBe(LAYOUT.static)
		local spin = model[Constants.EXCLUSIVE_CAROUSEL_SPIN]
		expect(spin:GetAttribute("MeshAsset")).toBe(LAYOUT.spin)
		for slot, mesh in { [static] = LAYOUT.static, [spin] = LAYOUT.spin } do
			local size = WorldLayout.meshSize(mesh, LAYOUT.scale)
			expect(slot.Size.X).toBeCloseTo(size[1], 4)
			expect(slot.Size.Y).toBeCloseTo(size[2], 4)
			expect(slot.Size.Z).toBeCloseTo(size[3], 4)
			expect(slot.Transparency).toBe(1)
			expect(slot.CanCollide).toBe(false)
		end
		local bottom = WorldLayout.carouselPoint(LAYOUT.spinOrigin)
		expect(spin.CFrame.Position.X).toBeCloseTo(bottom[1], 4)
		expect(spin.CFrame.Position.Z).toBeCloseTo(bottom[3], 4)
		expect(spin.CFrame.Position.Y - spin.Size.Y / 2).toBeCloseTo(bottom[2], 4)
	end)
	it("never collides with anything that turns, and stands the visible primitives in for the meshes", function()
		local spin = model[Constants.EXCLUSIVE_CAROUSEL_SPIN]
		local poles = 0
		for _, p in parts(spin) do
			expect(p.CanCollide).toBe(false)
			expect(p:GetAttribute("MeshStandIn")).toBe(LAYOUT.spin)
			if string.find(p.Name, "Pole", 1, true) then
				poles += 1
			end
		end
		expect(poles).toBe(#LAYOUT.riders)
		local cone = 0
		for _, p in model:GetChildren() do
			if p:IsA("WedgePart") then
				cone += 1
				expect(p:GetAttribute("MeshStandIn")).toBe(LAYOUT.static)
			end
		end
		expect(cone > 0).toBe(true)
	end)
	it("has a flat invisible deck collider at the deck top and a solid kiosk at the counter top", function()
		local deck = model.DeckCollider
		expect(deck.CanCollide).toBe(true)
		expect(deck.Transparency).toBe(1)
		expect(deck.CFrame.Position.Y + deck.Size.X / 2).toBeCloseTo(LAYOUT.deckTop * LAYOUT.scale, 4)
		expect(deck.Size.Y).toBeCloseTo(LAYOUT.deckRadius * LAYOUT.scale * 2, 4)
		local counter = model.Counter
		local top = WorldLayout.carouselPoint(LAYOUT.counter)
		expect(counter.CanCollide).toBe(true)
		expect(counter.CFrame.Position.X).toBeCloseTo(top[1], 4)
		expect(counter.CFrame.Position.Z).toBeCloseTo(top[3], 4)
		expect(counter.CFrame.Position.Y + counter.Size.Y / 2).toBeCloseTo(top[2], 4)
		-- in front of the deck, on the viewer's right (Props front is -Z, so right is -X)
		expect(top[3] < 0 and top[1] < 0).toBe(true)
	end)
end)

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-carousel-{os.time()}-{math.random(1, 1e9)}.rbxlx`
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

describe("Exclusive Shop carousel in the booted server", function()
	local stand = map:FindFirstChild(Constants.SHOP_STAND_EXCLUSIVE)
	it("boots clean and places the stand at its layout spot", function()
		expect(#rt.errors).toBe(0)
		expect(stand ~= nil).toBe(true)
		local spot = WorldLayout.PROP_SPOTS[Constants.SHOP_STAND_EXCLUSIVE]
		local pivot = stand:GetPivot()
		expect(pivot.Position.X).toBeCloseTo(spot.pos[1], 2)
		expect(pivot.Position.Z).toBeCloseTo(spot.pos[3], 2)
		local front = pivot.LookVector -- Props front is -Z
		local fx, fz = -spot.pos[1], -spot.pos[3]
		local len = math.sqrt(fx * fx + fz * fz)
		expect((front.X * fx + front.Z * fz) / len > 0.999).toBe(true)
	end)
	it("tags the stand ExclusiveShop and puts one ShopPrompt on the kiosk Counter", function()
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
	it("keeps the primitive carousel while the kit meshes are not uploaded", function()
		expect(stand.Static:FindFirstChild("Mesh")).toBeNil()
		expect(stand[Constants.EXCLUSIVE_CAROUSEL_SPIN]:FindFirstChild("Mesh")).toBeNil()
		expect(stand[Constants.EXCLUSIVE_CAROUSEL_SPIN].Deck.Transparency < 1).toBe(true)
	end)
	it("opens the Exclusive Shop from the prompt and closes it when the player walks away", function()
		local counter = stand.Counter.CFrame.Position
		local player = rt:addPlayer(3001, "Collector")
		rt:advance(3)
		player.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(counter.X, counter.Y + 3, counter.Z)
		stand.Counter.ShopPrompt.Triggered:Fire(player)
		rt:advance(0.1)
		expect(player:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE)).toBe(Constants.EXCLUSIVE_SHOP_ID)
		player.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(0, 5, 0)
		rt:advance(3)
		expect(player:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE)).toBeNil()
	end)
	it("does not open from far away", function()
		local player = rt:addPlayer(3002, "Faraway")
		rt:advance(3)
		player.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(0, 5, 0)
		stand.Counter.ShopPrompt.Triggered:Fire(player)
		rt:advance(0.1)
		expect(player:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE)).toBeNil()
	end)
	it("still boots clean after the players", function()
		expect(#rt.errors).toBe(0)
	end)
end)
