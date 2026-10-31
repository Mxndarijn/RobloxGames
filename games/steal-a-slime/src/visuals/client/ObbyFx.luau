--!strict
--[[
	ObbyFx (VisualsClient module, contract/obby.md)

	Plays the Goo Gauntlet's moving parts on this client, at server time, from the attributes server/ObbyView puts on
	workspace.Obby.Course parts (the OBBY_* names in Constants; the kinds are ObbyCourse.Motion):
	  * slide   moves along its axis and carries a player standing on it (surface velocity)
	  * spin    turns round its vertical axis and shoves what it hits (angular velocity)
	  * melt    the local player standing on it: fades and drops away after `delay`, comes back after `away`
	  * flip    solid in its share of the period, blinks just before it goes, see-through and not solid otherwise
	  * shrink  its width and depth breathe between full size and `min`
	  * bounce  the local player landing on it is thrown straight up (trampolines, slime cannons)
	  * lift    the local player inside the wind column rises
	  * swing   a pendulum swinging across the course, `arm` studs below its pivot (shoves what it hits)
	  * rock    a seesaw plank tipping forward and back round its centre
	  * roll    a log rolling round its own length; its turn carries a player standing on it sideways
	  * punch   shoots out along its axis, holds, slides back and rests (shoves what it hits)
	  * gust    a see-through wind zone that blows on and off; while on, the local player inside is pushed sideways
	It also turns the Goo Rings' swirls (the portal's and the ring home's: parts with Constants.GOO_SPIN, round their
	GOO_PIVOT's Z axis).
	Every change is local: each player collides with their own copy, so platforms move smoothly at frame rate.
	Parts farther than MAX_DISTANCE from the camera are skipped. Never fires remotes. Call `tick` once a frame.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))

local ObbyFx = {}

ObbyFx.MAX_DISTANCE = 260 -- studs from the camera
ObbyFx.FIND_EVERY = 1 -- seconds between looks for a new course
ObbyFx.FLIP_WARN = 0.5 -- seconds a flip tile blinks before it goes
ObbyFx.GONE_TRANSPARENCY = 0.85
ObbyFx.BOUNCE_COOLDOWN = 0.4 -- seconds before the same pad throws you again
ObbyFx.GUST_ON_TRANSPARENCY = 0.6
ObbyFx.GUST_OFF_TRANSPARENCY = 0.96
ObbyFx.GUST_WARN = 0.6 -- seconds a gust flickers before it starts blowing
-- A punch's beat as shares of its period: out, held, back, then resting.
ObbyFx.PUNCH_OUT = 0.1
ObbyFx.PUNCH_HOLD = 0.35
ObbyFx.PUNCH_BACK = 0.65

export type Controller = { tick: (camera: Camera?) -> (), stop: () -> () }

type Mover = {
	part: BasePart,
	kind: string,
	base: CFrame,
	size: Vector3,
	transparency: number,
	period: number,
	phase: number,
	axis: Vector3,
	amp: number,
	delay: number,
	away: number,
	duty: number,
	min: number,
	disc: boolean,
	power: number,
	arm: number,
	meltAt: number?, -- melt: local clock time it started melting
	readyAt: number?, -- bounce: local clock time it may throw again
}

-- The local player this frame: what they stand on, their root and humanoid.
type Local = { standingOn: BasePart?, root: BasePart?, humanoid: Humanoid? }

local TAU = 2 * math.pi

local function num(part: Instance, name: string, default: number): number
	local v = part:GetAttribute(name)
	return if type(v) == "number" and v == v then v else default
end

