--!strict
--[[
	WorldView (Roblox adapter)

	Makes workspace match the pure World:
	  * reconciles slime models against Scene.describe (ModelFactory.build,
	    wrapped by SlimeMesh for the mesh look; parenting, attributes OwnerUserId / State / Price / DespawnAt, ProximityPrompt,
	    pad placement, carry weld, volcano drop and escape-home bounce);
	  * plot attributes OwnerUserId / LockUntil / Rebirths (CONTRACT.md §5.2);
	    with FEATURES.Habitats, Pad Habitat / HabitatFrom / HabitatAt (HabitatPads)
	    and the owner / stats text on each plot Sign (PlotSigns);
	  * per-player WalkSpeed (Speed Coil when not carrying), unequipped
	    tools, the SpeedCoil tool and the `Carrying` / `TutorialStep` /
	    `SpeedCoil` attributes;
	  * the workspace `SlimeRain` / `RainActive` / `RainEndsAt` / `RainNextAt`
	    attributes;
	  * HomeZone checks (who is standing in their own plot);
	  * kill plane (Rescue): fallen characters go back to their plot / HubSpawn.
	Plots and pads are found by their PlotIndex / PadIndex attributes
	(PlotLookup), so WorldBuilder's names are only a fallback.
	Holds no gameplay rules.
]]

local InsertService = game:GetService("InsertService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Carry = require(script.Parent.Carry)
local Collection = require(ReplicatedStorage.Shared.Collection)
local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local FallbackWorld = require(script.Parent.FallbackWorld)
local Fountain = require(ReplicatedStorage.Shared.Fountain)
local FountainRide = require(ReplicatedStorage.Shared.FountainRide)
local Genome = require(ReplicatedStorage.Shared.Genome)
local GrowthLabel = require(script.Parent.GrowthLabel)
local HabitatPads = require(script.Parent.HabitatPads)
local PadStyle = require(ReplicatedStorage.Shared.PadStyle)
local ParadeLane = require(ReplicatedStorage.Shared.ParadeLane)
local Perks = require(ReplicatedStorage.Shared.Perks)
local PlayerData = require(ReplicatedStorage.Shared.PlayerData)
local PlotLockGuard = require(script.Parent.PlotLockGuard)
local PlotLookup = require(script.Parent.PlotLookup)
local PlotPrompts = require(script.Parent.PlotPrompts)
local PlotSigns = require(script.Parent.PlotSigns)
local PlotSkins = require(ReplicatedStorage.Shared.PlotSkins)
local Progression = require(ReplicatedStorage.Shared.Progression)
local PvpFun = require(script.Parent.PvpFun)
local PvpService = require(script.Parent.PvpService)
local PvpTrap = require(script.Parent.PvpTrap)
local Rescue = require(script.Parent.Rescue)
local RevengePlots = require(ReplicatedStorage.Shared.RevengePlots)
local Scene = require(script.Parent.Scene)
local SlimeMesh = require(script.Parent.SlimeMesh)
local Snapshot = require(script.Parent.Snapshot)
local StackGuard = require(script.Parent.StackGuard)
local TutorialProgress = require(ReplicatedStorage.Shared.TutorialProgress)
local World = require(script.Parent.World)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)
local WorldProps = require(script.Parent.WorldProps)

type Record = {
	model: Model,
	body: BasePart,
	prompt: ProximityPrompt,
	key: string,
	weld: WeldConstraint?,
	rideUntil: number, -- os.clock() when the fountain ride lands (0 = not riding)
}

local WorldView = {}

local records: { [string]: Record } = {}
local failed: { [string]: boolean } = {}
local modelFactory: any = nil
local plotCache: { [number]: Instance? } = {}
local habitats = HabitatPads.new() -- FEATURES.Habitats pad state (never saved)

WorldView.FALL_SECONDS = 0.3 -- a dropped slime falls to the ground
WorldView.CARRY_HEIGHT = 3 -- studs above the HumanoidRootPart

---------------------------------------------------------------------------
-- World lookup
---------------------------------------------------------------------------

