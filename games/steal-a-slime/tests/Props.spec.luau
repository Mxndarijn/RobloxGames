--!strict
-- Archer's Props as the server places them (WorldProps, CONTRACT.md §5.3): built
-- under Lune with Roblox datatypes, checked for names, anchoring and placement.
local roblox = require("@lune/roblox")

local Config = require("../src/shared/Config")
local Constants = require("../src/shared/Constants")
local StaticWorld = require("../scripts/StaticWorld")
local TestRunner = require("./TestRunner")
local WorldLayout = require("../src/visuals/shared/WorldLayout")

local describe, it, expect = TestRunner.describe, TestRunner.it, TestRunner.expect

local Props = StaticWorld.visual("Props")

local function spotFrame(name: string): any
	local spot = WorldLayout.PROP_SPOTS[name]
	return roblox.CFrame.new(spot.pos[1], spot.pos[2], spot.pos[3]) * roblox.CFrame.Angles(0, math.rad(spot.yaw), 0)
end

-- World-space points of every part's centre once the model is pivoted onto its spot.
local function worldParts(model: any, name: string): { any }
	local frame = spotFrame(name)
	local out = {}
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			table.insert(out, { part = inst, pos = (frame * inst.CFrame).Position })
		end
	end
	return out
end

-- WorldProps builds both shop stands from Props.shopStand under their own names (CONTRACT.md §27.2).
local function renamedStand(name: string): () -> any
	return function()
		local model = Props.shopStand()
		model.Name = name
		return model
	end
end

local PROPS = {
	[Constants.SHOP_STAND_ITEM] = renamedStand(Constants.SHOP_STAND_ITEM),
	[Constants.SHOP_STAND_UPGRADE] = renamedStand(Constants.SHOP_STAND_UPGRADE),
	[Constants.LEADERBOARD_BOARD] = Props.leaderboardBoard,
	[Constants.TUTORIAL_NPC] = Props.tutorialNpc,
}

describe("Props placed by WorldProps", function()
	it("builds every prop with the contracted name and a spot", function()
		for name, build in PROPS do
			local model = build()
			expect(model.ClassName).toBe("Model")
			expect(model.Name).toBe(name)
			expect(WorldLayout.PROP_SPOTS[name] ~= nil).toBeTruthy()
		end
	end)
	it("anchors every prop part", function()
		for name, build in PROPS do
			for _, entry in worldParts(build(), name) do
				expect(entry.part.Anchored).toBe(true)
			end
		end
	end)
	it("has the ShopStand Counter and the LeaderboardBoard rows path", function()
		local stand = Props.shopStand()
		expect(stand.PrimaryPart and stand.PrimaryPart.Name).toBe("Counter")
		local board = Props.leaderboardBoard()
		local gui = board.Board.BoardGui
		expect(gui.ClassName).toBe("SurfaceGui")
		expect(gui.Content.Title.ClassName).toBe("TextLabel")
		expect(gui.Content.Rows.ClassName).toBe("Frame")
		Props.fillLeaderboard(board, { { rank = 1, name = "A", value = 5 }, { rank = 2, name = "B", value = 3 } })
		local row = gui.Content.Rows:FindFirstChild("Row_2")
		expect(row and row.Value.Text).toBe("3")
		expect(row and row.Rank.Text).toBe("#2")
	end)
	it("draws the Top Earners list straight on the board face: no backing panel, no extra parts (B2)", function()
		local board = Props.leaderboardBoard()
		local gui = board.Board.BoardGui
		expect(board.Board.Transparency).toBe(1)
		expect(gui.Content.BackgroundTransparency).toBe(1)
		local parts = 0
		for _, d in board:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
			end
		end
		expect(parts).toBe(5) -- Board, Frame, 2 posts, Collider: nothing added for the list
		Props.fillLeaderboard(board, { { rank = 1, name = "A", value = 5 }, { rank = 2, name = "B", value = 3 } })
		local odd, even = gui.Content.Rows.Row_1, gui.Content.Rows.Row_2
		expect(odd.BackgroundTransparency).toBe(1)
		expect(even.BackgroundTransparency).toBe(0)
	end)
	it("keeps the ShopStand SHOP sign unlit so it reads at night (v17 fixes)", function()
		local sign = Props.shopStand().Sign
		expect(sign.SignGui.LightInfluence).toBe(0)
	end)
	it("gives each shop stand its own look: sign colours, decor that survives the skin, a centred box", function()
		local item, upgrade = Props.shopStand("ItemShop"), Props.shopStand("UpgradeShop")
		expect(item.Sign.Color ~= upgrade.Sign.Color).toBe(true)
		expect(upgrade:GetAttribute("MeshTint")).toBe(Props.STAND_STYLES.UpgradeShop.tint)
		for _, stand in { item, upgrade } do
			local kept, lo, hi = 0, math.huge, -math.huge
			for _, d in stand:GetDescendants() do
				if d:IsA("BasePart") then
					lo = math.min(lo, d.CFrame.Position.X - d.Size.X / 2)
					hi = math.max(hi, d.CFrame.Position.X + d.Size.X / 2)
					if d:GetAttribute("MeshKeep") == true then
						kept += 1
						expect(d.CanCollide).toBe(false)
						expect(d.CanQuery).toBe(false)
					end
				end
			end
			expect(kept > 0).toBe(true)
			expect(lo).toBeCloseTo(-hi, 3) -- the skin lands on the box centre: decor never shifts it
		end
		expect(item:FindFirstChild("DecorEgg") ~= nil).toBe(true)
		expect(upgrade:FindFirstChild("DecorAnvilTop") ~= nil).toBe(true)
		expect(Props.shopStand():FindFirstChild("DecorEgg")).toBeNil() -- the single ShopStand keeps its plain look
	end)
	it("builds the SpeedCoil tool with an unanchored Handle", function()
		local tool = Props.speedCoil()
		expect(tool.ClassName).toBe("Tool")
		expect(tool.Name).toBe(Constants.SPEED_COIL_TOOL)
		expect(tool.Handle.Anchored).toBe(false)
		expect(tool.Handle.CanCollide).toBe(false)
	end)
	it("stands on the ground, off the drop ring, plots and HubSpawn", function()
		local spawn = StaticWorld.spawnPosition()
		for name, build in PROPS do
			for _, entry in worldParts(build(), name) do
				local p, size = entry.pos, entry.part.Size
				expect(p.Y - size.Y / 2 > -0.5).toBeTruthy()
				expect(math.sqrt(p.X ^ 2 + p.Z ^ 2) > 62 + 4).toBeTruthy()
				local half = StaticWorld.SPAWN_SIZE[1] / 2 + 2
				expect(math.abs(p.X - spawn[1]) < half and math.abs(p.Z - spawn[3]) < half).toBe(false)
				for i = 1, Config.PLOT_COUNT do
					local c = WorldLayout.plotCentre(i)
					local h = WorldLayout.PLOT_SIZE / 2
					expect(math.abs(p.X - c[1]) < h and math.abs(p.Z - c[3]) < h).toBe(false)
				end
			end
		end
	end)
end)

