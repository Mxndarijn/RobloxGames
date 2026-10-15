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

	One untinted template per look (open / locked) is built on first use;
	every preview is a Clone of it with the body tinted. mount() recycles the
	viewport's WorldModel and camera and only swaps the model.
]]

export type Opts = {
	locked: boolean?,
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
local function buildTemplate(locked: boolean): Model
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
	return model
end

local templates: { [boolean]: Model } = {}

local function templateFor(locked: boolean): Model
	local cached: Model? = templates[locked]
	if cached then
		return cached
	end
	local built = buildTemplate(locked)
	templates[locked] = built
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
-- (0..255), or the dark silhouette when locked.
function SlimePreview.build(colorRgb: { number }, opts: Opts?): Model
	local locked = opts ~= nil and opts.locked == true
	local model = templateFor(locked):Clone()
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

-- Drops the model, WorldModel and camera from `viewport`.
function SlimePreview.unmount(viewport: Instance)
	for _, child in viewport:GetChildren() do
		if child:IsA("WorldModel") or child:IsA("Camera") then
			child:Destroy()
		end
	end
end

return table.freeze(SlimePreview)
