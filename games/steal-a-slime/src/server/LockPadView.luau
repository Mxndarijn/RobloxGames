--!strict
--[[
	LockPadView (Roblox adapter)

	Puts each plot's lock pad (CONTRACT.md §8.5) on the floor round its LockButton: a shared RingPadView, Model
	Plot_<i>.LockPad with a Model Seg_<i> per lit step, coloured from LockPadRing.ring. It follows the
	LockButton when a base swap moves it. `standing` says whether a root part is on a plot's pad. Holds no rules:
	LockPad decides.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage.Shared.Constants)
local LockPad = require(script.Parent.LockPad)
local LockPadRing = require(ReplicatedStorage.Shared.LockPadRing)
local RingPadView = require(ReplicatedStorage.Lib.pad.RingPadView)
local WorldLayout = require(ReplicatedStorage.Visuals.WorldLayout)

local LOOKS: { [string]: RingPadView.Look } = LockPadRing.partLooks()

local pads: { [number]: RingPadView.Pad } = {}

local LockPadView = {}

-- World Y of the plot's ground-floor walking surface: the top of its Base (every base, the greybox too).
local function floorY(plot: Instance): number?
	local base = plot:FindFirstChild("Base")
	return if base and base:IsA("BasePart") then base.Position.Y + base.Size.Y / 2 else nil
end

local function build(plot: Instance): RingPadView.Pad
	local old = plot:FindFirstChild(Constants.LOCK_PAD_NAME)
	if old then
		old:Destroy()
	end
	return RingPadView.new(plot, { name = Constants.LOCK_PAD_NAME, shape = LockPad.SHAPE, looks = LOOKS })
end

--[[
	Makes plot `index`'s pad match `ring`, round `button` (its LockButton). No button: the pad goes away.
]]
function LockPadView.update(plot: Instance, index: number, button: BasePart?, ring: LockPadRing.Ring)
	local pad = pads[index]
	local floor = floorY(plot)
	if not button or not floor then
		if pad then
			pad:destroy()
			pads[index] = nil
		end
		return
	end
	local live = if pad and pad.model.Parent == plot then pad else build(plot)
	pads[index] = live
	local p = button.Position
	local _, yaw = WorldLayout.plotCentre(index)
	live:place(Vector3.new(p.X, floor, p.Z), yaw)
	live:show(ring.lit, ring.mode, LockPadRing.REST[ring.mode] or "dim")
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
