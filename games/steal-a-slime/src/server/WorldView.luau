--!strict
--[[
	WorldView (Roblox adapter)

	Makes workspace match the pure World:
	  * reconciles slime models against Scene.describe (ModelFactory.build,
	    wrapped by SlimeMesh for the mesh look; Mystery Eggs by Visuals.EggModel with the owner-only HatchPrompt and
	    the EggKind / EggHatchAt / EggHatchSeconds attributes, rebuilt when the egg hatches; parenting, attributes
	    OwnerUserId / State / Price / DespawnAt, ProximityPrompt,
	    pad placement, carry weld, volcano drop, the parade lane walk, a
	    dropped slime's walk back to the lane and the escape-home glide);
	  * plot attributes OwnerUserId / LockUntil (CONTRACT.md §5.2);
	    with FEATURES.Habitats, Pad Habitat / HabitatFrom / HabitatAt (HabitatPads)
	    and the owner / stats text on each plot Sign (PlotSigns);
	  * per-player WalkSpeed (Speed Coil while held), unequipped
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
local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BaseFloors = require(script.Parent.BaseFloors)
local BaseShapeSwap = require(script.Parent.BaseShapeSwap)
local BaseShapes = require(ReplicatedStorage.Visuals.BaseShapes)
local BossArea = require(ReplicatedStorage.Shared.BossArea)
local BossChoreo = require(ReplicatedStorage.Shared.BossChoreo)
local BossFxView = require(script.Parent.BossFxView)
local Carry = require(script.Parent.Carry)
local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local EggKind = require(ReplicatedStorage.Shared.EggKind)
local EggModel = require(ReplicatedStorage.Visuals.EggModel)
local FallbackWorld = require(script.Parent.FallbackWorld)
local Fountain = require(ReplicatedStorage.Shared.Fountain)
local FountainRide = require(ReplicatedStorage.Shared.FountainRide)
local Genome = require(ReplicatedStorage.Shared.Genome)
local GrabBlock = require(ReplicatedStorage.Shared.GrabBlock)
local HabitatPads = require(script.Parent.HabitatPads)
local HomeZone = require(ReplicatedStorage.Shared.HomeZone)
local JarRoute = require(script.Parent.JarRoute)
local KitDelivery = require(script.Parent.KitDelivery)
local LaneTraffic = require(ReplicatedStorage.Shared.LaneTraffic)
local LockPad = require(script.Parent.LockPad)
local LockPadView = require(script.Parent.LockPadView)
local MeshSwap = require(script.Parent.MeshSwap)
local MoveWatch = require(script.Parent.MoveWatch)
local PadStyle = require(ReplicatedStorage.Shared.PadStyle)
local ParadeChoreo = require(ReplicatedStorage.Shared.ParadeChoreo)
local ParadeLane = require(ReplicatedStorage.Shared.ParadeLane)
local Perks = require(ReplicatedStorage.Shared.Perks)
local PetSeats = require(ReplicatedStorage.Shared.PetSeats)
local PlotBases = require(ReplicatedStorage.Shared.PlotBases)
local PlotGuests = require(script.Parent.PlotGuests)
local PlotLockGuard = require(script.Parent.PlotLockGuard)
local PlotLookup = require(script.Parent.PlotLookup)
local PlotPrompts = require(script.Parent.PlotPrompts)
local PlotSigns = require(script.Parent.PlotSigns)
local PlotSkins = require(ReplicatedStorage.Shared.PlotSkins)
local PvpBlaster = require(script.Parent.PvpBlaster)
local PvpFun = require(script.Parent.PvpFun)
local PvpHeld = require(script.Parent.PvpHeld)
local PvpService = require(script.Parent.PvpService)
local PvpTrap = require(script.Parent.PvpTrap)
local Rescue = require(script.Parent.Rescue)
local SafeCall = require(script.Parent.SafeCall)
local Scene = require(script.Parent.Scene)
local SlimeGuard = require(script.Parent.SlimeGuard)
local SlimeLabelView = require(script.Parent.SlimeLabelView)
local SlimeMesh = require(script.Parent.SlimeMesh)
local SlimePersona = require(ReplicatedStorage.Shared.SlimePersona)
local SlimeShineView = require(script.Parent.SlimeShineView)
local StackGuard = require(script.Parent.StackGuard)
local StealGhost = require(script.Parent.StealGhost)
local TutorialProgress = require(ReplicatedStorage.Shared.TutorialProgress)
local VatView = require(script.Parent.VatView)
local World = require(script.Parent.World)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)
local WorldProps = require(script.Parent.WorldProps)

type Record = {
	model: Model,
	body: BasePart,
	prompt: ProximityPrompt,
	hatch: ProximityPrompt?, -- Mystery Eggs: the owner-only HatchPrompt
	egg: boolean, -- built as a Mystery Egg (a hatch rebuilds the model as its slime)
	species: string?, -- built as this species (a Lucky Charm morph rebuilds the model as its new species)
	key: string,
	placed: boolean, -- place() has succeeded once; until then the model stays out of workspace (it is built at the
	-- world origin, the fountain axis)
	weld: WeldConstraint?,
	rideUntil: number, -- os.clock() when the fountain ride lands (0 = not riding)
	ghost: Model?, -- StealGhost: the see-through copy left on the pad while a thief carries it
	pendingKit: string?, -- built before this species kit loaded (shared mesh look): rebuilt once it arrives
	walking: ParadeLane.Return?, -- the walk back it follows (a reroute of the same walk carries on, no new fall)
}

local WorldView = {}

local records: { [string]: Record } = {}
-- Lane slimes walking the parade (followLane): one loop pivots them all.
type LaneWalk = { key: string, wild: World.Wild }
local laneWalks: { [string]: LaneWalk } = {}
local failed: { [string]: boolean } = {}
local modelFactory: any = nil
local slimeMesh: SlimeMesh.SlimeMesh? = nil
local plotCache: { [number]: Instance? } = {}
local habitats = HabitatPads.new() -- FEATURES.Habitats pad state (never saved)
local eggMeshes: { [string]: MeshPart | false } = {} -- uploaded Mystery Egg meshes (MeshAssets mystery_egg_*), by name

-- The player's own kit folder: a disabled ScreenGui in their PlayerGui, so only they replicate it and it survives
-- respawns (SpeciesModel reads it).
local function kitFolder(player: Player): Instance?
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if gui == nil then
		return nil
	end
	local folder = gui:FindFirstChild(Constants.SLIME_KITS_FOLDER)
	if folder == nil then
		local screen = Instance.new("ScreenGui")
		screen.Name = Constants.SLIME_KITS_FOLDER
		screen.Enabled = false
		screen.ResetOnSpawn = false
		screen.Parent = gui
		folder = screen
	end
	return folder
end

-- Species kit meshes, sent per player on RequestKits (SlimeDex / rebirth previews).
local kitDelivery = KitDelivery.new({
	loaded = function(kit: string): any?
		return if slimeMesh then slimeMesh.kits[kit] else nil
	end,
	failed = function(kit: string): boolean
		-- Without the factory there is no mesh look and no kit ever loads.
		return slimeMesh == nil or slimeMesh.failedKits[kit] == true
	end,
	deliver = function(userId: number, kit: string, template: any)
		local player = Players:GetPlayerByUserId(userId)
		local folder = player and kitFolder(player)
		if folder == nil then
			return
		end
		local copy = (template :: MeshPart):Clone()
		copy.Name = kit
		copy.Anchored = true
		copy.CanCollide = false
		copy.CanQuery = false
		copy.CanTouch = false
		copy.Parent = folder
	end,
})

-- RequestKits (Actions ctx.sendKits): `kits` are KitRequest kit names.
function WorldView.sendKits(userId: number, kits: { string })
	KitDelivery.request(kitDelivery, userId, kits)
end

-- The player left: their kit folder went with their PlayerGui.
function WorldView.forgetKits(userId: number)
	KitDelivery.forget(kitDelivery, userId)
end

WorldView.FALL_SECONDS = 0.3 -- a dropped slime falls to the ground
WorldView.CARRY_HEIGHT = 3 -- studs above the HumanoidRootPart when the character has no Head

---------------------------------------------------------------------------
-- World lookup
---------------------------------------------------------------------------

-- Returns the WorldBuilder module when it built the world (nil on the greybox): its buildFloor adds upper floors.
function WorldView.setup(): any?
	-- The world ships static in the place (world/*.rbxmx); WorldBuilder is idempotent and reuses it.
	-- Build before anything that yields (LoadAsset below): characters may already be spawning.
	-- Greybox only if the builder is missing or fails.
	local visuals = ReplicatedStorage:FindFirstChild("Visuals")
	local builder = visuals and visuals:FindFirstChild("WorldBuilder")
	local built: any? = nil
	if builder then
		local ok, err = pcall(function()
			local module = require(builder :: ModuleScript) :: any
			module.build(workspace)
			built = module
		end)
		if not ok then
			warn(`[Server] WorldBuilder.build failed: {err}`)
		end
	end
	if not workspace:FindFirstChild(Constants.PLOTS_FOLDER) then
		FallbackWorld.build()
		built = nil
	end
	-- FallenPartsDestroyHeight is plugin-only to write; default.project.json sets it.
	if workspace.FallenPartsDestroyHeight > Rescue.KILL_PLANE_Y then
		warn(`[Server] FallenPartsDestroyHeight {workspace.FallenPartsDestroyHeight} is above the kill plane`)
	end
	local factory = visuals and visuals:FindFirstChild("ModelFactory")
	if factory then
		-- Mesh look over Archer's factory; LoadAsset yields once here, falls back to procedural.
		-- Clients can't LoadAsset: a SlimeDex / rebirth preview asks for the kits it shows (RequestKits) and
		-- KitDelivery copies just those to that player (WorldView.sendKits).
		local mesh = SlimeMesh.new({
			factory = require(factory :: ModuleScript) :: any,
			loadAsset = function(assetId: number): Instance
				return InsertService:LoadAsset(assetId)
			end,
			onKit = function(kit: string, template: MeshPart)
				KitDelivery.kitLoaded(kitDelivery, kit, template)
			end,
		})
		slimeMesh = mesh
		workspace:SetAttribute(Constants.SLIME_LOOK_ATTRIBUTE, SlimeMesh.load(mesh))
		modelFactory = {
			build = function(slimeData: any): Model
				return SlimeMesh.build(mesh, slimeData)
			end,
		}
	end
	-- Uploaded egg meshes (MeshAssets mystery_egg_<kind> / mystery_egg_nest) load in the background; until then (or
	-- without an upload) EggModel builds the primitive look.
	task.spawn(function()
		local names = { "mystery_egg_nest" }
		for _, kind in EggKind.list() do
			table.insert(names, `mystery_egg_{kind.id}`)
		end
		for _, name in names do
			local ok, mesh = pcall(MeshSwap.load, name)
			eggMeshes[name] = if ok and mesh then mesh else false
		end
	end)
	WorldView.setRain(false) -- SlimeRain = false until the first rain
	if not workspace:FindFirstChild(Constants.WILD_FOLDER) then
		local folder = Instance.new("Folder")
		folder.Name = Constants.WILD_FOLDER
		folder.Parent = workspace
	end
	return built
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

-- Pads 1..Config.PADS_MAX of a plot with one scan of the plot's children (same result as WorldView.pad per index).
local function plotPads(plotIndex: number): { [number]: BasePart }
	local found =
		PlotLookup.allByIndex(WorldView.plot(plotIndex), Constants.PAD_INDEX_ATTRIBUTE, Config.PADS_MAX, "Pad_")
	local pads: { [number]: BasePart } = {}
	for index, part in found do
		if part:IsA("BasePart") then
			pads[index] = part
		end
	end
	return pads
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

WorldView.GROUND_PARAMS_TTL = 0.1 -- s: how long the ground ray filter is reused (characters and slime folders change rarely)

local groundCache: { params: RaycastParams, builtAt: number }? = nil

-- Slime models and characters never count as ground (a ray that hits the carrier's head made
-- dropped slimes float, CONTRACT.md §8.11). Built at most once per GROUND_PARAMS_TTL: every returning slime rays
-- every Heartbeat.
local function groundParams(): RaycastParams
	local clock = os.clock()
	local cached = groundCache
	if cached and clock - cached.builtAt < WorldView.GROUND_PARAMS_TTL then
		return cached.params
	end
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
	groundCache = { params = params, builtAt = clock }
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

WorldView.BOSS_RAY_UP = 60 -- studs above an attack's centre the floor probe starts (over the boss, under nothing)
WorldView.BOSS_EYE = 4 -- studs above the arena floor the line-of-sight ray starts (over curbs and puddles)

--[[
	Whether a boss attack centred on `from` (x / z; Y = a hint for where the arena floor is) can strike the character
	whose root is `root`: the root is at most `height` studs above the floor under the attack (and not under it), and
	a ray from just above that floor to the root hits nothing solid (slimes, the boss, characters and non-collidable
	parts never block). Nothing found under the attack = no floor to measure from, so only the line is checked.
]]
-- The arena floor height at world (x, z): the first collidable surface below a probe BOSS_RAY_UP over the plaza
-- origin (the same probe bossExposed uses), or nil when there is none. Guards and goo puddles stand on it.
function WorldView.bossFloor(x: number, z: number): number?
	local top = crater().Y + WorldView.BOSS_RAY_UP
	local floor = surfaceBelow(Vector3.new(x, top, z), WorldView.BOSS_RAY_UP * 2)
	return if floor then floor.Position.Y else nil
end

function WorldView.bossExposed(from: Vector3, root: Vector3, height: number): boolean
	local params = groundParams()
	local floor = surfaceBelow(Vector3.new(from.X, from.Y + WorldView.BOSS_RAY_UP, from.Z), WorldView.BOSS_RAY_UP * 2)
	local floorY = if floor then floor.Position.Y else from.Y
	if root.Y - floorY > height or root.Y < floorY - 2 then
		return false
	end
	local eye = Vector3.new(from.X, floorY + WorldView.BOSS_EYE, from.Z)
	return workspace:Raycast(eye, root - eye, params) == nil
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

-- The fighting boss's wild record by slime id while it moves (BossChoreo), for its reach checks.
local bossMoves: { [string]: World.Wild } = {}

-- The boss at its move's pose at `now`, on the ground (its lift is drawn by clients), facing its heading.
local function bossCFrame(move: BossChoreo.Move, now: number): CFrame
	local x, z, hx, hz = BossChoreo.world(move, now)
	local ground = surfaceBelow(Vector3.new(x, crater().Y + 200, z), 400) or CFrame.new(x, 0, z)
	local at = ground.Position
	return CFrame.lookAt(at, at + Vector3.new(hx, 0, hz))
end

-- The fountain centre in world studs: the boss's plaza coordinates are round it.
function WorldView.plazaOrigin(): Vector3
	return crater()
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

-- Where a carried slime sits: its bottom (the model pivot) on top of the carrier's Head, welded to the Head so it
-- bobs with it. Without a Head it sits CARRY_HEIGHT above the root.
function WorldView.carrySeat(root: BasePart): (BasePart, CFrame)
	local character = root.Parent
	local head = character and character:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		local up = root.CFrame.UpVector
		local top = head.Position + up * (head.Size.Y / 2)
		return head, root.CFrame.Rotation + top
	end
	return root, root.CFrame * CFrame.new(0, WorldView.CARRY_HEIGHT, 0)
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
				-- A lane walker stays Riding through the lead-in; the lane loop clears it there.
				if not laneWalks[id] then
					record.model:SetAttribute(Constants.RIDING_ATTRIBUTE, nil)
				end
				return
			end
			RunService.Heartbeat:Wait()
		end
	end)
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
	return ParadeLane.wildLateral(wild.radius)
end

-- FEATURES.SlimeChoreo: its lane beats (ParadeChoreo), built once per wild record.
local plans: { [World.Wild]: ParadeChoreo.Plan } = setmetatable({}, { __mode = "k" }) :: any

-- Studs a lane wild is ahead of (+) or behind (-) its plain lane spot at `now` (0 without a plan).
local function laneAhead(wild: World.Wild, now: number): number
	local choreo = wild.choreo
	if not choreo then
		return 0
	end
	local startAt, seconds, lead = ParadeLane.walkTimes(wild.spawnedAt, wild.expiresAt)
	local plan = plans[wild]
	if not plan then
		plan = ParadeChoreo.plan(choreo.seed, SlimePersona.of(wild.slime.species).temper, seconds, lead)
		plans[wild] = plan
	end
	return ParadeChoreo.offset(plan, now - startAt) * ParadeLane.walkSpeed(wild.expiresAt - wild.spawnedAt)
end

-- `drawn` (LaneTraffic): the lane distance the queue lets it walk at, when that differs from its plan.
local function laneCFrame(wild: World.Wild, now: number, drawn: number?): CFrame
	local ahead = if drawn
		then drawn - ParadeLane.distance(wild.spawnedAt, wild.expiresAt, now)
		else laneAhead(wild, now)
	local pose = ParadeLane.pose(wild.spawnedAt, wild.expiresAt, laneLateral(wild), now, ahead)
	local p, h = pose.position, pose.heading
	local at = Vector3.new(p[1], p[2], p[3])
	return CFrame.lookAt(at, at + Vector3.new(h[1], 0, h[2]))
end

-- A parade slime's ride is the emerge + slide only: it leaves the mouth at ParadeLane.RIDE_SECONDS and is
-- already on the lane walk there (laneCFrame), so there is no run-out glide to the lane and no wait.
local function laneRide(wild: World.Wild): (number, (t: number) -> CFrame)
	local ride = FountainRide.new(WorldLayout.SLIDE_PATH, ParadeLane.entrySpot(laneLateral(wild)))
	local seconds = ParadeLane.RIDE_SECONDS
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
-- Lane slimes walking the parade: one loop pivots them all each Heartbeat, after LaneTraffic has queued them
-- (a slime never walks into the one ahead), until a record changes (grabbed, dropped) or the model is gone.
local laneDrawn: { [string]: number } = {} -- LaneTraffic state: the lane distance each walker is drawn at
local laneLoop = false

local function laneWalker(id: string, wild: World.Wild, now: number): LaneTraffic.Walker
	local lifetime = wild.expiresAt - wild.spawnedAt
	local pace = ParadeLane.walkSpeed(lifetime)
	local s = ParadeLane.distance(wild.spawnedAt, wild.expiresAt, now) + laneAhead(wild, now)
	local left = wild.expiresAt - ParadeLane.DRAIN_SECONDS - now
	return {
		id = id,
		s = s,
		lateral = laneLateral(wild),
		radius = Config.SLIME_BASE_DIAMETER * (wild.slime.size or 1) / 2,
		pace = pace,
		floor = s - LaneTraffic.holdLimit(left, pace),
	}
end

local function stepLanes(dt: number)
	local now = workspace:GetServerTimeNow()
	local clock = os.clock()
	local walkers: { LaneTraffic.Walker } = {}
	for id, walk in laneWalks do
		local record = records[id]
		if not record or record.key ~= walk.key or not record.model.Parent then
			laneWalks[id] = nil
		elseif
			clock >= record.rideUntil and ParadeLane.phase(walk.wild.spawnedAt, walk.wild.expiresAt, now) == "Walk"
		then
			table.insert(walkers, laneWalker(id, walk.wild, now))
		end
	end
	LaneTraffic.step(walkers, laneDrawn, dt)
	for id, walk in laneWalks do
		local record = records[id]
		if record and clock >= record.rideUntil then
			local wild = walk.wild
			record.model:PivotTo(laneCFrame(wild, now, laneDrawn[id]))
			-- still Riding through the lead-in from the slide mouth (it crosses the landing ring's gap), queue included
			local leading = (laneDrawn[id] or ParadeLane.distance(wild.spawnedAt, wild.expiresAt, now)) < 0
			if (record.model:GetAttribute(Constants.RIDING_ATTRIBUTE) == true) ~= leading then
				record.model:SetAttribute(Constants.RIDING_ATTRIBUTE, if leading then true else nil)
			end
		end
	end
end

local function followLane(id: string, key: string, wild: World.Wild)
	laneWalks[id] = { key = key, wild = wild }
	if laneLoop then
		return
	end
	laneLoop = true
	task.spawn(function()
		local safeCall = SafeCall.new(warn)
		local dt = 0
		while true do
			safeCall("lane step", stepLanes, dt)
			dt = RunService.Heartbeat:Wait()
		end
	end)
end

-- Keeps the boss Body near its move (BOSS.MOVE_PIVOT_INTERVAL) until its record changes. Clients draw the move
-- itself every frame (BossMove attribute), so the Body only has to be close: the prompt, streaming and the label.
local function followBoss(id: string, key: string, wild: World.Wild)
	task.spawn(function()
		while true do
			local record = records[id]
			local move = wild.move
			if not record or record.key ~= key or not record.model.Parent or not move or wild.position ~= nil then
				return
			end
			record.model:PivotTo(bossCFrame(move, workspace:GetServerTimeNow()))
			task.wait(Config.BOSS.MOVE_PIVOT_INTERVAL)
		end
	end)
end

WorldView.WALK_STEP_UP = 3 -- studs above its last height a walking slime looks for the ground (steps, ramps)
WorldView.WALK_RAY_DEPTH = 12 -- and how far below that
WorldView.WALK_Y_RATE = 10 -- 1 / s: how fast its height follows the ground (no snapping over an edge)

-- Ground height under a returning slime at (x, z), near `y`, easing onto the goo crown (LANE_Y) over its last
-- lane width so it hands over to the lane pose without a step. Keeps `y` where there is no ground.
local function walkHeight(plan: ParadeLane.Return, x: number, z: number, y: number, now: number): number
	local up = WorldView.WALK_STEP_UP
	local ground = surfaceBelow(Vector3.new(x, y + up, z), up + WorldView.WALK_RAY_DEPTH)
	local target = if ground then ground.Y else y
	local left = plan.length - ParadeLane.returnTravelled(now - plan.startAt, plan.speed)
	local onto = 1 - math.clamp(left / (2 * ParadeLane.HALF_WIDTH), 0, 1)
	return target + (ParadeLane.LANE_Y - target) * onto * onto * (3 - 2 * onto)
end

local function returnCFrame(plan: ParadeLane.Return, y: number, now: number): CFrame
	local x, z, hx, hz = ParadeLane.returnPose(plan, now)
	local at = Vector3.new(x, y, z)
	return CFrame.lookAt(at, at + Vector3.new(hx, 0, hz))
end

-- Where a dropped slime lands before it walks back: the plan's start on the ground under the drop (LANE_Y when
-- there is none), facing its first step.
local function returnStart(wild: World.Wild, plan: ParadeLane.Return): CFrame
	local fromY = if typeof(wild.position) == "Vector3" then wild.position.Y else ParadeLane.LANE_Y
	local ground =
		surfaceBelow(Vector3.new(plan.fromX, fromY + WorldView.DROP_RAY_UP, plan.fromZ), WorldView.DROP_RAY_DEPTH)
	return returnCFrame(plan, if ground then ground.Y else ParadeLane.LANE_Y, plan.startAt)
end

-- Walks a dropped slime back to the parade lane (contract/slime-walk.md): the server pivots it along
-- ParadeLane.returnPose every Heartbeat, on the ground under it, until its record changes (grabbed, or arrived:
-- Spawner clears wild.returning and the lane takes over) or the model is gone.
WorldView.STEP_ASIDE_RATE = 4 -- 1 / s: how fast a walking slime steps round a slime or the boss in its way

-- The other slime bodies near (x, z), for LaneTraffic.push.
local function bodiesNear(self: string, x: number, z: number, reach: number): { LaneTraffic.Body }
	local out = {}
	for otherId, record in records do
		if otherId ~= self and record.model.Parent and not record.egg then
			local p = record.body.Position
			local dx, dz = p.X - x, p.Z - z
			if dx * dx + dz * dz < reach * reach then
				table.insert(out, { x = p.X, z = p.Z, radius = record.body.Size.X / 2 * record.model:GetScale() })
			end
		end
	end
	return out
end

local function followReturn(id: string, key: string, plan: ParadeLane.Return, y0: number)
	task.spawn(function()
		local y = y0
		local dt = 0
		local asideX, asideZ = 0, 0 -- steps round other slimes and the boss
		while true do
			local record = records[id]
			if not record or record.key ~= key or not record.model.Parent then
				return
			end
			if os.clock() >= record.rideUntil then
				local now = workspace:GetServerTimeNow()
				local x, z = ParadeLane.returnPose(plan, now)
				-- Step round anything in the way, easing back onto the path once it is clear (gone by arrival).
				local radius = record.body.Size.X / 2
				local px, pz = LaneTraffic.push(x, z, radius, bodiesNear(id, x, z, radius + 12))
				local k = math.min(1, dt * WorldView.STEP_ASIDE_RATE)
				local fade = math.clamp((plan.arriveAt - now) / 1.5, 0, 1)
				asideX += (px * fade - asideX) * k
				asideZ += (pz * fade - asideZ) * k
				x, z = x + asideX, z + asideZ
				local target = walkHeight(plan, x, z, y, now)
				y += (target - y) * math.min(1, dt * WorldView.WALK_Y_RATE)
				local cf = returnCFrame(plan, y, now)
				record.model:PivotTo(cf + Vector3.new(asideX, 0, asideZ))
			end
			dt = RunService.Heartbeat:Wait()
		end
	end)
end

-- The walk back's path (contract/slime-walk.md): PathfindingService round walls, through doorways (the lock
-- barrier is pass-through, setBarrierSolid) and over bridges; JarRoute down a jar tower's spiral stair first, which
-- the navmesh can't see.
WorldView.PATH_AGENT = table.freeze({
	AgentRadius = 1.5,
	AgentHeight = 4, -- above WALK_STEP_UP: nothing over the path is low enough for the ground ray to land on
	AgentCanJump = true,
	AgentCanClimb = false,
	WaypointSpacing = 4,
})

local function plotFrame(index: number): CFrame
	local centre, yaw = WorldLayout.plotCentre(index)
	return CFrame.new(centre[1], centre[2], centre[3]) * CFrame.Angles(0, math.rad(yaw), 0)
end

local function append(route: { number }, x: number, z: number)
	table.insert(route, x)
	table.insert(route, z)
end

-- The tower leg (world x, z) when `at` is on an upper floor that stands, and the ground-floor spot it ends on.
-- The plot's base id (its PlotBase attribute, CONTRACT.md §44), nil for the jar.
local function baseOf(plot: Instance): string?
	local base = plot:GetAttribute(Constants.PLOT_BASE_ATTRIBUTE)
	return if type(base) == "string" then base else nil
end

local function towerLeg(at: Vector3): ({ number }?, Vector3?)
	for index = 1, Config.PLOT_COUNT do
		local frame = plotFrame(index)
		local p = frame:PointToObjectSpace(at)
		local plot = WorldView.plot(index)
		local route = plot == nil or BaseShapes.get(baseOf(plot)).route
		local leg = if route then JarRoute.down(p.X, p.Y, p.Z) else nil
		if leg and plot and plot:FindFirstChild(`Floor_{WorldLayout.floorAt(p.Y)}`) then
			local out = {}
			for k = 1, #leg, 2 do
				local w = frame:PointToWorldSpace(Vector3.new(leg[k], 0, leg[k + 1]))
				append(out, w.X, w.Z)
			end
			local foot = Vector3.new(leg[#leg - 1], WorldLayout.floorTop(1), leg[#leg])
			return out, frame:PointToWorldSpace(foot)
		end
	end
	return nil, nil
end

-- PathfindingService waypoints (world x, z) between `from` and `goal`, both ends left out; nil when there is no path.
local function groundLeg(from: Vector3, goal: Vector3): { number }?
	local path = PathfindingService:CreatePath(WorldView.PATH_AGENT :: any)
	local ok = pcall(function()
		path:ComputeAsync(from, goal)
	end)
	if not ok or path.Status ~= Enum.PathStatus.Success then
		return nil
	end
	local waypoints = path:GetWaypoints()
	local out = {}
	for k = 2, #waypoints - 1 do
		local p = waypoints[k].Position
		append(out, p.X, p.Z)
	end
	return out
end

-- Finds the path for a slime that was just dropped at `start` and swaps it in (Carry.reroute) while it falls.
local function routeHome(world: World.World, id: string, plan: ParadeLane.Return, start: Vector3)
	task.spawn(function()
		local route: { number } = {}
		local tower, foot = towerLeg(start)
		if tower then
			table.move(tower, 1, #tower, 1, route)
		end
		local ground = groundLeg(foot or start, Vector3.new(plan.x1, ParadeLane.LANE_Y, plan.z1))
		if ground then
			table.move(ground, 1, #ground, #route + 1, route)
		end
		Carry.reroute(world, id, plan.startAt, route, workspace:GetServerTimeNow())
	end)
end

-- An escaped slime glides home flat (eased, facing its pad), no arc.
local function glide(from: CFrame, to: CFrame): (t: number) -> CFrame
	local flat = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local facing = if flat.Magnitude > 1e-3 then flat.Unit else to.LookVector
	return function(t: number): CFrame
		if t >= 1 then
			return to
		end
		local u = t * t * (3 - 2 * t)
		local at = from.Position:Lerp(to.Position, u)
		return CFrame.lookAt(at, at + facing)
	end
end

local function setAttr(instance: Instance, name: string, value: any)
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

local function eggMesh(name: string): MeshPart?
	local mesh = eggMeshes[name]
	if mesh == nil or mesh == false then
		return nil
	end
	return mesh :: MeshPart
end

-- Builds a Mystery Egg model: the uploaded meshes when they loaded, else primitives.
local function buildEgg(entry: Scene.Entry): Model
	local kind = (entry.slime.egg :: EggKind.Egg).kind
	return EggModel.build(entry.id, kind, {
		shell = eggMesh(`mystery_egg_{kind}`),
		nest = eggMesh("mystery_egg_nest"),
	})
end

local function create(entry: Scene.Entry, onPrompt: (Player, string) -> (), onHatch: (Player, string) -> ()): Record?
	local isEgg = EggKind.isEgg(entry.slime)
	if failed[entry.id] or (not modelFactory and not isEgg) then
		return nil
	end
	local ok, model = pcall(if isEgg then buildEgg else modelFactory.build, if isEgg then entry else entry.slime)
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
	local hatch: ProximityPrompt? = nil
	if isEgg then
		local p = Instance.new("ProximityPrompt")
		p.Name = Constants.HATCH_PROMPT_NAME
		p.ActionText = "Hatch!"
		p.ObjectText = Genome.displayName(entry.slime)
		local keys = Constants.SLIME_PROMPT_KEYS.hatch
		p.KeyboardKeyCode = (Enum.KeyCode :: any)[keys.keyboard]
		p.GamepadKeyCode = (Enum.KeyCode :: any)[keys.gamepad]
		p.RequiresLineOfSight = false
		p.HoldDuration = Config.HOLD_CONFIRM_SECONDS
		p.MaxActivationDistance = Config.STEAL_REACH - 2
		p.Enabled = false
		p.Parent = body
		p.Triggered:Connect(function(player: Player)
			onHatch(player, id)
		end)
		hatch = p
	end
	return {
		model = model,
		body = body,
		prompt = prompt,
		hatch = hatch,
		egg = isEgg,
		species = entry.slime.species,
		key = "",
		placed = false,
		weld = nil,
		rideUntil = 0,
		walking = nil,
		pendingKit = if slimeMesh and not isEgg then SlimeMesh.pendingKit(slimeMesh, entry.slime) else nil,
	}
end

local function unweld(record: Record)
	if record.weld then
		record.weld:Destroy()
		record.weld = nil
	end
	record.body.Anchored = true
end

local function clearGhost(record: Record)
	if record.ghost then
		record.ghost:Destroy()
		record.ghost = nil
	end
end

-- Leaves a see-through copy on the pad while a thief carries the slime off (before the model moves to them).
local function syncGhost(record: Record, entry: Scene.Entry)
	if not StealGhost.wants(entry) then
		clearGhost(record)
		return
	end
	if record.ghost and record.ghost.Parent then
		return
	end
	local plotIndex, pad = entry.plotIndex :: number, entry.pad :: number
	local plot = WorldView.plot(plotIndex)
	local target = padTop(plotIndex, pad)
	if not plot or not target then
		return
	end
	record.ghost = StealGhost.build(record.model, target, plot, Config.STEAL_GHOST_TRANSPARENCY)
end

-- The carried boss drips a goo trail, so chasers can find the carrier; it goes when the boss is put down.
local GOO_TRAIL = "BossGooTrail"
local function syncGooTrail(record: Record, on: boolean)
	local body = record.body
	local trail = body:FindFirstChild(GOO_TRAIL)
	if not on then
		if trail then
			trail:Destroy()
		end
		for _, name in { "GooTrailA", "GooTrailB" } do
			local a = body:FindFirstChild(name)
			if a then
				a:Destroy()
			end
		end
		return
	end
	if trail then
		return
	end
	local half = body.Size.X * 0.35
	local a0 = Instance.new("Attachment")
	a0.Name = "GooTrailA"
	a0.Position = Vector3.new(-half, -body.Size.Y / 2, 0)
	a0.Parent = body
	local a1 = Instance.new("Attachment")
	a1.Name = "GooTrailB"
	a1.Position = Vector3.new(half, -body.Size.Y / 2, 0)
	a1.Parent = body
	local t = Instance.new("Trail")
	t.Name = GOO_TRAIL
	t.Attachment0, t.Attachment1 = a0, a1
	t.Color = ColorSequence.new(Color3.fromRGB(110, 210, 90))
	t.Transparency = NumberSequence.new(0.2, 1)
	t.Lifetime = 2.5
	t.LightEmission = 0.3
	t.FaceCamera = true
	t.Parent = body
end

-- Returns false when the model couldn't be placed yet (retried next reconcile).
local function place(world: World.World, record: Record, entry: Scene.Entry, previous: string?): boolean
	local model = record.model
	model:SetAttribute("OwnerUserId", entry.ownerUserId)
	model:SetAttribute("State", entry.state)
	model:SetAttribute("Price", entry.price)
	SlimeShineView.apply(model, entry.slime)
	local grabNeed = if entry.state == "Wild" and not entry.boss then GrabBlock.rebirthsFor(entry.slime) else 0
	model:SetAttribute(Constants.GRAB_REBIRTHS_ATTRIBUTE, if grabNeed > 0 then grabNeed else nil)
	model:SetAttribute(Constants.BOSS_ATTRIBUTE, if entry.boss then true else nil)
	-- The lane beats: the client rebuilds the same ParadeChoreo plan from these (contract/slime-life.md).
	local choreo = if entry.state == "Wild"
			and entry.wild
			and entry.wild.position == nil
		then entry.wild.choreo
		else nil
	model:SetAttribute(Constants.CHOREO_SEED_ATTRIBUTE, if choreo then choreo.seed else nil)
	model:SetAttribute(Constants.LANE_AT_ATTRIBUTE, if choreo and entry.wild then entry.wild.spawnedAt else nil)
	model:SetAttribute(Constants.LANE_UNTIL_ATTRIBUTE, if choreo and entry.wild then entry.wild.expiresAt else nil)
	model:SetAttribute(Constants.RARE_ATTRIBUTE, entry.rare)
	-- A dropped wild egg: clients play the smash (contract/mystery-egg.md 40.7). Set before the model moves, so the
	-- client's copy starts where the carrier held it.
	model:SetAttribute(Constants.EGG_SMASHED_AT_ATTRIBUTE, if entry.wild then entry.wild.smashedAt else nil)

	syncGhost(record, entry)
	syncGooTrail(record, entry.boss and entry.state == "Carried")
	if entry.state == "Carried" then
		local carrier = entry.carrierUserId and Players:GetPlayerByUserId(entry.carrierUserId)
		local root = WorldView.rootPart(carrier)
		if not root then
			return false
		end
		unweld(record)
		local anchor, seat = WorldView.carrySeat(root)
		model:PivotTo(seat)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = anchor
		weld.Part1 = record.body
		weld.Parent = record.body
		record.weld = weld
		record.body.Anchored = false
		return true
	end

	local from = model:GetPivot()
	local fallUntil = record.rideUntil
	unweld(record)
	record.rideUntil = 0
	model:SetAttribute(Constants.RIDING_ATTRIBUTE, nil)
	-- The fighting boss is BOSS.SCALE x its size; it pops back to 1 for the haul.
	local scale = entry.bossScale or 1
	if math.abs(model:GetScale() - scale) > 1e-3 then
		model:ScaleTo(scale)
	end
	if entry.state == "Wild" then
		model.Parent = workspace:FindFirstChild(Constants.WILD_FOLDER)
		local wild = entry.wild
		if not wild then
			return true
		end
		if entry.boss and wild.position == nil and wild.move then
			-- The boss moves round its plaza spot (no parade lane, no fountain ride) and stands where the haul caught it.
			model:PivotTo(bossCFrame(wild.move, workspace:GetServerTimeNow()))
			followBoss(entry.id, entry.key, wild)
			return true
		end
		local plan = wild.returning
		if ParadeLane.enabled() and plan then
			-- Dropped: it falls out of the carrier's arms, then walks back to the lane.
			local start = returnStart(wild, plan)
			local walking = record.walking
			record.walking = plan
			if previous ~= nil and walking and walking.startAt == plan.startAt then
				-- The same walk on its new path (Carry.reroute): finish the fall it was in, then walk.
				local left = fallUntil - os.clock()
				if left > 0 then
					record.rideUntil = os.clock() + left
					animate(entry.id, entry.key, left, function(t: number): CFrame
						return from:Lerp(start, t)
					end)
				end
				followReturn(entry.id, entry.key, plan, if left > 0 then start.Y else from.Y)
			elseif previous ~= nil then
				record.rideUntil = os.clock() + WorldView.FALL_SECONDS
				animate(entry.id, entry.key, WorldView.FALL_SECONDS, function(t: number): CFrame
					return from:Lerp(start, t * t)
				end)
				followReturn(entry.id, entry.key, plan, start.Y)
				routeHome(world, entry.id, plan, start.Position)
			else
				local now = workspace:GetServerTimeNow()
				local y = if now > plan.startAt then ParadeLane.LANE_Y else start.Y
				model:PivotTo(returnCFrame(plan, y, now))
				followReturn(entry.id, entry.key, plan, y)
			end
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
	local target = entry.plotIndex and entry.pad and padTop(entry.plotIndex, entry.pad)
	if not target then
		-- Its pad is not built yet (a join with slimes on upper floors: BaseFloors builds them after this
		-- reconcile): retried next time, so it lands on the pad once it is there.
		return false
	end
	model.Parent = folder or plot
	if entry.state == "Escaping" and previous ~= nil then
		animate(entry.id, entry.key, World.ESCAPE_BOUNCE_SECONDS, glide(from, target))
	else
		model:PivotTo(target)
	end
	return true
end

-- A slime built before its species kit loaded wears the shared mesh; once the kit is in, it is rebuilt in its own
-- look. Only while it sits on a pad or walks wild: a carried, escaping or riding slime waits until it lands.
local function kitArrived(record: Record, entry: Scene.Entry, clock: number): boolean
	local kit = record.pendingKit
	return kit ~= nil
		and slimeMesh ~= nil
		and SlimeMesh.hasKit(slimeMesh, kit)
		and (entry.state == "Pad" or entry.state == "Wild")
		and clock >= record.rideUntil
end

-- A pad slime's status row: the vat's ("In vat"), else none.
function WorldView.padStatus(owner: any, id: string): string?
	return VatView.labelStatus(owner.data, id)
end

--[[
	Creates, moves and destroys slime models to match the World. Call a few
	times a second and after any action.
]]
-- Plots whose pads moved (a base swap, server/BaseShapeSwap): their pad slimes are placed again on the next reconcile.
local stalePlots: { [number]: boolean } = {}
function WorldView.replacePlotSlimes(plotIndex: number)
	stalePlots[plotIndex] = true
end

function WorldView.reconcile(
	world: World.World,
	now: number,
	onPrompt: (Player, string) -> (),
	onHatch: (Player, string) -> ()
)
	local entries = Scene.describe(world, now)
	local clock = os.clock()
	for id, record in records do
		local entry = entries[id]
		if
			not entry
			or record.egg ~= EggKind.isEgg(entry.slime)
			or record.species ~= entry.slime.species
			or kitArrived(record, entry, clock)
		then
			clearGhost(record)
			record.model:Destroy()
			records[id] = nil
		end
	end
	table.clear(bossMoves)
	for id, entry in entries do
		local record: Record? = records[id]
		if not record then
			record = create(entry, onPrompt, onHatch)
			if not record then
				continue
			end
			records[id] = record
		end
		assert(record, "record")
		record.prompt.ActionText = entry.promptText
		-- GuestsOnly before Enabled: a client applies them in order, so the prompt never shows un-gated for a frame.
		record.prompt:SetAttribute(Constants.PROMPT_GUESTS_ATTRIBUTE, entry.guestsOnly)
		record.prompt.Enabled = entry.promptEnabled
		record.prompt:SetAttribute(Constants.PROMPT_HIDE_ATTRIBUTE, entry.hideFromUserId)
		record.prompt.HoldDuration = entry.promptHold
		-- The hatch show (contract/mystery-egg.md §40.6): on the egg model during the wobble, then on the slime
		-- model (set before a new model is parented in place()).
		local hatched = entry.hatch
		setAttr(record.model, Constants.HATCHED_AT_ATTRIBUTE, hatched and hatched.at)
		setAttr(record.model, Constants.HATCHED_FROM_ATTRIBUTE, hatched and hatched.kind)
		setAttr(record.model, Constants.HATCH_LUCKY_ATTRIBUTE, if hatched and hatched.lucky then true else nil)
		setAttr(record.model, Constants.HATCH_TIER_ATTRIBUTE, if hatched and record.egg then hatched.tier else nil)
		-- The Lucky Charm show (contract/lucky-charm.md): on the caught model, then on the promoted one.
		local lucky = entry.lucky
		setAttr(record.model, Constants.LUCKY_AT_ATTRIBUTE, lucky and lucky.at)
		setAttr(record.model, Constants.LUCKY_FROM_TIER_ATTRIBUTE, lucky and lucky.before.tier)
		if record.egg then
			local egg = entry.slime.egg :: EggKind.Egg
			local kind = EggKind.get(egg.kind)
			setAttr(record.model, Constants.EGG_HATCH_AT_ATTRIBUTE, egg.hatchAt)
			setAttr(record.model, Constants.EGG_HATCH_SECONDS_ATTRIBUTE, kind and kind.hatchSeconds)
			EggModel.showNest(record.model, entry.state == "Pad")
			local hatch = record.hatch
			if hatch then
				if hatch.Enabled ~= entry.hatchReady then
					hatch.Enabled = entry.hatchReady
				end
				local text = entry.hatchText or Genome.displayName(entry.slime)
				if hatch.ObjectText ~= text then
					hatch.ObjectText = text
				end
				-- Owner tag only while ready: PromptHide re-enables an owner prompt when its owner becomes the
				-- local player, which would show Hatch on an egg that isn't ready (a stolen one, say).
				setAttr(hatch, Constants.PROMPT_OWNER_ATTRIBUTE, if entry.hatchReady then entry.ownerUserId else nil)
			end
		end
		-- Every reconcile, not only in place(): the telegraph window opens without a key change.
		record.model:SetAttribute(Constants.DESPAWN_AT_ATTRIBUTE, entry.despawnAt)
		-- The boss's move changes without a key change; clients draw it from this (BossChoreo).
		local move = if entry.boss
				and entry.state == "Wild"
				and entry.wild
				and entry.wild.position == nil
			then entry.wild.move
			else nil
		setAttr(record.model, Constants.BOSS_MOVE_ATTRIBUTE, if move then BossChoreo.encode(move) else nil)
		if move and entry.wild then
			bossMoves[id] = entry.wild
		end
		SlimeLabelView.applyGrowth(record.model, entry.slime, now)
		local moved = entry.plotIndex ~= nil and entry.pad ~= nil and stalePlots[entry.plotIndex] == true
		if record.key ~= entry.key or moved then
			local previous = if record.placed and not moved then record.key else nil
			record.key = entry.key
			if place(world, record, entry, previous) then
				record.placed = true
			else
				record.key = "" -- retry next time
			end
			-- A carried slime is welded on its carrier wherever its model sits; one never placed stays out of
			-- workspace rather than show at its build spot.
			if record.placed and not record.model.Parent then
				record.model.Parent = workspace:FindFirstChild(Constants.WILD_FOLDER)
			end
		end
		-- After place(): the boss scale is applied there, and the label height is measured on the final scale.
		local owner = if entry.state == "Pad" then world.sessions[entry.ownerUserId] else nil
		SlimeLabelView.apply(
			record.model,
			record.body,
			entry.slime,
			entry.income,
			if entry.state == "Pad" then entry.pad else nil,
			now,
			if owner then WorldView.padStatus(owner, id) else nil
		)
	end
	table.clear(stalePlots) -- placed once on their new pads (a pad not built yet retries through its key)
	for id in failed do
		if not entries[id] then
			failed[id] = nil
		end
	end
	-- The boss's guards, goo puddles and the attributes its telegraphs are drawn from.
	local bossId = world.boss and world.boss.slimeId
	local bossRecord = if bossId then records[bossId] else nil
	local bossWild = if bossId then world.wild[bossId] else nil
	local tint = bossWild and bossWild.slime.color
	local origin = crater()
	local hx, hz = BossArea.home()
	local ground = surfaceBelow(Vector3.new(origin.X + hx, origin.Y + 200, origin.Z + hz), 400)
	BossFxView.sync(
		world,
		if bossRecord then bossRecord.model else nil,
		origin,
		if ground then ground.Y else 0,
		if tint then Color3.fromRGB(tint[1], tint[2], tint[3]) else nil,
		if modelFactory and bossWild then { build = modelFactory.build, slime = bossWild.slime } else nil,
		WorldView.bossFloor
	)
end

-- A slime model's Body (Effects target), or nil if it has no model.
local function modelOf(id: string): Model?
	local record = records[id]
	return if record then record.model else nil
end

function WorldView.slimeBody(id: string): BasePart?
	local record = records[id]
	return record and record.body
end

-- Server-side position of a slime's Body (for reach checks).
function WorldView.slimePosition(id: string): Vector3?
	local record = records[id]
	if not record then
		return nil
	end
	-- The moving boss: where its move has it now, not where the Body was last pivoted.
	local wild = bossMoves[id]
	local move = wild and wild.move
	if move and wild and wild.position == nil then
		local x, z = BossChoreo.world(move, workspace:GetServerTimeNow())
		return Vector3.new(x, record.body.Position.Y, z)
	end
	return record.body.Position
end

---------------------------------------------------------------------------
-- Plots and players
---------------------------------------------------------------------------

local plotPromptParts: { [string]: string } = {
	[Constants.LOCK_PROMPT_NAME] = "LockButton",
	[Constants.FRIENDS_PROMPT_NAME] = "LockButton",
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
		[Constants.FRIENDS_PROMPT_NAME] = "ToggleFriends",
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
			-- The vat prompt only opens the merge vat menu (the menu confirms each step), so it is instant.
			local opensMenu = kind == "Merge"
			prompt.HoldDuration = if opensMenu then 0 else Config.HOLD_CONFIRM_SECONDS
			if kind == "Lock" or kind == "ToggleFriends" then
				-- Both sit on the LockButton: Custom style, so the client's key card draws one card with a row each
				-- instead of two Roblox bubbles on the same spot (ui/SlimeKeyCard).
				prompt.Style = Enum.ProximityPromptStyle.Custom
			end
			if kind == "ToggleFriends" then
				local keys = Constants.FRIENDS_PROMPT_KEYS
				prompt.KeyboardKeyCode = (Enum.KeyCode :: any)[keys.keyboard]
				prompt.GamepadKeyCode = (Enum.KeyCode :: any)[keys.gamepad]
				prompt.HoldDuration = 0 -- free and undoable
			end
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

-- The part plot `index`'s prompt `kind` ("Lock" | "ToggleFriends" | "Merge" | "BuyPad") sits on (BuyPad moves), or nil.
function WorldView.plotPromptPart(index: number, kind: string): BasePart?
	local name = if kind == "Lock"
		then Constants.LOCK_PROMPT_NAME
		elseif kind == "ToggleFriends" then Constants.FRIENDS_PROMPT_NAME
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
local setOpenDoorSolid: (Instance, boolean) -> ()

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

-- Lock enforcement. The LockBarrier panels ship non-colliding (client cosmetics); the server makes
-- them solid while the plot is locked. Panels sit in PlotLock_<i>, the owner's character in
-- PlotOwner_<i>, and that pair does not collide, so the owner walks through. Everyone else is blocked both ways
-- (PlotLockGuard): no way in, and an intruder inside stays in until the lock ends.
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
end

-- Guests (PlotGuests) and former guests still inside (SlimeGuard.formerGuests): plot i's stopper also lets player
-- p through by making PlotLock_<i> x PlotOwner_<p's plot> non-colliding. Every player owns one plot, so that group is
-- p's character and no new groups are needed. Only pairs that changed are touched; the settings replicate to every
-- client. Returns who passes each plot's stopper (SlimeGuard.stopperPasses), for the plot's Guests attribute.
local guestPairs: { [string]: { lock: string, owner: string } } = {}
local function syncGuestPairs(world: World.World): { [number]: { number } }
	ensureGroups()
	local passes = SlimeGuard.stopperPasses(world)
	local wanted: { [string]: { lock: string, owner: string } } = {}
	for i, ids in passes do
		for _, id in ids do
			local visitor = world.sessions[id]
			local j = visitor and visitor.plotIndex
			if j and i ~= j then
				wanted[`{i}:{j}`] = { lock = PlotLockGuard.lockGroup(i), owner = PlotLockGuard.ownerGroup(j) }
			end
		end
	end
	for key, pair in guestPairs do
		if not wanted[key] then
			pcall(function()
				PhysicsService:CollisionGroupSetCollidable(pair.lock, pair.owner, true)
			end)
			guestPairs[key] = nil
		end
	end
	for key, pair in wanted do
		if not guestPairs[key] then
			local ok, err = pcall(function()
				PhysicsService:CollisionGroupSetCollidable(pair.lock, pair.owner, false)
			end)
			if ok then
				guestPairs[key] = pair
			else
				warn(`[WorldView] guest pair {key}: {err}`)
			end
		end
	end
	return passes
end

function setBarrierSolid(plot: Instance, index: number, solid: boolean)
	local barrier = plot:FindFirstChild("LockBarrier")
	if not barrier then
		return
	end
	ensureGroups()
	for _, panel in barrier:GetChildren() do
		if panel:IsA("BasePart") then
			-- A dropped slime's path back to the lane goes through a shut door (routeHome).
			if not panel:FindFirstChildOfClass("PathfindingModifier") then
				local modifier = Instance.new("PathfindingModifier")
				modifier.PassThrough = true
				modifier.Parent = panel
			end
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

-- The open door (swung out on its hinges) is solid for everyone while the plot is open; while locked it is shut in
-- the doorway (the LockBarrier), so its open-door collider goes.
function setOpenDoorSolid(plot: Instance, solid: boolean)
	local collider = plot:FindFirstChild("OpenDoorCollider")
	if collider and collider:IsA("BasePart") and collider.CanCollide ~= solid then
		collider.CanCollide = solid
	end
end

local function setPartGroup(part: Instance, group: string)
	if part:IsA("BasePart") and part.CollisionGroup ~= group then
		pcall(function()
			part.CollisionGroup = group
		end)
	end
end

-- The group each live character is meant to be in; parts added later (tools, accessories) join it.
local characterGroups: { [Model]: string } = setmetatable({}, { __mode = "k" }) :: any

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

-- Characters the server just moved itself (userId -> true), taken by SlimeGuardView so the movement check skips
-- the jump. Runtime only.
local serverMoves: { [number]: boolean } = {}

function WorldView.markServerMove(userId: number)
	serverMoves[userId] = true
end

-- True once after the server moved this player's character.
function WorldView.takeServerMove(userId: number): boolean
	local moved = serverMoves[userId] == true
	serverMoves[userId] = nil
	return moved
end

local function markCharacterMoved(character: Model)
	local player = Players:GetPlayerFromCharacter(character)
	if player then
		WorldView.markServerMove(player.UserId)
	end
end

-- Server-initiated teleport of `character`: the move guard's next sample of that player re-baselines.
local function allowMove(character: Model, seconds: number)
	local owner = Players:GetPlayerFromCharacter(character)
	if owner then
		MoveWatch.allow(owner.UserId, seconds)
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
	allowMove(character, Config.MOVE_GUARD.TELEPORT_ALLOW)
	markCharacterMoved(character)
	return true
end

-- Per player: the character's collision group. The owner's character is in PlotOwner_<i> (walks through its own
-- barrier); everyone else is in Default, which every locked barrier blocks both ways unless they are let through
-- (syncGuestPairs). Nobody is moved for a lock.
function WorldView.enforceLocks(world: World.World, player: Player)
	local root = WorldView.rootPart(player)
	local character = player.Character
	if not root or not character then
		return
	end
	local own = World.session(world, player.UserId)
	local wanted = if own then PlotLockGuard.ownerGroup(own.plotIndex) else "Default"
	if root.CollisionGroup ~= wanted or characterGroups[character] ~= wanted then
		ensureGroups()
		setCharacterGroup(character, wanted)
	end
	ejectFromStack(character, root)
end

-- `floors` (nil on the greybox) builds and removes the plots' upper floors (BaseFloors).
function WorldView.updatePlots(world: World.World, now: number, floors: BaseFloors.Context?)
	local habitatsOn = Config.FEATURES.Habitats
	HabitatPads.step(habitats, world, now, habitatsOn)
	local passes = syncGuestPairs(world)
	for index = 1, world.plotCount do
		local plot = WorldView.plot(index)
		if plot then
			local userId = world.plots[index]
			local session = userId and world.sessions[userId]
			-- the base first (CONTRACT.md §44): BaseFloors builds the upper floors of the plot's base
			local base = if Config.FEATURES.BaseShapes and session
				then PlotBases.current(session.data)
				else Config.PLOT_BASE_DEFAULT
			if (plot:GetAttribute(Constants.PLOT_BASE_ATTRIBUTE) or Config.PLOT_BASE_DEFAULT) ~= base then
				BaseShapeSwap.swap(plot, index, base, nil, WorldView.markServerMove)
				plot:SetAttribute(Constants.PLOT_BASE_ATTRIBUTE, if Config.FEATURES.BaseShapes then base else nil)
				WorldView.replacePlotSlimes(index)
			elseif Config.FEATURES.BaseShapes then
				setIfChanged(plot, Constants.PLOT_BASE_ATTRIBUTE, base)
			end
			if floors then
				BaseFloors.sync(plot, index, if session then session.data.padsUnlocked else 0, floors)
			end
			local view = PlotPrompts.describe(world, index, now)
			setIfChanged(plot, "OwnerUserId", if session then session.userId else 0)
			setIfChanged(plot, "LockUntil", if session then session.lockUntil else 0)
			setIfChanged(plot, Constants.PLOT_LOCKED_ATTRIBUTE, view.locked)
			setIfChanged(plot, Constants.PLOT_FRIENDS_ALLOWED_ATTRIBUTE, if view.friendsAllowed then true else nil)
			setIfChanged(plot, Constants.PLOT_GUESTS_ATTRIBUTE, PlotGuests.encode(passes[index] or {}))
			setBarrierSolid(plot, index, view.locked)
			setOpenDoorSolid(plot, not view.locked)
			LockPadView.update(
				plot,
				index,
				WorldView.plotPromptPart(index, "Lock"),
				if session
					then LockPad.ring(now, session.lockUntil, session.lockStartedAt, session.lockPadSince)
					else LockPad.ring(now, 0, 0, nil)
			)
			setIfChanged(plot, Constants.PLOT_PADS_UNLOCKED_ATTRIBUTE, view.padsUnlocked)
			setIfChanged(plot, Constants.PLOT_NEXT_PAD_COST_ATTRIBUTE, view.nextPadCost)
			if Config.FEATURES.PlotSkins then
				setIfChanged(
					plot,
					Constants.PLOT_SKIN_ATTRIBUTE,
					if session then PlotSkins.current(session.data) else Config.PLOT_SKIN_DEFAULT
				)
			end
			local pads = plotPads(index)
			for pad = 1, Config.PADS_MAX do
				local part = pads[pad]
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
				applyPrompt(prompts[Constants.FRIENDS_PROMPT_NAME], view.friends, view.ownerUserId)
				applyPrompt(prompts[Constants.MERGE_PROMPT_NAME], view.merge, view.ownerUserId)
				local buyPad = prompts[Constants.BUY_PAD_PROMPT_NAME]
				local padPart = pads[view.buyPad.pad] or WorldView.pad(index, view.buyPad.pad)
				if buyPad and padPart and buyPad.Parent ~= padPart then
					buyPad.Parent = padPart
				end
				applyPrompt(buyPad, view.buyPad, view.ownerUserId)
			end
			VatView.sync(plot, index, if session then session.data else nil, now, modelOf, world.carriedBy)
			local sign = plot:FindFirstChild("Sign")
			if sign then
				PlotSigns.apply(
					sign,
					PlotSigns.lines(index, session, if session then World.incomeOf(world, session) else nil)
				)
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
	local size = zone.Size
	return HomeZone.contains(
		p.X,
		p.Y,
		p.Z,
		{ size.X, size.Y, size.Z },
		zone:GetAttribute("Radius"),
		zone:GetAttribute("ReachUp")
	)
end

-- The player's character root in plot `plotIndex`'s plot-local frame, y on WorldLayout.floorTop's scale (the Base's
-- top is PLOT_FLOOR_TOP), or nil without a character or plot.
function WorldView.plotPoint(userId: number, plotIndex: number): { number }?
	local root = WorldView.rootPart(Players:GetPlayerByUserId(userId))
	local plot = WorldView.plot(plotIndex)
	local base = plot and plot:FindFirstChild("Base")
	if not (root and base and base:IsA("BasePart")) then
		return nil
	end
	local p = base.CFrame:PointToObjectSpace(root.Position)
	return { p.X, p.Y - base.Size.Y / 2 + WorldLayout.PLOT_FLOOR_TOP, p.Z }
end

-- Drop tube (CONTRACT.md §5.3): puts the player's character in plot `plotIndex`'s splash pool, still. False when
-- there is no character or no plot.
function WorldView.dropDown(userId: number, plotIndex: number): boolean
	local player = Players:GetPlayerByUserId(userId)
	local character = player and player.Character
	local root = WorldView.rootPart(player)
	local plot = WorldView.plot(plotIndex)
	local base = plot and plot:FindFirstChild("Base")
	if not (character and root and base and base:IsA("BasePart")) then
		return false
	end
	local land = BaseShapes.get(baseOf(plot :: Instance)).dropLanding()
	local y = land[2] - WorldLayout.PLOT_FLOOR_TOP + base.Size.Y / 2
	character:PivotTo(base.CFrame * CFrame.new(land[1], y, land[3]))
	root.AssemblyLinearVelocity = Vector3.zero
	MoveWatch.allow(userId, Config.MOVE_GUARD.TELEPORT_ALLOW)
	WorldView.markServerMove(userId)
	return true
end

-- Spawn point on top of the plot's Base.
function WorldView.plotSpawn(plotIndex: number): CFrame?
	local plot = WorldView.plot(plotIndex)
	local base = plot and plot:FindFirstChild("Base")
	if base and base:IsA("BasePart") then
		local spot = WorldLayout.SPAWN_SPOT
		return base.CFrame * CFrame.new(spot[1], base.Size.Y / 2 + 4, spot[2])
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
	WorldView.markServerMove(player.UserId)
	for _, part in character:GetDescendants() do
		if part:IsA("BasePart") then
			part.AssemblyLinearVelocity = Vector3.zero
			part.AssemblyAngularVelocity = Vector3.zero
		end
	end
	MoveWatch.allow(player.UserId, Config.MOVE_GUARD.TELEPORT_ALLOW)
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
		tool.ToolTip = "Speed Coil: hold to run faster"
		tool.Parent = backpack
	end
end

function WorldView.updatePlayer(
	world: World.World,
	player: Player,
	session: World.Session,
	now: number,
	ctx: PvpService.Context
)
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
		setAttribute(player, Constants.PVP_EQUIPPED_ATTRIBUTE, PvpService.equipped(session))
		-- the held model (CONTRACT.md §26.3): put away while carrying, like the Tools
		PvpHeld.sync(character, if carry then nil else PvpService.equipped(session))
		local root = WorldView.rootPart(player)
		PvpTrap.tick(world, session, root and root.Position, now, ctx)
		PvpBlaster.tick(world, session, root and root.Position, now, ctx)
		PvpFun.tick(world, session, root and root.Position, now, ctx)
	end
	local pet = World.pet(world, session) -- a stolen pet stops following
	setAttribute(player, Constants.PET_ATTRIBUTE, pet and pet.id)
	setAttribute(player, Constants.PET_SEAT_ATTRIBUTE, PetSeats.current(data))
	if data.speedCoil then
		ensureSpeedCoil(player)
	end
	-- The coil only works while held (Merijn 2026-10-22): equipped = the Tool sits in the character.
	local coilHeld = data.speedCoil and character ~= nil and character:FindFirstChild(Constants.SPEED_COIL_TOOL) ~= nil
	if (session.coilHeld == true) ~= coilHeld then
		session.coilHeld = coilHeld
		World.markDirty(session) -- State.walkSpeed changes
	end
	local target = Carry.targetWalkSpeed(session, now) -- PvP holds / slows multiply in (PvpSlow, PvpFun)
	if Config.FEATURES.PvP and PvpFun.frozen(session, now) then
		target = 0 -- Fun bubble lift / pancake / dance (<= CONTROL_MAX_SECONDS)
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