function WorldView.setup()
	-- The world ships static in the place (world/*.rbxmx); WorldBuilder is idempotent and reuses it.
	-- Build before anything that yields (LoadAsset below): characters may already be spawning.
	-- Greybox only if the builder is missing or fails.
	local visuals = ReplicatedStorage:FindFirstChild("Visuals")
	local builder = visuals and visuals:FindFirstChild("WorldBuilder")
	if builder then
		local ok, err = pcall(function()
			(require(builder :: ModuleScript) :: any).build(workspace)
		end)
		if not ok then
			warn(`[Server] WorldBuilder.build failed: {err}`)
		end
	end
	if not workspace:FindFirstChild(Constants.PLOTS_FOLDER) then
		FallbackWorld.build()
	end
	-- FallenPartsDestroyHeight is plugin-only to write; default.project.json sets it.
	if workspace.FallenPartsDestroyHeight > Rescue.KILL_PLANE_Y then
		warn(`[Server] FallenPartsDestroyHeight {workspace.FallenPartsDestroyHeight} is above the kill plane`)
	end
	local factory = visuals and visuals:FindFirstChild("ModelFactory")
	if factory then
		-- Mesh look over Archer's factory; LoadAsset yields once here, falls back to procedural.
		local mesh = SlimeMesh.new({
			factory = require(factory :: ModuleScript) :: any,
			loadAsset = function(assetId: number): Instance
				return InsertService:LoadAsset(assetId)
			end,
		})
		workspace:SetAttribute(Constants.SLIME_LOOK_ATTRIBUTE, SlimeMesh.load(mesh))
		modelFactory = {
			build = function(slimeData: any): Model
				return SlimeMesh.build(mesh, slimeData)
			end,
		}
	end
	WorldView.setRain(false) -- SlimeRain = false until the first rain
	if not workspace:FindFirstChild(Constants.WILD_FOLDER) then
		local folder = Instance.new("Folder")
		folder.Name = Constants.WILD_FOLDER
		folder.Parent = workspace
	end
end

-- Plot model with PlotIndex == index (cached while it stays in workspace.Plots).
function WorldView.plot(index: number): Instance?
	local plots = workspace:FindFirstChild(Constants.PLOTS_FOLDER)
	if not plots then
		return nil
	end
	local cached = plotCache[index]
	if cached and cached.Parent == plots and cached:GetAttribute(Constants.PLOT_INDEX_ATTRIBUTE) == index then
		return cached
	end
	local plot = PlotLookup.byIndex(plots, Constants.PLOT_INDEX_ATTRIBUTE, index, `Plot_{index}`)
	plotCache[index] = plot
	return plot
end

function WorldView.pad(plotIndex: number, pad: number): BasePart?
	local plot = WorldView.plot(plotIndex)
	local part = PlotLookup.byIndex(plot, Constants.PAD_INDEX_ATTRIBUTE, pad, `Pad_{pad}`)
	if part and part:IsA("BasePart") then
		return part
	end
	return nil
end

-- Top surface of a pad. Slime models pivot at the bottom centre (ModelFactory sets
-- Body.PivotOffset), so model:PivotTo(padTop) rests the slime on the pad.
local function padTop(plotIndex: number, pad: number): CFrame?
	local part = WorldView.pad(plotIndex, pad)
	if part then
		return part.CFrame * CFrame.new(0, part.Size.Y / 2, 0)
	end
	return nil
end

local function crater(): Vector3
	local map = workspace:FindFirstChild(Constants.MAP_FOLDER)
	local volcano = map and map:FindFirstChild("Volcano")
	local part = volcano and volcano:FindFirstChild("Crater")
	if part and part:IsA("BasePart") then
		return part.Position
	end
	return Vector3.new(0, 20, 0)
end

-- Slime models and characters never count as ground (a ray that hits the carrier's head made
-- dropped slimes float, CONTRACT.md §8.11).
local function groundParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true -- canopies, HomeZones and other triggers are not ground
	local exclude: { Instance } = {}
	local wildFolder = workspace:FindFirstChild(Constants.WILD_FOLDER)
	if wildFolder then
		table.insert(exclude, wildFolder)
	end
	local plots = workspace:FindFirstChild(Constants.PLOTS_FOLDER)
	for _, plot in if plots then plots:GetChildren() else {} do
		local slimes = plot:FindFirstChild(Constants.PLOT_SLIMES_FOLDER)
		if slimes then
			table.insert(exclude, slimes)
		end
	end
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(exclude, player.Character)
		end
	end
	params.FilterDescendantsInstances = exclude
	return params
end

-- First collidable surface below `origin` within `depth` studs, or nil.
local function surfaceBelow(origin: Vector3, depth: number): CFrame?
	local hit = workspace:Raycast(origin, Vector3.new(0, -depth, 0), groundParams())
	if hit then
		return CFrame.new(origin.X, hit.Position.Y, origin.Z)
	end
	return nil
end

WorldView.DROP_RAY_UP = 4 -- studs above the carrier's root the drop ray starts (below canopies)
WorldView.DROP_RAY_DEPTH = 200

local function volcanoLanding(wild: World.Wild): CFrame
	local origin = crater()
	-- Landings on the low slide's footprint move out past it (FountainRide.clearLanding).
	local x, z = FountainRide.clearLanding(
		WorldLayout.SLIDE_PATH,
		math.cos(wild.angle) * wild.radius,
		math.sin(wild.angle) * wild.radius
	)
	local spot = origin + Vector3.new(x, 0, z)
	return surfaceBelow(Vector3.new(spot.X, origin.Y + 200, spot.Z), 400) or CFrame.new(spot.X, 0, spot.Z)
end

local function wildLanding(wild: World.Wild): CFrame
	if typeof(wild.position) == "Vector3" then
		-- A wild put down inside the landing ring's band rests just outside it (Fountain.clearOfRing).
		local origin = crater()
		local x, z = Fountain.clearOfRing(wild.position.X - origin.X, wild.position.Z - origin.Z)
		local spot = Vector3.new(origin.X + x, wild.position.Y, origin.Z + z)
		local dropped = surfaceBelow(spot + Vector3.new(0, WorldView.DROP_RAY_UP, 0), WorldView.DROP_RAY_DEPTH)
		if dropped then
			return dropped
		end
	end
	return volcanoLanding(wild) -- dropped over the void: back to its volcano spot
end

function WorldView.rootPart(player: Player?): BasePart?
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

---------------------------------------------------------------------------
-- Slime models
---------------------------------------------------------------------------

-- Moves the model along a path over `seconds`, unless its record changed.
local function animate(id: string, key: string, seconds: number, path: (t: number) -> CFrame)
	task.spawn(function()
		local start = os.clock()
		while true do
			local record = records[id]
			if not record or record.key ~= key or not record.model.Parent then
				return
			end
			local t = math.min((os.clock() - start) / seconds, 1)
			record.model:PivotTo(path(t))
			if t >= 1 then
				record.model:SetAttribute(Constants.RIDING_ATTRIBUTE, nil)
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function arc(from: CFrame, to: CFrame, height: number): (t: number) -> CFrame
	return function(t: number): CFrame
		return from:Lerp(to, t) + Vector3.new(0, math.sin(t * math.pi) * height, 0)
	end
end

-- The fountain ride (FountainRide): out of the goo crown, down every
-- waypoint of the spiral (WorldLayout.SLIDE_PATH), out of the mouth and round
-- the plaza to the landing, clear of the low slide. The model stays anchored
-- and is pivoted along it; the final pivot is exactly `landing`.
local function fountainRide(landing: CFrame): (number, (t: number) -> CFrame)
	local ride = FountainRide.new(WorldLayout.SLIDE_PATH, { landing.X, landing.Y, landing.Z })
	return ride.duration,
		function(t: number): CFrame
			if t >= 1 then
				return landing
			end
			local p, dir = FountainRide.sample(ride, t * ride.duration)
			local at = Vector3.new(p[1], p[2], p[3])
			return CFrame.lookAt(at, at + Vector3.new(dir[1], dir[2], dir[3]))
		end
end

-- FEATURES.Parade: the slime's sideways offset on the goo lane and its pose there.
local function laneLateral(wild: World.Wild): number
	return ParadeLane.lateral(wild.radius, Fountain.MIN_RADIUS, Fountain.MAX_RADIUS)
end

local function laneCFrame(wild: World.Wild, now: number): CFrame
	local pose = ParadeLane.pose(wild.spawnedAt, wild.expiresAt, laneLateral(wild), now)
	local p, h = pose.position, pose.heading
	local at = Vector3.new(p[1], p[2], p[3])
	return CFrame.lookAt(at, at + Vector3.new(h[1], 0, h[2]))
end

-- A parade slime's ride is the emerge + slide only: it leaves the mouth at ParadeLane.HOP_SECONDS and is
-- already on the lane walk there (laneCFrame), so there is no run-out glide to the lane and no wait.
local function laneRide(wild: World.Wild): (number, (t: number) -> CFrame)
	local ride = FountainRide.new(WorldLayout.SLIDE_PATH, ParadeLane.entrySpot(laneLateral(wild)))
	local seconds = ParadeLane.HOP_SECONDS
	return seconds,
		function(t: number): CFrame
			if t >= 1 then
				return laneCFrame(wild, wild.spawnedAt + seconds)
			end
			local p, dir = FountainRide.sample(ride, t * ride.slideEndsAt)
			local at = Vector3.new(p[1], p[2], p[3])
			return CFrame.lookAt(at, at + Vector3.new(dir[1], dir[2], dir[3]))
		end
end
-- Pivots a lane slime along the parade every frame (after its ride lands)
-- until its record changes (grabbed, dropped) or the model is gone.
local function followLane(id: string, key: string, wild: World.Wild)
	task.spawn(function()
		while true do
			local record = records[id]
			if not record or record.key ~= key or not record.model.Parent then
				return
			end
			if os.clock() >= record.rideUntil then
				local now = workspace:GetServerTimeNow()
				record.model:PivotTo(laneCFrame(wild, now))
				-- still Riding through the lead-in from the slide mouth (it crosses the landing ring's gap)
				local leading = ParadeLane.distance(wild.spawnedAt, wild.expiresAt, now) < 0
				if (record.model:GetAttribute(Constants.RIDING_ATTRIBUTE) == true) ~= leading then
					record.model:SetAttribute(Constants.RIDING_ATTRIBUTE, if leading then true else nil)
				end
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function create(entry: Scene.Entry, onPrompt: (Player, string) -> ()): Record?
	if failed[entry.id] or not modelFactory then
		return nil
	end
	local ok, model = pcall(modelFactory.build, entry.slime)
	if not ok or typeof(model) ~= "Instance" or not model:IsA("Model") then
		failed[entry.id] = true
		warn(`[Server] ModelFactory.build failed for {entry.id}: {model}`)
		return nil
	end
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		failed[entry.id] = true
		model:Destroy()
		return nil
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = Constants.GRAB_PROMPT_NAME
	prompt.ObjectText = (if entry.boss then "BOSS " else "") .. Genome.displayName(entry.slime)
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = Config.HOLD_CONFIRM_SECONDS -- reconcile sets the real value per state
	prompt.MaxActivationDistance = Config.STEAL_REACH - 2
	prompt.Parent = body
	local id = entry.id
	prompt.Triggered:Connect(function(player: Player)
		onPrompt(player, id)
	end)
	return { model = model, body = body, prompt = prompt, key = "", weld = nil, rideUntil = 0 }
end

local function unweld(record: Record)
	if record.weld then
		record.weld:Destroy()
		record.weld = nil
	end
	record.body.Anchored = true
end

-- Returns false when the model couldn't be placed yet (retried next reconcile).
local function place(record: Record, entry: Scene.Entry, previous: string?): boolean
	local model = record.model
	model:SetAttribute("OwnerUserId", entry.ownerUserId)
	model:SetAttribute("State", entry.state)
	model:SetAttribute("Price", entry.price)
	model:SetAttribute(Constants.BOSS_ATTRIBUTE, if entry.boss then true else nil)
	model:SetAttribute(Constants.RARE_ATTRIBUTE, entry.rare)

	if entry.state == "Carried" then
		local carrier = entry.carrierUserId and Players:GetPlayerByUserId(entry.carrierUserId)
		local root = WorldView.rootPart(carrier)
		if not root then
			return false
		end
		unweld(record)
		model:PivotTo(root.CFrame * CFrame.new(0, WorldView.CARRY_HEIGHT, 0))
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = record.body
		weld.Parent = record.body
		record.weld = weld
		record.body.Anchored = false
		return true
	end

	local from = model:GetPivot()
	unweld(record)
	record.rideUntil = 0
	model:SetAttribute(Constants.RIDING_ATTRIBUTE, nil)
	if entry.state == "Wild" then
		model.Parent = workspace:FindFirstChild(Constants.WILD_FOLDER)
		local wild = entry.wild
		if not wild then
			return true
		end
		if ParadeLane.enabled() and wild.position == nil then
			-- Fresh drops ride the slide and walk on from its mouth; later ones (a rebuilt model) join where they are.
			local now = workspace:GetServerTimeNow()
			if previous == nil and ParadeLane.phase(wild.spawnedAt, wild.expiresAt, now) == "Ride" then
				local seconds, ride = laneRide(wild)
				record.rideUntil = os.clock() + seconds
				model:SetAttribute(Constants.RIDING_ATTRIBUTE, true)
				animate(entry.id, entry.key, seconds, ride)
			else
				model:PivotTo(laneCFrame(wild, now))
			end
			followLane(entry.id, entry.key, wild)
			return true
		end
		local landing = wildLanding(wild)
		if previous == nil and wild.position == nil then
			local seconds, ride = fountainRide(landing)
			record.rideUntil = os.clock() + seconds
			model:SetAttribute(Constants.RIDING_ATTRIBUTE, true)
			animate(entry.id, entry.key, seconds, ride)
		elseif previous ~= nil and wild.position ~= nil then
			animate(entry.id, entry.key, WorldView.FALL_SECONDS, function(t: number): CFrame
				return from:Lerp(landing, t * t) -- falls out of the carrier's arms
			end)
		else
			model:PivotTo(landing)
		end
		return true
	end

	local plot = entry.plotIndex and WorldView.plot(entry.plotIndex)
	local folder = plot and plot:FindFirstChild(Constants.PLOT_SLIMES_FOLDER)
	model.Parent = folder or plot
	local target = entry.plotIndex and entry.pad and padTop(entry.plotIndex, entry.pad)
	if not target then
		return true
	end
	if entry.state == "Escaping" and previous ~= nil then
		animate(entry.id, entry.key, World.ESCAPE_BOUNCE_SECONDS, arc(from, target, 10))
	else
		model:PivotTo(target)
	end
	return true
end

--[[
	Creates, moves and destroys slime models to match the World. Call a few
	times a second and after any action.
]]
function WorldView.reconcile(world: World.World, now: number, onPrompt: (Player, string) -> ())
	local entries = Scene.describe(world, now)
	for id, record in records do
		if not entries[id] then
			record.model:Destroy()
			records[id] = nil
		end
	end
	for id, entry in entries do
		local record: Record? = records[id]
		local isNew = false
		if not record then
			record = create(entry, onPrompt)
			if not record then
				continue
			end
			records[id] = record
			isNew = true
		end
		assert(record, "record")
		record.prompt.ActionText = entry.promptText
		record.prompt.Enabled = entry.promptEnabled
		record.prompt:SetAttribute(Constants.PROMPT_HIDE_ATTRIBUTE, entry.hideFromUserId)
		record.prompt.HoldDuration = entry.promptHold
		-- Every reconcile, not only in place(): the telegraph window opens without a key change.
		record.model:SetAttribute(Constants.DESPAWN_AT_ATTRIBUTE, entry.despawnAt)
		GrowthLabel.apply(record.model, record.body, entry.slime)
		if record.key ~= entry.key then
			local previous = if isNew then nil else record.key
			record.key = entry.key
			if not place(record, entry, previous) then
				record.key = "" -- retry next time
			end
			if isNew and not record.model.Parent then
				record.model.Parent = workspace:FindFirstChild(Constants.WILD_FOLDER)
			end
		end
	end
	for id in failed do
		if not entries[id] then
			failed[id] = nil
		end
	end
end

-- A slime model's Body (Effects target), or nil if it has no model.
function WorldView.slimeBody(id: string): BasePart?
	local record = records[id]
	return record and record.body
end

-- Server-side position of a slime's Body (for reach checks).
function WorldView.slimePosition(id: string): Vector3?
	local record = records[id]
	return record and record.body.Position
end

---------------------------------------------------------------------------
-- Plots and players
---------------------------------------------------------------------------

local plotPromptParts: { [string]: string } = {
	[Constants.LOCK_PROMPT_NAME] = "LockButton",
	[Constants.MERGE_PROMPT_NAME] = "MergeVat",
}
local plotPrompts: { [number]: { [string]: ProximityPrompt } } = {}

--[[
	Creates the owner-only plot prompts (CONTRACT.md §8.5): LockPrompt on
	LockButton, MergePrompt on MergeVat and BuyPadPrompt (moved onto the
	lowest locked pad by updatePlots). `onTrigger(player, plotIndex, kind)`
	with kind "Lock" | "Merge" | "BuyPad". Texts / Enabled / ShowOnlyToUserId
	are kept current by updatePlots.
]]
function WorldView.addPlotPrompts(onTrigger: (Player, number, string) -> ())
	local kinds = {
		[Constants.LOCK_PROMPT_NAME] = "Lock",
		[Constants.MERGE_PROMPT_NAME] = "Merge",
		[Constants.BUY_PAD_PROMPT_NAME] = "BuyPad",
	}
	for index = 1, Config.PLOT_COUNT do
		local plot = WorldView.plot(index)
		if not plot then
			continue
		end
		plotPrompts[index] = {}
		for name, kind in kinds do
			local parent = if plotPromptParts[name]
				then plot:FindFirstChild(plotPromptParts[name])
				else WorldView.pad(index, Config.PADS_START + 1)
			if not parent or not parent:IsA("BasePart") then
				continue
			end
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = name
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			-- The 3-slime vat prompt only opens the merge menu (the menu confirms each merge), so it is instant.
			local opensMenu = kind == "Merge" and Config.FEATURES.MergeVat3
			prompt.HoldDuration = if opensMenu then 0 else Config.HOLD_CONFIRM_SECONDS
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = Config.PLOT_PAD_PROMPT_DISTANCE
			prompt.Enabled = false
			prompt.Parent = parent
			prompt.Triggered:Connect(function(player: Player)
				onTrigger(player, index, kind)
			end)
			plotPrompts[index][name] = prompt
		end
	end
end

-- The part plot `index`'s prompt `kind` ("Lock" | "Merge" | "BuyPad") currently sits on (BuyPad moves), or nil.
function WorldView.plotPromptPart(index: number, kind: string): BasePart?
	local name = if kind == "Lock"
		then Constants.LOCK_PROMPT_NAME
		elseif kind == "Merge" then Constants.MERGE_PROMPT_NAME
		elseif kind == "BuyPad" then Constants.BUY_PAD_PROMPT_NAME
		else nil
	local prompt = name and plotPrompts[index] and plotPrompts[index][name]
	local parent = prompt and prompt.Parent
	return if parent and parent:IsA("BasePart") then parent else nil
end

local function applyPrompt(prompt: ProximityPrompt?, view: PlotPrompts.Prompt, owner: number?)
	if not prompt then
		return
	end
	if prompt.ActionText ~= view.actionText then
		prompt.ActionText = view.actionText
	end
	if prompt.ObjectText ~= view.objectText then
		prompt.ObjectText = view.objectText
	end
	local enabled = view.enabled and owner ~= nil
	if prompt.Enabled ~= enabled then
		prompt.Enabled = enabled
	end
	if prompt:GetAttribute(Constants.PROMPT_OWNER_ATTRIBUTE) ~= owner then
		prompt:SetAttribute(Constants.PROMPT_OWNER_ATTRIBUTE, owner)
	end
end

local setBarrierSolid: (Instance, number, boolean) -> ()

local function setIfChanged(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

-- Locked pads (and their Stand mesh) go grey Slate, unlocked ones get the stored base look back (PadStyle).
-- The base look is read once into attributes, so an unlock restores the exact colour and material.
local function styleLook(part: BasePart, unlocked: boolean)
	local stored = part:GetAttribute("BaseColor")
	local baseColor: Color3 = if typeof(stored) == "Color3" then stored else part.Color
	if typeof(stored) ~= "Color3" then
		part:SetAttribute("BaseColor", baseColor)
		part:SetAttribute("BaseMaterial", part.Material.Name)
	end
	local baseMaterial = part:GetAttribute("BaseMaterial") :: string
	local base = { baseColor.R * 255, baseColor.G * 255, baseColor.B * 255 }
	local rgb, material = PadStyle.look(base, baseMaterial, unlocked)
	local color = if unlocked then baseColor else Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	if part.Color ~= color then
		part.Color = color
	end
	local enum = (Enum.Material :: any)[material]
	if part.Material ~= enum then
		part.Material = enum
	end
end

local function stylePad(pad: BasePart, unlocked: boolean)
	styleLook(pad, unlocked)
	local stand = pad:FindFirstChild("Stand")
	if stand and stand:IsA("BasePart") then
		styleLook(stand, unlocked)
		-- With a mesh stand-in (MeshSwap) the Pad and Stand parts are hidden (Transparency 1) and the visible pad is
		-- the Stand's "Mesh" MeshPart, so the locked look has to land on that too or every pad looks unlocked.
		local mesh = stand:FindFirstChild("Mesh")
		if mesh and mesh:IsA("MeshPart") then
			styleLook(mesh, unlocked)
		end
	end
end

-- DexTierMask per plot, recomputed only when the owner or dex count changes.
local dexMasks: { [number]: { userId: number, count: number, mask: number } } = {}

local function dexMask(index: number, session: World.Session, count: number): number
	local cached = dexMasks[index]
	if cached and cached.userId == session.userId and cached.count == count then
		return cached.mask
	end
	local fresh = { userId = session.userId, count = count, mask = Collection.tierMask(session.data) }
	dexMasks[index] = fresh
	return fresh.mask
end

-- Lock enforcement. The LockBarrier panels ship non-colliding (client cosmetics); the server makes
-- them solid while the plot is locked. Panels sit in PlotLock_<i>, the owner's character in
-- PlotOwner_<i>, and that pair does not collide, so the owner walks through. The barrier is one-way: a non-owner
-- standing inside a locked plot is put in PlotLeaver (collides with no panel) until it is out, so it can leave.
-- Nobody is ever moved by the server.
local groupsReady = false
local function ensureGroups()
	if groupsReady then
		return
	end
	groupsReady = true
	for index = 1, Config.PLOT_COUNT do
		local lock, owner = PlotLockGuard.lockGroup(index), PlotLockGuard.ownerGroup(index)
		local ok, err = pcall(function()
			PhysicsService:RegisterCollisionGroup(lock)
			PhysicsService:RegisterCollisionGroup(owner)
			PhysicsService:CollisionGroupSetCollidable(lock, owner, false)
		end)
		if not ok then
			warn(`[WorldView] collision groups for plot {index}: {err}`)
		end
	end
	local ok, err = pcall(function()
		PhysicsService:RegisterCollisionGroup(PlotLockGuard.LEAVER_GROUP)
		for index = 1, Config.PLOT_COUNT do
			PhysicsService:CollisionGroupSetCollidable(
				PlotLockGuard.LEAVER_GROUP,
				PlotLockGuard.lockGroup(index),
				false
			)
		end
	end)
	if not ok then
		warn(`[WorldView] leaver collision group: {err}`)
	end
end

function setBarrierSolid(plot: Instance, index: number, solid: boolean)
	local barrier = plot:FindFirstChild("LockBarrier")
	if not barrier then
		return
	end
	ensureGroups()
	for _, panel in barrier:GetChildren() do
		if panel:IsA("BasePart") then
			if panel.CanCollide ~= solid then
				panel.CanCollide = solid
			end
			local group = PlotLockGuard.lockGroup(index)
			if panel.CollisionGroup ~= group then
				pcall(function()
					panel.CollisionGroup = group
				end)
			end
		end
	end
end

-- Plot-local z of the front LockBarrier slab's outer face (the real layout constant).
local FRONT_Z = WorldLayout.frontBarrier().zOuter

local function setPartGroup(part: Instance, group: string)
	if part:IsA("BasePart") and part.CollisionGroup ~= group then
		pcall(function()
			part.CollisionGroup = group
		end)
	end
end

-- The group each live character is meant to be in; parts added later (tools, accessories) join it.
local characterGroups: { [Model]: string } = setmetatable({}, { __mode = "k" }) :: any
-- Per user: the plot index they currently pass the barrier of (leaver state, for the exit hysteresis).
local leavingPlot: { [number]: number? } = {}

local function setCharacterGroup(character: Model, group: string)
	if characterGroups[character] == nil then
		character.DescendantAdded:Connect(function(part)
			setPartGroup(part, characterGroups[character] or "Default")
		end)
	end
	characterGroups[character] = group
	for _, part in character:GetDescendants() do
		setPartGroup(part, group)
	end
end

-- Bug #10: a character whose root overlaps the fountain-top slime stack (Map.Volcano.EmergeMesh) is not pushed out by
-- the solid mesh, so move it above the top (radially outside if something is overhead). True when it moved.
local function ejectFromStack(character: Model, root: BasePart): boolean
	local volcano = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Volcano")
	local slot = volcano and volcano:FindFirstChild("EmergeMesh")
	local ref = slot and (slot:FindFirstChild("Mesh") or slot)
	if not (ref and ref:IsA("BasePart")) then
		return false
	end
	local half = ref.Size / 2
	local p = ref.CFrame:PointToObjectSpace(root.Position)
	if not StackGuard.inside(p.X, p.Y, p.Z, half.X, half.Y, half.Z) then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local top = ref.CFrame * Vector3.new(p.X, half.Y, p.Z)
	local blocked = workspace:Raycast(top, Vector3.new(0, StackGuard.LIFT + 4, 0), params) ~= nil
	local x, y, z = StackGuard.ejectPoint(p.X, p.Y, p.Z, half.X, half.Y, half.Z, blocked)
	character:PivotTo(ref.CFrame * CFrame.new(x, y, z))
	root.AssemblyLinearVelocity = Vector3.zero
	return true
end

-- Per player: the character's collision group. The owner's character is in PlotOwner_<i> (walks through its
-- barrier). Any character that is not the owner of a locked plot it stands inside is a leaver (PlotLeaver: passes
-- the panels, so it can walk out; the exit hysteresis is PlotLockGuard.EXIT_MARGIN). Everyone else collides, so
-- entering stays blocked. Nothing here ever changes a character's position.
function WorldView.enforceLocks(world: World.World, player: Player)
	local root = WorldView.rootPart(player)
	local character = player.Character
	if not root or not character then
		return
	end
	local own = World.session(world, player.UserId)
	local wanted = if own then PlotLockGuard.ownerGroup(own.plotIndex) else "Default"
	local wasIn = leavingPlot[player.UserId]
	local leaving: number? = nil
	for index = 1, world.plotCount do
		local ownerId = world.plots[index]
		local session = ownerId and world.sessions[ownerId]
		local plot = if session and session.userId ~= player.UserId then WorldView.plot(index) else nil
		local base = plot and plot:FindFirstChild("Base")
		if
			session
			and plot
			and base
			and base:IsA("BasePart")
			and plot:GetAttribute(Constants.PLOT_LOCKED_ATTRIBUTE) == true
		then
			local p = base.CFrame:PointToObjectSpace(root.Position)
			if
				PlotLockGuard.isLeaver(
					player.UserId,
					session.userId,
					true,
					p.X,
					p.Y,
					p.Z,
					base.Size.X / 2,
					FRONT_Z,
					wasIn == index
				)
			then
				leaving = index
				break
			end
		end
	end
	leavingPlot[player.UserId] = leaving
	if leaving then
		wanted = PlotLockGuard.LEAVER_GROUP
	end
	if root.CollisionGroup ~= wanted or characterGroups[character] ~= wanted then
		ensureGroups()
		setCharacterGroup(character, wanted)
	end
	ejectFromStack(character, root)
end

function WorldView.updatePlots(world: World.World, now: number)
	local habitatsOn = Config.FEATURES.Habitats
	HabitatPads.step(habitats, world, now, habitatsOn)
	for index = 1, world.plotCount do
		local plot = WorldView.plot(index)
		if plot then
			local userId = world.plots[index]
			local session = userId and world.sessions[userId]
			local view = PlotPrompts.describe(world, index, now)
			setIfChanged(plot, "OwnerUserId", if session then session.userId else 0)
			setIfChanged(plot, "LockUntil", if session then session.lockUntil else 0)
			setIfChanged(plot, "Rebirths", if session then session.data.rebirths else 0)
			setIfChanged(plot, Constants.PLOT_LOCKED_ATTRIBUTE, view.locked)
			setBarrierSolid(plot, index, view.locked)
			setIfChanged(plot, Constants.PLOT_LOCK_COST_ATTRIBUTE, view.lockCost)
			setIfChanged(plot, Constants.PLOT_PADS_UNLOCKED_ATTRIBUTE, view.padsUnlocked)
			setIfChanged(plot, Constants.PLOT_NEXT_PAD_COST_ATTRIBUTE, view.nextPadCost)
			if Config.FEATURES.PlotSkins then
				setIfChanged(
					plot,
					Constants.PLOT_SKIN_ATTRIBUTE,
					if session then PlotSkins.current(session.data) else Config.PLOT_SKIN_DEFAULT
				)
			end
			if Config.FEATURES.RainMagnet then
				setIfChanged(
					plot,
					Constants.PLOT_RAIN_MAGNET_ATTRIBUTE,
					if session then Perks.upgradeLevel(session.data, "RainMagnet") else 0
				)
			end
			local dexCount = if session then PlayerData.dexCount(session.data) else 0
			setIfChanged(plot, Constants.PLOT_DEX_COUNT_ATTRIBUTE, dexCount)
			setIfChanged(plot, Constants.PLOT_DEX_TOTAL_ATTRIBUTE, Snapshot.DEX_TOTAL)
			setIfChanged(
				plot,
				Constants.PLOT_DEX_TIER_MASK_ATTRIBUTE,
				if session then dexMask(index, session, dexCount) else 0
			)
			for pad = 1, Config.PADS_MAX do
				local part = WorldView.pad(index, pad)
				if part then
					local unlocked = pad <= view.padsUnlocked
					setIfChanged(part, Constants.PAD_UNLOCKED_ATTRIBUTE, unlocked)
					stylePad(part, PadStyle.showsUnlocked(session ~= nil, unlocked))
					local habitat = if habitatsOn then HabitatPads.get(habitats, index, pad) else nil
					if habitat then
						-- At first so a client that sees Habitat change also reads the matching stamp.
						setIfChanged(part, Constants.HABITAT_AT_ATTRIBUTE, habitat.at)
						setIfChanged(part, Constants.HABITAT_FROM_ATTRIBUTE, habitat.from)
						setIfChanged(part, Constants.HABITAT_ATTRIBUTE, habitat.id)
					end
				end
			end
			local prompts = plotPrompts[index]
			if prompts then
				applyPrompt(prompts[Constants.LOCK_PROMPT_NAME], view.lock, view.ownerUserId)
				applyPrompt(prompts[Constants.MERGE_PROMPT_NAME], view.merge, view.ownerUserId)
				local buyPad = prompts[Constants.BUY_PAD_PROMPT_NAME]
				local padPart = WorldView.pad(index, view.buyPad.pad)
				if buyPad and padPart and buyPad.Parent ~= padPart then
					buyPad.Parent = padPart
				end
				applyPrompt(buyPad, view.buyPad, view.ownerUserId)
			end
			local sign = plot:FindFirstChild("Sign")
			if sign then
				PlotSigns.apply(sign, PlotSigns.lines(index, session))
			end
		end
	end
end

-- True if the player's root part is inside their own plot's HomeZone.
function WorldView.inHomeZone(player: Player, plotIndex: number): boolean
	local root = WorldView.rootPart(player)
	return root ~= nil and WorldView.pointInHomeZone(root.Position, plotIndex)
end

-- Same test for a world point (Goo Trap placement).
function WorldView.pointInHomeZone(position: Vector3, plotIndex: number): boolean
	local plot = WorldView.plot(plotIndex)
	local zone = plot and plot:FindFirstChild(Constants.HOME_ZONE)
	if not zone or not zone:IsA("BasePart") then
		return false
	end
	local p = zone.CFrame:PointToObjectSpace(position)
	local half = zone.Size / 2
	return math.abs(p.X) <= half.X and math.abs(p.Z) <= half.Z and p.Y >= -half.Y - 4 and p.Y <= half.Y + 8
end

-- Spawn point on top of the plot's Base.
function WorldView.plotSpawn(plotIndex: number): CFrame?
	local plot = WorldView.plot(plotIndex)
	local base = plot and plot:FindFirstChild("Base")
	if base and base:IsA("BasePart") then
		return base.CFrame * CFrame.new(0, base.Size.Y / 2 + 4, 0)
	end
	return nil
end

-- Spawn point on top of the hub SpawnLocation (world/HubSpawn.rbxmx), or any SpawnLocation.
function WorldView.hubSpawn(): CFrame?
	local spawn = workspace:FindFirstChild("HubSpawn")
	if not (spawn and spawn:IsA("SpawnLocation")) then
		spawn = workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	end
	if spawn and spawn:IsA("SpawnLocation") then
		return spawn.CFrame * CFrame.new(0, spawn.Size.Y / 2 + 4, 0)
	end
	return nil
end

-- Kill plane (Rescue): puts a living character that fell below the plane back on
-- its plot / the hub. Returns true if it moved the character.
function WorldView.rescue(player: Player, plotIndex: number?, pvpGuard: boolean?): boolean
	local character = player.Character
	local root = WorldView.rootPart(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not character or not root or not humanoid then
		return false
	end
	if not Rescue.shouldRescuePvp(root.Position.Y, humanoid.Health > 0, pvpGuard == true) then
		return false
	end
	local plotSpawn = if plotIndex then WorldView.plotSpawn(plotIndex) else nil
	character:PivotTo(Rescue.target(plotSpawn, WorldView.hubSpawn(), CFrame.new(0, 50, 0)))
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	return true
end

local function setAttribute(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

-- Keeps one SpeedCoil tool in the Backpack or character while it's owned.
local function ensureSpeedCoil(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	if not backpack or backpack:FindFirstChild(Constants.SPEED_COIL_TOOL) then
		return
	end
	if character and character:FindFirstChild(Constants.SPEED_COIL_TOOL) then
		return
	end
	local tool = WorldProps.speedCoil()
	if tool then
		tool.ToolTip = "Speed Coil: always on"
		tool.Parent = backpack
	end
end

function WorldView.updatePlayer(player: Player, session: World.Session, now: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local carry = session.carry
	local data = session.data
	WorldView.setCarrying(player, carry and carry.slimeId)
	setAttribute(player, Constants.TUTORIAL_STEP_ATTRIBUTE, TutorialProgress.current(data))
	setAttribute(player, Constants.TUTORIAL_STEP_ID_ATTRIBUTE, TutorialProgress.currentId(data))
	setAttribute(player, Constants.SPEED_COIL_ATTRIBUTE, if data.speedCoil then true else nil)
	setAttribute(player, Constants.REBIRTH_TITLE_ATTRIBUTE, Perks.title(data.rebirths))
	if Config.FEATURES.PvP then
		setAttribute(player, Constants.PVP_SHIELD_ATTRIBUTE, PvpService.shieldUntil(session, now))
		setAttribute(player, Constants.PVP_EQUIPPED_ATTRIBUTE, PvpService.equipped(session))
		local root = WorldView.rootPart(player)
		PvpService.tick(session, root and root.Position, now)
		PvpTrap.tick(session, root and root.Position, now)
		PvpFun.tick(session, root and root.Position, now)
	end
	local pet = Progression.keeper(data)
	setAttribute(player, Constants.PET_ATTRIBUTE, pet and pet.id)
	if data.speedCoil then
		ensureSpeedCoil(player)
	end
	local target = Carry.targetWalkSpeed(session, now)
	if Config.FEATURES.PvP and PvpTrap.frozen(session, now) then
		target = 0 -- Goo Trap freeze (PvpTrap, <= CONTROL_MAX_SECONDS)
	end
	setAttribute(player, Constants.WALK_SPEED_ATTRIBUTE, target)
	if not humanoid then
		return
	end
	-- Always enforce the server's speed (v12 only overwrote speeds it recognised, so any
	-- other start value locked the coil out). WalkSpeed is a float32: compare loosely.
	if math.abs(humanoid.WalkSpeed - target) > 0.01 then
		humanoid.WalkSpeed = target
	end
	if carry and character and character:FindFirstChildOfClass("Tool") then
		humanoid:UnequipTools()
	end
end

-- Player attribute `Carrying` (CONTRACT.md §5.2): slime id while carrying, cleared otherwise.
function WorldView.setCarrying(player: Player, slimeId: string?)
	if player:GetAttribute(Constants.CARRYING_ATTRIBUTE) ~= slimeId then
		player:SetAttribute(Constants.CARRYING_ATTRIBUTE, slimeId)
	end
end

-- Player attribute `RevengePlots` (FEATURES.Revenge): thief plot indexes, "3,5", nil = none. Victim only.
function WorldView.setRevengePlots(player: Player, plots: { number })
	setAttribute(player, Constants.REVENGE_PLOTS_ATTRIBUTE, RevengePlots.format(plots))
end

function WorldView.setRain(active: boolean, endsAt: number?, nextAt: number?)
	workspace:SetAttribute(Constants.RAIN_ATTRIBUTE, active)
	workspace:SetAttribute(Constants.RAIN_ACTIVE_ATTRIBUTE, active)
	workspace:SetAttribute(Constants.RAIN_ENDS_AT_ATTRIBUTE, endsAt)
	workspace:SetAttribute(Constants.RAIN_NEXT_AT_ATTRIBUTE, nextAt)
end

-- Workspace attribute `BossNextAt` (server time): drives the HUD's next-event chip.
function WorldView.setBossNextAt(nextAt: number?)
	if workspace:GetAttribute(Constants.BOSS_NEXT_AT_ATTRIBUTE) ~= nextAt then
		workspace:SetAttribute(Constants.BOSS_NEXT_AT_ATTRIBUTE, nextAt)
	end
end

return WorldView
