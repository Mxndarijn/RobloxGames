--!strict
--[[
	TutorialArrow (VisualsClient module)

	Leads the local player to the target of the current tutorial step
	(contract/tutorial.md) with the shared ground guide (Lib.guide.GuideView):
	neon chevrons on the ground along a pathfinding route, a ring and a
	labelled marker on the target, an outline and a screen-edge pointer.

	  Grab         the closest wild slime the player can afford, else the
	               cheapest one ("Need $X") (TutorialTargets.grab)
	  Deposit      own HomeZone              Lock    own LockButton (the pad)
	  Leaderboard  Map.LeaderboardBoard      Guide   Map.TutorialNpc
	  BuyPad       closest own pad with an enabled BuyPadPrompt
	  Merge        own MergeVat
	  BuyItem      the closer of the Item Shop and Upgrade Shop stands

	Where the player must stand on the target (the home zone, the lock pad, a
	pad, a slime) the route ends on it; elsewhere GuideView picks a free spot
	next to the target. The walks across the plaza get a longer trail
	(FAR_TRAIL). Keyed on the Player attribute TutorialStepId. The target is
	re-picked every POLL seconds; GuideTarget keeps the current pick unless
	another is clearly closer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local ObbyLook = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("ObbyLook"))
local PlayerSettings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PlayerSettings"))
local TutorialTargets = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("TutorialTargets"))
local Guide = ReplicatedStorage:WaitForChild("Lib"):WaitForChild("guide")
local GuideTarget = require(Guide:WaitForChild("GuideTarget"))
local GuideView = require(Guide:WaitForChild("GuideView"))

local TutorialArrow = {}

TutorialArrow.POLL = 0.25
-- `standOn`: the route ends on the part itself (the player has to stand there), not next to it.
TutorialArrow.OWN_PLOT_TARGETS = table.freeze({
	Deposit = table.freeze({ part = "HomeZone", label = "Bring it home", standOn = true }),
	Lock = table.freeze({ part = "LockButton", label = "Stand here", standOn = true }),
	Merge = table.freeze({ part = "MergeVat", label = "Merge", standOn = false }),
})
-- Props under workspace.Map, by step.
TutorialArrow.MAP_TARGETS = table.freeze({
	Leaderboard = table.freeze({ { name = Constants.LEADERBOARD_BOARD, label = "Leaderboard" } }),
	Guide = table.freeze({ { name = Constants.TUTORIAL_NPC, label = "Talk to the Guide" } }),
	BuyItem = table.freeze({
		{ name = Constants.SHOP_STAND_ITEM, label = "Item Shop" },
		{ name = Constants.SHOP_STAND_UPGRADE, label = "Upgrade Shop" },
	}),
} :: { [string]: { { name: string, label: string } } })
-- Trail for the walks across the plaza; the other steps use GuideTrail's defaults.
TutorialArrow.FAR_TRAIL = table.freeze({ maxLength = 200, spacing = 5, maxCount = 40 })

-- `goal`: where the route ends when the player has to stand on the target; nil = next to it (GuideView).
type Choice = { target: PVInstance, key: string, label: string?, goal: Vector3? }

-- A stable key per Instance (two slimes can share a name).
local keys: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
local nextKey = 0
local function keyOf(instance: Instance): string
	local key = keys[instance]
	if not key then
		nextKey += 1
		key = tostring(nextKey)
		keys[instance] = key
	end
	return key
end

local function stepId(player: Player): string?
	local id = player:GetAttribute(Constants.TUTORIAL_STEP_ID_ATTRIBUTE)
	return if type(id) == "string" then id else nil
end

local function cash(player: Player): number
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Cash")
	return if value and value:IsA("ValueBase") then tonumber((value :: any).Value) or 0 else 0
end

local function enabledPrompt(model: Instance, name: string): ProximityPrompt?
	local prompt = model:FindFirstChild(name, true)
	return if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then prompt else nil
end

local function closest(list: { GuideTarget.Candidate<Choice> }, from: Vector3, currentKey: string?): Choice?
	local picked = GuideTarget.pick(list, { x = from.X, z = from.Z }, currentKey)
	return if picked then picked.value else nil
end

local function candidate(
	target: PVInstance,
	key: string,
	label: string?,
	standOn: boolean?
): GuideTarget.Candidate<Choice>
	local at = target:GetPivot().Position
	local goal = if standOn then at else nil
	return { key = key, x = at.X, z = at.Z, value = { target = target, key = key, label = label, goal = goal } }
end

