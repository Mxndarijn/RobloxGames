--!strict
--[[
	TutorialArrow (VisualsClient module)

	Client-only Beam (Props.tutorialArrow) from the local character's
	HumanoidRootPart to the target of the current tutorial step (CONTRACT.md
	§8.3): Grab Map.Volcano.Crater, Deposit own HomeZone, Lock own LockButton,
	BuyPad own pad carrying BuyPadPrompt, Merge own MergeVat, Steal another
	owned plot's Base, Rebirth / nil none. Keyed on the Player attribute
	TutorialStepId; falls back to TutorialStep via TutorialProgress.STEPS.
	Re-checked every POLL seconds; reads attributes only.

	Look: Neon chevrons (Props.tutorialChevrons, under the camera) flow along
	the beam's curve and a big marker chevron bobs over the target; the beam
	itself carries moving bright bands (Props.arrowBands). Both animate on
	RenderStepped, FLOW chevron spacings per second.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local Props = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("Props"))
local TutorialProgress = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TutorialProgress"))

local TutorialArrow = {}

TutorialArrow.POLL = 0.5
TutorialArrow.FLOW = 0.8
TutorialArrow.OWN_PLOT_TARGETS = table.freeze({ Deposit = "HomeZone", Lock = "LockButton", Merge = "MergeVat" })

local function part(instance: Instance?): BasePart?
	if instance and instance:IsA("BasePart") then
		return instance
	end
	return nil
end

-- The own plot's Pad_<j> holding an enabled BuyPadPrompt (nil when all pads are bought).
local function buyPad(plot: Instance): BasePart?
	for _, child in plot:GetChildren() do
		local prompt = child:FindFirstChild(Constants.BUY_PAD_PROMPT_NAME)
		if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
			return part(child)
		end
	end
	return nil
end

local function stepId(player: Player): string?
	local id = player:GetAttribute(Constants.TUTORIAL_STEP_ID_ATTRIBUTE)
	if type(id) == "string" then
		return id
	end
	local step = player:GetAttribute(Constants.TUTORIAL_STEP_ATTRIBUTE)
	return if type(step) == "number" then TutorialProgress.STEPS[step] else nil
end

local function target(id: string?, userId: number): BasePart?
	if id == "Grab" then
		local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
		local volcano = map and map:FindFirstChild("Volcano")
		return part(volcano and volcano:FindFirstChild("Crater"))
	end
	local plots = workspace:FindFirstChild(Constants.PLOTS_FOLDER)
	if not plots or not id then
		return nil
	end
	local own = TutorialArrow.OWN_PLOT_TARGETS[id]
	for _, plot in plots:GetChildren() do
		local owner = plot:GetAttribute("OwnerUserId")
		if owner == userId and id == "BuyPad" then
			return buyPad(plot)
		elseif own and owner == userId then
			return part(plot:FindFirstChild(own))
		elseif id == "Steal" and type(owner) == "number" and owner ~= 0 and owner ~= userId then
			return part(plot:FindFirstChild("Base"))
		end
	end
	return nil
end

function TutorialArrow.start()
	local player = Players.LocalPlayer
	local current: { Instance }? = nil
	local beam: Beam? = nil
	local chevrons: Model? = nil
	local from: BasePart? = nil
	local to: BasePart? = nil
	local tip: Attachment? = nil
	local function clear()
		if current then
			for _, instance in current do
				instance:Destroy()
			end
		end
		current, from, to, beam, chevrons, tip = nil, nil, nil, nil, nil, nil
	end
	local function animate(now: number)
		local camera = workspace.CurrentCamera
		if not (beam and chevrons and camera and beam.Parent) then
			return
		end
		if tip and from and to then
			Props.arrowAim(tip, from, to) -- the capped end follows the character / target
		end
		local phase = (now * TutorialArrow.FLOW) % 1
		Props.placeChevrons(chevrons, Props.arrowCurve(beam), phase, camera.CFrame.Position, now)
		beam.Transparency = Props.arrowBands(phase)
	end
	local function update()
		local character = player.Character
		local root = part(character and character:FindFirstChild("HumanoidRootPart"))
		local goal = target(stepId(player), player.UserId)
		if not root or not goal then
			clear()
			return
		end
		-- rebuild when the target crosses the cap distance (the end attachment lives on the goal when near, on the root when far)
		local near = (goal.Position - root.Position).Magnitude <= Props.ARROW_MAX_LENGTH
		if
			root == from
			and goal == to
			and current
			and current[1].Parent
			and (tip ~= nil and (tip.Parent == goal) == near)
		then
			return
		end
		clear()
		local newBeam, a0, a1 = Props.tutorialArrow(root, goal)
		local newChevrons = Props.tutorialChevrons()
		newChevrons.Parent = workspace.CurrentCamera or workspace
		current, from, to = { newBeam, a0, a1, newChevrons }, root, goal
		beam, chevrons, tip = newBeam, newChevrons, a1
		animate(os.clock())
	end
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(animate, os.clock())
		if not ok then
			warn(`[VisualsClient] tutorial arrow: {err}`)
			clear()
		end
	end)
	task.spawn(function()
		while true do
			local ok, err = pcall(update)
			if not ok then
				warn(`[VisualsClient] tutorial arrow: {err}`)
				clear()
			end
			task.wait(TutorialArrow.POLL)
		end
	end)
end

return TutorialArrow
