--!strict
--[[
	WorldProps (Roblox adapter)

	Places the world props from Archer's ReplicatedStorage.Visuals.Props at
	WorldLayout.PROP_SPOTS under workspace.Map (CONTRACT.md §5.3):
	ShopStand (with the "Open Shop" ProximityPrompt on Counter; with FEATURES.WorldShops on, the ItemShopStand
	and UpgradeShopStand instead, each with its own ShopPrompt and ShopId attribute, CONTRACT.md §27),
	LeaderboardBoard and TutorialNpc (with the "Talk" prompt). A prop that already exists anywhere
	under workspace (e.g. a static copy) is reused. Every part is anchored.
	Also writes the leaderboard rows into the board and builds the Speed Coil
	tool. Holds no gameplay rules; a missing Visuals module just means no props.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Leaderboard = require(script.Parent.Leaderboard)
local Shops = require(ReplicatedStorage.Shared.Shops)

local WorldProps = {}

-- v28: one prompt per prop. Both only open a client menu (the UI listens
-- for PromptTriggered); nothing is bought or changed on the server.
WorldProps.SHOP_PROMPT = table.freeze({
	name = Constants.SHOP_PROMPT_NAME,
	objectText = "Shop",
	actionText = "Open Shop",
})
-- FEATURES.WorldShops (CONTRACT.md §27.3): same prompt name, one per stand; the server opens the shop on Triggered.
WorldProps.SHOP_PROMPTS = table.freeze({
	ItemShop = table.freeze({
		name = WorldProps.SHOP_PROMPT.name,
		objectText = "Item Shop",
		actionText = "Browse items",
	}),
	UpgradeShop = table.freeze({
		name = WorldProps.SHOP_PROMPT.name,
		objectText = "Upgrade Shop",
		actionText = "Browse upgrades",
	}),
})
-- The sign text of each stand (the Props sign says SHOP).
local STAND_SIGNS: { [string]: string } = { ItemShop = "ITEM SHOP", UpgradeShop = "UPGRADE SHOP" }

WorldProps.GUIDE_PROMPT = table.freeze({
	name = Constants.GUIDE_PROMPT_NAME,
	objectText = "Guide",
	actionText = "Talk",
})

local function visual(name: string): any
	local visuals = ReplicatedStorage:FindFirstChild("Visuals")
	local module = visuals and visuals:FindFirstChild(name)
	if not module or not module:IsA("ModuleScript") then
		return nil
	end
	local ok, result = pcall(require, module)
	if not ok then
		warn(`[Server] Visuals.{name} failed to load: {result}`)
		return nil
	end
	return result
end

local function findModel(name: string): Model?
	local found = workspace:FindFirstChild(name, true)
	if found and found:IsA("Model") then
		return found
	end
	return nil
end

local function anchorAll(model: Instance)
	for _, inst in model:GetDescendants() do
		if inst:IsA("BasePart") then
			inst.Anchored = true
		end
	end
end

local placed: { [string]: Model } = {}

-- The skin's size on `model`: native x one uniform scale (WorldLayout.meshSize,
-- as #47 does for the plot slots), the scale matching the Model's height.
-- Fitting the Model's box per axis squashed the top earners board 3.08:1
-- (v27 gate B3). nil when the mesh has no native size.
function WorldProps.meshSize(WorldLayout: any, mesh: string, model: Model): Vector3?
	if not (WorldLayout and WorldLayout.meshSize) then
		return nil
	end
	local ok, unit = pcall(WorldLayout.meshSize, mesh, 1)
	if not ok or type(unit) ~= "table" or not (unit[2] and unit[2] > 0) then
		return nil
	end
	local _, box = model:GetBoundingBox()
	local size = WorldLayout.meshSize(mesh, box.Y / unit[2])
	return Vector3.new(size[1], size[2], size[3])
end

function WorldProps.worldShops(): boolean
	return Config.FEATURES.WorldShops == true
end

-- A shop stand builder: Props.shopStand renamed, its sign text set (no new parts).
local function standBuilder(Props: any, name: string, shopId: string?): (() -> Instance)?
	if not (Props and Props.shopStand) then
		return nil
	end
	return function()
		local model = Props.shopStand()
		model.Name = name
		local text = shopId and model:FindFirstChild("Text", true)
		if text and text:IsA("TextLabel") then
			text.Text = STAND_SIGNS[shopId :: string]
		end
		return model
	end
end

-- Places any missing prop. Returns the props by name (missing ones are absent).
function WorldProps.place(): { [string]: Model }
	local Props = visual("Props")
	local WorldLayout = visual("WorldLayout")
	local builders: { [string]: any } = {
		[Constants.LEADERBOARD_BOARD] = Props and Props.leaderboardBoard,
		[Constants.TUTORIAL_NPC] = Props and Props.tutorialNpc,
	}
	if WorldProps.worldShops() then
		builders[Constants.SHOP_STAND_ITEM] = standBuilder(Props, Constants.SHOP_STAND_ITEM, "ItemShop")
		builders[Constants.SHOP_STAND_UPGRADE] = standBuilder(Props, Constants.SHOP_STAND_UPGRADE, "UpgradeShop")
	else
		builders[Constants.SHOP_STAND] = Props and Props.shopStand
	end
	local parent = workspace:FindFirstChild(Constants.MAP_FOLDER) or workspace
	for name, build in builders do
		local model = findModel(name)
		-- the single ShopStand sits at the Item Shop's spot
		local spotName = if name == Constants.SHOP_STAND then Constants.SHOP_STAND_ITEM else name
		local spot = WorldLayout and WorldLayout.PROP_SPOTS and WorldLayout.PROP_SPOTS[spotName]
		if not model and build and spot then
			local ok, result = pcall(build)
			if ok and typeof(result) == "Instance" and result:IsA("Model") then
				model = result
				result:PivotTo(
					CFrame.new(spot.pos[1], spot.pos[2], spot.pos[3]) * CFrame.Angles(0, math.rad(spot.yaw), 0)
				)
				anchorAll(result)
				result.Parent = parent
			else
				warn(`[Server] Props for {name} failed: {result}`)
			end
		end
		if model then
			anchorAll(model)
			-- Slime Ranch skin (server/MeshSwap) once the kit mesh is uploaded.
			local mesh = WorldLayout and WorldLayout.PROP_MESHES and WorldLayout.PROP_MESHES[spotName]
			if mesh and model:GetAttribute("MeshAsset") == nil then
				model:SetAttribute("MeshAsset", mesh)
			end
			local skin = model:GetAttribute("MeshAsset")
			if typeof(skin) == "string" and model:GetAttribute("MeshSize") == nil then
				local size = WorldProps.meshSize(WorldLayout, skin, model)
				if size then
					model:SetAttribute("MeshSize", size)
				end
			end
			placed[name] = model
		end
	end
	return placed
end

local function addPrompt(part: Instance?, def: { name: string, objectText: string, actionText: string })
	if not part or not part:IsA("BasePart") or part:FindFirstChild(def.name) then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = def.name
	prompt.ObjectText = def.objectText
	prompt.ActionText = def.actionText
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 12
	prompt.Parent = part
end

local function counterOf(stand: Model?): BasePart?
	local counter = stand and (stand:FindFirstChild("Counter") or stand.PrimaryPart)
	return if counter and counter:IsA("BasePart") then counter else nil
end

-- The Counter of the stand of `shopId` ("ItemShop" | "UpgradeShop"), or nil while it is not placed.
function WorldProps.shopCounter(shopId: string): BasePart?
	local shop = Shops.shop(shopId)
	return counterOf(if shop then placed[shop.stand] else nil)
end

-- "Open Shop" on the ShopStand's Counter and "Talk" on the TutorialNpc's
-- root (CONTRACT.md §5.3). With FEATURES.WorldShops each stand gets its own ShopPrompt plus the ShopId
-- attribute, and `onShop(player, shopId)` runs on the server when it is triggered (CONTRACT.md §27.3).
-- Call after place().
function WorldProps.addShopPrompts(onShop: ((player: Player, shopId: string) -> ())?)
	if WorldProps.worldShops() then
		for _, shopId in Shops.ORDER do
			local stand = placed[(Shops.shop(shopId) :: Shops.Shop).stand]
			local counter = counterOf(stand)
			if stand and counter then
				stand:SetAttribute(Constants.SHOP_ID_ATTRIBUTE, shopId)
				addPrompt(counter, WorldProps.SHOP_PROMPTS[shopId])
				local prompt = counter:FindFirstChild(Constants.SHOP_PROMPT_NAME)
				if onShop and prompt and prompt:IsA("ProximityPrompt") then
					prompt.Triggered:Connect(function(player: Player)
						onShop(player, shopId)
					end)
				end
			end
		end
	else
		addPrompt(counterOf(placed[Constants.SHOP_STAND]), WorldProps.SHOP_PROMPT)
	end
	local npc = placed[Constants.TUTORIAL_NPC]
	addPrompt(npc and (npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart), WorldProps.GUIDE_PROMPT)
end

-- Writes Leaderboard.boardRows into the board's Rows frame (in place when the
-- row count is unchanged, CONTRACT.md §5.3).
function WorldProps.fillBoard(board: any)
	local model = placed[Constants.LEADERBOARD_BOARD]
	local container = model and model:FindFirstChild("Rows", true)
	if not model or not container then
		return
	end
	local rows = Leaderboard.boardRows(board)
	local same = true
	local count = 0
	for _, child in container:GetChildren() do
		if child:IsA("Frame") then
			count += 1
		end
	end
	for k = 1, #rows do
		local frame = container:FindFirstChild(`Row_{k}`)
		if
			not (
				frame
				and frame:FindFirstChild("Rank")
				and frame:FindFirstChild("Name")
				and frame:FindFirstChild("Value")
			)
		then
			same = false
		end
	end
	if not same or count ~= #rows then
		local Props = visual("Props")
		if not Props then
			return
		end
		local blanks = {}
		for k = 1, #rows do
			table.insert(blanks, { rank = k, name = "", value = 0 })
		end
		Props.fillLeaderboard(model, blanks)
	end
	for k, row in rows do
		local frame = container:FindFirstChild(`Row_{k}`)
		if frame then
			for field, text in { Rank = row.rank, Name = row.name, Value = row.value } :: { [string]: string } do
				local label = frame:FindFirstChild(field)
				if label and label:IsA("TextLabel") and label.Text ~= text then
					label.Text = text
				end
			end
		end
	end
end

-- A new Speed Coil tool (Props.speedCoil), or nil without Visuals.
function WorldProps.speedCoil(): Tool?
	local Props = visual("Props")
	if not Props then
		return nil
	end
	local ok, tool = pcall(Props.speedCoil)
	if ok and typeof(tool) == "Instance" and tool:IsA("Tool") then
		tool.Name = Constants.SPEED_COIL_TOOL
		return tool
	end
	return nil
end

return WorldProps
