--!strict
--[[
	SlimePreview

	Cheap client-side slime model for SlimeDex ViewportFrames. Lives in ui/
	(not visuals): Ball body + eyes, tinted from the row colour. Locked rows
	use a dark silhouette body with dim, half-transparent eyes.

	Choice: Ball parts, not SpecialMesh + Config.SLIME_MESH_ASSET_ID. MeshId
	needs the asset online and fails under Lune; a Ball reads as a blob in a
	small ViewportFrame and always builds. Real mesh/ModelFactory previews
	remain a later upgrade once shared client builders exist.

	Mutations get a finish (FINISHES, keyed by save id): body material plus
	an optional accent behind or on the slime, so the v28 Rainbow / Crystal /
	Eclipse rows read apart from plain tints (a dark Eclipse body gets a
	bright corona, never the locked look).

	One untinted template per look (locked, open, or open + mutation) is
	built on first use; every preview is a Clone of it with the body tinted.
	mount() recycles the viewport's WorldModel and camera and only swaps the
	model.
]]

export type Opts = {
	locked: boolean?,
	mutation: string?, -- save id ("Lava", "Eclipse", ...); "None" / nil = plain
}

-- A disc (thin cylinder facing the camera) behind the body, or a small
-- block on top of it.
export type Accent = {
	name: string,
	kind: "Disc" | "Shard",
	diameter: number,
	color: { number },
	z: number?, -- disc depth behind the body (negative)
}

export type Finish = {
	material: Enum.Material?,
	transparency: number?,
	reflectance: number?,
	accents: { Accent }?,
}

local SlimePreview = {}

-- At most this many Dex rows (by list position) get a live ViewportFrame;
-- later rows keep the colour swatch.
SlimePreview.MAX_LIVE = 24

SlimePreview.SILHOUETTE = Color3.fromRGB(28, 30, 38)

local WHITE = Color3.fromRGB(245, 248, 255)
local INK = Color3.fromRGB(20, 22, 30)
local DIM_EYE = Color3.fromRGB(70, 72, 84)
local DIM_PUPIL = Color3.fromRGB(40, 42, 50)

-- Per mutation save id. Lava displays as Syrup (docs/archive/RANCH_RENAME.md).
SlimePreview.FINISHES = table.freeze({
	Glow = table.freeze({ material = Enum.Material.Neon }),
	Lava = table.freeze({ reflectance = 0.15 }),
	Wet = table.freeze({ material = Enum.Material.Glass, transparency = 0.1, reflectance = 0.2 }),
	Frozen = table.freeze({
		material = Enum.Material.Ice,
		reflectance = 0.25,
		accents = table.freeze({
			table.freeze({ name = "Frost", kind = "Shard", diameter = 0.4, color = { 235, 250, 255 } }),
		}),
	}),
	Galaxy = table.freeze({
		accents = table.freeze({
			table.freeze({ name = "Nebula", kind = "Disc", diameter = 2.5, color = { 70, 40, 140 }, z = -0.7 }),
		}),
	}),
	Rainbow = table.freeze({
		accents = table.freeze({
			table.freeze({ name = "BandRed", kind = "Disc", diameter = 2.9, color = { 255, 80, 90 }, z = -0.7 }),
			table.freeze({ name = "BandYellow", kind = "Disc", diameter = 2.6, color = { 255, 220, 80 }, z = -0.68 }),
			table.freeze({ name = "BandBlue", kind = "Disc", diameter = 2.3, color = { 90, 170, 255 }, z = -0.66 }),
		}),
	}),
	Gold = table.freeze({ material = Enum.Material.Foil, reflectance = 0.35 }),
	Crystal = table.freeze({
		material = Enum.Material.Glass,
		transparency = 0.25,
		reflectance = 0.3,
		accents = table.freeze({
			table.freeze({ name = "Shard", kind = "Shard", diameter = 0.5, color = { 200, 245, 255 } }),
		}),
	}),
	Eclipse = table.freeze({
		accents = table.freeze({
			table.freeze({ name = "Corona", kind = "Disc", diameter = 2.7, color = { 255, 214, 140 }, z = -0.7 }),
		}),
	}),
} :: { [string]: Finish })

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

