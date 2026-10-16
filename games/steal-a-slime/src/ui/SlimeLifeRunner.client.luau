--!strict
--[[
	Runner for SlimeLife (TODO v28 #17): client-only idle life for wild and
	pad slimes (tag Constants.SLIME_TAG, State "Wild" / "Pad"). Nothing
	replicates; it never fires remotes.

	Why a rig and not PivotTo: VisualsClient (Archer) already owns the model
	pivot (bob, tilt, escape hops) and rebases whenever someone else moves it,
	so a second PivotTo writer would make the two drift. Instead, for each
	slime picked by SlimeLife.select this adds a local, invisible "LifeRoot"
	part welded to Body and moves the decorations (eyes, mouth, rims, crown,
	the "Mesh" skin) from their WeldConstraint onto Welds from LifeRoot.
	Per frame only LifeRoot's weld C0 moves (hop, look, wobble) plus the
	skin's squash: the Mesh skin's Size, or a local SpecialMesh on the
	procedural Body ball (a Ball part can't be sized non-uniformly). Body
	itself never moves, so the pivot, the GrabPrompt and VisualsClient's
	blinks and bob are untouched; our motion rides on top of the bob.

	Released (parts put back, WeldConstraints re-enabled) as soon as the
	slime leaves the active set, changes State (Carried / Escaping: the
	carry weld and VisualsClient's wriggle take over), gets DespawnAt
	(DespawnTelegraphFx shrinks it) or gains / loses a part.

	Animated path (slime rig, src/visuals/shared/SlimeRig): when the slime has
	its Animator and MeshAssets.ANIMATIONS has idle, hop and both looks, the
	same selection plays SlimeIdleSquish (loop), SlimeHop and SlimeLookLeft /
	Right on that Animator instead (SlimeAnim schedules the events), with no
	LifeRoot, no weld or Size writes and no per-frame work. The Animation
	instances are shared by every rig and each rig loads its tracks once.
	Missing ids or no Animator: the procedural path below runs unchanged.
	Both paths share the LOD: nearest SlimeLife.MAX_ACTIVE slimes, within
	MAX_DISTANCE and on screen.

	Cost: at most SlimeLife.MAX_ACTIVE rigs within SlimeLife.MAX_DISTANCE of
	the camera, 3-4 property writes each per frame, selection 4x a second,
	at most ACQUIRE_PER_TICK new rigs per tick, at most SlimeLife
	.MAX_SPARKLING emitters.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local MeshAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MeshAssets"))
local SlimeAnim = require(script.Parent:WaitForChild("SlimeAnim"))
local SlimeLife = require(script.Parent:WaitForChild("SlimeLife"))

local SELECT_EVERY = 0.25
local ACQUIRE_PER_TICK = 4
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
	squash: SpecialMesh?,
	params: SlimeLife.Params,
	clock: SlimeLife.Clock,
	sparkle: ParticleEmitter?,
	conns: { RBXScriptConnection },
	dirty: boolean,
}

type AnimRig = {
	model: Model,
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
local trackSets: { [Model]: SlimeAnim.Tracks } = setmetatable({}, { __mode = "k" }) :: any
local animationIds = SlimeAnim.ids(MeshAssets.animationId)
local animationInstances: { [string]: Animation } = {} -- one per id, shared by every rig
local active: { [string]: boolean } = {}

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
	if rig.skin and rig.skinSize and rig.skin.part.Parent then
		rig.skin.part.Size = rig.skinSize
	end
	if rig.squash then
		rig.squash:Destroy()
	end
	-- Destroying LifeRoot drops every Weld (they are its children); each part is
	-- then free for a moment, so put it back on Body before its WeldConstraint
	-- re-captures the offset. All synchronous: no physics step in between.
	rig.root:Destroy()
	for _, piece in rig.pieces do
		if piece.part.Parent == model and rig.body.Parent == model then
			piece.part.CFrame = rig.body.CFrame * piece.offset
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
	-- Random start so a crowd doesn't breathe in step.
	idle:Play(SlimeAnim.FADE)
	idle.TimePosition = math.random() * math.max(idle.Length - 0.01, 0)
	local rig: AnimRig = {
		model = model,
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
	return rig
end

local function stepAnim(rig: AnimRig, now: number)
	for _, event in SlimeAnim.tick(rig.sched, rig.params, now, math.random) do
		if event == "Land" then
			if rig.sparkle and rig.params.landBurst > 0 then
				rig.sparkle:Emit(rig.params.landBurst)
			end
		else
			local key = if event == "Hop" then "hop" elseif event == "LookLeft" then "lookLeft" else "lookRight"
			local track = rig.tracks:get(key)
			if track then
				track:Play(SlimeAnim.FADE)
			end
		end
	end
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
		if not model:IsDescendantOf(workspace) then
			releaseAnim(model)
		end
	end
	local cands = candidates(camera)
	local wanted = SlimeLife.select(cands, active)
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
	local budget = ACQUIRE_PER_TICK
	for id in wanted do
		local model = byId[id]
		if model and not rigs[model] and not animRigs[model] and budget > 0 then
			budget -= 1
			local animated = nil
			if animationIds then
				local okAnim, anim = pcall(acquireAnim, model)
				if okAnim then
					animated = anim
				else
					warn(`[SlimeLife] {id}: {anim}`)
					pcall(releaseAnim, model)
				end
			end
			if animated then
				animRigs[model] = animated
				continue
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
	local sparkling = SlimeLife.sparkleSet(cands, active)
	for model, rig in rigs do
		setSparkle(rig, sparkling[slimeId(model)] == true)
	end
	for model, rig in animRigs do
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

local function onSlime(instance: Instance)
	if instance:IsA("Model") then
		slimes[instance] = true
	end
end

local function onSlimeRemoved(instance: Instance)
	if instance:IsA("Model") then
		slimes[instance] = nil
		release(instance)
		releaseAnim(instance)
	end
end

CollectionService:GetInstanceAddedSignal(Constants.SLIME_TAG):Connect(onSlime)
CollectionService:GetInstanceRemovedSignal(Constants.SLIME_TAG):Connect(onSlimeRemoved)
for _, model in CollectionService:GetTagged(Constants.SLIME_TAG) do
	onSlime(model)
end

local nextSelect = 0
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
