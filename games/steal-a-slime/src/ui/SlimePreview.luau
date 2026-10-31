--!strict
--[[
	SlimePreview

	Cheap client-side slime model for SlimeDex ViewportFrames. Lives in ui/
	(not visuals): Ball body + eyes, tinted from the row colour. A species the
	player has not found or does not have shows grey: its own mesh recoloured
	grey once that is made, else the mesh or ball washed grey.

	Choice: Ball parts, not SpecialMesh + Config.SLIME_MESH_ASSET_ID. MeshId
	needs the asset online and fails under Lune; a Ball reads as a blob in a
	small ViewportFrame and always builds. Real mesh/ModelFactory previews
	remain a later upgrade once shared client builders exist.

	One untinted template is built on first use; every preview is a Clone of it with the body tinted.
	mount() recycles the viewport's WorldModel and camera and only swaps the
	model.
]]

export type Opts = {
	greyed: boolean?, -- every colour washed to grey: a species not found yet, or a slime you don't have
}

local SlimePreview = {}

-- At most this many rows of one list (Dex cards, Merge and Plot slime rows) get a live ViewportFrame;
-- the rest keep the colour swatch.
SlimePreview.MAX_LIVE = 24

SlimePreview.GREYED = Color3.fromRGB(150, 156, 160) -- the body of a greyed ball preview

-- `color` washed to grey, keeping its lightness so the slime's markings still read.
function SlimePreview.greyOf(color: Color3): Color3
	local l = 0.3 * color.R + 0.59 * color.G + 0.11 * color.B
	local v = 0.35 + 0.4 * l
	return Color3.new(v, v, v)
end

local WHITE = Color3.fromRGB(245, 248, 255)
local INK = Color3.fromRGB(20, 22, 30)

