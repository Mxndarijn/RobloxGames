--!strict
--[[
	PlotMascot (owner: Archer)

	The goo jar tower's client-only decor (CONTRACT.md §5.3, docs/base-remodel): the slime mascot on the top jar's
	lid, bigger with each version (the number of jars standing), crowned at the last one, and a goo ooze ring round
	the top of every standing jar. VisualsClient (PlotVisuals) calls PlotMascot.apply(plot) a few times a second;
	it only rebuilds when the version changed. The parts are local (nothing replicates), anchored, non-colliding,
	never queried.

	PlotMascot.version(plot) / pose(version) are pure enough for Lune (version reads only Floor_<f> children).
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

local PlotMascot = {}

PlotMascot.NAME = "JarDecor"
PlotMascot.BODY = 5 -- mascot body diameter at version 1
PlotMascot.GROW = 0.3 -- extra scale per version
PlotMascot.GOO = { 110, 226, 170 }
PlotMascot.GOO_HI = { 170, 250, 205 }
PlotMascot.CROWN = { 255, 205, 60 }
PlotMascot.OOZE_OUT = 1.3 -- the ooze ring reaches this far past the jar's glass
PlotMascot.OOZE_HEIGHT = 0.8

export type Pose = { scale: number, crown: boolean, lidY: number }

-- How many jars the plot shows: 1 + every Floor_<f> standing.
function PlotMascot.version(plot: any): number
	local v = 1
	for f = 2, #Config.BASE_FLOORS do
		if plot:FindFirstChild(`Floor_{f}`) then
			v = f
		end
	end
	return v
end

-- The mascot for `version`: scale, crown, and the plot-local height of the top lid it sits on.
function PlotMascot.pose(version: number): Pose
	return {
		scale = 1 + PlotMascot.GROW * (version - 1),
		crown = version >= #Config.BASE_FLOORS,
		lidY = WorldLayout.floorTop(version + 1),
	}
end

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end

local function part(
	parent: Instance,
	name: string,
	shape: Enum.PartType,
	size: Vector3,
	cf: CFrame,
	color: { number }
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = shape
	p.Size = size
	p.CFrame = cf
	p.Color = rgb(color)
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function build(plot: Instance, base: BasePart, version: number): Model
	local model = Instance.new("Model")
	model.Name = PlotMascot.NAME
	model:SetAttribute("Version", version)
	-- Plot-local (Base-frame) point: the Base's centre is half its height under the plot floor.
	local function at(x: number, y: number, z: number): CFrame
		return base.CFrame * CFrame.new(x, y - WorldLayout.PLOT_FLOOR_TOP + base.Size.Y / 2, z)
	end
	for f = 1, version do
		local r = WorldLayout.jarRadius(f) + WorldLayout.JAR_WALL + PlotMascot.OOZE_OUT
		local y = WorldLayout.floorTop(f + 1) - PlotMascot.OOZE_HEIGHT / 2
		local ooze = part(
			model,
			`Ooze_{f}`,
			Enum.PartType.Cylinder,
			Vector3.new(PlotMascot.OOZE_HEIGHT, r * 2, r * 2),
			at(0, y, 0) * CFrame.Angles(0, 0, math.pi / 2),
			PlotMascot.GOO
		)
		ooze.Material = Enum.Material.SmoothPlastic
		ooze.Transparency = 0.25
	end
	local pose = PlotMascot.pose(version)
	local d = PlotMascot.BODY * pose.scale
	local body = part(
		model,
		"Body",
		Enum.PartType.Ball,
		Vector3.new(d, d * 0.8, d),
		at(0, pose.lidY + d * 0.4, 0),
		PlotMascot.GOO
	)
	body.Material = Enum.Material.SmoothPlastic
	body.Transparency = 0.1
	part(
		model,
		"Shine",
		Enum.PartType.Ball,
		Vector3.one * d * 0.25,
		at(d * 0.18, pose.lidY + d * 0.62, -d * 0.18),
		PlotMascot.GOO_HI
	)
	for k, side in { -1, 1 } do
		-- the face looks out of the door (plot-local -Z)
		part(
			model,
			`Eye_{k}`,
			Enum.PartType.Ball,
			Vector3.one * d * 0.16,
			at(side * d * 0.17, pose.lidY + d * 0.5, -d * 0.4),
			{ 30, 30, 40 }
		)
	end
	if pose.crown then
		local crown = part(
			model,
			"Crown",
			Enum.PartType.Cylinder,
			Vector3.new(d * 0.25, d * 0.45, d * 0.45),
			at(0, pose.lidY + d * 0.8 + d * 0.12, 0) * CFrame.Angles(0, 0, math.pi / 2),
			PlotMascot.CROWN
		)
		crown.Material = Enum.Material.Neon
	end
	model.Parent = plot
	return model
end

-- Keeps the plot's local jar decor in step with the jars standing. Idempotent.
function PlotMascot.apply(plot: Instance)
	local base = plot:FindFirstChild("Base")
	if not (base and base:IsA("BasePart")) then
		return
	end
	local current = plot:FindFirstChild(PlotMascot.NAME)
	-- The jar tower meshes carry their own mascot, crown and goo ooze (the jars' MascotLook slots): no local decor then.
	local looks = plot:FindFirstChild("JarLooks")
	if looks and looks:FindFirstChild("MascotLook") then
		if current then
			current:Destroy()
		end
		return
	end
	local version = PlotMascot.version(plot)
	if current and current:GetAttribute("Version") == version then
		return
	end
	if current then
		current:Destroy()
	end
	build(plot, base, version)
end

return table.freeze(PlotMascot)
