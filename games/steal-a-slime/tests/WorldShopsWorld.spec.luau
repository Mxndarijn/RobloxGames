--!nocheck
-- The world side of CONTRACT.md §27: the Item Shop and Upgrade Shop stands in the booted server (one ShopPrompt on
-- each Counter, ShopId, mesh collision and no extra collider parts), their placement against PropClearance, and the
-- server-side prompt -> OpenShop -> auto-close round trip.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local PropClearance = require("../src/visuals/shared/PropClearance")
local Runtime = require("../tools/livetest/Runtime")
local StaticWorld = require("../scripts/StaticWorld")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local STANDS = {
	{
		model = Constants.SHOP_STAND_ITEM,
		shopId = "ItemShop",
		object = "Item Shop",
		action = "Browse items",
		sign = "ITEM SHOP",
	},
	{
		model = Constants.SHOP_STAND_UPGRADE,
		shopId = "UpgradeShop",
		object = "Upgrade Shop",
		action = "Browse upgrades",
		sign = "UPGRADE SHOP",
	},
}

local function partCount(model): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function polar(bearing: number, r: number): { number }
	local a = math.rad(bearing)
	return { math.sin(a) * r, math.cos(a) * r }
end

describe("world shop placement", function()
	local spots = WorldLayout.PROP_SPOTS
	it("has both stands on the ring-path side (r 90 / r 96) and facing the fountain", function()
		for name, r in { [Constants.SHOP_STAND_ITEM] = 90, [Constants.SHOP_STAND_UPGRADE] = 96 } do
			local spot = spots[name]
			expect(spot ~= nil).toBe(true)
			expect(math.sqrt(spot.pos[1] ^ 2 + spot.pos[3] ^ 2)).toBeCloseTo(r, 3)
		end
		local up = polar(34.5, 96)
		expect(spots.UpgradeShopStand.pos[1]).toBeCloseTo(up[1], 3)
		expect(spots.UpgradeShopStand.pos[3]).toBeCloseTo(up[2], 3)
		local item = polar(67.5, 90)
		expect(spots.ItemShopStand.pos[1]).toBeCloseTo(item[1], 3)
		expect(spots.ItemShopStand.pos[3]).toBeCloseTo(item[2], 3)
		expect(WorldLayout.PROP_MESHES.ItemShopStand).toBe("ranch_item_shop")
		expect(WorldLayout.PROP_MESHES.UpgradeShopStand).toBe("ranch_upgrade_cabinet")
	end)
	it("keeps the stands' footprints off the lane, ring path, plots, entrances and the other zones", function()
		for _, name in { Constants.SHOP_STAND_ITEM, Constants.SHOP_STAND_UPGRADE } do
			local stand = WorldLayout.SHOP_STANDS[name]
			local size = WorldLayout.meshSize(stand.mesh, stand.scale)
			local spot = spots[name]
			local hits = PropClearance.conflicts({ pos = spot.pos, size = size, yaw = spot.yaw })
			for _, hit in hits do
				if hit ~= name then
					error(`{name} overlaps {hit}`)
				end
			end
		end
	end)
	it("keeps every ranch prop out of the 12 stud spot circle of each stand", function()
		for _, name in { Constants.SHOP_STAND_ITEM, Constants.SHOP_STAND_UPGRADE } do
			local spot = spots[name]
			for _, prop in WorldLayout.RANCH_PROPS do
				local rad = math.sqrt(prop.size[1] ^ 2 + prop.size[3] ^ 2) / 2
				local dist = math.sqrt((prop.pos[1] - spot.pos[1]) ^ 2 + (prop.pos[3] - spot.pos[3]) ^ 2)
				expect(`{name}/{prop.name} {dist >= PropClearance.SPOT_RADIUS + rad}`).toBe(`{name}/{prop.name} true`)
			end
		end
	end)
	it("keeps the Upgrade Shop at least 19.5 studs (about two stand widths) from the Campfire", function()
		local fire = polar(22.5, 92)
		local up = spots.UpgradeShopStand.pos
		expect(math.sqrt((up[1] - fire[1]) ^ 2 + (up[3] - fire[2]) ^ 2) > 19.5).toBe(true)
	end)
	it("keeps the stands, the ritual meadow and the other props apart", function()
		local ritual = polar(Config.RITUAL.BEARING, Config.RITUAL.DISTANCE)
		local up = spots.UpgradeShopStand.pos
		expect(math.sqrt((up[1] - ritual[1]) ^ 2 + (up[3] - ritual[2]) ^ 2) > 54).toBe(true)
		local names = { "ItemShopStand", "UpgradeShopStand", "LeaderboardBoard", "TutorialNpc" }
		for i, a in names do
			for j = i + 1, #names do
				local pa, pb = spots[a].pos, spots[names[j]].pos
				expect(math.sqrt((pa[1] - pb[1]) ^ 2 + (pa[3] - pb[3]) ^ 2) > 2 * PropClearance.SPOT_RADIUS).toBe(true)
			end
		end
	end)
end)

local path = `{process.env.TMPDIR or "/tmp"}/steal-a-slime-worldshops-{os.time()}-{math.random(1, 1e9)}.rbxlx`
local built = process.exec("rojo", { "build", "-o", path })
assert(built.ok, `rojo build failed: {built.stderr}`)
local rt = Runtime.new(path, {
	createMeshPart = function(_meshId, options)
		local part = roblox.Instance.new("MeshPart")
		if options and options.CollisionFidelity then
			part.CollisionFidelity = options.CollisionFidelity
		end
		return part
	end,
})
fs.removeFile(path)
rt:boot()
rt:advance(2)
local Props = StaticWorld.visual("Props")
local map = rt.workspace.Map

