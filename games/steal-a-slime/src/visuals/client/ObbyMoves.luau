--!strict
--[[
	ObbyMoves (VisualsClient module, contract/obby-sections.md §7)

	The obby's character controllers, on the local player only. They read the parts of workspace.Obby.Course (built
	by ObbyCourseView, decoded from each part's ObbySpec JSON; vectors in the course frame, the model's ObbyFrame)
	and rescan when the course or its Slot changes. ObbyFx moves the parts (swinging vines, sweeping cannons); this
	reads where they are now. Everything runs only while ObbyLook.isInside.

	  boost   standing on a boost strip sets WalkSpeed to `boost.speed`; `carry` s after you leave it eases back
	          over EASE_SECONDS (a speed under 16 slows you: back strips)
	  slide   on a slide part you keep your speed, the slope pulls you downhill at `slide.pull` studs/s², walking
	          only steers (STEER_ACCEL, a quarter of a normal start) and the speed is capped at `slide.cap`. The
	          speed carries through a jump off the end; landing on any other floor (brake goo) ends it
	  vine    a rope swing (physics in shared ObbySections/Vine, the same the checks use): a knob within `vine.reach`
	          of your body (feet to head) grabs you, in a jump or walking at it. You hang from it, arms up, on a real
	          pendulum that keeps your run; holding the way you swing pumps it. A fresh jump press lets go with the
	          swing's speed plus a hop; a few dots show the flight's start (`vine.hint` s, mint when it lands safe
	          or on a rope). The rope you leave eases back to its server-time swing. Other clients see the hold through
	          ObbyVineSync (`held`, `rope`). "Jump to let go" on the first grabs
	  cannon  walking into a barrel snaps you in (PlatformStand, camera behind the barrel); a dotted line shows the
	          shot's arc for the barrel's aim now (red when it ends in goo or misses); jump fires: you follow that
	          fixed arc and are handed back to physics HAND_LIFT studs above the landing
	  moon    inside a moon zone a VectorForce carries (1 - `zone.gravity`) of your weight
	  dark    inside a dark zone the screen fades to night over DARK_SECONDS and a PointLight of `zone.light` studs
	          sits on you; leaving fades it back

	"Inside" is your body, not the root's centre (ObbyZone): a moon or dark zone holds you while any of you from the
	feet to the head is within ZONE_PAD of its shape (ZONE_PAD + ZONE_HOLD once you are in, so its edge never flickers;
	a moon zone's shape is the bubble dome ObbyParts draws, the ellipsoid in its box, not the box).

	The momentum a controller hands back (a slide's end jump, a vine release, a cannon landing) is kept
	in the air by the same "drive" that steers the slide: it calls Humanoid:Move right after the control script, so
	the humanoid's own air control does not brake it. Every controller puts the character back exactly when it ends
	(the WalkSpeed it found, PlatformStand off, the camera type and subject it found, no force or light left) and
	all of them end on every ObbyFall reset (ObbyFall.onReset), on leaving the obby world, on a new character and
	on a course rebuild. The dark zone never writes Lighting (NightSky owns it): its night is its own
	ColorCorrection, destroyed when it ends, so nothing can leak. Never fires remotes. Call `tick(dt)` once a frame.
]]

local Debris = game:GetService("Debris")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Visuals = ReplicatedStorage:WaitForChild("Visuals")
local Constants = require(Shared:WaitForChild("Constants"))
local GooPalette = require(Shared:WaitForChild("GooPalette"))
local ObbyFall = require(script.Parent:WaitForChild("ObbyFall"))
local ObbyLook = require(Visuals:WaitForChild("ObbyLook"))
local ObbyParts = require(Visuals:WaitForChild("ObbyParts"))
local ObbyVinePose = require(script.Parent:WaitForChild("ObbyVinePose"))
local ObbyZone = require(Visuals:WaitForChild("ObbyZone"))
local Vine = require(Shared:WaitForChild("ObbySections"):WaitForChild("Vine"))

local ObbyMoves = {}

ObbyMoves.BASE_WALK = 16 -- the obby's walking speed (contract §7); used when the humanoid's own can't be read
ObbyMoves.FLOOR_EXTRA = 1.5 -- studs below the feet the floor ray still counts as standing on a part

-- boost
ObbyMoves.EASE_SECONDS = 0.3 -- a boost eases back to the base speed over this long

-- slide (and the momentum drive)
ObbyMoves.STEER_ACCEL = 16 -- studs/s²: a quarter of a normal start (a humanoid reaches 16 studs/s in about 0.25 s)
ObbyMoves.FLAT_SLOPE = math.cos(math.rad(2)) -- a floor flatter than 2° has no downhill pull
ObbyMoves.GLIDE_MIN = 0.1 -- seconds in the air before a landing ends the kept momentum (the take-off frame)
ObbyMoves.GLIDE_MAX = 3 -- seconds of kept momentum at most

-- zones (moon, dark)
ObbyMoves.HEAD_UP = 2.5 -- studs from the root's centre to the top of the head
ObbyMoves.ZONE_PAD = 0.5 -- studs round a zone's box (sideways) the body counts as in it when it comes in
ObbyMoves.ZONE_HOLD = 0.5 -- extra studs it stays in by once it is in

-- vine (the physics and its numbers are in shared ObbySections/Vine)
ObbyMoves.REGRAB_SAME = 1.2 -- seconds before the rope you let go of grabs you again
ObbyMoves.REGRAB_ANY = 0.15 -- seconds before any rope grabs you again (a chain catches the next rope at once)
ObbyMoves.WALK_IN = 0.3 -- on the ground a rope only grabs you while you walk at it (MoveDirection · way to it)
ObbyMoves.GRAB_EASE = 0.12 -- seconds the body and the rope take to meet after a grab
ObbyMoves.RETURN = 0.8 -- seconds a rope you let go of takes to ease back to its server-time swing
ObbyMoves.PRESS_GAP = 0.12 -- a jump request this long after the last one is a fresh press (held jump repeats)
ObbyMoves.VINE_DOTS = 6 -- dots of the let-go flight while you hang
ObbyMoves.VINE_DOT = 0.4
ObbyMoves.PUFF = "rbxasset://textures/particles/smoke_main.dds" -- built-in (never uploaded)
ObbyMoves.HINT_GRABS = 3 -- the "Jump to let go" hint shows on this many grabs
ObbyMoves.HINT_TEXT = "Jump to let go"
ObbyMoves.JUMP_GRACE = 0.2 -- seconds after a grab or a seat in which a jump press does not count (the held jump)

-- cannon
ObbyMoves.CANNON_POWER = 75 -- studs/s when a cannon's spec leaves it out (the old SlimeCannon launch speed)
ObbyMoves.CANNON_ARC = 45 -- degrees up when a cannon's spec leaves it out
ObbyMoves.ENTER_MARGIN = 1.5 -- studs round the barrel's box that count as walking into it
ObbyMoves.RELOAD = 1 -- seconds after a shot before the same cannon takes you again
ObbyMoves.HAND_LIFT = 2 -- studs above the landing where the flight hands you back to physics
ObbyMoves.ARC_STEP = 1 / 30 -- seconds between arc samples
ObbyMoves.ARC_SECONDS = 4 -- the longest flight traced; a shot that lands nowhere by then is a miss
ObbyMoves.LAUNCH_CLEAR = 0.15 -- seconds of flight before the arc can land (it leaves the barrel's own deck)
ObbyMoves.HAZARD_PAD = 1 -- studs round a hazard's box the arc counts as hitting it
ObbyMoves.DOTS = 22 -- dots on the aim line (plus the landing dot)
ObbyMoves.DOT_SIZE = 0.45
ObbyMoves.LANDING_DOT = 1.4
ObbyMoves.CAM_BACK = 14 -- the seated camera: studs behind the barrel,
ObbyMoves.CAM_UP = 6 -- above it,
ObbyMoves.CAM_AHEAD = 24 -- and looking at a point this far ahead of it
-- The seat: you lie along the barrel like a human cannonball, arms up, head and shoulders out of its mouth. The
-- barrel (the cannon mesh, ObbyParts.SKINS.cannon) points SEAT_TILT degrees up from the barrel's centre, its lip
-- SEAT_MOUTH studs along that axis; the root sits SEAT_OUT studs back from the lip. In flight you go head first.
ObbyMoves.SEAT_TILT = 12
ObbyMoves.SEAT_MOUTH = 1.9
ObbyMoves.SEAT_OUT = 0.5

-- dark
ObbyMoves.DARK_SECONDS = 0.6 -- the fade in and out
ObbyMoves.DARK_NAME = "ObbyMovesDark"
ObbyMoves.DARK_LOOK = table.freeze({ -- the ColorCorrection at full dark: a cool night with crushed shadows
	TintColor = Color3.fromRGB(96, 108, 168),
	Brightness = -0.18,
	Contrast = 0.25,
	Saturation = -0.35,
})
ObbyMoves.LIGHT_BRIGHTNESS = 2.4 -- the player's PointLight at full dark
ObbyMoves.LIGHT_COLOR = Color3.fromRGB(255, 226, 170) -- a warm lantern
ObbyMoves.LIGHT_NAME = "ObbyMovesLight"
ObbyMoves.DEFAULT_LIGHT = 16 -- studs when a dark zone leaves its radius out

-- moon
ObbyMoves.MOON_NAME = "ObbyMovesMoon"

-- Built-in sounds only (never uploaded), quiet and short (contract §8).
local SOUNDS = table.freeze({
	squelch = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.25, speed = 1.6 },
	whoom = { id = "rbxasset://sounds/impact_water.mp3", volume = 0.2, speed = 0.55 },
	load = { id = "rbxasset://sounds/action_jump_land.mp3", volume = 0.35, speed = 0.8 },
	fire = { id = "rbxasset://sounds/action_jump.mp3", volume = 0.45, speed = 0.6 },
})

local function rgb(c: { number }): Color3
	return Color3.fromRGB(c[1], c[2], c[3])
end
local DOT_OK = rgb(GooPalette.Mint)
local DOT_BAD = ObbyParts.HAZARD.color -- the hazard look's red (contract §8)

-- `held`: the ObbyId of the vine rope the local player hangs on ("" = none), for ObbyVineSync to send.
-- `rope`: the course's vine rope with that ObbyId (its knob, ghost rope part, pivot and plane), nil if none.
export type Controller = {
	tick: (dt: number) -> (),
	stop: () -> (),
	held: () -> string,
	rope: (id: string) -> Rope?,
}

type Spec = { [string]: any }
export type Item = { part: BasePart, spec: Spec }

-- A rope you hold: its knob item, the ghost rope part on the same pivot, the pivot (world), the swing's plane
-- direction (+angle) and up, its arm (pivot to the knob's centre) and the knob's grab reach and dot seconds.
export type Rope = {
	item: Item,
	ropePart: BasePart?,
	pivot: Vector3,
	dir: Vector3,
	up: Vector3,
	arm: number,
	hint: number,
}
-- A rope you let go of, swinging on by itself while it eases back to its server-time swing.
type Return = { knob: BasePart, ropePart: BasePart?, arm: number, th: number, w: number, at: number }

-- The local player this frame.
type Me = {
	humanoid: Humanoid,
	root: BasePart,
	floor: BasePart?, -- the course part under the feet (a short ray down), if any
	normal: Vector3, -- that floor's surface normal
	grounded: boolean,
	clock: number,
	dt: number,
}

-- How the momentum drive steers: "slide" on a slide part (with downhill pull), "glide" in the air after a
-- controller handed back its speed.
type Drive = { kind: string, pull: number, cap: number, downhill: Vector3, since: number }

local function num(t: any, key: string, default: number): number
	local v = if type(t) == "table" then t[key] else nil
	return if type(v) == "number" and v == v then v else default
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v: Vector3, fallback: Vector3): Vector3
	return if v.Magnitude > 1e-4 then v.Unit else fallback
end

-- True when `p` is inside `part`'s box grown by `pad` studs on every side.
local function inBox(part: BasePart, p: Vector3, pad: number): boolean
	local q = part.CFrame:PointToObjectSpace(p)
	local half = part.Size / 2
	return math.abs(q.X) <= half.X + pad and math.abs(q.Y) <= half.Y + pad and math.abs(q.Z) <= half.Z + pad
end

local function playSound(name: string, parent: Instance)
	local s = SOUNDS[name]
	if not s then
		return
	end
	local sound = Instance.new("Sound")
	sound.SoundId = s.id
	sound.Volume = s.volume
	sound.PlaybackSpeed = s.speed
	sound.RollOffMaxDistance = 60
	local group = SoundService:FindFirstChild("SFX")
	if group and group:IsA("SoundGroup") then
		sound.SoundGroup = group
	end
	sound.Parent = parent
	sound:Play()
	Debris:AddItem(sound, 3)
end

local function decode(part: BasePart): Spec?
	local raw = part:GetAttribute(Constants.OBBY_SPEC)
	if type(raw) ~= "string" then
		return nil
	end
	local ok, value = pcall(HttpService.JSONDecode, HttpService, raw)
	return if ok and type(value) == "table" then value else nil
end

-- One cannon shot traced for the aim now: the root's path, when it hands back, where it lands and whether it ends
-- badly (in a hazard or nowhere).
type Arc = { origin: Vector3, velocity: Vector3, handT: number, hitT: number, landing: Vector3?, bad: boolean }

local function arcAt(a: Arc, t: number, g: number): Vector3
	return a.origin + a.velocity * t + Vector3.new(0, -0.5 * g * t * t, 0)
end

local function arcVelocity(a: Arc, t: number, g: number): Vector3
	return a.velocity + Vector3.new(0, -g * t, 0)
end

function ObbyMoves.start(): Controller
	local player = Players.LocalPlayer
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include

	-- the course
	local course: Instance? = nil
	local slot: any = nil
	local frame = CFrame.identity
	local specOf: { [BasePart]: Spec } = {}
	local vines: { Item } = {}
	local cannons: { Item } = {}
	local moons: { Item } = {}
	local darks: { Item } = {}
	local hazards: { BasePart } = {}

	-- shared state
	local character: Model? = nil
	local me: Me? = nil -- this frame's, for the drive step
	local jumpAt = -math.huge -- os.clock of the last jump press
	local usedJump = -math.huge
	local walkBase: number? = nil -- the WalkSpeed found before a controller first changed it
	local platformBase: boolean? = nil -- the PlatformStand found before a hold
	local drive: Drive? = nil
	local hold: string? = nil -- "vine" | "cannon" | "flight" while one owns the character
	local wasInside = false

	-- per controller
	local boost = { speed = nil :: number?, from = 0, lastOn = 0, carry = 0 }
	local vine = {
		item = nil :: Item?,
		at = 0,
		last = nil :: Item?,
		lastAt = -math.huge,
		grabs = 0,
		rope = nil :: Rope?, -- the held rope's pivot, plane and parts
		th = 0, -- its angle (radians, Vine's)
		w = 0, -- its angular speed
		from = Vector3.zero, -- the root where the grab took it
		returns = {} :: { Return }, -- ropes let go of, easing back to their own swing
		arms = {} :: ObbyVinePose.Saved, -- each shoulder's C0 (or torso attachment) before the arms went up
		beam = nil :: Beam?,
		hands = nil :: Attachment?,
	}
	local pressAt = -math.huge -- os.clock of the last fresh jump press (not a held jump's repeat)
	local requestAt = -math.huge
	local usedPress = -math.huge
	local cannon =
		{ item = nil :: Item?, at = 0, last = nil :: Item?, lastAt = -math.huge, arc = nil :: Arc?, flightT = 0 }
	local camera = { kind = nil :: Enum.CameraType?, subject = nil :: Instance? }
	local moon = { inside = false, zone = nil :: Item?, attachment = nil :: Attachment?, force = nil :: VectorForce? }
	local dark = {
		zone = nil :: Item?,
		amount = 0,
		light = ObbyMoves.DEFAULT_LIGHT,
		effect = nil :: ColorCorrectionEffect?,
		lamp = nil :: PointLight?,
	}
	local dots: { BasePart } = {}
	local dotFolder: Folder? = nil
	local hintGui: ScreenGui? = nil

	local function takeJump(after: number): boolean
		if jumpAt > after and jumpAt > usedJump then
			usedJump = jumpAt
			return true
		end
		return false
	end

	-- WalkSpeed: the first change remembers what was there, the release puts exactly that back.
	local function setWalk(h: Humanoid, speed: number)
		if walkBase == nil then
			walkBase = h.WalkSpeed
		end
		if h.WalkSpeed ~= speed then
			h.WalkSpeed = speed
		end
	end
	local function releaseWalk(h: Humanoid?)
		if walkBase ~= nil and h then
			h.WalkSpeed = walkBase
		end
		walkBase = nil
	end
	local function baseWalk(): number
		return walkBase or ObbyMoves.BASE_WALK
	end

	local function platform(h: Humanoid, on: boolean)
		if on then
			if platformBase == nil then
				platformBase = h.PlatformStand
			end
			h.PlatformStand = true
		elseif platformBase ~= nil then
			h.PlatformStand = platformBase
			platformBase = nil
		end
	end

	local function glide(velocity: Vector3, clock: number)
		local h = flat(velocity)
		drive = {
			kind = "glide",
			pull = 0,
			cap = math.max(h.Magnitude, ObbyMoves.BASE_WALK),
			downhill = Vector3.zero,
			since = clock,
		}
	end

	------------------------------------------------------------------ visuals: hint, aim line, camera

	local function showHint(on: boolean)
		if not on then
			if hintGui then
				hintGui:Destroy()
				hintGui = nil
			end
			return
		end
		if hintGui then
			return
		end
		local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then
			return
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "ObbyMovesHint"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		local label = Instance.new("TextLabel")
		label.AnchorPoint = Vector2.new(0.5, 1)
		label.Position = UDim2.new(0.5, 0, 1, -170) -- above the touch jump button's row
		label.Size = UDim2.fromOffset(200, 44) -- a 44 px tall pill (the touch-size rule, though it is not a button)
		label.BackgroundColor3 = rgb(GooPalette.Bg)
		label.BackgroundTransparency = 0.15
		label.TextColor3 = rgb(GooPalette.Text)
		label.Font = Enum.Font.GothamBold
		label.TextSize = 18
		label.Text = ObbyMoves.HINT_TEXT
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = label
		local stroke = Instance.new("UIStroke")
		stroke.Color = rgb(GooPalette.Ink)
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = label
		label.Parent = gui
		gui.Parent = playerGui
		hintGui = gui
	end

	local function clearDots()
		if dotFolder then
			dotFolder:Destroy()
			dotFolder = nil
		end
		table.clear(dots)
	end

	local function dot(i: number, size: number): BasePart
		local d = dots[i]
		if d and d.Parent then
			return d
		end
		if not dotFolder then
			local folder = Instance.new("Folder")
			folder.Name = "ObbyAimLine"
			folder.Parent = workspace.CurrentCamera or workspace
			dotFolder = folder
		end
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.one * size
		p.Material = Enum.Material.Neon -- small, so it doesn't bloom (contract §8)
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Parent = dotFolder
		dots[i] = p
		return p
	end

	local function drawArc(a: Arc, g: number)
		local color = if a.bad then DOT_BAD else DOT_OK
		local stop = if a.landing then a.hitT else a.handT
		for i = 1, ObbyMoves.DOTS do
			local d = dot(i, ObbyMoves.DOT_SIZE)
			d.Color = color
			d.CFrame = CFrame.new(arcAt(a, stop * i / (ObbyMoves.DOTS + 1), g))
		end
		local landing = dot(ObbyMoves.DOTS + 1, ObbyMoves.LANDING_DOT)
		landing.Color = color
		landing.Transparency = if a.landing then 0 else 1
		landing.CFrame = CFrame.new(a.landing or Vector3.zero)
	end

	local function holdCamera(on: boolean)
		local cam = workspace.CurrentCamera
		if not cam then
			return
		end
		if on then
			if camera.kind == nil then
				camera.kind = cam.CameraType
				camera.subject = cam.CameraSubject
			end
			cam.CameraType = Enum.CameraType.Scriptable
		elseif camera.kind ~= nil then
			cam.CameraType = camera.kind
			if camera.subject and camera.subject.Parent then
				cam.CameraSubject = camera.subject
			end
			camera.kind = nil
			camera.subject = nil
		end
	end

	------------------------------------------------------------------ ending

	-- The held rope's look: its angle on the knob and the rope part, shown `fade` (0..1) over its own swing (ObbyFx).
	local function showRope(knob: BasePart, ropePart: BasePart?, th: number?, fade: number?)
		knob:SetAttribute(Vine.HELD_ANGLE, th)
		knob:SetAttribute(Vine.HELD_FADE, fade)
		if ropePart then
			ropePart:SetAttribute(Vine.HELD_ANGLE, th)
			ropePart:SetAttribute(Vine.HELD_FADE, fade)
		end
	end

	-- Every rope let go of goes straight back to its own swing (a reset, a rebuild, leaving the obby).
	local function clearVineReturns()
		for _, r in vine.returns do
			showRope(r.knob, r.ropePart, nil, nil)
		end
		table.clear(vine.returns)
	end

	-- Arms up on the knob while you hang (ObbyVinePose), put back exactly after.
	local function armsUp(on: boolean)
		if not on then
			ObbyVinePose.lower(vine.arms)
			return
		end
		if #vine.arms > 0 or not character then
			return
		end
		vine.arms = ObbyVinePose.raise(character :: Model)
	end

	-- The stick, in the world (flat): the control module's move vector turned by the camera. Humanoid.MoveDirection
	-- reads zero while PlatformStand is on, so the rope reads the controls themselves.
	local controls: any = nil
	local function vineStick(): Vector3
		if controls == nil then
			local scripts = player and player:FindFirstChild("PlayerScripts")
			local module = scripts and scripts:FindFirstChild("PlayerModule")
			if module and module:IsA("ModuleScript") then
				local ok, pm = pcall(require, module)
				controls = if ok and type(pm) == "table" and pm.GetControls then pm:GetControls() else false
			else
				return Vector3.zero
			end
		end
		local cam = workspace.CurrentCamera
		if not controls or not cam then
			return Vector3.zero
		end
		local ok, mv = pcall(controls.GetMoveVector, controls)
		if not ok or typeof(mv) ~= "Vector3" then
			return Vector3.zero
		end
		local look = unitOr(flat(cam.CFrame.LookVector), Vector3.zero)
		local right = unitOr(flat(cam.CFrame.RightVector), Vector3.zero)
		return right * mv.X - look * mv.Z
	end

	-- A small puff of goo where a grab or a let go happens (a built-in smoke texture, gone in a second).
	local function puff(at: Vector3, color: Color3, count: number)
		local holder = Instance.new("Attachment")
		holder.Name = "ObbyVinePuff"
		holder.WorldPosition = at
		local e = Instance.new("ParticleEmitter")
		e.Texture = ObbyMoves.PUFF
		e.Color = ColorSequence.new(color)
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) })
		e.Lifetime = NumberRange.new(0.35, 0.55)
		e.Speed = NumberRange.new(4, 8)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 6
		e.Rate = 0
		e.LightEmission = 0
		e.Parent = holder
		holder.Parent = workspace.Terrain
		e:Emit(count)
		Debris:AddItem(holder, 1.2)
	end

	local function endVine(h: Humanoid?)
		local r = vine.rope
		if vine.item then
			vine.last = vine.item
			vine.lastAt = os.clock()
		end
		if r then
			-- the rope swings on from where you left it and eases back to its own swing
			table.insert(
				vine.returns,
				{ knob = r.item.part, ropePart = r.ropePart, arm = r.arm, th = vine.th, w = vine.w, at = os.clock() }
			)
		end
		vine.item = nil
		vine.rope = nil
		armsUp(false)
		if vine.beam then
			vine.beam:Destroy()
			vine.beam = nil
		end
		if vine.hands then
			vine.hands:Destroy()
			vine.hands = nil
		end
		if hold == "vine" then
			clearDots()
		end
		if h then
			platform(h, false)
		end
		showHint(false)
		if hold == "vine" then
			hold = nil
		end
	end

	local function endCannon(h: Humanoid?)
		if cannon.item then
			cannon.last = cannon.item
			cannon.lastAt = os.clock()
		end
		cannon.item = nil
		cannon.arc = nil
		if hold == "cannon" or hold == "flight" then
			armsUp(false)
		end
		if h then
			platform(h, false)
		end
		holdCamera(false)
		clearDots()
		if hold == "cannon" or hold == "flight" then
			hold = nil
		end
	end

	local function endMoon()
		if moon.force then
			moon.force:Destroy()
		end
		if moon.attachment then
			moon.attachment:Destroy()
		end
		moon.force = nil
		moon.attachment = nil
		moon.inside = false
	end

	local function endDark()
		if dark.effect then
			dark.effect:Destroy()
		end
		if dark.lamp then
			dark.lamp:Destroy()
		end
		dark.effect = nil
		dark.lamp = nil
		dark.amount = 0
	end

	-- Ends every controller and puts the character back exactly (contract §7: also on every reset).
	local function endAll()
		local h = me and me.humanoid
		if not h and character then
			h = character:FindFirstChildOfClass("Humanoid")
		end
		endVine(h)
		clearVineReturns()
		endCannon(h)
		endMoon()
		endDark()
		moon.zone = nil
		dark.zone = nil
		drive = nil
		boost.speed = nil
		releaseWalk(h)
		if h then
			platform(h, false)
		end
		hold = nil
	end

	------------------------------------------------------------------ the course

	local function scan(model: Instance)
		specOf = {}
		vines, cannons, moons, darks, hazards = {}, {}, {}, {}, {}
		local f = model:GetAttribute(Constants.OBBY_FRAME)
		frame = if typeof(f) == "CFrame" then f else CFrame.identity
		for _, d in model:GetDescendants() do
			if not d:IsA("BasePart") then
				continue
			end
			local spec = decode(d)
			if not spec then
				continue
			end
			specOf[d] = spec
			local item = { part = d, spec = spec }
			if type(spec.vine) == "table" then
				table.insert(vines, item)
			end
			if type(spec.cannon) == "table" then
				table.insert(cannons, item)
			end
			if spec.hazard == true then
				table.insert(hazards, d)
			end
			local zone = spec.zone
			if type(zone) == "table" then
				if zone.kind == "moon" then
					table.insert(moons, item)
				elseif zone.kind == "dark" then
					table.insert(darks, item)
				end
			end
		end
		params.FilterDescendantsInstances = { model }
	end

	-- Looks up workspace.Obby.Course; on a new model or a new Slot everything ends and the parts are read again.
	local function findCourse(): Instance?
		local folder = workspace:FindFirstChild(Constants.OBBY_FOLDER)
		local model = folder and folder:FindFirstChild(Constants.OBBY_COURSE)
		local s = model and model:GetAttribute("Slot")
		if model ~= course or s ~= slot then
			endAll()
			course = model
			slot = s
			if model then
				scan(model)
			else
				specOf = {}
				vines, cannons, moons, darks, hazards = {}, {}, {}, {}, {}
			end
		end
		return course
	end

	local function inHazard(p: Vector3): boolean
		for _, part in hazards do
			if part.Parent and inBox(part, p, ObbyMoves.HAZARD_PAD) then
				return true
			end
		end
		return false
	end

	------------------------------------------------------------------ boost

	local function stepBoost(m: Me)
		local spec = m.floor and specOf[m.floor]
		local b = spec and spec.boost
		if m.grounded and type(b) == "table" then
			local speed = num(b, "speed", ObbyMoves.BASE_WALK)
			boost.speed = speed
			boost.from = speed
			boost.lastOn = m.clock
			boost.carry = num(b, "carry", 0)
			return
		end
		local speed = boost.speed
		if speed == nil or m.clock - boost.lastOn < boost.carry then
			return
		end
		local base = baseWalk()
		local step = math.abs(boost.from - base) / ObbyMoves.EASE_SECONDS * m.dt
		if math.abs(speed - base) <= step then
			boost.speed = nil
		else
			boost.speed = speed + math.sign(base - speed) * step
		end
	end

	------------------------------------------------------------------ slide

	local function stepSlide(m: Me)
		local spec = m.floor and specOf[m.floor]
		local s = spec and spec.slide
		if m.grounded and type(s) == "table" then
			local n = m.normal
			local downhill = Vector3.zero
			if n.Y < ObbyMoves.FLAT_SLOPE then
				-- gravity along the surface, flattened: the way a ball would roll
				downhill = unitOr(flat(Vector3.new(0, -1, 0) + n * n.Y), Vector3.zero)
			end
			local cap = num(s, "cap", ObbyMoves.BASE_WALK * 2)
			if drive and drive.kind == "slide" then
				drive.pull = num(s, "pull", 0)
				drive.cap = cap
				drive.downhill = downhill
			else
				drive = { kind = "slide", pull = num(s, "pull", 0), cap = cap, downhill = downhill, since = m.clock }
			end
			return
		end
		local d = drive
		if not d then
			return
		end
		if not m.grounded then
			if d.kind == "slide" then
				-- off the end in a jump: keep the speed through the air
				glide(m.root.AssemblyLinearVelocity, m.clock)
			elseif m.clock - d.since > ObbyMoves.GLIDE_MAX then
				drive = nil
			end
		elseif d.kind == "slide" or m.clock - d.since > ObbyMoves.GLIDE_MIN then
			-- landed on a floor that is not a slide (brake goo, a pad): the humanoid walks normally again
			drive = nil
		end
	end

	-- Right after the control script (it calls Humanoid:Move at RenderPriority.Input): keeps the drive's speed,
	-- adds the pull, lets the stick steer and hands the humanoid that as its walk.
	local function stepDrive(dt: number)
		local d = drive
		local m = me
		if not d or not m or hold ~= nil or m.humanoid.Health <= 0 then
			return
		end
		local v = m.root.AssemblyLinearVelocity
		local h = flat(v)
		if d.kind == "slide" then
			h += d.downhill * d.pull * dt
		end
		h += flat(m.humanoid.MoveDirection) * ObbyMoves.STEER_ACCEL * dt
		if h.Magnitude > d.cap then
			h = h.Unit * d.cap
		end
		local speed = h.Magnitude
		setWalk(m.humanoid, speed)
		m.humanoid:Move(if speed > 1e-3 then h / speed else Vector3.zero, false)
		m.root.AssemblyLinearVelocity = Vector3.new(h.X, v.Y, h.Z)
	end

	------------------------------------------------------------------ vine

	-- The rope a knob hangs from, in the world: the pivot `arm` over the knob's rest centre, the swing's plane
	-- (+angle along the course for axis "x", else -z as Kit's swing) and the ghost rope part on the same pivot.
	local function ropeOf(item: Item): Rope?
		local motion = item.spec.motion
		if type(motion) ~= "table" or motion.kind ~= "swing" then
			return nil
		end
		local arm = num(motion, "arm", 0)
		local up = frame.YVector
		local function restOf(p: BasePart): Vector3
			local base = p:GetAttribute(Constants.OBBY_BASE)
			return if typeof(base) == "CFrame" then base.Position else p.Position
		end
		local pivot = restOf(item.part) + up * arm
		local ropePart: BasePart? = nil
		for p, spec in specOf do
			local m = spec.motion
			if p ~= item.part and spec.vine == nil and type(m) == "table" and m.kind == "swing" then
				if (restOf(p) + up * num(m, "arm", 0) - pivot).Magnitude < 0.05 then
					ropePart = p
					break
				end
			end
		end
		return {
			item = item,
			ropePart = ropePart,
			pivot = pivot,
			dir = if motion.axis == "x" then frame.XVector else -frame.ZVector,
			up = up,
			arm = arm,
			hint = num(item.spec.vine, "hint", Vine.HINT.medium),
		}
	end

	-- Where your root hangs on rope `r` at angle `th`, and its velocity at `w` radians/s (plus `kick` up).
	local function hangOf(r: Rope, th: number, w: number, kick: number): (Vector3, Vector3)
		local s, y = Vine.rootAt(r.arm, th)
		local vs, vy = Vine.velocityAt(r.arm, th, w)
		return r.pivot + r.dir * s + r.up * y, r.dir * vs + r.up * (vy + kick)
	end

	-- The let-go flight's first `r.hint` seconds as dots: mint when it ends on a safe floor or in another rope's
	-- reach, red when it ends in goo or nowhere (the same rules as the checks: tests/ObbyCheck vineLands).
	local function vineHint(m: Me, r: Rope, origin: Vector3, velocity: Vector3)
		local g = workspace.Gravity
		local drop = Vector3.new(0, m.humanoid.HipHeight + m.root.Size.Y / 2, 0)
		local stopT, good = ObbyMoves.ARC_SECONDS, false
		local prev = origin
		local t = 0
		while t < ObbyMoves.ARC_SECONDS do
			local nextT = t + ObbyMoves.ARC_STEP
			local p = origin + velocity * nextT + Vector3.new(0, -0.5 * g * nextT * nextT, 0)
			if inHazard(p) then
				stopT = nextT
				break
			end
			local caught = false
			for _, other in vines do
				local k = other.part
				if other ~= r.item and k.Parent then
					local q = k.Position
					if Vine.touches(p.X, p.Y, p.Z, q.X, q.Y, q.Z, num(other.spec.vine, "reach", 3)) then
						caught = true
						break
					end
				end
			end
			if caught then
				stopT, good = nextT, true
				break
			end
			local hit = workspace:Raycast(prev - drop, p - prev, params)
			if hit and (hit.Instance :: BasePart).CanCollide then
				local spec = specOf[hit.Instance :: BasePart]
				stopT, good = nextT, not (spec and spec.hazard == true)
				break
			end
			prev = p
			t = nextT
		end
		local color = if good then DOT_OK else DOT_BAD
		local shown = math.min(stopT, r.hint)
		for i = 1, ObbyMoves.VINE_DOTS do
			local d = dot(i, ObbyMoves.VINE_DOT)
			local tt = shown * i / ObbyMoves.VINE_DOTS
			d.Color = color
			d.Transparency = 0
			d.CFrame = CFrame.new(origin + velocity * tt + Vector3.new(0, -0.5 * g * tt * tt, 0))
		end
	end

	-- The rope between the knob and your hands: a Beam from the knob's centre to between the hands.
	local function vineBeam(r: Rope)
		local knob = r.item.part
		local hands = vine.hands
		if not vine.beam or not hands then
			local beam, a1 = ObbyVinePose.rope(knob)
			vine.beam = beam
			vine.hands = a1
			hands = a1
		end
		local c = character
		local grip = if c then ObbyVinePose.grip(c) else nil
		local at = hands :: Attachment
		at.WorldPosition = grip or knob.Position
	end

	-- Ropes let go of swing on by themselves and fade back to their server-time swing over RETURN.
	local function stepReturns(m: Me)
		for i = #vine.returns, 1, -1 do
			local r = vine.returns[i]
			local fade = 1 - (m.clock - r.at) / ObbyMoves.RETURN
			if fade <= 0 or not r.knob.Parent then
				showRope(r.knob, r.ropePart, nil, nil)
				table.remove(vine.returns, i)
			else
				r.th, r.w = Vine.step(r.arm, r.th, r.w, 0, m.dt)
				showRope(r.knob, r.ropePart, r.th, fade * fade * (3 - 2 * fade))
			end
		end
	end

	-- A knob within reach grabs you (in the air, or on the ground while you walk at it). True when one did.
	local function grabRope(m: Me): boolean
		if m.clock - vine.lastAt < ObbyMoves.REGRAB_ANY then
			return false
		end
		local p = m.root.Position
		local walk = flat(m.humanoid.MoveDirection)
		for _, candidate in vines do
			local knob = candidate.part
			if not knob.Parent then
				continue
			end
			if candidate == vine.last and m.clock - vine.lastAt < ObbyMoves.REGRAB_SAME then
				continue
			end
			local q = knob.Position
			if not Vine.touches(p.X, p.Y, p.Z, q.X, q.Y, q.Z, num(candidate.spec.vine, "reach", 3)) then
				continue
			end
			-- on the ground only while you walk at it (never a rope behind you on a landing pad)
			if m.grounded and walk:Dot(unitOr(flat(q - p), Vector3.zero)) < ObbyMoves.WALK_IN then
				continue
			end
			local r = ropeOf(candidate)
			if not r then
				continue
			end
			-- the rope swings to your angle and keeps CARRY of your speed along the swing, plus some of its own
			local rel = p - r.pivot
			local v = m.root.AssemblyLinearVelocity
			local ka = q - r.pivot
			local kth = math.atan2(ka:Dot(r.dir), -ka:Dot(r.up))
			local tangent = r.dir * math.cos(kth) + r.up * math.sin(kth)
			local ropeW = if r.arm > 1e-3 then knob.AssemblyLinearVelocity:Dot(tangent) / r.arm else 0
			vine.th, vine.w = Vine.grab(r.arm, rel:Dot(r.dir), rel:Dot(r.up), v:Dot(r.dir), v:Dot(r.up), ropeW)
			vine.item = candidate
			vine.rope = r
			vine.at = m.clock
			vine.from = p
			vine.grabs += 1
			-- a rope still easing back from your last let go is yours again
			for i = #vine.returns, 1, -1 do
				if vine.returns[i].knob == knob then
					table.remove(vine.returns, i)
				end
			end
			hold = "vine"
			drive = nil
			platform(m.humanoid, true)
			armsUp(true)
			playSound("squelch", m.root)
			puff(q, knob.Color, 8)
			showHint(vine.grabs <= ObbyMoves.HINT_GRABS)
			return true
		end
		return false
	end

	local function stepVine(m: Me)
		stepReturns(m)
		if vine.item == nil then
			if hold ~= nil or not grabRope(m) then
				return
			end
		end
		local r = vine.rope :: Rope
		local knob = r.item.part
		if not knob.Parent then
			endVine(m.humanoid)
			return
		end
		-- the pump: the stick along the swing's plane
		local push = math.clamp(vineStick():Dot(unitOr(flat(r.dir), Vector3.zero)), -1, 1)
		vine.th, vine.w = Vine.step(r.arm, vine.th, vine.w, push, m.dt)
		local hang, velocity = hangOf(r, vine.th, vine.w, 0)
		local k = math.clamp((m.clock - vine.at) / ObbyMoves.GRAB_EASE, 0, 1)
		local ease = k * k * (3 - 2 * k)
		showRope(knob, r.ropePart, vine.th, ease)
		if pressAt > vine.at + Vine.GRACE and pressAt > usedPress then
			usedPress = pressAt
			usedJump = math.max(usedJump, jumpAt)
			local _, release = hangOf(r, vine.th, vine.w, Vine.UP)
			endVine(m.humanoid)
			m.humanoid.Jump = false
			m.root.AssemblyLinearVelocity = release
			m.root.AssemblyAngularVelocity = Vector3.zero
			m.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
			glide(release, m.clock)
			playSound("whoom", m.root)
			puff(knob.Position, Color3.new(1, 1, 1), 6)
			return
		end
		-- the body leans with the rope (TILT of its angle), facing down the course
		local pos = vine.from:Lerp(hang, ease)
		local face = unitOr(flat(frame.XVector), Vector3.xAxis)
		local lean = CFrame.fromAxisAngle(unitOr(r.dir:Cross(r.up), Vector3.zAxis), Vine.TILT * vine.th)
		m.root.CFrame = CFrame.new(pos) * lean * CFrame.lookAt(Vector3.zero, face)
		m.root.AssemblyLinearVelocity = velocity
		m.root.AssemblyAngularVelocity = Vector3.zero
		local _, release = hangOf(r, vine.th, vine.w, Vine.UP)
		vineHint(m, r, hang, release)
		vineBeam(r)
	end

	------------------------------------------------------------------ cannon

	-- A root lying along `up` (its head that way), face to the sky.
	local function lying(at: Vector3, up: Vector3): CFrame
		local face = Vector3.yAxis - up * up.Y
		if face.Magnitude < 1e-3 then
			face = -Vector3.xAxis
		end
		face = face.Unit
		return CFrame.fromMatrix(at, face:Cross(up), up)
	end

	-- The barrel's aim now (its X axis, as ObbyFx sweeps it), its mouth and the shot's start velocity.
	local function aim(item: Item): (Vector3, Vector3, Vector3)
		local part = item.part
		local heading = unitOr(flat(part.CFrame.XVector), unitOr(flat(frame.XVector), Vector3.xAxis))
		local up = math.rad(num(item.spec.cannon, "arc", ObbyMoves.CANNON_ARC))
		local power = num(item.spec.cannon, "power", ObbyMoves.CANNON_POWER)
		local mouth = part.Position + heading * (part.Size.X / 2 + 1)
		local velocity = (heading * math.cos(up) + Vector3.yAxis * math.sin(up)) * power
		return heading, mouth, velocity
	end

	-- Traces the shot for the aim now: lands where the feet first meet a solid course part (see-through, not solid
	-- parts are passed through), hands back HAND_LIFT studs above that on the way down; bad when it passes through
	-- a hazard first or lands nowhere within ARC_SECONDS.
	local function trace(origin: Vector3, velocity: Vector3, feet: number, g: number): Arc
		local a: Arc = {
			origin = origin,
			velocity = velocity,
			handT = ObbyMoves.ARC_SECONDS,
			hitT = ObbyMoves.ARC_SECONDS,
			landing = nil,
			bad = true,
		}
		local drop = Vector3.new(0, feet, 0)
		local t = 0
		local prev = origin
		while t < ObbyMoves.ARC_SECONDS do
			local nextT = t + ObbyMoves.ARC_STEP
			local p = arcAt(a, nextT, g)
			if inHazard(p) then
				a.hitT = nextT
				a.handT = nextT
				a.landing = p
				return a
			end
			local from = prev - drop
			local dir = p - prev
			local hit: RaycastResult? = nil
			-- (not on the way out of the barrel: the feet start below the mouth, by the cannon's own deck)
			for _ = 1, if nextT > ObbyMoves.LAUNCH_CLEAR then 4 else 0 do -- pass through at most a few see-through, not solid parts (an open gate, a flipped tile)
				local r = workspace:Raycast(from, dir, params)
				if not r or (r.Instance :: BasePart).CanCollide then
					hit = r
					break
				end
				local used = (r.Position - from).Magnitude + 0.05
				local length = dir.Magnitude
				if used >= length then
					break
				end
				from = r.Position + dir.Unit * 0.05
				dir = dir.Unit * (length - used)
			end
			if hit then
				local part = hit.Instance :: BasePart
				local share = (hit.Position - (prev - drop)).Magnitude / math.max((p - prev).Magnitude, 1e-4)
				a.hitT = t + ObbyMoves.ARC_STEP * math.clamp(share, 0, 1)
				a.landing = hit.Position
				a.bad = specOf[part] ~= nil and specOf[part].hazard == true
				-- the later time the feet are HAND_LIFT above the landing (on the way down), else the segment start
				local vy = velocity.Y
				local rise = origin.Y - feet - (hit.Position.Y + ObbyMoves.HAND_LIFT)
				local disc = vy * vy + 2 * g * rise
				local down = if disc >= 0 and g > 0 then (vy + math.sqrt(disc)) / g else -1
				a.handT = if down >= 0 and down <= a.hitT then down else t
				return a
			end
			prev = p
			t = nextT
		end
		return a
	end

	local function feetDrop(m: Me): number
		return m.humanoid.HipHeight + m.root.Size.Y / 2
	end

	local function stepCannon(m: Me)
		local g = workspace.Gravity
		if hold == "flight" then
			local a = cannon.arc :: Arc
			cannon.flightT += m.dt
			local t = math.min(cannon.flightT, a.handT)
			local p = arcAt(a, t, g)
			local v = arcVelocity(a, t, g)
			if inHazard(p) then
				endCannon(m.humanoid)
				ObbyFall.reset("hazard")
				return
			end
			if cannon.flightT >= a.handT then
				endCannon(m.humanoid)
				m.root.CFrame = CFrame.lookAt(p, p + unitOr(flat(v), flat(m.root.CFrame.LookVector)))
				m.root.AssemblyLinearVelocity = v
				m.humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
				glide(v, m.clock)
				return
			end
			m.root.CFrame = lying(p, unitOr(v, Vector3.yAxis)) -- head first, arms up
			m.root.AssemblyLinearVelocity = v
			m.root.AssemblyAngularVelocity = Vector3.zero
			return
		end
		local item = cannon.item
		if item == nil then
			if hold ~= nil then
				return
			end
			for _, candidate in cannons do
				if not candidate.part.Parent then
					continue
				end
				if candidate == cannon.last and m.clock - cannon.lastAt < ObbyMoves.RELOAD then
					continue
				end
				if inBox(candidate.part, m.root.Position, ObbyMoves.ENTER_MARGIN) then
					item = candidate
					cannon.item = candidate
					cannon.at = m.clock
					hold = "cannon"
					drive = nil
					platform(m.humanoid, true)
					holdCamera(true)
					armsUp(true)
					playSound("load", m.root)
					break
				end
			end
			if item == nil then
				return
			end
		end
		local part = (item :: Item).part
		if not part.Parent then
			endCannon(m.humanoid)
			return
		end
		local heading, mouth, velocity = aim(item :: Item)
		local a = trace(mouth, velocity, feetDrop(m), g)
		local centre = part.Position
		local tilt = math.rad(ObbyMoves.SEAT_TILT)
		local axis = heading * math.cos(tilt) + Vector3.yAxis * math.sin(tilt)
		m.root.CFrame = lying(centre + axis * (ObbyMoves.SEAT_MOUTH - ObbyMoves.SEAT_OUT), axis)
		m.root.AssemblyLinearVelocity = Vector3.zero
		m.root.AssemblyAngularVelocity = Vector3.zero
		local cam = workspace.CurrentCamera
		if cam then
			local eye = centre - heading * ObbyMoves.CAM_BACK + Vector3.new(0, ObbyMoves.CAM_UP, 0)
			cam.CFrame = CFrame.lookAt(eye, centre + heading * ObbyMoves.CAM_AHEAD)
		end
		if takeJump(cannon.at + ObbyMoves.JUMP_GRACE) then
			-- fire: the camera follows you again, the dots go, the root rides the arc traced now
			holdCamera(false)
			clearDots()
			cannon.arc = a
			cannon.flightT = 0
			hold = "flight"
			m.humanoid.Jump = false
			m.root.CFrame = lying(mouth, velocity.Unit)
			playSound("fire", m.root)
			return
		end
		drawArc(a, g)
	end

	------------------------------------------------------------------ moon

	-- The zone of `list` the body (feet to head) is in: `current` (the one it was in) while it stays within
	-- ZONE_PAD + ZONE_HOLD, else the first within ZONE_PAD.
	local function zoneAt(list: { Item }, m: Me, current: Item?): Item?
		local a = m.root.Position - Vector3.new(0, feetDrop(m), 0)
		local b = m.root.Position + Vector3.new(0, ObbyMoves.HEAD_UP, 0)
		local function isIn(item: Item, pad: number): boolean
			local part = item.part
			-- a moon bubble is the dome ObbyParts draws (a Sphere mesh: the ellipsoid in the box), even before its
			-- mesh has streamed in
			local zone = item.spec.zone
			local shape = if zone and zone.kind == "moon" then "ellipsoid" else ObbyZone.shapeOf(part)
			return part.Parent ~= nil and ObbyZone.touches(part.CFrame, part.Size, shape, a, b, pad)
		end
		if current and table.find(list, current) and isIn(current, ObbyMoves.ZONE_PAD + ObbyMoves.ZONE_HOLD) then
			return current
		end
		for _, item in list do
			if isIn(item, ObbyMoves.ZONE_PAD) then
				return item
			end
		end
		return nil
	end

	local function stepMoon(m: Me)
		local zone = zoneAt(moons, m, moon.zone)
		moon.zone = zone
		if not zone then
			if moon.inside then
				playSound("whoom", m.root)
				endMoon()
			end
			return
		end
		if not moon.inside then
			moon.inside = true
			playSound("whoom", m.root)
		end
		local force = moon.force
		if not force or force.Parent == nil or moon.attachment == nil or moon.attachment.Parent ~= m.root then
			endMoon()
			moon.inside = true
			local attachment = Instance.new("Attachment")
			attachment.Name = ObbyMoves.MOON_NAME
			attachment.Parent = m.root
			local f = Instance.new("VectorForce")
			f.Name = ObbyMoves.MOON_NAME
			f.Attachment0 = attachment
			f.RelativeTo = Enum.ActuatorRelativeTo.World
			f.ApplyAtCenterOfMass = true
			f.Parent = m.root
			moon.attachment = attachment
			moon.force = f
			force = f
		end
		local gravity = math.clamp(num(zone.spec.zone, "gravity", 1), 0, 1);
		(force :: VectorForce).Force = Vector3.new(0, m.root.AssemblyMass * workspace.Gravity * (1 - gravity), 0)
	end

	------------------------------------------------------------------ dark

	local function stepDark(m: Me)
		local zone = zoneAt(darks, m, dark.zone)
		dark.zone = zone
		if zone then
			dark.light = num(zone.spec.zone, "light", ObbyMoves.DEFAULT_LIGHT)
		end
		local target = if zone then 1 else 0
		local step = m.dt / ObbyMoves.DARK_SECONDS
		if math.abs(target - dark.amount) <= step then
			dark.amount = target
		else
			dark.amount += math.sign(target - dark.amount) * step
		end
		if dark.amount <= 0 then
			endDark()
			return
		end
		local effect = dark.effect
		if not effect or effect.Parent ~= Lighting then
			local cc = Instance.new("ColorCorrectionEffect")
			cc.Name = ObbyMoves.DARK_NAME
			cc.Parent = Lighting
			dark.effect = cc
			effect = cc
		end
		local lamp = dark.lamp
		if not lamp or lamp.Parent ~= m.root then
			if lamp then
				lamp:Destroy()
			end
			local light = Instance.new("PointLight")
			light.Name = ObbyMoves.LIGHT_NAME
			light.Color = ObbyMoves.LIGHT_COLOR
			light.Shadows = false
			light.Parent = m.root
			dark.lamp = light
			lamp = light
		end
		local k = dark.amount * dark.amount * (3 - 2 * dark.amount) -- smoothstep, so the fade eases in and out
		local look = ObbyMoves.DARK_LOOK
		local cc = effect :: ColorCorrectionEffect
		cc.TintColor = Color3.new(1, 1, 1):Lerp(look.TintColor, k)
		cc.Brightness = look.Brightness * k
		cc.Contrast = look.Contrast * k
		cc.Saturation = look.Saturation * k
		local pl = lamp :: PointLight
		pl.Range = dark.light
		pl.Brightness = ObbyMoves.LIGHT_BRIGHTNESS * k
	end

	------------------------------------------------------------------ the frame

	local function localMe(dt: number): Me?
		local char = player and player.Character
		if char ~= character then
			endAll()
			character = char
		end
		if not char then
			return nil
		end
		local humanoid = char:FindFirstChildOfClass("Humanoid")
		local root = char:FindFirstChild("HumanoidRootPart")
		if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
			return nil
		end
		local floor: BasePart? = nil
		local normal = Vector3.yAxis
		local reach = humanoid.HipHeight + root.Size.Y / 2 + ObbyMoves.FLOOR_EXTRA
		local hit = workspace:Raycast(root.Position, Vector3.new(0, -reach, 0), params)
		if hit and hit.Instance:IsA("BasePart") then
			floor = hit.Instance
			normal = hit.Normal
		end
		return {
			humanoid = humanoid,
			root = root,
			floor = floor,
			normal = normal,
			grounded = humanoid.FloorMaterial ~= Enum.Material.Air,
			clock = os.clock(),
			dt = dt,
		}
	end

	local function tick(dt: number)
		if not ObbyLook.isInside() then
			if wasInside then
				wasInside = false
				endAll()
			end
			me = nil
			return
		end
		wasInside = true
		if not findCourse() then
			me = nil
			return
		end
		local m = localMe(dt)
		me = m
		if not m then
			return
		end
		stepCannon(m)
		stepVine(m)
		if hold == nil then
			stepSlide(m)
		end
		stepBoost(m)
		stepMoon(m)
		stepDark(m)
		-- WalkSpeed: the drive sets it in its own step; else the boost's, else exactly what was there
		if drive == nil or hold ~= nil then
			if boost.speed then
				setWalk(m.humanoid, boost.speed :: number)
			else
				releaseWalk(m.humanoid)
			end
		end
	end

	local jumpConnection = UserInputService.JumpRequest:Connect(function()
		local now = os.clock()
		-- a held jump repeats its request: only one after a gap is a fresh press (the vine lets go on those)
		if now - requestAt > ObbyMoves.PRESS_GAP then
			pressAt = now
		end
		requestAt = now
		jumpAt = now
	end)
	local removeReset = ObbyFall.onReset(function()
		endAll()
	end)
	local DRIVE_STEP = "ObbyMovesDrive"
	RunService:BindToRenderStep(DRIVE_STEP, Enum.RenderPriority.Input.Value + 1, stepDrive)

	local function stop()
		endAll()
		jumpConnection:Disconnect()
		removeReset()
		RunService:UnbindFromRenderStep(DRIVE_STEP)
		course = nil
		slot = nil
		me = nil
	end

	local function held(): string
		local item = vine.item
		local id = if item then item.part:GetAttribute(Constants.OBBY_ID) else nil
		return if type(id) == "string" then id else ""
	end

	local function rope(id: string): Rope?
		for _, item in vines do
			if item.part:GetAttribute(Constants.OBBY_ID) == id then
				return ropeOf(item)
			end
		end
		return nil
	end

	return { tick = tick, stop = stop, held = held, rope = rope }
end

return ObbyMoves