local function ball(name: string, diameter: number, color: Color3, position: Vector3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(diameter, diameter, diameter)
	p.Position = position
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- 2-stud body at the origin, eyes on the +Z face (towards the camera).
local function buildTemplate(): Model
	local model = Instance.new("Model")
	model.Name = "SlimePreview"
	model.PrimaryPart = ball("Body", 2, SlimePreview.GREYED, Vector3.zero, model)
	local sides: { { suffix: string, x: number } } = { { suffix = "L", x = -0.35 }, { suffix = "R", x = 0.35 } }
	for _, side in sides do
		local suffix, x = side.suffix, side.x
		ball(`EyeWhite{suffix}`, 0.42, WHITE, Vector3.new(x, 0.25, 0.72), model)
		ball(`Pupil{suffix}`, 0.2, INK, Vector3.new(x, 0.22, 0.84), model)
	end
	return model
end

local template: Model? = nil

local function templateFor(): Model
	if template == nil then
		template = buildTemplate()
	end
	return template :: Model
end

-- The viewport's WorldModel, created on first use.
local function worldFor(vf: ViewportFrame): Instance
	local existing = vf:FindFirstChild("World")
	if existing then
		return existing
	end
	local created = Instance.new("WorldModel")
	created.Name = "World"
	created.Parent = vf
	return created
end

local function rgb(colorRgb: { number }): Color3
	local function channel(i: number): number
		return math.clamp(math.floor(colorRgb[i] or 0), 0, 255)
	end
	return Color3.fromRGB(channel(1), channel(2), channel(3))
end

-- Unparented Model cloned from the template: body tinted to colorRgb
-- (0..255), or grey when greyed.
function SlimePreview.build(colorRgb: { number }, opts: Opts?): Model
	local model = templateFor():Clone()
	local body = model:FindFirstChild("Body") :: Part
	local greyed = opts ~= nil and opts.greyed == true
	body.Color = if greyed then SlimePreview.GREYED else rgb(colorRgb)
	return model
end

-- Puts a built slime into `viewport` with a framed camera. Reuses the
-- viewport's WorldModel and camera; only the model is replaced. Returns
-- false on failure (caller keeps the colour swatch).
function SlimePreview.mount(viewport: Instance, colorRgb: { number }, opts: Opts?): boolean
	local ok, err = pcall(function()
		local vf = viewport :: ViewportFrame
		local world = worldFor(vf)
		world:ClearAllChildren()
		local cam = vf:FindFirstChild("PreviewCamera") :: Camera?
		if cam == nil then
			local created = Instance.new("Camera")
			created.Name = "PreviewCamera"
			created.CFrame = CFrame.lookAt(Vector3.new(0, 0.15, 3.4), Vector3.zero)
			created.Parent = vf
			vf.CurrentCamera = created
			vf.Ambient = Color3.fromRGB(180, 185, 200)
			vf.LightColor = Color3.fromRGB(255, 255, 255)
			vf.LightDirection = Vector3.new(-0.4, -1, -0.6)
		end
		SlimePreview.build(colorRgb, opts).Parent = world
	end)
	if not ok then
		warn(`[SlimePreview] mount failed: {err}`)
		SlimePreview.unmount(viewport)
		return false
	end
	return true
end

-- Puts an already built slime Model (Visuals.ModelFactory: pivot at the
-- bottom centre, front = -Z) into `viewport`, framed from the front-above.
-- Every part is anchored (a viewport runs no physics) and lights /
-- sparkles are dropped; `greyed` washes every part's colour to grey. Returns
-- false on failure (caller falls back to SlimePreview.mount).
function SlimePreview.mountModel(viewport: Instance, model: Model, opts: Opts?): boolean
	local ok, err = pcall(function()
		local greyed = opts ~= nil and opts.greyed == true
		for _, inst in model:GetDescendants() do
			if inst:IsA("BasePart") then
				local part = inst :: BasePart
				part.Anchored = true
				if greyed then
					part.Color = SlimePreview.greyOf(part.Color)
					part.Reflectance = 0
				end
			elseif inst:IsA("Light") or inst:IsA("Sparkles") or inst:IsA("ParticleEmitter") then
				inst:Destroy()
			end
		end
		local vf = viewport :: ViewportFrame
		local world = worldFor(vf)
		world:ClearAllChildren()
		local box, size = model:GetBoundingBox()
		local extent = math.max(size.X, size.Y, size.Z, 0.5)
		local cam = vf:FindFirstChild("PreviewCamera") :: Camera?
		if cam == nil then
			local created = Instance.new("Camera")
			created.Name = "PreviewCamera"
			created.Parent = vf
			cam = created
		end
		local camera = cam :: Camera
		camera.FieldOfView = 40
		-- Distance that fits `extent` in a 40 degree view, plus a margin.
		local distance = extent / (2 * math.tan(math.rad(20))) * 1.15
		local centre = box.Position
		camera.CFrame = CFrame.lookAt(centre + Vector3.new(0, extent * 0.25, -distance), centre)
		vf.CurrentCamera = camera
		vf.Ambient = Color3.fromRGB(190, 190, 205)
		vf.LightColor = Color3.fromRGB(255, 255, 255)
		vf.LightDirection = Vector3.new(0.4, -1, 0.6)
		model.Parent = world
	end)
	if not ok then
		warn(`[SlimePreview] model mount failed: {err}`)
		SlimePreview.unmount(viewport)
		return false
	end
	return true
end

-- Drops the model, WorldModel and camera from `viewport`.
function SlimePreview.unmount(viewport: Instance)
	for _, child in viewport:GetChildren() do
		if child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end
end

-- How far an avatar well behind a slime preview leans from Theme.Row towards Theme.Ink.
SlimePreview.WELL_TINT = 0.4

-- What a slime's preview looks like: the genome fields its model is built from. A viewport is remounted only
-- when this changes.
function SlimePreview.lookOf(slime: any): string
	local c = if type(slime.color) == "table" then slime.color else {}
	return table.concat({
		tostring(slime.id),
		tostring(slime.species),
		tostring(slime.tier),
		`{c[1]},{c[2]},{c[3]}`,
		tostring(slime.size),
		tostring(slime.pattern),
		tostring(slime.eyes),
		tostring(slime.mouth),
	}, ":")
end

-- Where a slime preview's model comes from: `species` (ctx.buildSpecies) gives the species mesh the SlimeDex
-- shows, `slime` (ctx.buildSlime) the generated model from the genome. Either may be nil.
export type Builders = {
	species: ((speciesId: string) -> Model?)?,
	greySpecies: ((speciesId: string) -> Model?)?, -- the species mesh recoloured grey (SpeciesModel.greyBuilder)
	slime: ((genome: any) -> Model?)?,
}

-- Shows `slime` (a genome) in `viewport` the way the SlimeDex shows its species: the species mesh when it has
-- replicated, else the generated model, else the Ball blob in the slime's colour. The mounted look names its
-- source, so a row that fell back switches to the mesh once it arrives; a mesh look is never rebuilt and a
-- failed fallback is not retried. The viewport is visible only while something is mounted.
function SlimePreview.mountSlime(viewport: Instance, slime: any, builders: Builders?)
	local base = SlimePreview.lookOf(slime)
	local current = viewport:GetAttribute("Look")
	if current == `{base}:mesh` then
		return
	end
	local b: Builders = builders or {}
	if b.species and type(slime.species) == "string" then
		local built, model = pcall(b.species, slime.species)
		if built and model ~= nil then
			if SlimePreview.mountModel(viewport, model, nil) then
				viewport:SetAttribute("Look", `{base}:mesh`);
				(viewport :: ViewportFrame).Visible = true
				return
			end
		end
	end
	if current == `{base}:built` then
		return
	end
	local ok = false
	if b.slime then
		local built, model = pcall(b.slime, slime)
		ok = built and model ~= nil and SlimePreview.mountModel(viewport, model, nil)
	end
	if not ok then
		ok = SlimePreview.mount(viewport, if type(slime.color) == "table" then slime.color else {}, nil)
	end
	viewport:SetAttribute("Look", `{base}:built`);
	(viewport :: ViewportFrame).Visible = ok
end

-- A species as the menus show it: its mesh in full colour once found (or owned), the same mesh in grey before.
export type SpeciesLook = { key: string, found: boolean, tier: number, speciesColor: { number } }

-- Builds the model `look` shows, best source first, and names that source. Found: the species mesh, else the
-- model generated from `genome(look)`, else the Ball blob in the species colour. Not found: the grey species
-- mesh, else the species mesh washed grey, else a grey blob; never the generated model, which does not look
-- like the species.
local function speciesSource(look: SpeciesLook, b: Builders): (Model?, string)
	local function try(build: ((string) -> Model?)?): Model?
		if build == nil then
			return nil
		end
		local ok, model = pcall(build, look.key)
		return if ok then model else nil
	end
	if not look.found then
		local grey = try(b.greySpecies)
		if grey then
			return grey, "grey"
		end
	end
	local species = try(b.species)
	return species, if species then "mesh" else "none"
end

-- Shows `look` in `viewport` (see speciesSource). The mounted look names its source, so a well that fell back
-- switches to the better model once it is there; nothing is rebuilt while the look and source stay the same.
-- Returns whether something is mounted (the viewport is visible then).
function SlimePreview.mountSpecies(
	viewport: Instance,
	look: SpeciesLook,
	builders: Builders?,
	genome: (SpeciesLook) -> any
): boolean
	local b: Builders = builders or {}
	local model, source = speciesSource(look, b)
	local tag = `{look.key}:{look.found}:{source}`
	if viewport:GetAttribute("Look") == tag then
		if model then
			model:Destroy()
		end
		return (viewport :: ViewportFrame).Visible
	end
	-- The grey mesh is grey already; anything else is washed grey while the species is not found.
	local opts = { greyed = not look.found and source ~= "grey" }
	local ok = model ~= nil and SlimePreview.mountModel(viewport, model :: Model, opts)
	if not ok and look.found and b.slime then
		local built, generated = pcall(b.slime, genome(look))
		ok = built and generated ~= nil and SlimePreview.mountModel(viewport, generated, opts)
	end
	if not ok then
		ok = SlimePreview.mount(viewport, look.speciesColor, opts)
	end
	viewport:SetAttribute("Look", tag);
	(viewport :: ViewportFrame).Visible = ok
	return ok
end

-- Empties a viewport mounted by mountSlime and hides it.
function SlimePreview.unmountSlime(viewport: Instance)
	if viewport:GetAttribute("Look") ~= nil then
		SlimePreview.unmount(viewport)
		viewport:SetAttribute("Look", nil)
	end
	(viewport :: ViewportFrame).Visible = false
end

export type ListEntry = {
	viewport: Instance,
	slime: any, -- the genome to show
	y: number, -- the row's top inside the list canvas (design px)
	h: number,
}

-- List virtualisation: the MAX_LIVE entries nearest `centre` (a canvas y, the middle of the scroll window)
-- show their slime; every other entry is emptied. Ties go to the higher row.
function SlimePreview.syncNearest(entries: { ListEntry }, centre: number, builders: Builders?)
	local order = table.clone(entries)
	table.sort(order, function(a, b)
		local da, db = math.abs(a.y + a.h / 2 - centre), math.abs(b.y + b.h / 2 - centre)
		if da ~= db then
			return da < db
		end
		return a.y < b.y
	end)
	for i, entry in order do
		if i <= SlimePreview.MAX_LIVE then
			SlimePreview.mountSlime(entry.viewport, entry.slime, builders)
		else
			SlimePreview.unmountSlime(entry.viewport)
		end
	end
end

return table.freeze(SlimePreview)