describe("shop stand sign", function()
	it("has a high-contrast, scaled, unlit label on the existing Sign part", function()
		local stand = Props.shopStand()
		local label = stand:FindFirstChild("Text", true)
		expect(label.TextScaled).toBe(true)
		local jelly = label.Parent
		local function lum(c)
			return 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
		end
		-- Ink text on the jelly's middle colour (the Sign part carries it)
		expect(lum(stand.Sign.Color) - lum(label.TextColor3) > 0.5).toBe(true)
		expect(jelly.Name).toBe("Jelly")
		expect(jelly.Parent.LightInfluence).toBe(0)
	end)
end)

describe("world shop stands in the booted server", function()
	it("boots clean", function()
		expect(#rt.errors).toBe(0)
	end)
	it("places both stands with one ShopPrompt on the Counter and the ShopId attribute", function()
		for _, def in STANDS do
			local stand = map:FindFirstChild(def.model)
			expect(stand ~= nil).toBe(true)
			expect(stand:GetAttribute(Constants.SHOP_ID_ATTRIBUTE)).toBe(def.shopId)
			expect(stand.PrimaryPart.Name).toBe("Counter")
			local prompts = {}
			for _, d in stand:GetDescendants() do
				if d:IsA("ProximityPrompt") then
					table.insert(prompts, d)
				end
			end
			expect(#prompts).toBe(1)
			local prompt = prompts[1]
			expect(prompt.Parent).toBe(stand.Counter)
			expect(prompt.Name).toBe("ShopPrompt")
			expect(prompt.ObjectText).toBe(def.object)
			expect(prompt.ActionText).toBe(def.action)
			expect(prompt.KeyboardKeyCode.Name).toBe("E")
			expect(prompt.HoldDuration).toBe(0)
			expect(prompt.MaxActivationDistance).toBe(12)
		end
		expect(map:FindFirstChild(Constants.SHOP_STAND)).toBeNil() -- the single HUD-shop stand is gone while WorldShops is on
	end)
	it("sits at the layout spots and writes the sign text on the face", function()
		for _, def in STANDS do
			local stand = map[def.model]
			local spot = WorldLayout.PROP_SPOTS[def.model]
			local pivot = stand:GetPivot().Position
			expect(pivot.X).toBeCloseTo(spot.pos[1], 2)
			expect(pivot.Z).toBeCloseTo(spot.pos[3], 2)
			expect(stand:FindFirstChild("Text", true).Text).toBe(def.sign)
			expect(stand:GetAttribute("MeshAsset")).toBe(WorldLayout.SHOP_STANDS[def.model].mesh)
		end
	end)
	it("collides through the Hull mesh and adds no collider parts of its own", function()
		for _, def in STANDS do
			local stand = map[def.model]
			local base = partCount(Props.shopStand(def.shopId))
			expect(partCount(stand)).toBe(base + 1) -- the primitives + the one skin MeshPart
			local mesh = stand:FindFirstChild("Mesh")
			expect(mesh.CanCollide).toBe(true)
			expect(mesh.CollisionFidelity).toBe(roblox.Enum.CollisionFidelity.Hull)
			for _, d in stand:GetDescendants() do
				expect(string.find(string.lower(d.Name), "collider", 1, true)).toBeNil()
			end
		end
	end)
	it("opens the shop on the server when the prompt is triggered, and closes it when the player walks away", function()
		local stand = map[Constants.SHOP_STAND_UPGRADE]
		local counter = stand.Counter.CFrame.Position
		local player = rt:addPlayer(2001, "Shopper")
		rt:advance(3) -- joined: the server moved them to their plot
		player.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(counter.X, counter.Y + 3, counter.Z + 4)
		expect(player:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE)).toBeNil()
		stand.Counter.ShopPrompt.Triggered:Fire(player)
		rt:advance(0.1)
		expect(player:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE)).toBe("UpgradeShop")
		-- walks far away: the throttled tick closes it
		player.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(0, 5, 0)
		rt:advance(3)
		expect(player:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE)).toBeNil()
	end)
	it("does not open from far away (the prompt may fire from further than SHOP_RANGE)", function()
		local stand = map[Constants.SHOP_STAND_ITEM]
		local counter = stand.Counter.CFrame.Position
		local player = rt:addPlayer(2002, "Far")
		rt:advance(3)
		expect(counter.X ~= 0).toBe(true)
		player.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(0, 5, 0)
		stand.Counter.ShopPrompt.Triggered:Fire(player)
		rt:advance(0.1)
		expect(player:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE)).toBeNil()
	end)
	it("opens the Item Shop in range and closes it when the character dies", function()
		local stand = map[Constants.SHOP_STAND_ITEM]
		local counter = stand.Counter.CFrame.Position
		local player = rt:addPlayer(2003, "Mortal")
		rt:advance(3)
		player.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(counter.X, counter.Y + 3, counter.Z)
		stand.Counter.ShopPrompt.Triggered:Fire(player)
		rt:advance(0.1)
		expect(player:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE)).toBe("ItemShop")
		player.Character.Humanoid.Health = 0
		rt:advance(3)
		expect(player:GetAttribute(Constants.OPEN_SHOP_ATTRIBUTE)).toBeNil()
	end)
	it("still boots clean after the players", function()
		expect(#rt.errors).toBe(0)
	end)
end)
