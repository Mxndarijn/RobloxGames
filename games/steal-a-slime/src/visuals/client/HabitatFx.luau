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

	A look is the habitat's layers (Habitats.layers): the bed disc (a
	primitive in the theme's colour and material), the rarity frame, the
	glowing lip (top tiers; Secret's cycles through the rainbow), the theme
	props and the signature prop on the front of the rim (Habitats.FRONT_YAW,
	PROP_RADIUS), rising in that order. A layer with an uploaded mesh is a
	clone of the server's MeshPart template in ReplicatedStorage.HabitatMeshes
	(MeshSwap.publishHabitatTemplates; a MeshPart keeps the kit's vertex
	colours) at native size, its bottom on the deck (or `drop` below it).
	Until its template arrives the frame and theme are PLACEHOLDER primitives
	in Habitats colours (glow and prop show nothing); looks rebuild when one
	arrives.
	Reads attributes only; never fires remotes. Nothing replicates.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Constants = require(Shared:WaitForChild("Constants"))
local EffectPrefs = require(ReplicatedStorage:WaitForChild("Visuals"):WaitForChild("EffectPrefs"))
local HabitatMorph = require(Shared:WaitForChild("HabitatMorph"))
local Habitats = require(Shared:WaitForChild("Habitats"))
local MeshAssets = require(Shared:WaitForChild("MeshAssets"))
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

-- Pad-local turn that puts a kit mesh's front on the walkway side, and that side's direction.
local FRONT = CFrame.Angles(0, math.rad(Habitats.FRONT_YAW), 0)
local FRONT_DIR = FRONT:VectorToWorldSpace(Vector3.zAxis)
-- An uploaded MeshPart comes in turned from the kit's axes (MeshAssets.IMPORT_YAW, as every MeshSwap slot); offsets
-- are in the kit's axes, so only the part itself takes this turn.
local IMPORT_TURN = CFrame.Angles(0, math.rad(MeshAssets.IMPORT_YAW), 0)

-- A layer's mesh: a clone of the server's MeshPart template at native size. A MeshPart's origin is its bbox centre:
-- the bottom sits `drop` below the deck. Frame, glow and theme are centred on the dish and rise out of it (height
-- only); the signature prop stands on the front of the rim and pops up whole.
local function meshPiece(model: Model, template: BasePart, layer: Habitats.Layer, overlay: Habitats.OverlayMesh): Piece
	local size = Vector3.new(overlay.size[1], overlay.size[2], overlay.size[3])
	local part = template:Clone()
	part.Name = layer.kind
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Size = size
	part.Transparency = 1
	if layer.glow then
		part.Material = Enum.Material.Neon
		part.Color = Color3.fromRGB(layer.glow[1], layer.glow[2], layer.glow[3])
	end
	part.Parent = model
	local up = Vector3.new(0, size.Y / 2 - overlay.drop, 0)
	local shift = FRONT:VectorToWorldSpace(Vector3.new(overlay.offset[1], 0, overlay.offset[2]))
	local at = if layer.kind == "prop" then FRONT_DIR * Habitats.PROP_RADIUS + up else up + shift
	return {
		part = part,
		size = size,
		offset = CFrame.new(at) * FRONT * IMPORT_TURN,
		transparency = 0,
		rise = layer.kind ~= "prop",
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
-- the placeholder theme props: back and both sides (the front is the signature prop's)
local THEME_SPOTS = { 180, 90, -90 }

-- The bed: a thin disc over the stand's goo bed (its top sits BED_LIFT above the dish rim), inside the frame, in the
-- theme's colour and material. Always a primitive; it spreads out from the centre as the habitat rises.
local BED_LIFT = 0.05
local BED_THICK = 0.04

local function bedPiece(model: Model, layer: Habitats.Layer): Piece
	local material = (Enum.Material :: any)[layer.material or ""] or Enum.Material.SmoothPlastic
	return piece(
		model,
		"Bed",
		Enum.PartType.Cylinder,
		Vector3.new(BED_THICK, 2 * MAT_EDGE, 2 * MAT_EDGE),
		CFrame.new(0, BED_LIFT + BED_THICK / 2, 0) * CFrame.Angles(0, 0, math.pi / 2),
		rgb(layer.color),
		material
	)
end

-- Placeholder primitives for a layer whose mesh isn't uploaded yet: the frame as a ring of strips, the theme as
-- three blocks. The glow lip and the signature prop show nothing until their mesh arrives.
local function placeholderPieces(model: Model, layer: Habitats.Layer): { Piece }
	local pieces: { Piece } = {}
	if layer.kind == "frame" then
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
					rgb(layer.color),
					Enum.Material.SmoothPlastic
				)
			)
		end
	elseif layer.kind == "theme" then
		for k, deg in THEME_SPOTS do
			local h = if k == 1 then 1.2 else 0.8
			local dir = (FRONT * CFrame.Angles(0, math.rad(deg), 0)):VectorToWorldSpace(Vector3.zAxis)
			table.insert(
				pieces,
				piece(
					model,
					`Prop{k}`,
					Enum.PartType.Block,
					Vector3.new(0.8, h, 0.8),
					CFrame.new(dir * BAND + Vector3.new(0, h / 2, 0)),
					if k == 1 then rgb(layer.accent) else rgb(layer.color),
					Enum.Material.SmoothPlastic
				)
			)
		end
	end
	return pieces
end

-- Glow lips that cycle through the rainbow (Secret frames); stepped in HabitatFx.step while near the camera.
local shimmering: { [BasePart]: boolean } = {}

local function buildLook(pad: BasePart, id: string): Look?
	local layers = Habitats.layers(id)
	if #layers == 0 then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = `{pad.Parent and pad.Parent.Name or "Plot"}_{pad.Name}_{id}`
	local pieces: { Piece } = {}
	for _, layer in layers do
		local overlay = layer.overlay
		local template = overlay and templateFor(layer.mesh)
		if layer.kind == "bed" then
			table.insert(pieces, bedPiece(model, layer))
		elseif overlay and template then
			local p = meshPiece(model, template, layer, overlay)
			table.insert(pieces, p)
			if layer.shimmer then
				shimmering[p.part] = true
			end
		else
			for _, p in placeholderPieces(model, layer) do
				table.insert(pieces, p)
			end
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
	local look = Habitats.look(id)
	if not look then
		return
	end
	local habitat = look.theme
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

-- Roblox's Reduced Motion or the game's setting (the ReducedMotion attribute).
local function reducedMotion(): boolean
	return EffectPrefs.reducedMotion(Players.LocalPlayer, GuiService)
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
	local leaving = track.id
	track.id = nextId
	local count = HabitatMorph.burst(Config.HABITAT_ANIM, quality)
	if EffectPrefs.isLow(Players.LocalPlayer) then
		count = math.min(count, Config.HABITAT_ANIM.BURST_SIMPLE) -- Goo effects Low: the small puff
	end
	emitBurst(track, if nextId == Habitats.BASE then leaving else nextId, count) -- a leave puffs in the old colours
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

local function usesMesh(id: string, name: string): boolean
	for _, layer in Habitats.layers(id) do
		if layer.mesh == name then
			return true
		end
	end
	return false
end

-- A template arrived (the server publishes them after boot): rebuild the
-- looks that use that mesh, keeping their weights.
local function onTemplate(name: string)
	for _, track in tracks do
		for id, look in track.looks do
			if usesMesh(id, name) then
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

-- Rainbow glow lips: hue cycles every SHIMMER_PERIOD seconds, only within SHIMMER_RANGE studs of the camera.
local SHIMMER_PERIOD = 4
local SHIMMER_RANGE = 160

local function stepShimmer()
	local camera = workspace.CurrentCamera
	if not camera or next(shimmering) == nil then
		return
	end
	local hue = (os.clock() / SHIMMER_PERIOD) % 1
	local eye = camera.CFrame.Position
	for part in shimmering do
		if not part.Parent then
			shimmering[part] = nil
		elseif (part.Position - eye).Magnitude < SHIMMER_RANGE then
			part.Color = Color3.fromHSV(hue, 0.55, 1)
		end
	end
end

-- Moves every unsettled pad one frame along, and the rainbow lips (RenderStepped).
function HabitatFx.step(dt: number)
	for _, track in tracks do
		if not Habitats.isSettled(track.weights, track.id) then
			track.weights = Habitats.stepWeights(track.weights, track.id, dt)
			ensureLooks(track)
			apply(track)
		end
	end
	stepShimmer()
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
