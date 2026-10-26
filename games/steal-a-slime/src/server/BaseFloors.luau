--!strict
--[[
	BaseFloors (Roblox adapter, owner: Phoenix)

	Keeps each plot's upper floors (CONTRACT.md §5.3) in step with its owner's pads: floor f (2..#BASE_FLOORS)
	stands while Economy.floorsShown(padsUnlocked) >= f (0 pads on a free plot), and goes when that stops (the owner
	left). `ctx.build` adds a floor's instances (WorldBuilder.buildFloor), `ctx.meshes` gives their slots the kit
	meshes (MeshSwap.applyUnder, run in its own thread because it yields). Removing a floor parks the BuyPadPrompt
	on floor 1 first, so the prompt record never points at a destroyed pad, and sets anyone standing in that jar
	down on floor 1 (straight below, on the plot's Base) so nobody falls through the tower. A jar's lid (parts with the JarLid
	attribute) is hidden and non-colliding while the jar above it stands. Only the top jar's DropHatch is open (shown,
	its DropPrompt on): the tube is taken from the top of the tower, never from a jar in between. Each new jar's DropHatch gets the
	DropPrompt (`ctx.drop` runs the rule, Actions.useDropTube: the owner, not while carrying). Holds no gameplay rules.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseShapes = require(ReplicatedStorage.Visuals.BaseShapes)
local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local Economy = require(ReplicatedStorage.Shared.Economy)
local PlotLookup = require(script.Parent.PlotLookup)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)

local BaseFloors = {}

-- `base` is the plot's PlotBase attribute (CONTRACT.md §44; nil = the goo jar tower).
export type Context = {
	build: (plot: Instance, plotIndex: number, floor: number, base: string?) -> { Instance },
	-- the roof colliders on the top floor (WorldBuilder.buildTop); nil leaves the roof alone
	top: ((plot: Instance, plotIndex: number, floor: number, base: string?) -> Instance)?,
	meshes: (instances: { Instance }) -> (),
	drop: ((player: Player, plotIndex: number) -> ())?,
}

BaseFloors.DROP_ACTION = "Drop down"
BaseFloors.DROP_OBJECT = "Goo tube"
-- The DropPrompt sits on an Attachment this far in from the hatch (toward the jar's centre): its line of sight is
-- measured to there, clear of the glass the hatch sits in, so a player inside sees it and the DropShield outside the
-- glass hides it from anyone on the ledge.
BaseFloors.DROP_PROMPT_INSET = 1.5

-- The DropPrompt on every DropHatch in `instances` (a freshly built floor).
local function addDropPrompts(instances: { Instance }, plotIndex: number, ctx: Context)
	local drop = ctx.drop
	if not drop then
		return
	end
	for _, root in instances do
		for _, d in root:GetDescendants() do
			if
				d.Name == "DropHatch"
				and d:IsA("BasePart")
				and not d:FindFirstChild(Constants.DROP_PROMPT_NAME, true)
			then
				-- the hatch's local +Z points out of the jar
				local anchor = Instance.new("Attachment")
				anchor.Name = "DropPromptAt"
				anchor.Position = Vector3.new(0, 0, -BaseFloors.DROP_PROMPT_INSET)
				anchor.Parent = d
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = Constants.DROP_PROMPT_NAME
				prompt.ActionText = BaseFloors.DROP_ACTION
				prompt.ObjectText = BaseFloors.DROP_OBJECT
				prompt.KeyboardKeyCode = Enum.KeyCode.E
				-- the DropShield outside the glass blocks it, so a player outside the top jar does not see it
				prompt.RequiresLineOfSight = true
				prompt.Parent = anchor
				prompt.Triggered:Connect(function(player: Player)
					drop(player, plotIndex)
				end)
			end
		end
	end
end

-- The plot's base id (the PlotBase attribute, CONTRACT.md §44), nil for the jar.
local function baseOf(plot: Instance): string?
	local base = plot:GetAttribute(Constants.PLOT_BASE_ATTRIBUTE)
	return if type(base) == "string" then base else nil
end

-- Characters standing in floor `floor` (above its deck, inside its walls) are set down on the plot's Base straight
-- below, just before that floor goes.
local function evacuate(plot: Instance, floor: number)
	local base = plot:FindFirstChild("Base")
	if not (base and base:IsA("BasePart")) then
		return
	end
	local floorY = base.Position.Y + base.Size.Y / 2
	local deckY = floorY + WorldLayout.floorTop(floor) - WorldLayout.floorTop(1)
	local shape = BaseShapes.get(baseOf(plot))
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			local p = base.CFrame:PointToObjectSpace(root.Position)
			-- one stud of slack past the walls
			if root.Position.Y >= deckY - 1 and shape.inside(floor, p.X, p.Z, 1) then
				local at = root.Position
				character:PivotTo(CFrame.new(at.X, floorY + 3, at.Z) * root.CFrame.Rotation)
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end
end

local function removeFloor(plot: Instance, floor: number)
	evacuate(plot, floor)
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

-- Every lid of the plot: solid only while it is the top jar's (no Floor_<n + 1> above it); its look is the jar trim
-- mesh. Every jar look with JarFloor / JarShow: "top" shows only while no jar stands on jar n, "covered" only while
-- one does (JarHidden, and the swapped Mesh's transparency).
local function setLids(plot: Instance)
	local top = 1
	for f = 2, #Config.BASE_FLOORS do
		if plot:FindFirstChild(`Floor_{f}`) then
			top = f
		end
	end
	for f = 2, #Config.BASE_FLOORS do
		local model = plot:FindFirstChild(`Floor_{f}`)
		local hatch = model and model:FindFirstChild("DropHatch")
		if hatch and hatch:IsA("BasePart") then
			local open = f == top
			hatch.Transparency = if open then 0 else 1
			hatch.CanCollide = open
			local prompt = hatch:FindFirstChild(Constants.DROP_PROMPT_NAME, true)
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Enabled = open
			end
		end
	end
	for _, d in plot:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local n = d:GetAttribute("JarLid")
		if typeof(n) == "number" then
			-- the lid never collides (the roof is TopColliders, shaped like the glass); queryable on the top jar
			local covered = plot:FindFirstChild(`Floor_{n + 1}`) ~= nil
			d.CanCollide = false
			d.CanQuery = not covered
		end
		local f, show = d:GetAttribute("JarFloor"), d:GetAttribute("JarShow")
		if typeof(f) == "number" and (show == "top" or show == "covered") then
			local covered = plot:FindFirstChild(`Floor_{f + 1}`) ~= nil
			local hidden = (show == "top") == covered
			d:SetAttribute("JarHidden", hidden)
			if d:GetAttribute("JarCollide") == true then
				-- a collider that only stands while its jar is shown (the top of the stair)
				d.CanCollide = not hidden
				d.CanQuery = not hidden
			end
			local mesh = d:FindFirstChild("Mesh")
			if mesh and mesh:IsA("BasePart") then
				local clear = d:GetAttribute("MeshTransparency")
				mesh.Transparency = if hidden then 1 elseif typeof(clear) == "number" then clear else 0
			end
			-- a plot skin's companion on the slot (the mascot's hat, MeshSwap) shows with it
			local extra = d:FindFirstChild("ThemeExtra")
			if extra and extra:IsA("BasePart") then
				extra.Transparency = if hidden then 1 else 0
			end
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
			local built = ctx.build(plot, plotIndex, floor, baseOf(plot))
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
	-- one roof per plot, on its top jar (also the first time a plot is seen: jar 1)
	if ctx.top then
		local top = 1
		for floor = 2, #Config.BASE_FLOORS do
			if plot:FindFirstChild(`Floor_{floor}`) then
				top = floor
			end
		end
		local roof = plot:FindFirstChild("TopColliders")
		if not roof or roof:GetAttribute("TopFloor") ~= top then
			ctx.top(plot, plotIndex, top, baseOf(plot))
		end
	end
end

-- Removes every upper floor and the roof colliders (a base swap, server/BaseShapeSwap): people up there are set down
-- on floor 1 first and the BuyPadPrompt is parked on floor 1, as when a floor goes.
function BaseFloors.clear(plot: Instance)
	for floor = #Config.BASE_FLOORS, 2, -1 do
		if plot:FindFirstChild(`Floor_{floor}`) then
			removeFloor(plot, floor)
		end
	end
	local roof = plot:FindFirstChild("TopColliders")
	if roof then
		roof:Destroy()
	end
end

return BaseFloors