local function mover(part: BasePart): Mover?
	local kind = part:GetAttribute(Constants.OBBY_MOTION)
	local base = part:GetAttribute(Constants.OBBY_BASE)
	if type(kind) ~= "string" or typeof(base) ~= "CFrame" then
		return nil
	end
	local axis = part:GetAttribute(Constants.OBBY_AXIS)
	local period = num(part, Constants.OBBY_PERIOD, 3)
	return {
		part = part,
		kind = kind,
		base = base,
		size = part.Size,
		transparency = part.Transparency,
		period = if period == 0 then 3 else period,
		phase = num(part, Constants.OBBY_PHASE, 0),
		axis = if typeof(axis) == "Vector3" then axis else Vector3.zAxis,
		amp = num(part, Constants.OBBY_AMP, 0),
		delay = num(part, Constants.OBBY_DELAY, 0.7),
		away = num(part, Constants.OBBY_AWAY, 2.5),
		duty = num(part, Constants.OBBY_DUTY, 0.65),
		min = num(part, Constants.OBBY_MIN, 0.3),
		disc = part:GetAttribute(Constants.OBBY_SHRINK_AXES) == "yz",
		power = num(part, Constants.OBBY_POWER, 50),
		arm = num(part, Constants.OBBY_ARM, 0),
	}
end

-- How far out a punch is (0..1) at `cycle`, and how fast that changes per cycle.
local function punchAt(cycle: number): (number, number)
	if cycle < ObbyFx.PUNCH_OUT then
		local a = cycle / ObbyFx.PUNCH_OUT * math.pi / 2
		return math.sin(a), math.cos(a) * math.pi / 2 / ObbyFx.PUNCH_OUT
	elseif cycle < ObbyFx.PUNCH_HOLD then
		return 1, 0
	elseif cycle < ObbyFx.PUNCH_BACK then
		local span = ObbyFx.PUNCH_BACK - ObbyFx.PUNCH_HOLD
		return 1 - (cycle - ObbyFx.PUNCH_HOLD) / span, -1 / span
	end
	return 0, 0
end

local function setSolid(m: Mover, solid: boolean, transparency: number)
	if m.part.CanCollide ~= solid then
		m.part.CanCollide = solid
	end
	if m.part.Transparency ~= transparency then
		m.part.Transparency = transparency
	end
end

-- True when `p` is inside `part`'s box.
local function inside(part: BasePart, p: Vector3): boolean
	local q = part.CFrame:PointToObjectSpace(p)
	local half = part.Size / 2
	return math.abs(q.X) <= half.X and math.abs(q.Y) <= half.Y and math.abs(q.Z) <= half.Z
end

