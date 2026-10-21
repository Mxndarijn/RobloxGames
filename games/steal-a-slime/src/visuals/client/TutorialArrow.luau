--!strict
--[[
	TutorialArrow (VisualsClient module)

	Leads the local player to the target of the current tutorial step
	(CONTRACT.md §8.3) with the shared ground guide (Lib.guide.GuideView):
	neon chevrons on the ground, a ring and a labelled marker on the target,
	an outline and a screen-edge pointer.

	  Grab     the closest wild slime the player can afford, else the
	           cheapest one ("Need $X") (TutorialTargets.grab)
	  Deposit  own HomeZone          Lock   own LockButton
	  BuyPad   closest own pad with an enabled BuyPadPrompt
	  Merge    own MergeVat
	  Steal    closest slime with an enabled steal prompt on another
	           player's unlocked plot
	  Rebirth  none (ui/Hint rings the Rebirth menu button)

	Keyed on the Player attribute TutorialStepId (falls back to TutorialStep
	via TutorialProgress.STEPS). The target is re-picked every POLL seconds;
	GuideTarget keeps the current pick unless another is clearly closer.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local TutorialProgress = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TutorialProgress"))
local TutorialTargets = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("TutorialTargets"))
local Guide = ReplicatedStorage:WaitForChild("Lib"):WaitForChild("guide")
local GuideTarget = require(Guide:WaitForChild("GuideTarget"))
local GuideView = require(Guide:WaitForChild("GuideView"))

local TutorialArrow = {}

TutorialArrow.POLL = 0.25
TutorialArrow.OWN_PLOT_TARGETS = table.freeze({
	Deposit = table.freeze({ part = "HomeZone", label = "Bring it home" }),
	Lock = table.freeze({ part = "LockButton", label = "Lock base" }),
	Merge = table.freeze({ part = "MergeVat", label = "Merge" }),
})

type Choice = { target: PVInstance, key: string, label: string? }

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
	if type(id) == "string" then
		return id
	end
	local step = player:GetAttribute(Constants.TUTORIAL_STEP_ATTRIBUTE)
	return if type(step) == "number" then TutorialProgress.STEPS[step] else nil
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

local function candidate(target: PVInstance, key: string, label: string?): GuideTarget.Candidate<Choice>
	local at = target:GetPivot().Position
	return { key = key, x = at.X, z = at.Z, value = { target = target, key = key, label = label } }
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
	return if slime then { target = slime.value, key = slime.key, label = label } else nil
end

local function choose(player: Player, id: string?, from: Vector3, currentKey: string?): Choice?
	if id == "Grab" then
		return grab(player, from, currentKey)
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
				table.insert(list, candidate(part, keyOf(part), own.label))
			end
		elseif owner == player.UserId and id == "BuyPad" then
			for _, pad in plot:GetChildren() do
				local prompt = enabledPrompt(pad, Constants.BUY_PAD_PROMPT_NAME)
				if prompt and pad:IsA("PVInstance") then
					table.insert(list, candidate(pad, keyOf(pad), prompt.ActionText))
				end
			end
		elseif
			id == "Steal"
			and type(owner) == "number"
			and owner ~= 0
			and owner ~= player.UserId
			and plot:GetAttribute(Constants.PLOT_LOCKED_ATTRIBUTE) ~= true
		then
			local slimes = plot:FindFirstChild(Constants.PLOT_SLIMES_FOLDER)
			for _, model in if slimes then slimes:GetChildren() else {} do
				if model:IsA("Model") and enabledPrompt(model, Constants.GRAB_PROMPT_NAME) then
					table.insert(list, candidate(model, keyOf(model), "Steal"))
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
	local guide = GuideView.new({ getIgnore = ignoreList })
	local currentKey: string? = nil
	local running = true
	local function update()
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local choice = if root and root:IsA("BasePart")
			then choose(player, stepId(player), root.Position, currentKey)
			else nil
		currentKey = if choice then choice.key else nil
		guide:setTarget(if choice then choice.target else nil, if choice then choice.label else nil)
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