local function grab(player: Player, from: Vector3, currentKey: string?): Choice?
	local folder = workspace:FindFirstChild(Constants.WILD_FOLDER)
	if not folder then
		return nil
	end
	local wild: { TutorialTargets.Wild } = {}
	for _, model in folder:GetChildren() do
		if
			model:IsA("Model")
			and model:GetAttribute(Constants.RIDING_ATTRIBUTE) ~= true
			and enabledPrompt(model, Constants.GRAB_PROMPT_NAME)
		then
			local at = model:GetPivot().Position
			local price = model:GetAttribute("Price")
			table.insert(wild, {
				key = keyOf(model),
				x = at.X,
				z = at.Z,
				price = if type(price) == "number" then price else 0,
				value = model,
			})
		end
	end
	local slime, label = TutorialTargets.grab(wild, cash(player), { x = from.X, z = from.Z }, currentKey)
	if not slime then
		return nil
	end
	local model = slime.value :: PVInstance
	return { target = model, key = slime.key, label = label, goal = model:GetPivot().Position }
end

local function choose(player: Player, id: string?, from: Vector3, currentKey: string?): Choice?
	if id == "Grab" then
		return grab(player, from, currentKey)
	end
	local props = if id then TutorialArrow.MAP_TARGETS[id] else nil
	if props then
		local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
		local list: { GuideTarget.Candidate<Choice> } = {}
		for _, prop in props do
			local model = map and map:FindFirstChild(prop.name, true)
			if model and model:IsA("PVInstance") then
				table.insert(list, candidate(model, keyOf(model), prop.label))
			end
		end
		return closest(list, from, currentKey)
	end
	local plots = workspace:FindFirstChild(Constants.PLOTS_FOLDER)
	if not plots or not id then
		return nil
	end
	local list: { GuideTarget.Candidate<Choice> } = {}
	local own = TutorialArrow.OWN_PLOT_TARGETS[id]
	for _, plot in plots:GetChildren() do
		local owner = plot:GetAttribute("OwnerUserId")
		if owner == player.UserId and own then
			local part = plot:FindFirstChild(own.part)
			if part and part:IsA("PVInstance") then
				table.insert(list, candidate(part, keyOf(part), own.label, own.standOn))
			end
		elseif owner == player.UserId and id == "BuyPad" then
			for _, pad in plot:GetChildren() do
				local prompt = enabledPrompt(pad, Constants.BUY_PAD_PROMPT_NAME)
				if prompt and pad:IsA("PVInstance") then
					table.insert(list, candidate(pad, keyOf(pad), prompt.ActionText, true))
				end
			end
		end
	end
	return closest(list, from, currentKey)
end

-- Folders whose models the ground trail must not land on (walking slimes, pad slimes).
local function ignoreList(): { Instance }
	local out: { Instance } = {}
	local wild = workspace:FindFirstChild(Constants.WILD_FOLDER)
	if wild then
		table.insert(out, wild)
	end
	local plots = workspace:FindFirstChild(Constants.PLOTS_FOLDER)
	for _, plot in if plots then plots:GetChildren() else {} do
		local slimes = plot:FindFirstChild(Constants.PLOT_SLIMES_FOLDER)
		if slimes then
			table.insert(out, slimes)
		end
	end
	return out
end

function TutorialArrow.start(): () -> ()
	local player = Players.LocalPlayer
	-- clearLabels: the marker floats above the target slime's own tag instead of over it.
	-- shouldPath: no pathing from the obby world, a world away from every target (ObbyLook.isInside).
	local guide = GuideView.new({
		getIgnore = ignoreList,
		clearLabels = true,
		shouldPath = function()
			return not ObbyLook.isInside()
		end,
	})
	local currentKey: string? = nil
	local far = false
	local running = true
	local function update()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		-- Settings: "Tutorial hints" off means no arrow at all.
		local id = if PlayerSettings.on(player, "tutorialHints") then stepId(player) else nil
		local choice = if root and root:IsA("BasePart") then choose(player, id, root.Position, currentKey) else nil
		currentKey = if choice then choice.key else nil
		local wantFar = id ~= nil and TutorialArrow.MAP_TARGETS[id] ~= nil
		if wantFar ~= far then
			far = wantFar
			guide:setTrail(if far then TutorialArrow.FAR_TRAIL else nil)
		end
		guide:setTarget(
			if choice then choice.target else nil,
			if choice then choice.label else nil,
			if choice then choice.goal else nil
		)
		local gui = player:FindFirstChild("PlayerGui")
		local ui = gui and gui:FindFirstChild(Constants.UI_GUI_NAME)
		-- the edge pointer hides under an open menu, and in the obby world, where every target is a world away
		guide:setEdgeHidden(
			(ui ~= nil and ui:GetAttribute(Constants.MENU_OPEN_ATTRIBUTE) == true) or ObbyLook.isInside()
		)
	end
	task.spawn(function()
		while running do
			local ok, err = pcall(update)
			if not ok then
				warn(`[VisualsClient] tutorial arrow: {err}`)
				guide:clear()
			end
			task.wait(TutorialArrow.POLL)
		end
	end)
	return function()
		running = false
		guide:destroy()
	end
end

return TutorialArrow
