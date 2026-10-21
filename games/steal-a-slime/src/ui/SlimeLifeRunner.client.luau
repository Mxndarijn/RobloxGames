--!strict
--[[
	Runner for SlimeLife (TODO v28 #17): client-only idle life for wild and
	pad slimes (tag Constants.SLIME_TAG, State "Wild" / "Pad"). Nothing
	replicates; it never fires remotes.

	Why a rig and not PivotTo: VisualsClient (Archer) already owns the model
	pivot (bob, tilt) and rebases whenever someone else moves it,
	so a second PivotTo writer would make the two drift. Instead, for each
	slime picked by SlimeLife.select this adds a local, invisible "LifeRoot"
	part welded to Body and moves the decorations (eyes, mouth, rims, crown,
	the "Mesh" skin) from their WeldConstraint onto Welds from LifeRoot.
	Per frame only LifeRoot's weld C0 moves (look, wobble, sway) plus the
	skin's squash: the Mesh skin's Size, or a local SpecialMesh on the
	procedural Body ball (a Ball part can't be sized non-uniformly). Body
	itself never moves, so the pivot, the GrabPrompt and VisualsClient's
	blinks and bob are untouched; our motion rides on top of the bob.

	Released (parts put back, WeldConstraints re-enabled) as soon as the
	slime leaves the active set, changes State to one SlimeLife does not
	animate (Carried: the carry weld and VisualsClient's wriggle take over),
	gets DespawnAt (DespawnTelegraphFx shrinks it) or gains / loses a part.
	A motor rig survives a change between animated states (Wild / Pad /
	Escaping): it gets the new params and SlimeActor.setState. Any State
	change reselects on the next frame, so a slime put down on its pad is
	rigged (and drops in) the frame it arrives.

	Three drivers, picked per slime by SlimeAnim.mode (never none, a slime
	must not freeze):
	  "motor"  the default on a rigged slime (src/visuals/shared/SlimeRig):
	           SlimeMotor writes the pose to the FaceRoot / SkinRoot Motor6D
	           Transforms (+ the skin squash). No asset, no Animator. A species
	           mesh with Bones squashes, blinks and moves its accessories
	           through SlimeBones instead of the skin Size (same LOD tiers).
	  "anim"   only with Config.FEATURES.SlimeAnimations on AND after a probe
	           (one LoadAnimation of SlimeIdleSquish, off the select loop) saw
	           Length > 0: the slime's Animator plays the uploaded
	           SlimeIdleSquish (loop) and SlimeLookLeft / Right
	           (SlimeAnim schedules the events). A rig whose idle track is not
	           playing with Length > 0 after SlimeAnim.LOAD_TIMEOUT marks the
	           probe failed and every slime goes back to "motor".
	  "weld"   an unrigged slime: the LifeRoot / Weld path below.
	Both paths share the LOD: nearest SlimeLife.MAX_ACTIVE slimes, within
	MAX_DISTANCE and on screen.

	LOD (SlimeLod, Config.SLIME_LOD):
	the "motor" rigs get a tier per reselect from the camera distance and the
	saved graphics quality. With FEATURES.SlimeChoreo (an actor on every rig):
	every tier is drawn every frame from the smooth lane anchor, so no slime
	shows the Body's replication steps. near = the full SlimeActor life, for
	at most SLIME_LOD.NEAR_MAX rigs (SlimeLod.capNear); mid and far = the light
	detail (glide, gait, lane beats; no reactions, emotes or hop effects).
	Without it: near = full motion every frame, mid = squish only (smaller,
	every MID_EVERY frames), far = Transform reset once, then skipped. The
	model attribute LifeTier ("near" | "mid" | "far", client-only) says which;
	pc-watcher counts it.

	Cost: at most SlimeLife.MAX_ACTIVE rigs within SlimeLife.MAX_DISTANCE of
	the camera, 3-4 property writes each per frame, selection 4x a second,
	at most ACQUIRE_PER_TICK new rigs per tick, at most SlimeLife
	.MAX_SPARKLING emitters.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local MeshAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshAssets"))
local SlimeActor = require(script.Parent:WaitForChild("SlimeActor"))
local SlimeAnim = require(script.Parent:WaitForChild("SlimeAnim"))
local SlimeEmotes = require(script.Parent:WaitForChild("SlimeEmotes"))
local SlimeLife = require(script.Parent:WaitForChild("SlimeLife"))
local SlimeLod = require(script.Parent:WaitForChild("SlimeLod"))
local SlimeMotor = require(script.Parent:WaitForChild("SlimeMotor"))
local SlimeReact = require(script.Parent:WaitForChild("SlimeReact"))
local SlimeSpacing = require(script.Parent:WaitForChild("SlimeSpacing"))

local SELECT_EVERY = 0.25
local ACQUIRE_PER_TICK = 8
local ROOT_NAME = "LifeRoot"
local SQUASH_NAME = "LifeSquash"
local SKIN_NAME = "Mesh" -- SlimeMesh.MESH_NAME
-- SlimeRig (visuals/shared): the roots the decorations are welded to, and the Animator host.
local ROOT_PARTS = { FaceRoot = true, SkinRoot = true }
local SCREEN_MARGIN = 80 -- px outside the viewport that still count as on screen

type Piece = { part: BasePart, weld: Weld, offset: CFrame, constraint: WeldConstraint }

type Rig = {
	model: Model,
	body: BasePart,
	root: Part,
	joint: Weld,
	pieces: { Piece },
	skin: Piece?,
	skinSize: Vector3?,
	bodySize: Vector3, -- Body's size when the offsets and skinSize were measured
	squash: SpecialMesh?,
	params: SlimeLife.Params,
	clock: SlimeLife.Clock,
	sparkle: ParticleEmitter?,
	conns: { RBXScriptConnection },
	dirty: boolean,
}

type MotorRig = {
	model: Model,
	tier: SlimeLod.Tier,
	slot: number, -- staggers the mid-tier frames across slimes
	motor: SlimeMotor.Motor,
	actor: SlimeActor.Actor?, -- FEATURES.SlimeChoreo: gait, lane beats, reactions (near tier)
	params: SlimeLife.Params,
	sparkle: ParticleEmitter?,
	conns: { RBXScriptConnection },
}

type AnimRig = {
	model: Model,
	startedAt: number,
	checked: boolean,
	animator: Animator,
	tracks: SlimeAnim.Tracks,
	params: SlimeLife.Params,
	sched: SlimeAnim.Schedule,
	sparkle: ParticleEmitter?,
	conns: { RBXScriptConnection },
}

local slimes: { [Model]: boolean } = {}
local rigs: { [Model]: Rig } = {}
local animRigs: { [Model]: AnimRig } = {}
local motorRigs: { [Model]: MotorRig } = {}
local noMotor: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any -- motor step threw: this slime uses welds
local trackSets: { [Model]: SlimeAnim.Tracks } = setmetatable({}, { __mode = "k" }) :: any
-- FEATURES.SlimeChoreo drives every rig through SlimeMotor (gaits, beats, reactions ride on its Transform and bones),
-- so the uploaded KeyframeSequences stay off with it.
local animationsOn = Config.FEATURES.SlimeAnimations == true and Config.FEATURES.SlimeChoreo ~= true
local animationIds = if animationsOn then SlimeAnim.ids(MeshAssets.animationId) else nil
local probe: SlimeAnim.Verdict? = nil -- nil = not started; "wait" | "ok" | "failed"
local animationInstances: { [string]: Animation } = {} -- one per id, shared by every rig
local active: { [string]: boolean } = {}
local lodConfig: SlimeLod.Cfg = Config.SLIME_LOD
local qualityLevel: number? = nil
local frame = 0
local slotCounter = 0
local lifeOn = Config.FEATURES.SlimeChoreo == true
local emotes: SlimeEmotes.Pool? = nil
local slimeConns: { [Model]: { RBXScriptConnection } } = {}
-- The State each slime had before its current one (SlimeActor.attach: a Carried slime put on its pad drops in).
local prevStates: { [Model]: string? } = setmetatable({}, { __mode = "k" }) :: any
local lastStates: { [Model]: string? } = setmetatable({}, { __mode = "k" }) :: any
local stateAt: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any -- os.clock() of the last State change
-- A put-down plays only if the rig comes this soon after the State change (a slime rigged later just sits there).
local PUT_DOWN_WINDOW = 0.3
-- A pad slime whose Body jumps (a Move, a swap) while it has no rig (it was off screen) still hops over from where it
-- was: the jump is noted when it lands, the slime is rigged on the next frame and starts from the old spot.
local MOVE_JUMP = 1.5 -- studs (SlimeActor.MOVE_JUMP)
local padSpot: { [Model]: Vector3 } = setmetatable({}, { __mode = "k" }) :: any
local movedFrom: { [Model]: { at: Vector3, t: number } } = setmetatable({}, { __mode = "k" }) :: any
local hopping: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any -- os.clock() until it keeps its rig
local HOP_KEEP = 1.2 -- seconds a moved pad slime keeps its rig (its hop over, SlimeFidget.MOVE_HOP, and the splat)
local hiddenFor: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any -- frame it shows again
local nextSelect = 0
-- What every actor needs from this frame: the local character and its cash (leaderstats); filled by readFrame.
local lifeFrame: SlimeActor.Frame = { player = nil, cash = nil, userId = nil }
local lastFrameAt = os.clock()
local spacing: { SlimeSpacing.Item } = {} -- reused every frame
local spaced: { MotorRig } = {}
local PLAYER_RADIUS = 1.2 -- studs: the local character's footprint for SlimeSpacing
local playerSolid: SlimeSpacing.Solid = { x = 0, z = 0, r = PLAYER_RADIUS }
local playerSolids = { playerSolid }
-- Contract/slime-life.md social reactions: how far away neighbours notice a slime leaving.
local DRAIN_WATCH_DISTANCE = 20
local DRAIN_WATCH_SECONDS = 1.6
local BUMP_GAP = 0.85 -- share of the two radii two slimes may close to before they bump
local BUMP_COOLDOWN = 2.5

-- UserGameSettings.SavedQualityLevel, read safely (UserSettings() can throw outside a full client).
local function refreshQuality()
	local ok, settings = pcall(function()
		return UserSettings():GetService("UserGameSettings")
	end)
	qualityLevel = if ok then SlimeLod.readQuality(settings) else nil
end

local function slimeId(model: Model): string
	local id = model:GetAttribute("SlimeId")
	return if type(id) == "string" then id else model:GetFullName()
end

local function bodyOf(model: Model): BasePart?
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	return if body and body:IsA("BasePart") then body else nil
end

-- The factory's WeldConstraint holding `part` to Body or, in a rigged slime,
-- to its FaceRoot / SkinRoot (parented to the part).
local function constraintOf(part: BasePart, body: BasePart): WeldConstraint?
	local function holds(other: BasePart?): boolean
		return other == body or (other ~= nil and ROOT_PARTS[other.Name] == true and other.Parent == body.Parent)
	end
	for _, child in part:GetChildren() do
		if
			child:IsA("WeldConstraint")
			and child.Enabled
			and ((child.Part1 == part and holds(child.Part0)) or (child.Part0 == part and holds(child.Part1)))
		then
			return child
		end
	end
	return nil
end

local function release(model: Model)
	local rig = rigs[model]
	if not rig then
		return
	end
	rigs[model] = nil
	for _, conn in rig.conns do
		conn:Disconnect()
	end
	-- The server may have rescaled the model since acquire (ScaleTo): put the parts back at that scale.
	local k = rig.body.Size.Y / math.max(rig.bodySize.Y, 1e-6)
	if rig.skin and rig.skinSize and rig.skin.part.Parent then
		rig.skin.part.Size = rig.skinSize * k
	end
	if rig.squash then
		rig.squash:Destroy()
	end
	-- Destroying LifeRoot drops every Weld (they are its children); each part is
	-- then free for a moment, so put it back on Body before its WeldConstraint
	-- re-captures the offset. All synchronous: no physics step in between.
	rig.root:Destroy()
	model:SetAttribute("LifeMode", nil)
	for _, piece in rig.pieces do
		if piece.part.Parent == model and rig.body.Parent == model then
			piece.part.CFrame = rig.body.CFrame * CFrame.new(piece.offset.Position * k) * piece.offset.Rotation
		end
		piece.constraint.Enabled = true
	end
end

local function weldTo(root: BasePart, part: BasePart, offset: CFrame): Weld
	local weld = Instance.new("Weld")
	weld.Name = "LifeWeld"
	weld.Part0 = root
	weld.Part1 = part
	weld.C0 = offset
	weld.Parent = root
	return weld
end

local function acquire(model: Model): Rig?
	local body = bodyOf(model)
	if not (body and body.Anchored) then
		return nil
	end
	local params = SlimeLife.params(model:GetAttribute("Tier") :: number?, model:GetAttribute("State") :: string?)
	model:SetAttribute("LifeMode", "weld")

	local root = Instance.new("Part")
	root.Name = ROOT_NAME
	root.Size = body.Size
	root.CFrame = body.CFrame
	root.Transparency = 1
	root.CastShadow = false
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.Massless = true
	root.Anchored = false
	local joint = Instance.new("Weld")
	joint.Name = "LifeJoint"
	joint.Part0 = body
	joint.Part1 = root
	joint.Parent = root
	root.Parent = model -- first, so a failed acquire can find and drop it

	local pieces: { Piece } = {}
	local skin: Piece? = nil
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and child ~= body then
			local constraint = constraintOf(child, body)
			if constraint then
				local offset = body.CFrame:ToObjectSpace(child.CFrame)
				constraint.Enabled = false
				local piece =
					{ part = child, weld = weldTo(root, child, offset), offset = offset, constraint = constraint }
				table.insert(pieces, piece)
				if child.Name == SKIN_NAME and child:IsA("MeshPart") then
					skin = piece
				end
			end
		end
	end

	local squash: SpecialMesh? = nil
	if
		body:IsA("Part")
		and body.Shape == Enum.PartType.Ball
		and body.Transparency < 1
		and not body:FindFirstChildWhichIsA("DataModelMesh")
	then
		local mesh = Instance.new("SpecialMesh")
		mesh.Name = SQUASH_NAME
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = body
		squash = mesh
	end

	local rig: Rig = {
		model = model,
		body = body,
		root = root,
		joint = joint,
		pieces = pieces,
		skin = skin,
		skinSize = if skin then skin.part.Size else nil,
		bodySize = body.Size,
		squash = squash,
		params = params,
		clock = SlimeLife.newClock(params, os.clock(), math.random),
		sparkle = nil,
		conns = {},
		dirty = false,
	}
	local function drop()
		release(model)
	end
	local function mark()
		rig.dirty = true
	end
	table.insert(rig.conns, model:GetAttributeChangedSignal("State"):Connect(drop))
	table.insert(rig.conns, model:GetAttributeChangedSignal(Constants.DESPAWN_AT_ATTRIBUTE):Connect(drop))
	table.insert(rig.conns, body:GetPropertyChangedSignal("Anchored"):Connect(drop))
	-- A server ScaleTo (the boss's fight / haul size, growth) leaves every measured size, offset and bone rest
	-- frame stale: drop the rig, the next select builds it again at the new size.
	table.insert(rig.conns, body:GetPropertyChangedSignal("Size"):Connect(drop))
	table.insert(
		rig.conns,
		model.ChildAdded:Connect(function(child)
			if child:IsA("BasePart") then
				mark()
			end
		end)
	)
	table.insert(
		rig.conns,
		model.ChildRemoved:Connect(function(child)
			if child:IsA("BasePart") and child ~= root then
				mark()
			end
		end)
	)
	return rig
end

local function animatorOf(model: Model): Animator?
	local controller = model:FindFirstChild("AnimationController")
	local animator = controller and controller:FindFirstChild("Animator")
	return if animator and animator:IsA("Animator") then animator else nil
end

local function animationFor(id: string): Animation
	local animation = animationInstances[id]
	if not animation then
		local created = Instance.new("Animation")
		created.AnimationId = id
		animationInstances[id] = created
		return created
	end
	return animation
end

local function newTracks(animator: Animator, ids: SlimeAnim.Ids): SlimeAnim.Tracks
	return SlimeAnim.newTracks(function(key: string): any?
		local id = (ids :: any)[key]
		local ok, track = pcall(function()
			return animator:LoadAnimation(animationFor(id))
		end)
		if not ok then
			return nil
		end
		local t = track :: AnimationTrack
		t.Priority = if key == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Action
		t.Looped = key == "idle"
		return t
	end)
end

local function stopTracks(tracks: SlimeAnim.Tracks)
	for key in SlimeAnim.NAMES do
		local track = tracks:get(key)
		if track and track.IsPlaying then
			track:Stop(SlimeAnim.FADE)
		end
	end
end

local function releaseAnim(model: Model)
	local rig = animRigs[model]
	if not rig then
		return
	end
	animRigs[model] = nil
	model:SetAttribute("LifeAnimating", nil)
	model:SetAttribute("LifeMode", nil)
	for _, conn in rig.conns do
		conn:Disconnect()
	end
	pcall(stopTracks, rig.tracks)
	if rig.sparkle then
		rig.sparkle:Destroy()
	end
end

-- Animated path: the slime's own Animator plays the uploaded animations.
local function acquireAnim(model: Model): AnimRig?
	local ids = animationIds
	local animator = animatorOf(model)
	local body = bodyOf(model)
	if not (ids and animator and body and body.Anchored) then
		return nil
	end
	local tracks = trackSets[model]
	if not tracks then
		tracks = newTracks(animator, ids)
		trackSets[model] = tracks
	end
	local params = SlimeLife.params(model:GetAttribute("Tier") :: number?, model:GetAttribute("State") :: string?)
	local idle = tracks:get("idle")
	if not idle then
		return nil
	end
	model:SetAttribute("LifeAnimating", true) -- client-only; tools/pipeline/pc-watcher counts it
	model:SetAttribute("LifeMode", "anim")
	-- Random start so a crowd doesn't breathe in step.
	idle:Play(SlimeAnim.FADE)
	idle.TimePosition = math.random() * math.max(idle.Length - 0.01, 0)
	local rig: AnimRig = {
		model = model,
		startedAt = os.clock(),
		checked = false,
		animator = animator,
		tracks = tracks,
		params = params,
		sched = SlimeAnim.newSchedule(params, os.clock(), math.random),
		sparkle = nil,
		conns = {},
	}
	local function drop()
		releaseAnim(model)
	end
	table.insert(rig.conns, model:GetAttributeChangedSignal("State"):Connect(drop))
	table.insert(rig.conns, model:GetAttributeChangedSignal(Constants.DESPAWN_AT_ATTRIBUTE):Connect(drop))
	table.insert(rig.conns, body:GetPropertyChangedSignal("Anchored"):Connect(drop))
	-- A server ScaleTo (the boss's fight / haul size, growth) leaves every measured size, offset and bone rest
	-- frame stale: drop the rig, the next select builds it again at the new size.
	table.insert(rig.conns, body:GetPropertyChangedSignal("Size"):Connect(drop))
	return rig
end

local function stepAnim(rig: AnimRig, now: number)
	if not rig.checked then
		local idle = rig.tracks:get("idle")
		local verdict = if idle then SlimeAnim.verdict(idle.Length, now - rig.startedAt, idle.IsPlaying) else "failed"
		if verdict == "failed" then
			probe = "failed" -- every slime falls back to SlimeMotor at the next select
			error("idle track never played (Length 0 / not playing)")
		elseif verdict == "ok" then
			rig.checked = true
		end
	end
	for _, event in SlimeAnim.tick(rig.sched, rig.params, now, math.random) do
		local track = rig.tracks:get(if event == "LookLeft" then "lookLeft" else "lookRight")
		if track then
			track:Play(SlimeAnim.FADE)
		end
	end
end

local function releaseMotor(model: Model)
	local rig = motorRigs[model]
	if not rig then
		return
	end
	motorRigs[model] = nil
	model:SetAttribute("LifeAnimating", nil)
	model:SetAttribute("LifeMode", nil)
	model:SetAttribute("LifeTier", nil)
	for _, conn in rig.conns do
		conn:Disconnect()
	end
	if rig.actor then
		pcall(SlimeActor.release, rig.actor)
	end
	local anchor = rig.motor.body:FindFirstChild(Constants.TAG_ANCHOR)
	if anchor and anchor:IsA("Attachment") then
		anchor.Position = Vector3.zero -- the tag back on the Body
	end
	pcall(SlimeMotor.release, rig.motor)
	if rig.sparkle then
		rig.sparkle:Destroy()
	end
end

-- Procedural path on a rigged slime: SlimeMotor drives the Motor6D Transforms.
local function acquireMotor(model: Model): MotorRig?
	local body = bodyOf(model)
	if not (body and body.Anchored) or noMotor[model] then
		return nil
	end
	local motor = SlimeMotor.attach(model, os.clock(), math.random)
	if not motor then
		return nil
	end
	model:SetAttribute("LifeAnimating", true)
	model:SetAttribute("LifeMode", "motor")
	slotCounter = (slotCounter + 1) % lodConfig.MID_EVERY
	local rig: MotorRig = {
		model = model,
		tier = "near",
		slot = slotCounter,
		motor = motor,
		actor = if lifeOn
			then SlimeActor.attach(
				model,
				motor,
				os.clock(),
				if os.clock() - (stateAt[model] or -math.huge) < PUT_DOWN_WINDOW then prevStates[model] else nil,
				(function()
					local m = movedFrom[model]
					movedFrom[model] = nil
					return if m and os.clock() - m.t < PUT_DOWN_WINDOW then m.at else nil
				end)()
			)
			else nil,
		params = motor.params,
		sparkle = nil,
		conns = {},
	}
	model:SetAttribute("LifeTier", "near")
	local function drop()
		releaseMotor(model)
	end
	local state = model:GetAttribute("State")
	table.insert(
		rig.conns,
		model:GetAttributeChangedSignal("State"):Connect(function()
			local prev = state
			state = model:GetAttribute("State")
			if not (type(state) == "string" and SlimeLife.STATES[state] and rig.actor) then
				drop()
				return
			end
			rig.motor.params = SlimeLife.params(model:GetAttribute("Tier") :: number?, state :: string)
			rig.params = rig.motor.params
			SlimeActor.setState(rig.actor :: SlimeActor.Actor, prev :: string?, state :: string, os.clock())
		end)
	)
	table.insert(rig.conns, model:GetAttributeChangedSignal(Constants.DESPAWN_AT_ATTRIBUTE):Connect(drop))
	table.insert(rig.conns, body:GetPropertyChangedSignal("Anchored"):Connect(drop))
	-- A server ScaleTo (the boss's fight / haul size, growth) leaves every measured size, offset and bone rest
	-- frame stale: drop the rig, the next select builds it again at the new size.
	table.insert(rig.conns, body:GetPropertyChangedSignal("Size"):Connect(drop))
	return rig
end

-- One LoadAnimation of the idle animation, off the select loop (it yields
-- until the asset loads or fails). Length > 0 = the uploaded animations work
-- here (owner, moderation, format); anything else keeps every slime on SlimeMotor.
local function startProbe(animator: Animator, ids: SlimeAnim.Ids)
	probe = "wait"
	task.spawn(function()
		local t0 = os.clock()
		local ok, track = pcall(function()
			return animator:LoadAnimation(animationFor(ids.idle))
		end)
		if not ok then
			probe = "failed"
			return
		end
		local t = track :: AnimationTrack
		local verdict: SlimeAnim.Verdict = "wait"
		while verdict == "wait" do
			verdict = SlimeAnim.verdict(t.Length, os.clock() - t0)
			if verdict == "wait" then
				task.wait(0.25)
			end
		end
		probe = verdict
		pcall(function()
			t:Destroy()
		end)
	end)
end

local function setSparkle(rig: any, on: boolean)
	if on and not rig.sparkle and rig.params.sparkleRate > 0 then
		local e = Instance.new("ParticleEmitter")
		e.Name = "LifeSparkle"
		e.Texture = SlimeLife.SPARKLE_TEXTURE
		e.Rate = rig.params.sparkleRate
		e.Lifetime = NumberRange.new(SlimeLife.SPARKLE_LIFETIME[1], SlimeLife.SPARKLE_LIFETIME[2])
		e.Speed = NumberRange.new(0.5, 1.5)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-90, 90)
		e.LightEmission = 0.7
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.3, 0.35),
			NumberSequenceKeypoint.new(1, 0),
		})
		local rigBody = if rig.body then rig.body else bodyOf(rig.model)
		local tint = (if rigBody then rigBody.Color else Color3.new(1, 1, 1)):Lerp(Color3.new(1, 1, 1), 0.55)
		e.Color = ColorSequence.new(Color3.new(1, 1, 1), tint)
		e.Parent = if rig.root then rig.root else rig.model:FindFirstChild("SkinRoot") or rig.model
		rig.sparkle = e
	elseif not on and rig.sparkle then
		rig.sparkle:Destroy()
		rig.sparkle = nil
	end
end

local function onScreen(camera: Camera, position: Vector3): boolean
	local point, inFront = camera:WorldToViewportPoint(position)
	local size = camera.ViewportSize
	return inFront
		and point.X >= -SCREEN_MARGIN
		and point.Y >= -SCREEN_MARGIN
		and point.X <= size.X + SCREEN_MARGIN
		and point.Y <= size.Y + SCREEN_MARGIN
end

local function candidates(camera: Camera): { SlimeLife.Candidate }
	local cameraPos = camera.CFrame.Position
	local out = {}
	for model in slimes do
		local body = bodyOf(model)
		if body and model:IsDescendantOf(workspace) then
			table.insert(
				out,
				{
					id = slimeId(model),
					distance = (body.Position - cameraPos).Magnitude,
					onScreen = onScreen(camera, body.Position),
					state = model:GetAttribute("State") :: string?,
					despawning = model:GetAttribute(Constants.DESPAWN_AT_ATTRIBUTE) ~= nil,
					tier = model:GetAttribute("Tier") :: number?,
					model = model,
				} :: any
			)
		end
	end
	return out
end

local function reselect(camera: Camera)
	for model, rig in rigs do
		if rig.dirty or not model:IsDescendantOf(workspace) then
			release(model)
		end
	end
	for model in animRigs do
		if probe == "failed" or not model:IsDescendantOf(workspace) then
			releaseAnim(model)
		end
	end
	for model in motorRigs do
		if not model:IsDescendantOf(workspace) then
			releaseMotor(model)
		end
	end
	local cands = candidates(camera)
	local wanted = SlimeLife.select(cands, active)
	-- A slime in the middle of a put-down or a Move hop keeps (or gets) its rig, even if its Body has already
	-- jumped off screen: it hops away instead of vanishing from the pad it leaves.
	local clock = os.clock()
	for model, untilAt in hopping do
		if untilAt < clock then
			hopping[model] = nil
		elseif model:IsDescendantOf(workspace) then
			wanted[slimeId(model)] = true
		end
	end
	for model, rig in motorRigs do
		local kind = rig.actor and rig.actor.fidget.kind
		if (kind == "arrive" or kind == "drop") and model:IsDescendantOf(workspace) then
			wanted[slimeId(model)] = true
		end
	end
	local byId: { [string]: Model } = {}
	for _, c in cands do
		byId[c.id] = (c :: any).model
	end
	for model in rigs do
		if not wanted[slimeId(model)] then
			release(model)
		end
	end
	for model in animRigs do
		if not wanted[slimeId(model)] then
			releaseAnim(model)
		end
	end
	for model in motorRigs do
		if not wanted[slimeId(model)] then
			releaseMotor(model)
		end
	end
	local budget = ACQUIRE_PER_TICK
	for id in wanted do
		local model = byId[id]
		if model and not rigs[model] and not animRigs[model] and not motorRigs[model] and budget > 0 then
			budget -= 1
			local animator = animatorOf(model)
			if animationIds and animator and probe == nil then
				startProbe(animator, animationIds)
			end
			local mode = SlimeAnim.mode(animationsOn, animationIds, animator ~= nil, probe, animator ~= nil)
			if mode == "anim" then
				local okAnim, anim = pcall(acquireAnim, model)
				if okAnim and anim then
					animRigs[model] = anim
					continue
				end
				if not okAnim then
					warn(`[SlimeLife] {id}: {anim}`)
					pcall(releaseAnim, model)
				end
				mode = "motor"
			end
			if mode == "motor" then
				local okMotor, motorRig = pcall(acquireMotor, model)
				if okMotor and motorRig then
					motorRigs[model] = motorRig
					continue
				end
				if not okMotor then
					warn(`[SlimeLife] {id}: {motorRig}`)
					noMotor[model] = true
					pcall(releaseMotor, model)
				end
			end
			local ok, result = pcall(acquire, model)
			if ok and result then
				rigs[model] = result
			elseif not ok then
				warn(`[SlimeLife] {id}: {result}`)
				-- A half-built rig must not leave parts unwelded.
				local partial = model:FindFirstChild(ROOT_NAME)
				if partial then
					partial:Destroy()
				end
				for _, d in model:GetDescendants() do
					if d:IsA("WeldConstraint") then
						d.Enabled = true
					end
				end
			end
		end
	end
	active = {}
	for model in rigs do
		active[slimeId(model)] = true
	end
	for model in animRigs do
		active[slimeId(model)] = true
	end
	for model in motorRigs do
		active[slimeId(model)] = true
	end
	-- LOD tiers for the motor rigs, from the distances this selection already measured; only the
	-- NEAR_MAX nearest keep the full near life.
	refreshQuality()
	local ranked: { SlimeLod.Ranked & { rig: MotorRig } } = {}
	for _, c in cands do
		local rig = motorRigs[(c :: any).model]
		if rig then
			table.insert(ranked, {
				rig = rig,
				distance = c.distance,
				tier = SlimeLod.tierFor(lodConfig, qualityLevel, c.distance, rig.tier),
			})
		end
	end
	SlimeLod.capNear(lodConfig, ranked :: any)
	for _, r in ranked do
		if r.tier ~= r.rig.tier then
			r.rig.tier = r.tier
			r.rig.model:SetAttribute("LifeTier", r.tier)
		end
	end
	local sparkling = SlimeLife.sparkleSet(cands, active)
	for model, rig in rigs do
		setSparkle(rig, sparkling[slimeId(model)] == true)
	end
	for model, rig in animRigs do
		setSparkle(rig, sparkling[slimeId(model)] == true)
	end
	for model, rig in motorRigs do
		setSparkle(rig, sparkling[slimeId(model)] == true)
	end
end

local function step(rig: Rig, now: number)
	local landed = SlimeLife.advance(rig.clock, rig.params, now, math.random)
	if landed and rig.sparkle and rig.params.landBurst > 0 then
		rig.sparkle:Emit(rig.params.landBurst)
	end
	local pose = SlimeLife.pose(rig.params, rig.clock, now)
	local size = (rig.model:GetAttribute("Size") :: number?) or 1
	local r = rig.body.Size.Y / 2
	local lift = pose.lift * size
	-- Rock and turn around the bottom centre; the squashed centre sits r * sy up.
	rig.joint.C0 = CFrame.new(0, -r + lift, 0)
		* CFrame.Angles(0, pose.yaw, 0)
		* CFrame.Angles(pose.pitch, 0, pose.roll)
		* CFrame.new(0, r * pose.sy, 0)
	local scale = Vector3.new(pose.sx, pose.sy, pose.sz)
	local skin = rig.skin
	if skin and rig.skinSize then
		skin.part.Size = rig.skinSize * scale
		skin.weld.C0 = CFrame.new(skin.offset.Position * scale) * skin.offset.Rotation
	end
	if rig.squash then
		rig.squash.Scale = scale
		rig.squash.Offset = Vector3.new(0, lift - r * (1 - pose.sy), 0)
	end
end

-- Contract/slime-life.md social reactions: animated neighbours startle when a slime is grabbed and watch a slime
-- that starts to leave (its despawn telegraph).
local function neighbours(at: Vector3, radius: number, except: Model): { SlimeActor.Actor }
	local out = {}
	for model, rig in motorRigs do
		local actor = rig.actor
		if actor and rig.tier == "near" and model ~= except and (actor.visible - at).Magnitude < radius then
			table.insert(out, actor)
		end
	end
	return out
end

local function onStateChanged(model: Model)
	local body = bodyOf(model)
	if not (lifeOn and body and model:GetAttribute("State") == "Carried") then
		return
	end
	local now = os.clock()
	for _, actor in neighbours(body.Position, SlimeReact.STARTLE_DISTANCE, model) do
		SlimeActor.frighten(actor, now, body.Position, (actor.visible - body.Position).Magnitude * 0.03)
	end
end

local function onDespawnAt(model: Model)
	local body = bodyOf(model)
	if not (lifeOn and body and model:GetAttribute(Constants.DESPAWN_AT_ATTRIBUTE) ~= nil) then
		return
	end
	local now = os.clock()
	for _, actor in neighbours(body.Position, DRAIN_WATCH_DISTANCE, model) do
		SlimeActor.watch(actor, body.Position, now + DRAIN_WATCH_SECONDS, "worried")
	end
end

-- A pad slime's Body jumping to another pad (a Move, a swap): its mesh is already drawn there this frame (the
-- callback runs after physics) and its rig only puts it back on the old spot next frame, so it is hidden for those
-- frames instead of a jump and back; it keeps (or gets) a rig through the hop, and the actor hops it over.
local function watchPad(instance: Model, body: BasePart): RBXScriptConnection
	if instance:GetAttribute("State") == "Pad" then
		padSpot[instance] = body.Position
	end
	return body:GetPropertyChangedSignal("CFrame"):Connect(function()
		if instance:GetAttribute("State") ~= "Pad" then
			padSpot[instance] = nil
			return
		end
		local p = body.Position
		local was = padSpot[instance]
		padSpot[instance] = p
		if not was then
			return
		end
		local dx, dz = p.X - was.X, p.Z - was.Z
		if dx * dx + dz * dz <= MOVE_JUMP * MOVE_JUMP then
			return
		end
		for _, d in instance:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
			end
		end
		hiddenFor[instance] = frame + 3 -- the frame it lands, the one its rig catches up in, and the next
		hopping[instance] = os.clock() + HOP_KEEP
		if not motorRigs[instance] then
			movedFrom[instance] = { at = was, t = os.clock() }
		end
		nextSelect = 0
	end)
end

local function onSlime(instance: Instance)
	-- A Mystery Egg has no face or skin to animate (its looks are Visuals EggFx).
	if
		instance:IsA("Model")
		and not slimes[instance]
		and instance:GetAttribute(Constants.EGG_KIND_ATTRIBUTE) == nil
	then
		slimes[instance] = true
		nextSelect = 0 -- a new slime (off the fountain, put down) is rigged on the next frame
		local body = bodyOf(instance)
		local bodyConn = if body then watchPad(instance, body) else nil
		local waitConn: RBXScriptConnection? = nil
		if not body then
			-- the tag can arrive before the Body replicates: watch it once it does
			waitConn = instance.ChildAdded:Connect(function(child)
				if child.Name == "Body" and child:IsA("BasePart") and waitConn then
					waitConn:Disconnect()
					local conns = slimeConns[instance]
					if conns then
						table.insert(conns, watchPad(instance, child))
					end
				end
			end)
		end
		local state = instance:GetAttribute("State")
		lastStates[instance] = if type(state) == "string" then state else nil
		local conns = {
			instance:GetAttributeChangedSignal("State"):Connect(function()
				local now = instance:GetAttribute("State")
				prevStates[instance] = lastStates[instance]
				lastStates[instance] = if type(now) == "string" then now else nil
				stateAt[instance] = os.clock()
				nextSelect = 0 -- rig (or release) it on the next frame, not at the next 4 Hz selection
				local b = bodyOf(instance)
				padSpot[instance] = if now == "Pad" and b then b.Position else nil
				if lifeOn then
					onStateChanged(instance)
				end
			end),
		}
		if lifeOn then
			table.insert(
				conns,
				instance:GetAttributeChangedSignal(Constants.DESPAWN_AT_ATTRIBUTE):Connect(function()
					onDespawnAt(instance)
				end)
			)
		end
		if bodyConn then
			table.insert(conns, bodyConn)
		end
		if waitConn then
			table.insert(conns, waitConn)
		end
		slimeConns[instance] = conns
	end
end

local function onSlimeRemoved(instance: Instance)
	if instance:IsA("Model") then
		slimes[instance] = nil
		local conns = slimeConns[instance]
		if conns then
			for _, conn in conns do
				conn:Disconnect()
			end
			slimeConns[instance] = nil
		end
		release(instance)
		releaseAnim(instance)
		releaseMotor(instance)
	end
end

-- What every actor needs from this frame: the local character and its cash (leaderstats).
local function readFrame()
	local player = Players.LocalPlayer
	local character = player and player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	lifeFrame.player = if root and root:IsA("BasePart") then root.Position else nil
	lifeFrame.userId = if player then player.UserId else nil
	local stats = player and player:FindFirstChild("leaderstats")
	local cash = stats and stats:FindFirstChild("Cash")
	lifeFrame.cash = if cash and cash:IsA("ValueBase") then tonumber((cash :: any).Value) else nil
end

-- Two lane slimes closer than their radii allow: the one behind bumps the one ahead (once per cooldown).
local function bumps(now: number)
	local list = {}
	for model, rig in motorRigs do
		local actor = rig.actor
		if actor and rig.tier == "near" and model:GetAttribute("State") == "Wild" then
			table.insert(list, actor)
		end
	end
	for i = 1, #list do
		local a = list[i]
		for j = i + 1, #list do
			local b = list[j]
			local gap = (a.visible - b.visible).Magnitude
			local room = (a.motor.body.Size.X + b.motor.body.Size.X) / 2 * BUMP_GAP
			if gap < room then
				-- The one behind: the other lies ahead along its heading.
				local look = a.motor.body.CFrame.LookVector
				local behind, ahead = a, b
				if (a.visible - b.visible):Dot(look) > 0 then
					behind, ahead = b, a
				end
				if now - behind.bumpAt > BUMP_COOLDOWN and behind.speed >= ahead.speed then
					SlimeActor.bump(behind, now, true)
					SlimeActor.bump(ahead, now, false)
				end
			end
		end
	end
end

local function showEmotes(camera: Camera, now: number)
	if not emotes then
		local gui = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
		if not gui then
			return
		end
		emotes = SlimeEmotes.new(gui)
	end
	local cameraPos = camera.CFrame.Position
	local wants = {}
	for model, rig in motorRigs do
		local actor = rig.actor
		local root = rig.motor.skinJoint.Part1
		if actor and actor.emote and rig.tier == "near" and root and root:IsA("BasePart") then
			table.insert(wants, {
				adornee = root,
				emote = actor.emote,
				height = rig.motor.body.Size.Y / 2 + 0.6,
				key = model,
				distance = (actor.visible - cameraPos).Magnitude,
			})
		end
	end
	table.sort(wants, function(x, y)
		return x.distance < y.distance
	end)
	SlimeEmotes.show(emotes :: SlimeEmotes.Pool, wants :: any, now)
end

CollectionService:GetInstanceAddedSignal(Constants.SLIME_TAG):Connect(onSlime)
CollectionService:GetInstanceRemovedSignal(Constants.SLIME_TAG):Connect(onSlimeRemoved)
for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
	onSlime(model)
end

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if not camera then
		return
	end
	local now = os.clock()
	if now >= nextSelect then
		nextSelect = now + SELECT_EVERY
		reselect(camera)
	end
	for model, rig in animRigs do
		if model.Parent then
			local ok, err = pcall(stepAnim, rig, now)
			if not ok then
				warn(`[SlimeLife] anim step: {err}`)
				releaseAnim(model)
			end
		end
	end
	frame += 1
	for model, at in hiddenFor do
		if frame >= at then
			hiddenFor[model] = nil
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 0
				end
			end
		end
	end
	if lifeOn then
		readFrame()
	end
	local serverNow = workspace:GetServerTimeNow()
	local dt = math.clamp(now - lastFrameAt, 0, 0.1)
	lastFrameAt = now
	-- First pass: every actor places its slime. Every tier, every frame: the Transform carries the smooth lane
	-- anchor, so skipping a frame would show the Body's replication step. The full life only on the near tier.
	table.clear(spacing)
	table.clear(spaced)
	for model, rig in motorRigs do
		local actor = rig.actor
		if model.Parent and actor then
			local ok, err = pcall(SlimeActor.update, actor, lifeFrame, now, serverNow, math.random, rig.tier == "near")
			if ok then
				local r = rig.motor.body.Size.X / 2
				table.insert(spacing, {
					x = actor.visible.X,
					z = actor.visible.Z,
					r = r,
					px = actor.pushX,
					pz = actor.pushZ,
					rooted = actor.state == "Pad", -- a pad slime stays put when you walk past
				})
				table.insert(spaced, rig)
			else
				warn(`[SlimeLife] actor: {err}`)
				noMotor[model] = true
				releaseMotor(model)
			end
		end
	end
	-- Second pass: drawn slimes never sink into each other (SlimeSpacing), then each tag follows its slime.
	-- the local character is solid too: a slime steps round you instead of sinking into your legs
	local solid = nil
	if lifeFrame.player then
		playerSolid.x, playerSolid.z = lifeFrame.player.X, lifeFrame.player.Z
		solid = playerSolids
	end
	SlimeSpacing.step(spacing, dt, solid)
	for i, rig in spaced do
		local actor = rig.actor :: SlimeActor.Actor
		local item = spacing[i]
		SlimeActor.settle(actor, item.px, item.pz, dt)
		local body = rig.motor.body
		local anchor = body:FindFirstChild(Constants.TAG_ANCHOR)
		if anchor and anchor:IsA("Attachment") then
			anchor.Position = body.CFrame:VectorToObjectSpace(actor.tagOffset)
		end
	end
	for model, rig in motorRigs do
		if model.Parent then
			local tier = rig.tier
			local ok, result = true, false :: any
			local actor = rig.actor
			if actor then
				ok, result = pcall(SlimeMotor.step, rig.motor, now, math.random, actor.mods)
			elseif tier == "near" then
				ok, result = pcall(SlimeMotor.step, rig.motor, now, math.random)
			elseif SlimeLod.due(tier, frame, rig.slot, lodConfig) then
				ok, result = pcall(SlimeMotor.stepSquish, rig.motor, now, lodConfig.MID_AMPLITUDE)
			elseif tier == "far" then
				-- park's true means "reset this frame", not a landing: never a sparkle burst
				local okPark, err = pcall(SlimeMotor.park, rig.motor)
				ok, result = okPark, if okPark then false else err
			end
			if not ok then
				warn(`[SlimeLife] motor step: {result}`)
				noMotor[model] = true
				releaseMotor(model)
			elseif result and rig.sparkle and rig.params.landBurst > 0 then
				rig.sparkle:Emit(rig.params.landBurst)
			end
			if actor and tier ~= "near" then
				actor.emote = nil
				if actor.string then
					actor.string.Enabled = false
				end
			end
		end
	end
	if lifeOn then
		bumps(now)
		showEmotes(camera, now)
	end
	for model, rig in rigs do
		if model.Parent and not rig.dirty then
			local ok, err = pcall(step, rig, now)
			if not ok then
				warn(`[SlimeLife] step: {err}`)
				release(model)
			end
		end
	end
end)
