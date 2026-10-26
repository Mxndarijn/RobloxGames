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

-- WorldProps builds both shop stands from Props.shopStand(shopId), named for their stand (CONTRACT.md §27.2).
local function standBuilder(shopId: string): () -> any
	return function()
		return Props.shopStand(shopId)
	end
end

local PROPS = {
	[Constants.SHOP_STAND_ITEM] = standBuilder("ItemShop"),
	[Constants.SHOP_STAND_UPGRADE] = standBuilder("UpgradeShop"),
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
	it("has the shop stands' Counter and the LeaderboardBoard rows path", function()
		for style in Props.STAND_STYLES do
			local model = Props.shopStand(style)
			expect(model.PrimaryPart and model.PrimaryPart.Name).toBe("Counter")
		end
		local board = Props.leaderboardBoard()
		local gui = board.Board.BoardGui
		expect(gui.ClassName).toBe("SurfaceGui")
		expect(gui.Content.Header.Title.ClassName).toBe("TextLabel")
		expect(gui.Content.Header.Title.Text).toBe("Top Earners")
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
	it("keeps the shop stands' signs unlit so they read at night (v17 fixes)", function()
		for style in Props.STAND_STYLES do
			expect(Props.shopStand(style).Sign.SignGui.LightInfluence).toBe(0)
		end
	end)
	it("names each shop on a jelly sign (mint item shop, gold upgrade shop) with its drips on the sign face", function()
		local titles = {}
		for style, look in Props.STAND_STYLES do
			local gui = Props.shopStand(style).Sign.SignGui
			local jelly = gui.Jelly
			titles[style] = jelly.Text.Text
			if look.drawn then
				expect(jelly.Badge:FindFirstChild("UpArrow") ~= nil).toBe(true) -- drawn, not an emoji
				expect(jelly.Badge:FindFirstChild("Icon")).toBeNil()
			else
				expect(jelly.Badge.Icon.Text).toBe(look.icon)
			end
			expect(jelly:FindFirstChildOfClass("UIStroke") ~= nil).toBe(true)
			for _, d in gui:GetChildren() do
				if d:IsA("Frame") and string.sub(d.Name, 1, 4) == "Drip" then
					expect(d.Position.Y.Scale + d.Size.Y.Scale <= 1).toBe(true) -- inside the face
				end
			end
		end
		expect(titles.ItemShop).toBe("Item shop")
		expect(titles.UpgradeShop).toBe("Upgrade shop")
	end)
	it("gives each shop stand its own skin and sign colours, its box exactly the skin's box round the pivot", function()
		local item, upgrade = Props.shopStand("ItemShop"), Props.shopStand("UpgradeShop")
		expect(item.Sign.Color ~= upgrade.Sign.Color).toBe(true)
		for style, stand in { ItemShop = item, UpgradeShop = upgrade } do
			local def = WorldLayout.SHOP_STANDS[Props.STAND_STYLES[style].stand]
			local skin = WorldLayout.meshSize(def.mesh, def.scale)
			local lo = { math.huge, math.huge, math.huge }
			local hi = { -math.huge, -math.huge, -math.huge }
			for _, d in stand:GetDescendants() do
				if d:IsA("BasePart") then
					local p, s = d.CFrame.Position, d.Size
					lo = {
						math.min(lo[1], p.X - s.X / 2),
						math.min(lo[2], p.Y - s.Y / 2),
						math.min(lo[3], p.Z - s.Z / 2),
					}
					hi = {
						math.max(hi[1], p.X + s.X / 2),
						math.max(hi[2], p.Y + s.Y / 2),
						math.max(hi[3], p.Z + s.Z / 2),
					}
				end
			end
			for axis = 1, 3 do
				expect(hi[axis] - lo[axis]).toBeCloseTo(skin[axis], 3)
			end
			expect(lo[1]).toBeCloseTo(-hi[1], 3) -- centred on the pivot
			expect(lo[3]).toBeCloseTo(-hi[3], 3)
			expect(lo[2]).toBeCloseTo(0, 3) -- on the ground
			-- the Counter (prompt parent) fills the skin's counter, its top on the skin's counter top
			local counter = stand.Counter
			expect(counter.CFrame.Position.Z).toBeCloseTo(-def.counter.z * def.scale, 3)
			expect(stand.CounterTop.CFrame.Position.Y + 0.2).toBeCloseTo(def.counter.top * def.scale, 3)
		end
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
					-- in the plot's own turned frame (PropClearance's plot rect), not an axis-aligned square
					local c, yaw = WorldLayout.plotCentre(i)
					local a = math.rad(yaw)
					local dx, dz = p.X - c[1], p.Z - c[3]
					local x, z = dx * math.cos(a) - dz * math.sin(a), dx * math.sin(a) + dz * math.cos(a)
					local h = WorldLayout.PLOT_SIZE / 2
					expect(math.abs(x) < h and math.abs(z) < h).toBe(false)
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
