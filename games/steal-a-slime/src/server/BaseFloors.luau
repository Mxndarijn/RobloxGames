--!strict
--[[
	BaseFloors (Roblox adapter, owner: Phoenix)

	Keeps each plot's upper floors (CONTRACT.md §5.3) in step with its owner's pads: floor f (2..#BASE_FLOORS)
	stands while Economy.floorsShown(padsUnlocked) >= f (0 pads on a free plot), and goes when that stops (the owner
	left). `ctx.build` adds a floor's instances (WorldBuilder.buildFloor), `ctx.meshes` gives their slots the kit
	meshes (MeshSwap.applyUnder, run in its own thread because it yields). Removing a floor parks the BuyPadPrompt
	on floor 1 first, so the prompt record never points at a destroyed pad. A jar's lid (parts with the JarLid
	attribute) is hidden and non-colliding while the jar above it stands. Each new jar's DropHatch gets the
	DropPrompt (anyone; `ctx.drop` runs the rule, Actions.useDropTube). Holds no gameplay rules.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Economy = require(ReplicatedStorage.Shared.Economy)
local PlotLookup = require(script.Parent.PlotLookup)

local BaseFloors = {}

export type Context = {
	build: (plot: Instance, plotIndex: number, floor: number) -> { Instance },
	meshes: (instances: { Instance }) -> (),
	drop: ((player: Player, plotIndex: number) -> ())?,
}

BaseFloors.DROP_ACTION = "Drop down"
BaseFloors.DROP_OBJECT = "Goo tube"

-- The DropPrompt on every DropHatch in `instances` (a freshly built floor).
local function addDropPrompts(instances: { Instance }, plotIndex: number, ctx: Context)
	local drop = ctx.drop
	if not drop then
		return
	end
	for _, root in instances do
		for _, d in root:GetDescendants() do
			if d.Name == "DropHatch" and d:IsA("BasePart") and not d:FindFirstChild(Constants.DROP_PROMPT_NAME) then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = Constants.DROP_PROMPT_NAME
				prompt.ActionText = BaseFloors.DROP_ACTION
				prompt.ObjectText = BaseFloors.DROP_OBJECT
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				prompt.RequiresLineOfSight = false
				prompt.Parent = d
				prompt.Triggered:Connect(function(player: Player)
					drop(player, plotIndex)
				end)
			end
		end
	end
end

local function removeFloor(plot: Instance, floor: number)
	local park =
		PlotLookup.byIndex(plot, Constants.PAD_INDEX_ATTRIBUTE, Config.PADS_START + 1, `Pad_{Config.PADS_START + 1}`)
	for j = (floor - 1) * Config.PADS_PER_FLOOR + 1, floor * Config.PADS_PER_FLOOR do
		local pad = PlotLookup.byIndex(plot, Constants.PAD_INDEX_ATTRIBUTE, j, `Pad_{j}`)
		if pad then
			local prompt = pad:FindFirstChild(Constants.BUY_PAD_PROMPT_NAME)
			if prompt and park then
				prompt.Parent = park
			end
			pad:Destroy()
		end
	end
	local model = plot:FindFirstChild(`Floor_{floor}`)
	if model then
		model:Destroy()
	end
end

-- Every lid of the plot: shown and solid only while it is the top jar's (no Floor_<n + 1> above it).
local function setLids(plot: Instance)
	for _, d in plot:GetDescendants() do
		local n = d:GetAttribute("JarLid")
		if typeof(n) == "number" and d:IsA("BasePart") then
			local covered = plot:FindFirstChild(`Floor_{n + 1}`) ~= nil
			d.Transparency = if covered then 1 else 0
			d.CanCollide = not covered
			d.CanQuery = not covered
		end
	end
end

-- Builds or removes plot `plotIndex`'s upper floors for an owner with `padsUnlocked` pads (0 = free plot).
function BaseFloors.sync(plot: Instance, plotIndex: number, padsUnlocked: number, ctx: Context)
	local shown = if padsUnlocked > 0 then Economy.floorsShown(padsUnlocked) else 1
	local changed = false
	for floor = 2, #Config.BASE_FLOORS do
		local present = plot:FindFirstChild(`Floor_{floor}`) ~= nil
		if floor <= shown and not present then
			local built = ctx.build(plot, plotIndex, floor)
			addDropPrompts(built, plotIndex, ctx)
			task.spawn(ctx.meshes, built)
			changed = true
		elseif floor > shown and present then
			removeFloor(plot, floor)
			changed = true
		end
	end
	if changed then
		setLids(plot)
	end
end

return BaseFloors
