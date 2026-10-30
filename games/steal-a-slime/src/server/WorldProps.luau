--!strict
--[[
	WorldProps (Roblox adapter)

	Places the world props from Archer's ReplicatedStorage.Visuals.Props at
	WorldLayout.PROP_SPOTS under workspace.Map (CONTRACT.md §5.3):
	ItemShopStand and UpgradeShopStand (each with its own ShopPrompt on Counter and ShopId attribute,
	CONTRACT.md §27), the ExclusiveShopStand jar (Props.exclusiveJar, its
	ShopPrompt opens the Exclusive Shop panel, contract/exclusive-shop.md §7), the five Hall of Fame boards
	(Leaderboards.BOARDS, each tagged with its LeaderboardStat),
	ProfessorGoo, TutorialNpc (with the "Talk" prompt) and the Upcoming Events board (WorldLayout.EVENT_BOARD,
	filled by EventBoardView). A prop that already exists anywhere under workspace
	(e.g. a static copy) is reused. Every part is anchored. A spot with a `scale` scales the built Model.
	Also writes each board's rows and builds the Speed Coil tool. Holds no gameplay rules; a missing Visuals module just means no props.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local Leaderboard = require(script.Parent.Leaderboard)
local Leaderboards = require(ReplicatedStorage.Shared.Leaderboards)
local Shops = require(ReplicatedStorage.Shared.Shops)

local WorldProps = {}

-- One ShopPrompt per stand (CONTRACT.md §27.3); the server opens the shop on Triggered.
WorldProps.SHOP_PROMPTS = table.freeze({
	ItemShop = table.freeze({
		name = Constants.SHOP_PROMPT_NAME,
		objectText = "Item Shop",
		actionText = "Browse items",
	}),
	UpgradeShop = table.freeze({
		name = Constants.SHOP_PROMPT_NAME,
		objectText = "Upgrade Shop",
		actionText = "Browse upgrades",
	}),
	[Constants.EXCLUSIVE_SHOP_ID] = table.freeze({
		name = Constants.SHOP_PROMPT_NAME,
		objectText = "Exclusive Shop",
		actionText = "Browse exclusives",
	}),
})
-- The stand of each shop that has a ShopPrompt: the cash shops (Shops.ORDER) and the Exclusive Shop's jar, which
-- is no cash shop (its panel buys through MarketplaceService) but opens and closes the same way.
local function standOf(shopId: string): string?
	if shopId == Constants.EXCLUSIVE_SHOP_ID then
		return Constants.SHOP_STAND_EXCLUSIVE
	end
	local shop = Shops.shop(shopId)
	return if shop then shop.stand else nil
end
-- Professor Goo's prompt only opens the client's Leaderboards panel (the UI listens for PromptTriggered).
WorldProps.LEADERBOARD_PROMPT = table.freeze({
	name = Constants.LEADERBOARD_PROMPT_NAME,
	objectText = "Professor Goo",
	actionText = "View leaderboards",
})
WorldProps.LEADERBOARD_CLICK_DISTANCE = 32
-- The Guide's prompt opens a client menu (the UI listens for PromptTriggered); the server only counts it for the
-- tutorial's Guide step.
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

-- A shop stand builder: Props.shopStand with the skin, sign and model name of `shopId` (Props.STAND_STYLES).
local function standBuilder(Props: any, shopId: string): (() -> Instance)?
	if not (Props and Props.shopStand) then
		return nil
	end
	return function()
		return Props.shopStand(shopId)
	end
end

-- Places any missing prop. Returns the props by name (missing ones are absent).
function WorldProps.place(): { [string]: Model }
	local Props = visual("Props")
	local WorldLayout = visual("WorldLayout")
	local builders: { [string]: any } = {
		[Constants.TUTORIAL_NPC] = Props and Props.tutorialNpc,
		[Constants.PROFESSOR_GOO] = Props and Props.professorGoo,
		[Constants.HALL_ARCH] = Props and Props.hallArch,
		[Constants.OBBY_ARCH] = Props and Props.obbyArch,
	}
	for _, def in Leaderboards.BOARDS do
		builders[def.model] = if Props and Props.leaderboardBoard
			then function()
				return Props.leaderboardBoard(def)
			end
			else nil
	end
	-- The Upcoming Events wall: a Hall of Fame board that server/EventBoardView fills with its cards.
	local events = WorldLayout and WorldLayout.EVENT_BOARD
	if events and Props and Props.leaderboardBoard then
		builders[events.model] = function()
			return Props.leaderboardBoard({ model = events.model, title = "UPCOMING EVENTS", accent = { 120, 90, 220 } })
		end
	end
	builders[Constants.SHOP_STAND_ITEM] = standBuilder(Props, "ItemShop")
	builders[Constants.SHOP_STAND_UPGRADE] = standBuilder(Props, "UpgradeShop")
	if Props and Props.exclusiveJar then
		builders[Constants.SHOP_STAND_EXCLUSIVE] = Props.exclusiveJar
	end
	local parent = workspace:FindFirstChild(Constants.MAP_FOLDER) or workspace
	for name, build in builders do
		local model = findModel(name)
		local spot = WorldLayout and WorldLayout.PROP_SPOTS and WorldLayout.PROP_SPOTS[name]
		if not model and build and spot then
			local ok, result = pcall(build)
			if ok and typeof(result) == "Instance" and result:IsA("Model") then
				model = result
				if type(spot.scale) == "number" and spot.scale ~= 1 then
					result:ScaleTo(spot.scale)
				end
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
			local board = Leaderboards.forModel(name)
			if board then
				model:SetAttribute(Constants.LEADERBOARD_STAT_ATTRIBUTE, board.stat)
			end
			-- Slime Ranch skin (server/MeshSwap) once the kit mesh is uploaded; each shop stand has its own.
			local stand = WorldLayout and WorldLayout.SHOP_STANDS and WorldLayout.SHOP_STANDS[name]
			local mesh = if stand
				then stand.mesh
				else WorldLayout and WorldLayout.PROP_MESHES and WorldLayout.PROP_MESHES[name]
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

-- The Counter of the stand of `shopId` ("ItemShop" | "UpgradeShop" | "ExclusiveShop"), or nil while it is not placed.
-- Where placed prop `name` stands (its pivot), nil when it was not placed.
function WorldProps.position(name: string): Vector3?
	local model = placed[name]
	return if model and model.Parent then model:GetPivot().Position else nil
end

function WorldProps.shopCounter(shopId: string): BasePart?
	local stand = standOf(shopId)
	return counterOf(if stand then placed[stand] else nil)
end

-- Each stand's ShopPrompt on its Counter plus the ShopId attribute, `onShop(player, shopId)` running on the server
-- when it is triggered (CONTRACT.md §27.3), and "Talk" on the TutorialNpc's root (CONTRACT.md §5.3).
-- Call after place().
function WorldProps.addShopPrompts(
	onShop: ((player: Player, shopId: string) -> ())?,
	onGuide: ((player: Player) -> ())?
)
	local shopIds = table.clone(Shops.ORDER)
	table.insert(shopIds, Constants.EXCLUSIVE_SHOP_ID)
	for _, shopId in shopIds do
		local name = standOf(shopId)
		local stand = if name then placed[name] else nil
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
	local npc = placed[Constants.TUTORIAL_NPC]
	local npcRoot = npc and (npc:FindFirstChild("HumanoidRootPart") or npc.PrimaryPart)
	addPrompt(npcRoot, WorldProps.GUIDE_PROMPT)
	local guide = npcRoot and npcRoot:FindFirstChild(Constants.GUIDE_PROMPT_NAME)
	if onGuide and guide and guide:IsA("ProximityPrompt") then
		guide.Triggered:Connect(onGuide)
	end
	-- Professor Goo: "View leaderboards" (E / tap) and a ClickDetector for a click or right-click; both only open
	-- the client's Leaderboards panel.
	local professor = placed[Constants.PROFESSOR_GOO]
	addPrompt(
		professor and (professor:FindFirstChild("HumanoidRootPart") or professor.PrimaryPart),
		WorldProps.LEADERBOARD_PROMPT
	)
	if professor and not professor:FindFirstChild(Constants.LEADERBOARD_CLICK_NAME) then
		local click = Instance.new("ClickDetector")
		click.Name = Constants.LEADERBOARD_CLICK_NAME
		click.MaxActivationDistance = WorldProps.LEADERBOARD_CLICK_DISTANCE
		click.Parent = professor
	end
end

-- Writes Leaderboard.boardRows into the Rows frame of the world board of `board.stat` (in place when the row
-- count is unchanged, CONTRACT.md §5.3). A nil board blanks the podium board.
function WorldProps.fillBoard(board: any)
	local def = Leaderboards.get(type(board) == "table" and board.stat) or Leaderboards.podium()
	local model = placed[def.model]
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
