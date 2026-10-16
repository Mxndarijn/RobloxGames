--!strict
--[[
	WorldProps (Roblox adapter)

	Places the world props from Archer's ReplicatedStorage.Visuals.Props at
	WorldLayout.PROP_SPOTS under workspace.Map (CONTRACT.md §5.3):
	ShopStand (with the two shop ProximityPrompts on Counter),
	LeaderboardBoard and TutorialNpc. A prop that already exists anywhere
	under workspace (e.g. a static copy) is reused. Every part is anchored.
	Also writes the leaderboard rows into the board and builds the Speed Coil
	tool. Holds no gameplay rules; a missing Visuals module just means no props.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Economy = require(ReplicatedStorage.Shared.Economy)
local Leaderboard = require(script.Parent.Leaderboard)

local WorldProps = {}

-- Shop prompts on the ShopStand's Counter: name -> Request action.
WorldProps.SHOP_PROMPTS = table.freeze({
	{
		name = "ShopPrompt_SpeedCoil",
		action = "BuySpeedCoil",
		text = `Speed Coil ${Economy.formatNumber(Config.SPEED_COIL_PRICE)}`,
		key = Enum.KeyCode.E,
	},
	{ name = "ShopPrompt_LockUpgrade", action = "BuyLockUpgrade", text = "Longer locks", key = Enum.KeyCode.F },
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

-- Places any missing prop. Returns the props by name (missing ones are absent).
function WorldProps.place(): { [string]: Model }
	local Props = visual("Props")
	local WorldLayout = visual("WorldLayout")
	local builders = {
		[Constants.SHOP_STAND] = Props and Props.shopStand,
		[Constants.LEADERBOARD_BOARD] = Props and Props.leaderboardBoard,
		[Constants.TUTORIAL_NPC] = Props and Props.tutorialNpc,
	}
	local parent = workspace:FindFirstChild(Constants.MAP_FOLDER) or workspace
	for name, build in builders do
		local model = findModel(name)
		local spot = WorldLayout and WorldLayout.PROP_SPOTS and WorldLayout.PROP_SPOTS[name]
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
			local mesh = WorldLayout and WorldLayout.PROP_MESHES and WorldLayout.PROP_MESHES[name]
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

-- Adds the shop prompts to the ShopStand's Counter. `onTrigger(player, action)`.
function WorldProps.addShopPrompts(onTrigger: (Player, string) -> ())
	local stand = placed[Constants.SHOP_STAND]
	local counter = stand and (stand:FindFirstChild("Counter") or stand.PrimaryPart)
	if not counter or not counter:IsA("BasePart") then
		return
	end
	for _, def in WorldProps.SHOP_PROMPTS do
		if not counter:FindFirstChild(def.name) then
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = def.name
			prompt.ObjectText = "Shop"
			prompt.ActionText = def.text
			prompt.KeyboardKeyCode = def.key
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = 12
			prompt.Parent = counter
			local action = def.action
			prompt.Triggered:Connect(function(player: Player)
				onTrigger(player, action)
			end)
		end
	end
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
