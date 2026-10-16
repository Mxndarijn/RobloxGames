--!strict
--[[
	HabitatFx (VisualsClient module, FEATURES.Habitats, HABITATS.md)

	Every Pad_<j> with the attribute Habitat (Constants.HABITAT_ATTRIBUTE,
	set by the server) gets a client-only look per habitat in a local
	workspace folder "ClientHabitats". Each look has a weight (Shared.Habitats
	.stepWeights): the current habitat grows to 1 and every other look
	shrinks to 0 over Habitats.TRANSFORM_SECONDS, with a sparkle burst when a
	transform starts. The pad's own Stand fades out locally
	(LocalTransparencyModifier) while a habitat shows. The first time a pad is
	seen it snaps to its final state (join in progress), no burst.

	Mesh slots (Habitats.MESH_SLOTS) draw their uploaded mesh when
	Habitats.slotMesh(id) has one (MeshAssets meshId): a Part with a FileMesh
	SpecialMesh (MeshPart.MeshId can't be set from a script), footprint at
	native size, height fit so the mesh seat lands on the pad top. No meshId
	yet = PLACEHOLDER primitive parts in Habitats colours, as do the seven kit
	pad looks (swapping those in is a follow-up).
	Reads attributes only; never fires remotes. Nothing replicates.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local Habitats = require(Shared:WaitForChild("Habitats"))

local HabitatFx = {}

HabitatFx.SPARK = "rbxasset://textures/particles/sparkles_main.dds" -- built-in, same as Effects SPARK
HabitatFx.BURST = 24

type Piece = {
	part: BasePart,
	size: Vector3,
	offset: CFrame,
	transparency: number,
	mesh: SpecialMesh?, -- slot mesh look: Scale grows with the look, not Size
	scale: Vector3?,
}
type Look = { model: Model, pieces: { Piece } }
type Track = {
	pad: BasePart,
	id: string,
	seen: boolean, -- false until the pad's first Habitat attribute
	weights: Habitats.Weights,
	looks: { [string]: Look },
	burst: ParticleEmitter?,
	conn: RBXScriptConnection, -- Habitat attribute listener, disconnected in drop
}

local tracks: { [BasePart]: Track } = {}
local rootFolder: Folder? = nil

local function folder(): Folder
	if not rootFolder or not rootFolder.Parent then
		local f = Instance.new("Folder")
		f.Name = Constants.HABITAT_FOLDER
		f.Parent = workspace
		rootFolder = f
	end
	return rootFolder :: Folder
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function piece(
	model: Model,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	offset: CFrame,
	color: Color3,
	material: Enum.Material,
	transparency: number?
): Piece
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Color = color
	part.Material = material
	part.Size = size
	part.Transparency = 1
	part.Parent = model
	return { part = part, size = size, offset = offset, transparency = transparency or 0 }
end

-- One FileMesh piece for an uploaded slot mesh. Footprint stays native (the
-- slot is built to <= 7.96 on the 8-stud pad); Y scales by pad height / seat
-- so the mesh seat sits on the pad top, where the slime rests.
local function meshPiece(model: Model, pad: BasePart, slot: Habitats.SlotMesh, seat: number): Piece
	local native = Vector3.new(slot.size[1], slot.size[2], slot.size[3])
	local scale = Vector3.new(1, if seat > 0 then pad.Size.Y / seat else 1, 1)
	local size = native * scale
	local p = piece(
		model,
		"Mesh",
		Enum.PartType.Block,
		size,
		CFrame.new(0, size.Y / 2, 0), -- FileMesh origin is its bbox centre
		Color3.new(1, 1, 1),
		Enum.Material.SmoothPlastic
	)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.FileMesh
	mesh.MeshId = slot.meshId
	mesh.Scale = scale
	mesh.Parent = p.part
	p.mesh = mesh
	p.scale = scale
	return p
end

-- Offsets are from the pad's bottom centre (pad local space, +Y up).
local CORNERS = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

local function buildLook(pad: BasePart, id: string): Look?
	local habitat = Habitats.get(id)
	if not habitat or id == Habitats.BASE then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = `{pad.Parent and pad.Parent.Name or "Plot"}_{pad.Name}_{id}`
	local slot = Habitats.slotMesh(id)
	if slot then
		local pieces = { meshPiece(model, pad, slot, habitat.seat) }
		model.Parent = folder()
		return { model = model, pieces = pieces }
	end
	local color, accent = rgb(habitat.color), rgb(habitat.accent)
	local seatH = pad.Size.Y
	local pieces: { Piece } = {}
	local cylinder = CFrame.Angles(0, 0, math.rad(90)) -- Cylinder parts run along X
	-- Seat column: the slime keeps resting on the pad top while the Stand is hidden.
	table.insert(
		pieces,
		piece(
			model,
			"Seat",
			Enum.PartType.Cylinder,
			Vector3.new(seatH, 7.2, 7.2),
			CFrame.new(0, seatH / 2, 0) * cylinder,
			color,
			Enum.Material.SmoothPlastic
		)
	)
	table.insert(
		pieces,
		piece(
			model,
			"Ring",
			Enum.PartType.Cylinder,
			Vector3.new(0.4, 7.9, 7.9),
			CFrame.new(0, 0.2, 0) * cylinder,
			accent,
			Enum.Material.SmoothPlastic
		)
	)
	for k, c in CORNERS do
		local at = CFrame.new(c[1] * 3.1, 0, c[2] * 3.1)
		if id == "crystal_grotto" then
			local h = 2.6 + (k % 2) * 1.4
			table.insert(
				pieces,
				piece(
					model,
					`Crystal{k}`,
					Enum.PartType.Block,
					Vector3.new(0.7, h, 0.7),
					at * CFrame.new(0, h / 2 + 0.2, 0) * CFrame.Angles(math.rad(c[1] * 12), 0, math.rad(c[2] * 12)),
					accent,
					Enum.Material.Neon,
					0.25
				)
			)
		elseif id == "candy_patch" then
			table.insert(
				pieces,
				piece(
					model,
					`Gumdrop{k}`,
					Enum.PartType.Ball,
					Vector3.new(1.1, 1.1, 1.1),
					at * CFrame.new(0, 0.75, 0),
					if k % 2 == 0 then accent else color,
					Enum.Material.Glass,
					0.1
				)
			)
		else
			table.insert(
				pieces,
				piece(
					model,
					`Tuft{k}`,
					Enum.PartType.Block,
					Vector3.new(0.9, 0.9, 0.9),
					at * CFrame.new(0, 0.65, 0),
					accent,
					Enum.Material.SmoothPlastic
				)
			)
		end
	end
	model.Parent = folder()
	return { model = model, pieces = pieces }
end

-- Grows from the ground: size and height scale with an eased weight, fades in.
local function poseLook(pad: BasePart, look: Look, w: number)
	local e = 1 - (1 - w) ^ 3
	local s = 0.05 + 0.95 * e
	local bottom = pad.CFrame * CFrame.new(0, -pad.Size.Y / 2, 0)
	for _, p in look.pieces do
		local o = p.offset
		p.part.Size = p.size * s
		if p.mesh and p.scale then
			p.mesh.Scale = p.scale * s
		end
		p.part.CFrame = bottom * CFrame.new(o.Position * Vector3.new(1, s, 1)) * o.Rotation
		p.part.Transparency = 1 - w * (1 - p.transparency)
	end
end

local function setStandVisible(pad: BasePart, visibility: number)
	local stand = pad:FindFirstChild("Stand")
	if not stand then
		return
	end
	local modifier = 1 - visibility
	if stand:IsA("BasePart") then
		stand.LocalTransparencyModifier = modifier
	end
	for _, d in stand:GetDescendants() do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = modifier
		end
	end
end

local function emitBurst(track: Track, id: string)
	local habitat = Habitats.get(id) or Habitats.get(Habitats.BASE)
	if not habitat then
		return
	end
	local emitter = track.burst
	if not emitter or not emitter.Parent then
		local attachment = Instance.new("Attachment")
		attachment.Name = "HabitatBurst"
		attachment.Position = Vector3.new(0, track.pad.Size.Y / 2 + 1, 0)
		attachment.Parent = track.pad
		local e = Instance.new("ParticleEmitter")
		e.Texture = HabitatFx.SPARK
		e.Enabled = false
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Speed = NumberRange.new(6, 11)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Size = NumberSequence.new(0.6, 0)
		e.LightEmission = 0.6
		e.Parent = attachment
		track.burst = e
		emitter = e
	end
	assert(emitter, "emitter")
	emitter.Color = ColorSequence.new(rgb(habitat.accent), rgb(habitat.color))
	emitter:Emit(HabitatFx.BURST)
end

-- Unknown or missing ids read as BASE, so table drift never hides a pad.
local function readId(pad: BasePart): string
	return Habitats.resolve(pad:GetAttribute(Constants.HABITAT_ATTRIBUTE))
end

local function apply(track: Track)
	for id, look in track.looks do
		local w = track.weights[id]
		if w then
			poseLook(track.pad, look, w)
		else
			look.model:Destroy()
			track.looks[id] = nil
		end
	end
	setStandVisible(track.pad, Habitats.baseVisibility(track.weights))
end

local function ensureLooks(track: Track)
	for id in track.weights do
		if not track.looks[id] then
			local look = buildLook(track.pad, id)
			if look then
				track.looks[id] = look
			end
		end
	end
end

local function drop(pad: BasePart)
	local track = tracks[pad]
	if not track then
		return
	end
	track.conn:Disconnect()
	for _, look in track.looks do
		look.model:Destroy()
	end
	if track.burst and track.burst.Parent then
		(track.burst.Parent :: Instance):Destroy()
	end
	if pad.Parent then
		setStandVisible(pad, 1)
	end
	tracks[pad] = nil
end

-- First sight (join in progress, streamed in, or the first Habitat the
-- server writes): the final state, no tween, no burst.
local function snap(track: Track)
	track.seen = true
	track.id = readId(track.pad)
	track.weights = Habitats.initialWeights(track.id)
	ensureLooks(track)
	apply(track)
end

local function onHabitat(track: Track)
	if not track.seen then
		snap(track)
		return
	end
	local nextId = readId(track.pad)
	if nextId ~= track.id then
		track.id = nextId
		emitBurst(track, nextId)
	end
end

local function watch(pad: BasePart)
	if tracks[pad] then
		return
	end
	local track: Track
	track = {
		pad = pad,
		id = Habitats.BASE,
		seen = false,
		weights = {},
		looks = {},
		burst = nil,
		conn = pad:GetAttributeChangedSignal(Constants.HABITAT_ATTRIBUTE):Connect(function()
			onHabitat(track)
		end),
	}
	tracks[pad] = track
	if pad:GetAttribute(Constants.HABITAT_ATTRIBUTE) ~= nil then
		snap(track)
	end
end

local function isPad(d: Instance): boolean
	return d:IsA("BasePart") and d:GetAttribute(Constants.PAD_INDEX_ATTRIBUTE) ~= nil
end

-- Event-driven: one pass over Plots at start, then DescendantAdded /
-- DescendantRemoving (streaming, plot rebuilds). No periodic rescans.
function HabitatFx.attach(plots: Instance): { RBXScriptConnection }
	local conns = {
		plots.DescendantAdded:Connect(function(d)
			if isPad(d) then
				watch(d :: BasePart)
			end
		end),
		plots.DescendantRemoving:Connect(function(d)
			if tracks[d :: any] then
				drop(d :: BasePart)
			end
		end),
	}
	for _, d in plots:GetDescendants() do
		if isPad(d) then
			watch(d :: BasePart)
		end
	end
	return conns
end

-- Moves every unsettled pad one frame along (RenderStepped).
function HabitatFx.step(dt: number)
	for _, track in tracks do
		if not Habitats.isSettled(track.weights, track.id) then
			track.weights = Habitats.stepWeights(track.weights, track.id, dt)
			ensureLooks(track)
			apply(track)
		end
	end
end

-- Test / teardown hook: drops every pad (looks, burst, listener).
function HabitatFx.clear()
	for pad in tracks do
		drop(pad)
	end
end

-- Pads currently tracked (tests).
function HabitatFx.count(): number
	local n = 0
	for _ in tracks do
		n += 1
	end
	return n
end

function HabitatFx.start()
	if not Config.FEATURES.Habitats then
		return
	end
	task.spawn(function()
		local plots = workspace:WaitForChild(Constants.PLOTS_FOLDER)
		local ok, err = pcall(HabitatFx.attach, plots)
		if not ok then
			warn(`[VisualsClient] HabitatFx attach: {err}`)
		end
	end)
	RunService.RenderStepped:Connect(HabitatFx.step)
end

return HabitatFx