local function accentPart(accent: Accent, parent: Instance): Part
	local p = ball(accent.name, accent.diameter, Color3.fromRGB(255, 255, 255), Vector3.zero, parent)
	p.Color = Color3.fromRGB(accent.color[1], accent.color[2], accent.color[3])
	p.Material = Enum.Material.Neon
	if accent.kind == "Disc" then
		p.Shape = Enum.PartType.Cylinder
		p.Size = Vector3.new(0.05, accent.diameter, accent.diameter)
		-- Cylinder axis is X: turn it to Z so the disc faces the camera.
		p.CFrame = CFrame.new(0, 0, accent.z or -0.7) * CFrame.Angles(0, math.rad(90), 0)
	else
		p.Shape = Enum.PartType.Block
		p.Size = Vector3.new(accent.diameter * 0.6, accent.diameter, accent.diameter * 0.6)
		p.CFrame = CFrame.new(0.2, 1.05, 0) * CFrame.Angles(0, math.rad(45), math.rad(-15))
	end
	return p
end

-- 2-stud body at the origin, eyes on the +Z face (towards the camera).
local function buildTemplate(locked: boolean, mutation: string?): Model
	local model = Instance.new("Model")
	model.Name = if locked then "SlimePreviewLocked" else "SlimePreview"
	model.PrimaryPart = ball("Body", 2, SlimePreview.SILHOUETTE, Vector3.zero, model)
	local eyeColor = if locked then DIM_EYE else WHITE
	local pupilColor = if locked then DIM_PUPIL else INK
	local sides: { { suffix: string, x: number } } = { { suffix = "L", x = -0.35 }, { suffix = "R", x = 0.35 } }
	for _, side in sides do
		local suffix, x = side.suffix, side.x
		local white = ball(`EyeWhite{suffix}`, 0.42, eyeColor, Vector3.new(x, 0.25, 0.72), model)
		white.Transparency = if locked then 0.35 else 0
		local pupil = ball(`Pupil{suffix}`, 0.2, pupilColor, Vector3.new(x, 0.22, 0.84), model)
		pupil.Transparency = if locked then 0.5 else 0
	end
	model:SetAttribute("Locked", locked)
	local finish: Finish? = if mutation then SlimePreview.FINISHES[mutation] else nil
	if finish then
		local body = model.PrimaryPart :: Part
		body.Material = finish.material or body.Material
		body.Transparency = finish.transparency or 0
		body.Reflectance = finish.reflectance or 0
		for _, accent in finish.accents or {} do
			accentPart(accent, model)
		end
		model:SetAttribute("Mutation", mutation)
	end
	return model
end

local templates: { [string]: Model } = {}

-- Locked rows never show a mutation; unknown mutations use the plain look.
local function templateFor(locked: boolean, mutation: string?): Model
	local finished = if not locked and mutation and SlimePreview.FINISHES[mutation] then mutation else nil
	local key = if locked then "locked" elseif finished then `open:{finished}` else "open"
	local cached: Model? = templates[key]
	if cached then
		return cached
	end
	local built = buildTemplate(locked, finished)
	templates[key] = built
	return built
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
-- (0..255) with the mutation's finish, or the dark silhouette when locked.
function SlimePreview.build(colorRgb: { number }, opts: Opts?): Model
	local locked = opts ~= nil and opts.locked == true
	local model = templateFor(locked, if opts then opts.mutation else nil):Clone()
	local body = model:FindFirstChild("Body") :: Part
	body.Color = if locked then SlimePreview.SILHOUETTE else rgb(colorRgb)
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
-- sparkles are dropped; `locked` paints it as the dark silhouette. Returns
-- false on failure (caller falls back to SlimePreview.mount).
function SlimePreview.mountModel(viewport: Instance, model: Model, opts: Opts?): boolean
	local ok, err = pcall(function()
		local locked = opts ~= nil and opts.locked == true
		for _, inst in model:GetDescendants() do
			if inst:IsA("BasePart") then
				local part = inst :: BasePart
				part.Anchored = true
				if locked then
					part.Color = SlimePreview.SILHOUETTE
					part.Material = Enum.Material.SmoothPlastic
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

return table.freeze(SlimePreview)
