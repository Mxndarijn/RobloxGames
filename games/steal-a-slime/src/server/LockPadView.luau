--!strict
--[[
	LockPadView (Roblox adapter)

	Builds each plot's lock pad (CONTRACT.md §8.5): a Model Plot_<i>.LockPad of Config.LOCK_PAD.SEGMENTS flat segments
	Seg_1..Seg_n in a ring on the floor round the LockButton, and colours them from LockPad.ring. The segments never
	collide, take touches or answer raycasts. It follows the LockButton when a base swap moves it. `standing` says
	whether a root part is on a plot's pad. Holds no rules: LockPad decides.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Constants = require(ReplicatedStorage.Shared.Constants)
local LockPad = require(script.Parent.LockPad)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)

local PAD = Config.LOCK_PAD

-- Look per mode: lit segments wear `lit`, the rest `dim`.
local LOOK = table.freeze({
	dim = table.freeze({
		color = Color3.fromRGB(31, 111, 120),
		material = Enum.Material.SmoothPlastic,
		transparency = 0.25,
	}),
	charge = table.freeze({ color = Color3.fromRGB(88, 214, 207), material = Enum.Material.Neon, transparency = 0 }),
	locked = table.freeze({ color = Color3.fromRGB(229, 72, 77), material = Enum.Material.Neon, transparency = 0 }),
	ready = table.freeze({ color = Color3.fromRGB(63, 209, 122), material = Enum.Material.Neon, transparency = 0 }),
})
local GAP = 0.18 -- share of each segment's arc left open between segments
local MOVE_EPSILON = 0.05 -- studs the LockButton may drift before the ring is moved after it

type Pad = { model: Model, segments: { BasePart }, at: Vector3?, lit: number, mode: string }

local pads: { [number]: Pad } = {}

local LockPadView = {}

-- World Y of the plot's ground-floor walking surface: the top of its Base (every base, the greybox too).
local function floorY(plot: Instance): number?
	local base = plot:FindFirstChild("Base")
	return if base and base:IsA("BasePart") then base.Position.Y + base.Size.Y / 2 else nil
end

local function build(plot: Instance): Pad
	local old = plot:FindFirstChild(Constants.LOCK_PAD_NAME)
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = Constants.LOCK_PAD_NAME
	local arc = 2 * math.pi * PAD.RADIUS / PAD.SEGMENTS
	local segments: { BasePart } = {}
	for i = 1, PAD.SEGMENTS do
		local part = Instance.new("Part")
		part.Name = `Seg_{i}`
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(arc * (1 - GAP), PAD.THICKNESS, PAD.WIDTH)
		part.Color = LOOK.dim.color
		part.Material = LOOK.dim.material
		part.Transparency = LOOK.dim.transparency
		part.Parent = model
		segments[i] = part
	end
	model.Parent = plot
	return { model = model, segments = segments, at = nil, lit = 0, mode = "idle" }
end

-- Lays the segments round `centre` clockwise (seen from above), the first one on the plot's front side.
local function place(pad: Pad, centre: Vector3, yaw: number)
	local origin = CFrame.new(centre) * CFrame.Angles(0, math.rad(yaw), 0)
	for i, part in pad.segments do
		local angle = -(i - 0.5) / PAD.SEGMENTS * 2 * math.pi
		part.CFrame = origin * CFrame.Angles(0, angle, 0) * CFrame.new(0, PAD.LIFT + PAD.THICKNESS / 2, -PAD.RADIUS)
	end
	pad.at = centre
end

local function paint(pad: Pad, ring: LockPad.Ring)
	if pad.mode == ring.mode and pad.lit == ring.lit then
		return
	end
	pad.mode, pad.lit = ring.mode, ring.lit
	local lit = (LOOK :: any)[ring.mode] or LOOK.dim
	for i, part in pad.segments do
		local look = if i <= ring.lit then lit else LOOK.dim
		part.Color = look.color
		part.Material = look.material
		part.Transparency = look.transparency
	end
end

--[[
	Makes plot `index`'s pad match `ring`, round `button` (its LockButton). No button: the pad goes away.
]]
function LockPadView.update(plot: Instance, index: number, button: BasePart?, ring: LockPad.Ring)
	local pad = pads[index]
	local floor = floorY(plot)
	if not button or not floor then
		if pad then
			pad.model:Destroy()
			pads[index] = nil
		end
		return
	end
	local live: Pad = if pad and pad.model.Parent == plot then pad else build(plot)
	pads[index] = live
	local p = button.Position
	local centre = Vector3.new(p.X, floor, p.Z)
	if not live.at or (live.at - centre).Magnitude > MOVE_EPSILON then
		local _, yaw = WorldLayout.plotCentre(index)
		place(live, centre, yaw)
	end
	paint(live, ring)
end

-- True when `root` stands on `plot`'s lock pad round `button` (its LockButton).
function LockPadView.standing(plot: Instance, button: BasePart, root: BasePart): boolean
	local floor = floorY(plot)
	if not floor then
		return false
	end
	local b, r = button.Position, root.Position
	return LockPad.inside(r.X - b.X, r.Y - floor, r.Z - b.Z)
end

return LockPadView
