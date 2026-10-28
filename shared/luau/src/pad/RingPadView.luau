--!strict
--[[
	RingPadView (adapter, server or client)

	Builds a RingPad as parts and colours it. One Model `name` (default "RingPad") holds a Model Seg_<i> per piece,
	each with its blocks Block_<j>. The parts are anchored and never collide, take touches, answer raycasts or cast
	shadows, so players walk over the ring and only the game's own check (RingPad.inside) decides who stands on it.

	  local pad = RingPadView.new(parent, {
	      shape = { radius = 4.6, width = 1.6 },          -- RingPad.Options
	      looks = { charge = { color = ..., material = Enum.Material.Neon, transparency = 0 } },
	  })
	  pad:place(floorPoint, yawDegrees)  -- the centre on the floor; yaw turns the front (-Z) round +Y
	  pad:show(lit, "charge")            -- segments 1..lit wear looks.charge, the rest looks.dim
	  pad:show(lit, "charge", "ready")   -- ... and the rest looks.ready
	  pad:standing(position)             -- a world point is on the pad (uses the last place())
	  pad:destroy()

	Options (all optional): name, shape, looks (merged over RingPadView.LOOKS; `dim` is the unlit look),
	template (a BasePart cloned for every block instead of a plain Part; its Size is set per block).
]]

local RingPad = if script then require(script.Parent.RingPad) else require("./RingPad")

export type Look = { color: Color3, material: Enum.Material, transparency: number }

export type Options = {
	name: string?,
	shape: RingPad.Options?,
	looks: { [string]: Look }?,
	template: BasePart?,
}

export type Pad = {
	model: Model,
	shape: RingPad.Shape,
	place: (self: Pad, centre: Vector3, yaw: number) -> (),
	show: (self: Pad, lit: number, look: string, rest: string?) -> (),
	standing: (self: Pad, position: Vector3) -> boolean,
	destroy: (self: Pad) -> (),
}

local RingPadView = {}

-- Default looks. Opaque on purpose: a piece's blocks overlap a little on the inside of the ring.
RingPadView.LOOKS = table.freeze({
	dim = table.freeze({
		color = Color3.fromRGB(31, 111, 120),
		material = Enum.Material.SmoothPlastic,
		transparency = 0,
	}),
	lit = table.freeze({ color = Color3.fromRGB(88, 214, 207), material = Enum.Material.Neon, transparency = 0 }),
})

local MOVE_EPSILON = 0.05 -- studs the centre may drift before place() moves the parts again

function RingPadView.new(parent: Instance, options: Options?): Pad
	local o: Options = options or {}
	local shape = RingPad.shape(o.shape)
	local looks: { [string]: Look } = table.clone(RingPadView.LOOKS) :: any
	for key, look in o.looks or {} do
		looks[key] = look
	end

	local model = Instance.new("Model")
	model.Name = o.name or "RingPad"
	local pieces: { { BasePart } } = {}
	local blocks = RingPad.blocks(shape)
	for s = 1, shape.segments do
		local seg = Instance.new("Model")
		seg.Name = `Seg_{s}`
		seg.Parent = model
		pieces[s] = {}
	end
	for _, b in blocks do
		local part: BasePart = if o.template then o.template:Clone() else Instance.new("Part")
		part.Name = `Block_{b.index}`
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = false
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Size = Vector3.new(b.length, b.thickness, b.width)
		part.Parent = model:FindFirstChild(`Seg_{b.segment}`)
		table.insert(pieces[b.segment], part)
	end

	local centre: Vector3? = nil
	local frame = CFrame.identity
	local shown: { lit: number, look: string, rest: string }? = nil

	local pad = {} :: Pad
	pad.model = model
	pad.shape = shape

	function pad.place(_self: Pad, at: Vector3, yaw: number)
		if centre and (centre - at).Magnitude <= MOVE_EPSILON then
			return
		end
		centre = at
		frame = CFrame.new(at) * CFrame.Angles(0, math.rad(yaw), 0)
		local i = 0
		for s = 1, shape.segments do
			for _, part in pieces[s] do
				i += 1
				local b = blocks[i]
				part.CFrame = frame * CFrame.new(b.x, b.y, b.z) * CFrame.Angles(0, b.yaw, 0)
			end
		end
	end

	function pad.show(_self: Pad, lit: number, look: string, rest: string?)
		local restName = rest or "dim"
		if shown and shown.lit == lit and shown.look == look and shown.rest == restName then
			return
		end
		shown = { lit = lit, look = look, rest = restName }
		local on = looks[look] or looks.dim
		local off = looks[restName] or looks.dim
		for s, parts in pieces do
			local l = if s <= lit then on else off
			for _, part in parts do
				part.Color = l.color
				part.Material = l.material
				part.Transparency = l.transparency
			end
		end
	end

	function pad.standing(_self: Pad, position: Vector3): boolean
		if not centre then
			return false
		end
		local d = position - centre
		return RingPad.inside(shape, d.X, d.Y, d.Z)
	end

	function pad.destroy(_self: Pad)
		model:Destroy()
	end

	pad:show(0, "dim")
	model.Parent = parent
	return pad
end

return table.freeze(RingPadView)
