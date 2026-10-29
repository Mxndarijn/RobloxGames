--!strict
--[[
	LockMotion (PlotVisuals module)

	Makes locking a base look smooth on this client. Local changes only; the server still decides everything.

	  * The door: when a plot locks or opens while this client watches, the StopperShut mesh moves from the open pose
	    (StopperParked) to shut, or back, over DoorSwing.TIMING (DoorSwing.pose: round the hinge, or a slide for the
	    factory's shutter), the DoorRing fades to its new colour and a shut door puffs a little dust at its foot.
	    While it plays, PlotVisuals tells PlotDecor to leave the door looks alone (`busy`). A plot this client first
	    sees already locked shows shut, with no motion.
	  * The lock pad's charge: the server keeps the ring green while the owner stands on it; this client paints the
	    sweep onto the same segment parts every frame from the plot's LockPadSince (LockPadRing.ring), so it fills
	    smoothly. When the charge ends it paints the ring as the server has it, so a late replication never leaves
	    the sweep behind.

	  local motion = LockMotion.new()
	  motion.step(plots, serverNow, os.clock(), viewerUserId)  -- every frame, before PlotDecor
	  motion.busy(plot) -> boolean
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local LockPadRing = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("LockPadRing"))
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local DoorSwing = require(Visuals:WaitForChild("DoorSwing"))
local PlotDecor = require(Visuals:WaitForChild("PlotDecor"))

local LockMotion = {}

LockMotion.DUST = table.freeze({
	count = 14,
	color = Color3.fromRGB(214, 190, 150), -- dry plaza dust
	texture = "rbxasset://textures/particles/smoke_main.dds",
})

type Look = LockPadRing.PartLook
local LOOKS = LockPadRing.partLooks()

type Swing = {
	closing: boolean,
	startedAt: number, -- os.clock
	mesh: BasePart,
	parked: BasePart,
	shutPose: CFrame,
	openPose: CFrame,
	lastPose: CFrame,
	ring: BasePart?,
	ringFrom: Color3,
	see: number, -- the shut door's transparency for this viewer
}
type Plot = { shut: boolean, swing: Swing?, painted: number?, segments: { { BasePart } }?, pad: Instance? }

local lookMesh = PlotDecor.lookMesh

-- True when two poses are the same up to float rounding (a pose read back from a part).
local function same(a: CFrame, b: CFrame): boolean
	return (a.Position - b.Position).Magnitude < 1e-3 and (a.LookVector - b.LookVector).Magnitude < 1e-4
end

local function setLook(part: BasePart, look: Look)
	if part.Color ~= look.color then
		part.Color = look.color
	end
	if part.Material ~= look.material then
		part.Material = look.material
	end
	if part.Transparency ~= look.transparency then
		part.Transparency = look.transparency
	end
end

-- A one-shot dust puff at the foot of `mesh` (the emitter is made once and kept on the mesh).
local function puff(mesh: BasePart)
	local attachment = mesh:FindFirstChild("LockDust")
	if not attachment then
		local a = Instance.new("Attachment")
		a.Name = "LockDust"
		a.Position = Vector3.new(0, -mesh.Size.Y / 2 + 0.3, 0)
		local e = Instance.new("ParticleEmitter")
		e.Name = "Dust"
		e.Enabled = false
		e.Texture = LockMotion.DUST.texture
		e.Color = ColorSequence.new(LockMotion.DUST.color)
		e.LightEmission = 0
		e.Lifetime = NumberRange.new(0.5, 0.9)
		e.Speed = NumberRange.new(3, 6)
		e.SpreadAngle = Vector2.new(180, 15)
		e.Drag = 4
		e.Acceleration = Vector3.new(0, 2, 0)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.8) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
		e.Parent = a
		a.Parent = mesh
		attachment = a
	end
	local emitter = (attachment :: Instance):FindFirstChild("Dust")
	if emitter and emitter:IsA("ParticleEmitter") then
		emitter:Emit(LockMotion.DUST.count)
	end
end

-- The ring's segment parts, Seg_1..Seg_n, each a list of its blocks.
local function segmentsOf(pad: Instance): { { BasePart } }
	local out = {}
	local s = 1
	while true do
		local seg = pad:FindFirstChild(`Seg_{s}`)
		if not seg then
			break
		end
		local parts = {}
		for _, child in seg:GetChildren() do
			if child:IsA("BasePart") then
				table.insert(parts, child)
			end
		end
		out[s] = parts
		s += 1
	end
	return out
end

export type Motion = {
	step: (plots: Instance, now: number, clock: number, viewerUserId: number?) -> (),
	busy: (plot: Instance) -> boolean,
}

function LockMotion.new(): Motion
	local T = DoorSwing.TIMING
	local states: { [Instance]: Plot } = {}

	local function startSwing(plot: Instance, st: Plot, closing: boolean, see: boolean, clock: number)
		local mesh, parked = lookMesh(plot, "StopperShut"), lookMesh(plot, "StopperParked")
		local old = st.swing
		if old and same(old.mesh.CFrame, old.lastPose) then
			old.mesh.CFrame = old.shutPose -- reversed half way: start again from the shut pose
		end
		st.swing = nil
		if not (mesh and parked) then
			return -- no door meshes yet: PlotDecor shows the primitive stopper as before
		end
		local ring = lookMesh(plot, "DoorRing")
		local shutPose = mesh.CFrame
		st.swing = {
			closing = closing,
			startedAt = clock,
			mesh = mesh,
			parked = parked,
			shutPose = shutPose,
			openPose = parked.CFrame,
			lastPose = shutPose,
			ring = ring,
			ringFrom = if ring then ring.Color else PlotDecor.ringColor(not closing),
			see = if see then PlotDecor.OWNER_DOOR_TRANSPARENCY else 0,
		}
		parked.Transparency = 1
	end

	local function stepSwing(st: Plot, clock: number)
		local swing = st.swing :: Swing
		if not swing.mesh.Parent or not swing.parked.Parent then
			st.swing = nil
			return
		end
		local seconds = if swing.closing then T.closeSeconds else T.openSeconds
		local t = (clock - swing.startedAt) / seconds
		local ring = swing.ring
		if ring and ring.Parent then
			ring.Color = swing.ringFrom:Lerp(
				PlotDecor.ringColor(swing.closing),
				math.clamp((clock - swing.startedAt) / T.ringSeconds, 0, 1)
			)
		end
		if t >= 1 then
			-- Done: the shut mesh back on its own pose (unless the server moved it meanwhile), the end look as
			-- PlotDecor draws it.
			if same(swing.mesh.CFrame, swing.lastPose) then
				swing.mesh.CFrame = swing.shutPose
			end
			swing.mesh.Transparency = if swing.closing then swing.see else 1
			swing.parked.Transparency = if swing.closing then 1 else 0
			if swing.closing then
				puff(swing.mesh)
			end
			st.swing = nil
			return
		end
		if not same(swing.mesh.CFrame, swing.lastPose) then
			st.swing = nil -- the server moved the door (a base swap): stop and let PlotDecor draw it
			return
		end
		local e = DoorSwing.ease(t, if swing.closing then T.closeOvershoot else T.openOvershoot)
		local open = if swing.closing then 1 - e else e
		local pose = DoorSwing.pose(swing.shutPose, swing.openPose, open)
		swing.mesh.CFrame = pose
		swing.lastPose = pose
		swing.mesh.Transparency = swing.see
	end

	-- Paints the pad's segments: 1..lit in `mode`'s look, the rest in its REST look.
	local function paint(st: Plot, pad: Instance, lit: number, mode: string)
		if st.pad ~= pad or st.segments == nil then
			st.pad = pad
			st.segments = segmentsOf(pad)
		end
		local on = LOOKS[mode] or LOOKS.dim
		local off = LOOKS[LockPadRing.REST[mode] or "dim"] or LOOKS.dim
		for s, parts in st.segments :: { { BasePart } } do
			local look = if s <= lit then on else off
			for _, part in parts do
				setLook(part, look)
			end
		end
	end

	local function stepCharge(plot: Instance, st: Plot, owned: boolean, now: number)
		local since = plot:GetAttribute(Constants.PLOT_LOCK_PAD_SINCE_ATTRIBUTE)
		if since == nil and st.painted == nil then
			return -- nobody charging and nothing painted: the ring is the server's
		end
		local pad = plot:FindFirstChild(Constants.LOCK_PAD_NAME)
		if not pad then
			return
		end
		local lockUntil = plot:GetAttribute("LockUntil")
		local startedAt = plot:GetAttribute(Constants.PLOT_LOCK_STARTED_AT_ATTRIBUTE)
		local ring = LockPadRing.ring(
			owned,
			now,
			if type(lockUntil) == "number" then lockUntil else 0,
			if type(startedAt) == "number" then startedAt else 0,
			if type(since) == "number" then since else nil
		)
		if ring.mode == "charge" then
			if st.painted ~= ring.lit then
				paint(st, pad, ring.lit, "charge")
				st.painted = ring.lit
			end
		elseif st.painted ~= nil then
			paint(st, pad, ring.lit, ring.mode) -- back to what the server shows
			st.painted = nil
		end
	end

	local function step(plots: Instance, now: number, clock: number, viewerUserId: number?)
		for _, plot in plots:GetChildren() do
			if not plot:IsA("Model") then
				continue
			end
			local lock = PlotDecor.lockOf(plot, now, viewerUserId)
			local st = states[plot]
			if not st then
				st = { shut = lock.shut }
				states[plot] = st
			elseif st.shut ~= lock.shut then
				st.shut = lock.shut
				startSwing(plot, st, lock.shut, lock.see, clock)
			end
			if st.swing then
				stepSwing(st, clock)
			end
			stepCharge(plot, st, lock.owned, now)
		end
		for plot in states do
			if plot.Parent ~= plots then
				states[plot] = nil
			end
		end
	end

	local function busy(plot: Instance): boolean
		local st = states[plot]
		return st ~= nil and st.swing ~= nil
	end

	return { step = step, busy = busy }
end

return LockMotion