describe("MinimapData", function()
	local MinimapData = require("../src/visuals/shared/MinimapData")
	it("lists the fountain, every plot, the props and the spawn", function()
		local points = MinimapData.points()
		local kinds = {}
		for _, p in points do
			kinds[p.kind] = (kinds[p.kind] or 0) + 1
		end
		expect(kinds.Fountain).toBe(1)
		expect(kinds.Plot).toBe(Config.PLOT_COUNT)
		expect(kinds.Spawn).toBe(1)
		for name in WorldLayout.PROP_SPOTS do
			expect(kinds[name]).toBe(1)
		end
	end)
	it("pins both world shops with a label and an icon", function()
		local pins = {}
		for _, p in MinimapData.points() do
			if p.label then
				pins[p.name] = p
			end
		end
		expect(pins.ItemShopStand.label).toBe("Item Shop")
		expect(pins.UpgradeShopStand.label).toBe("Upgrade Shop")
		expect(pins.ItemShopStand.icon).toBe("🛒")
		expect(pins.UpgradeShopStand.icon).toBe("⬆️")
		expect(pins.LeaderboardBoard).toBeNil()
	end)
	it("puts the spawn where StaticWorld builds it and maps the ground to 0..1", function()
		local spawn = StaticWorld.spawnPosition()
		expect(MinimapData.SPAWN_YAW).toBe(StaticWorld.SPAWN_YAW)
		expect(MinimapData.SPAWN_RADIUS).toBe(StaticWorld.SPAWN_RADIUS)
		for _, p in MinimapData.points() do
			if p.kind == "Spawn" then
				expect(p.x).toBeCloseTo(spawn[1])
				expect(p.z).toBeCloseTo(spawn[3])
			end
			local u, v = MinimapData.toMap(p.x, p.z)
			expect(u > 0 and u < 1 and v > 0 and v < 1).toBeTruthy()
		end
		local u, v = MinimapData.toMap(0, 0)
		expect(u).toBe(0.5)
		expect(v).toBe(0.5)
	end)
end)
