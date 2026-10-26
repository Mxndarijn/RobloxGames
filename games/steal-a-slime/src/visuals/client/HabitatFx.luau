--!strict
--[[
	HabitatFx (VisualsClient module, FEATURES.Habitats, HABITATS.md)

	Every Pad_<j> with the attribute Habitat (Constants.HABITAT_ATTRIBUTE,
	set by the server) gets a client-only overlay per habitat in a local
	workspace folder "ClientHabitats". The pad and its round cork Stand never
	change: an overlay (themed frame ring and rim props) rests on the stand's
	dish (WorldLayout.PAD_DECK) round the slime. Each overlay has a weight
	(Shared.Habitats.stepWeights): the current habitat grows to 1 and every
	other overlay shrinks to 0 over Habitats.TRANSFORM_SECONDS, so a swap
	crossfades on the same pad, with a sparkle burst when a change starts.
	Overlays rise out of the deck with an overshoot and sink back
	(HabitatMorph). Quality "snap" (reduced motion, far from the camera, too
	many pads morphing) or "simple" (mid distance) cut the tween / puff. The
	first time a pad is seen it snaps to its final state (join in progress),
	no burst.

	An overlay with an uploaded mesh (Habitats.overlayMesh) is a clone of the
	server's MeshPart template in ReplicatedStorage.HabitatMeshes
	(MeshSwap.publishHabitatTemplates; a MeshPart keeps the kit's vertex
	colours) at native size, its bottom on the deck (or `drop` below it).
	Until its template arrives, or with no meshId, the overlay is PLACEHOLDER
	primitive rim props in Habitats colours; looks rebuild when one arrives.
	Reads attributes only; never fires remotes. Nothing replicates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local HabitatMorph = require(Shared:WaitForChild("HabitatMorph"))
local Habitats = require(Shared:WaitForChild("Habitats"))
local WorldLayout = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("WorldLayout"))

local HabitatFx = {}

HabitatFx.SPARK = "rbxasset://textures/particles/sparkles_main.dds" -- built-in, same as Effects SPARK
HabitatFx.BURST = Config.HABITAT_ANIM.BURST_FULL

type Piece = {
	part: BasePart,
	size: Vector3,
	offset: CFrame,
	transparency: number,
	rise: boolean, -- overlay mesh: rises out of the deck (height only), footprint fixed
}
type Look = { model: Model, pieces: { Piece } }
type Track = {
	pad: BasePart,
	id: string,
	seen: boolean, -- false until the pad's first Habitat attribute
	weights: Habitats.Weights,
	quality: HabitatMorph.Quality,
	looks: { [string]: Look },
	burst: ParticleEmitter?,
	conn: RBXScriptConnection, -- Habitat attribute listener, disconnected in drop
	moved: RBXScriptConnection, -- the pad moved (a base swap, CONTRACT.md §44): the looks follow it
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
	return { part = part, size = size, offset = offset, transparency = transparency or 0, rise = false }
end

-- The overlay mesh: a clone of the server's MeshPart template at native size.
-- A MeshPart's origin is its bbox centre: the bottom sits `drop` below the deck.
local function meshPiece(model: Model, template: BasePart, overlay: Habitats.OverlayMesh): Piece
	local size = Vector3.new(overlay.size[1], overlay.size[2], overlay.size[3])
	local part = template:Clone()
	part.Name = "Mesh"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.Transparency = 1
	part.Parent = model
	return {
		part = part,
		size = size,
		offset = CFrame.new(0, size.Y / 2 - overlay.drop, 0),
		transparency = 0,
		rise = true,
	}
end

local function templateFor(name: string?): BasePart?
	local templates = ReplicatedStorage:FindFirstChild(Constants.HABITAT_MESHES)
	local t = name and templates and templates:FindFirstChild(name)
	return if t and t:IsA("BasePart") then t else nil
end

-- Offsets are from the dish centre (pad local space, +Y up). The rim band is
-- a ring between the slime (radius MAT_EDGE) and the dish edge (DECK_EDGE).
local DECK_EDGE = WorldLayout.PAD_DECK.half
local MAT_EDGE = WorldLayout.PAD_DECK.matHalf
local BAND = (DECK_EDGE + MAT_EDGE) / 2
local FRAME_SIDES = 8 -- the placeholder ring: an octagon of flat strips
-- the placeholder's four props on the ring, on the diagonals
local DIAG = BAND / math.sqrt(2)
local CORNERS = { { DIAG, DIAG }, { DIAG, -DIAG }, { -DIAG, DIAG }, { -DIAG, -DIAG } }

local function buildLook(pad: BasePart, id: string): Look?
	local habitat = Habitats.get(id)
	if not habitat or id == Habitats.BASE then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = `{pad.Parent and pad.Parent.Name or "Plot"}_{pad.Name}_{id}`
	local overlay = Habitats.overlayMesh(id)
	local template = overlay and templateFor(habitat.overlay)
	if overlay and template then
		local pieces = { meshPiece(model, template, overlay) }
		model.Parent = folder()
		return { model = model, pieces = pieces }
	end
	local color, accent = rgb(habitat.color), rgb(habitat.accent)
	local pieces: { Piece } = {}
	-- Frame: an octagon of flat strips on the dish round the slime, each as long as its side of the ring.
	local width = DECK_EDGE - MAT_EDGE
	local length = 2 * BAND * math.tan(math.pi / FRAME_SIDES) + width * math.tan(math.pi / FRAME_SIDES)
	for k = 1, FRAME_SIDES do
		local a = (k - 1) * 2 * math.pi / FRAME_SIDES
		table.insert(
			pieces,
			piece(
				model,
				`Frame{k}`,
				Enum.PartType.Block,
				Vector3.new(length, 0.14, width),
				CFrame.Angles(0, a, 0) * CFrame.new(0, 0.07, BAND),
				color,
				Enum.Material.SmoothPlastic
			)
		)
	end
	for k, c in CORNERS do
		local at = CFrame.new(c[1], 0, c[2])
		if id == "crystal_grotto" then
			local h = 1.6 + (k % 2) * 0.8
			table.insert(
				pieces,
				piece(
					model,
					`Crystal{k}`,
					Enum.PartType.Block,
					Vector3.new(0.6, h, 0.6),
					at * CFrame.new(0, h / 2, 0) * CFrame.Angles(math.rad(c[2] * 14), 0, math.rad(-c[1] * 14)),
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
					Vector3.new(0.9, 0.9, 0.9),
					at * CFrame.new(0, 0.55, 0),
					if k % 2 == 0 then accent else color,
					Enum.Material.SmoothPlastic,
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
					Vector3.new(0.8, 0.8, 0.8),
					at * CFrame.new(0, 0.5, 0),
					accent,
					Enum.Material.SmoothPlastic
				)
			)
		end
	end
	model.Parent = folder()
	return { model = model, pieces = pieces }
end

-- Rises out of the deck: each prop's scale follows HabitatMorph.propScale
-- (staggered, overshoot while rising) and fades in with the weight. The
-- overlay mesh grows in height only (its footprint stays round the slime).
local function poseLook(pad: BasePart, look: Look, w: number, rising: boolean, quality: HabitatMorph.Quality)
	local deck = pad.CFrame * CFrame.new(0, WorldLayout.PAD_DECK.y - pad.Size.Y / 2, 0)
	local n = #look.pieces
	for i, p in look.pieces do
		local s = HabitatMorph.propScale(quality, w, i, n, rising, Config.HABITAT_ANIM)
		local o = p.offset
		p.part.Size = p.size * (if p.rise then Vector3.new(1, s, 1) else Vector3.new(s, s, s))
		p.part.CFrame = deck * CFrame.new(o.Position * Vector3.new(1, s, 1)) * o.Rotation
		p.part.Transparency = 1 - math.min(1, w * 1.5) * (1 - p.transparency)
	end
end

local function emitBurst(track: Track, id: string, count: number)
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
	emitter:Emit(count)
end

-- Unknown or missing ids read as BASE, so table drift never hides a pad.
local function readId(pad: BasePart): string
	return Habitats.resolve(pad:GetAttribute(Constants.HABITAT_ATTRIBUTE))
end

local function apply(track: Track)
	for id, look in track.looks do
		local w = track.weights[id]
		if w then
			poseLook(track.pad, look, w, id == track.id, track.quality)
		else
			look.model:Destroy()
			track.looks[id] = nil
		end
	end
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
	track.moved:Disconnect()
	for _, look in track.looks do
		look.model:Destroy()
	end
	if track.burst and track.burst.Parent then
		(track.burst.Parent :: Instance):Destroy()
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

local function reducedMotion(): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute(Config.HABITAT_ANIM.REDUCED_ATTRIBUTE) == true
end

local function cameraDistance(pad: BasePart): number?
	local camera = workspace.CurrentCamera
	return if camera then (camera.CFrame.Position - pad.Position).Magnitude else nil
end

local function animating(): number
	local n = 0
	for _, track in tracks do
		if not Habitats.isSettled(track.weights, track.id) then
			n += 1
		end
	end
	return n
end

local function onHabitat(track: Track)
	if not track.seen then
		snap(track)
		return
	end
	local nextId = readId(track.pad)
	if nextId == track.id then
		return
	end
	local quality: HabitatMorph.Quality =
		HabitatMorph.quality(Config.HABITAT_ANIM, reducedMotion(), cameraDistance(track.pad), animating())
	track.quality = quality
	if quality == "snap" then
		snap(track) -- final state at once, no puff
		return
	end
	track.id = nextId
	emitBurst(track, nextId, HabitatMorph.burst(Config.HABITAT_ANIM, quality))
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
		quality = "full",
		looks = {},
		burst = nil,
		conn = pad:GetAttributeChangedSignal(Constants.HABITAT_ATTRIBUTE):Connect(function()
			onHabitat(track)
		end),
		moved = pad:GetPropertyChangedSignal("CFrame"):Connect(function()
			apply(track)
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

-- A template arrived (the server publishes them after boot): rebuild the
-- placeholder looks of that habitat as the mesh, keeping their weights.
local function onTemplate(name: string)
	for _, track in tracks do
		for id, look in track.looks do
			local habitat = Habitats.get(id)
			if habitat and habitat.overlay == name then
				look.model:Destroy()
				track.looks[id] = nil
			end
		end
		ensureLooks(track)
		apply(track)
	end
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
	-- Templates (and their folder) may arrive after this pass.
	table.insert(
		conns,
		ReplicatedStorage.DescendantAdded:Connect(function(d)
			if d.Parent and d.Parent.Name == Constants.HABITAT_MESHES then
				onTemplate(d.Name)
			end
		end)
	)
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