local function play(m: Mover, t: number, clock: number, me: Local)
	local part = m.part
	local standingOn = me.standingOn
	-- Only the fraction of the cycle: server time is ~1.8e9 s, and CFrame angles are 32-bit floats.
	local cycle = (t / m.period + m.phase) % 1
	if m.kind == "slide" then
		local angle = TAU * cycle
		part.CFrame = m.base + m.axis * (m.amp * math.sin(angle))
		part.AssemblyLinearVelocity = m.axis * (m.amp * TAU / m.period * math.cos(angle))
	elseif m.kind == "spin" then
		-- Round the world's up axis, so a disc laid on its side spins flat like a bar does.
		part.CFrame = CFrame.new(m.base.Position) * CFrame.fromAxisAngle(Vector3.yAxis, TAU * cycle) * m.base.Rotation
		part.AssemblyAngularVelocity = Vector3.new(0, TAU / m.period, 0)
	elseif m.kind == "swing" then
		local amp = math.rad(m.amp)
		local angle = amp * math.sin(TAU * cycle)
		local pivot = m.base * CFrame.new(0, m.arm, 0)
		local swung = pivot * CFrame.Angles(angle, 0, 0)
		part.CFrame = swung * CFrame.new(0, -m.arm, 0)
		local rate = amp * TAU / m.period * math.cos(TAU * cycle)
		part.AssemblyLinearVelocity = swung.ZVector * (-m.arm * rate)
	elseif m.kind == "rock" then
		local amp = math.rad(m.amp)
		part.CFrame = m.base * CFrame.Angles(0, 0, amp * math.sin(TAU * cycle))
		part.AssemblyAngularVelocity = m.base.ZVector * (amp * TAU / m.period * math.cos(TAU * cycle))
	elseif m.kind == "roll" then
		-- Round its own length (the log's X axis); the top of the log moves sideways.
		part.CFrame = m.base * CFrame.Angles(TAU * cycle, 0, 0)
		part.AssemblyAngularVelocity = m.base.XVector * (TAU / m.period)
	elseif m.kind == "punch" then
		local out, rate = punchAt(cycle)
		part.CFrame = m.base + m.axis * (m.amp * out)
		part.AssemblyLinearVelocity = m.axis * (m.amp * rate / m.period)
	elseif m.kind == "gust" then
		local on = cycle < m.duty
		local warn = not on and cycle >= 1 - ObbyFx.GUST_WARN / math.abs(m.period)
		local transparency = ObbyFx.GUST_OFF_TRANSPARENCY
		if on then
			transparency = ObbyFx.GUST_ON_TRANSPARENCY
		elseif warn and math.floor(clock * 8) % 2 == 0 then
			transparency = (ObbyFx.GUST_ON_TRANSPARENCY + ObbyFx.GUST_OFF_TRANSPARENCY) / 2
		end
		if part.Transparency ~= transparency then
			part.Transparency = transparency
		end
		local root = me.root
		if on and root and inside(part, root.Position) then
			-- m.axis points the way it blows (the sign of its power is folded in by ObbyView).
			local v = root.AssemblyLinearVelocity
			local along = v:Dot(m.axis)
			if along < m.power then
				root.AssemblyLinearVelocity = v + m.axis * (m.power - along)
			end
		end
	elseif m.kind == "bounce" then
		if standingOn == part and me.root and clock >= (m.readyAt or 0) then
			m.readyAt = clock + ObbyFx.BOUNCE_COOLDOWN
			if me.humanoid then
				me.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
			end
			local v = me.root.AssemblyLinearVelocity
			me.root.AssemblyLinearVelocity = Vector3.new(v.X, m.power, v.Z)
		end
	elseif m.kind == "lift" then
		local root = me.root
		if root and inside(part, root.Position) then
			local v = root.AssemblyLinearVelocity
			if v.Y < m.power then
				root.AssemblyLinearVelocity = Vector3.new(v.X, m.power, v.Z)
			end
		end
	elseif m.kind == "flip" then
		local frac = cycle
		if frac >= m.duty then
			setSolid(m, false, ObbyFx.GONE_TRANSPARENCY)
		elseif frac >= m.duty - ObbyFx.FLIP_WARN / math.abs(m.period) then
			local blink = math.floor(clock * 8) % 2 == 0
			setSolid(m, true, if blink then 0.5 else m.transparency)
		else
			setSolid(m, true, m.transparency)
		end
	elseif m.kind == "shrink" then
		local s = m.min + (1 - m.min) * (0.5 + 0.5 * math.cos(TAU * cycle))
		part.Size = if m.disc
			then Vector3.new(m.size.X, m.size.Y * s, m.size.Z * s)
			else Vector3.new(m.size.X * s, m.size.Y, m.size.Z * s)
		part.CFrame = m.base
	elseif m.kind == "melt" then
		if m.meltAt == nil and standingOn == part then
			m.meltAt = clock
		end
		local since = if m.meltAt then clock - m.meltAt else -1
		if since < 0 then
			setSolid(m, true, m.transparency)
		elseif since < m.delay then
			setSolid(m, true, m.transparency + (ObbyFx.GONE_TRANSPARENCY - m.transparency) * since / m.delay * 0.6)
		elseif since < m.delay + m.away then
			setSolid(m, false, ObbyFx.GONE_TRANSPARENCY)
		else
			m.meltAt = nil
			setSolid(m, true, m.transparency)
		end
	end
end

-- The part under the local player's feet (a short ray down from the root), or nil.
local function floorUnder(root: BasePart?, params: RaycastParams): BasePart?
	if not root then
		return nil
	end
	local hit = workspace:Raycast(root.Position, Vector3.new(0, -4.5, 0), params)
	return if hit and hit.Instance:IsA("BasePart") then hit.Instance else nil
end

type Swirl = { part: BasePart, pivot: CFrame, offset: CFrame, speed: number }

-- The Goo Ring swirl parts under `containers`, each with its rest offset from the ring centre.
local function findSwirls(containers: { Instance }): { Swirl }
	local out: { Swirl } = {}
	for _, container in containers do
		for _, d in container:GetDescendants() do
			local speed = d:GetAttribute(Constants.GOO_SPIN)
			local pivot = d:GetAttribute(Constants.GOO_PIVOT)
			if d:IsA("BasePart") and typeof(speed) == "number" and typeof(pivot) == "CFrame" then
				table.insert(out, { part = d, pivot = pivot, offset = pivot:ToObjectSpace(d.CFrame), speed = speed })
			end
		end
	end
	return out
end

function ObbyFx.start(): Controller
	local movers: { Mover } = {}
	local course: Instance? = nil
	local nextFind = 0
	local swirls: { Swirl } = {}
	local swirlKey: { Instance? } = {}
	local nextSwirlFind = 0

	-- Turns every Goo Ring swirl near the camera; looks for new rings (portal, a rebuilt course) every FIND_EVERY.
	local function spinSwirls(clock: number, camPos: Vector3?)
		if clock >= nextSwirlFind then
			nextSwirlFind = clock + ObbyFx.FIND_EVERY
			local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
			local portal = folder and folder:FindFirstChild(Constants.OBBY_PORTAL)
			local built = folder and folder:FindFirstChild(Constants.OBBY_COURSE)
			if portal ~= swirlKey[1] or built ~= swirlKey[2] then
				swirlKey = { portal, built }
				local containers: { Instance } = {}
				for _, c in { portal, built } do
					if c then
						table.insert(containers, c)
					end
				end
				swirls = findSwirls(containers)
			end
		end
		local far = ObbyFx.MAX_DISTANCE * ObbyFx.MAX_DISTANCE
		for _, sw in swirls do
			local d = if camPos then sw.pivot.Position - camPos else Vector3.zero
			if sw.part.Parent ~= nil and d:Dot(d) <= far then
				sw.part.CFrame = sw.pivot * CFrame.Angles(0, 0, clock * sw.speed) * sw.offset
			end
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include

	local function scan(model: Instance)
		movers = {}
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") then
				local m = mover(child)
				if m then
					table.insert(movers, m)
				end
			end
		end
		params.FilterDescendantsInstances = { model }
	end

	local function tick(camera: Camera?)
		local clock = os.clock()
		spinSwirls(clock, if camera then camera.CFrame.Position else nil)
		if course == nil or course.Parent == nil then
			if clock < nextFind then
				return
			end
			nextFind = clock + ObbyFx.FIND_EVERY
			local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
			local found = folder and folder:FindFirstChild(Constants.OBBY_COURSE)
			if not found then
				movers = {}
				course = nil
				return
			end
			course = found
			scan(found)
		end
		if #movers == 0 then
			return
		end
		local t = workspace:GetServerTimeNow()
		local camPos = if camera then camera.CFrame.Position else nil
		local character = Players.LocalPlayer and Players.LocalPlayer.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local me: Local = {
			standingOn = floorUnder(root, params),
			root = root,
			humanoid = character and character:FindFirstChildOfClass("Humanoid"),
		}
		local far = ObbyFx.MAX_DISTANCE * ObbyFx.MAX_DISTANCE
		for _, m in movers do
			if m.part.Parent ~= nil then
				local d = if camPos then m.base.Position - camPos else Vector3.zero
				if d:Dot(d) <= far then
					play(m, t, clock, me)
				end
			end
		end
	end

	return {
		tick = tick,
		stop = function()
			movers = {}
			course = nil
			swirls = {}
			swirlKey = {}
		end,
	}
end

return ObbyFx
