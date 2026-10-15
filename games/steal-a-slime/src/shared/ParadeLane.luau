--!strict
--[[
	ParadeLane (pure, FEATURES.Parade, sketch, default off)

	Wild slimes leave the fountain slide, hop onto the goo-parade lane (#25:
	centreline r 68, 8 x 45° = 7 parade_lane_arc45 + 1 parade_lane_gate) and
	walk to the despawn gate. Lane position follows time left: the arc still
	to walk to the gate is the share of lifetime still left, so a slime
	reaches the gate as it expires and drains there. Spawn cadence, cap and
	lifetime don't change (SPAWN_INTERVAL, MAX_WILD_SLIMES, WILD_LIFETIME /
	BOSS_LIFETIME).

	Angles use the wild slime convention (World.Wild.angle, WorldView:
	offset = (cos a, 0, sin a) * radius around the fountain centre).
	  GATE_ANGLE = pi/2 = +Z. The kit scene (_parade_lane_scene.py) puts the
	  gate at kit -90°; kit (x, y) -> Roblox (x, -y) makes that +Z, the slide
	  exit side, next to the goo drain (WorldLayout GooDrain at z 52).
	  Riders go kit counter-clockwise, which is decreasing Roblox angle: they
	  enter at the gate's far edge (GATE_ANGLE - GATE_HALF_WIDTH), walk the
	  seven arcs (SWEEP = 2pi - GATE_HALF_WIDTH) and stop at the gate centre,
	  where the countdown ring sits.

	The ring warning is the despawn telegraph: the last
	Config.DESPAWN_TELEGRAPH_SECONDS (5) of a 75 s lifetime cover the last
	~23° of the lane, i.e. the slime is at the gate. No extra HUD.

	No Roblox APIs at load time.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local DespawnTelegraph = if script then require(script.Parent.DespawnTelegraph) else require("./DespawnTelegraph")

local ParadeLane = {}

ParadeLane.LANE_RADIUS = 68 -- FOUNTAIN_SIZES goo-parade centreline
ParadeLane.GATE_ANGLE = math.pi / 2 -- +Z, see header
ParadeLane.GATE_HALF_WIDTH = math.pi / 8 -- the gate piece spans 45°
ParadeLane.SWEEP = math.pi * 2 - ParadeLane.GATE_HALF_WIDTH -- entry edge round to the gate centre
ParadeLane.HOP_SECONDS = 2.4 -- = WorldView.DROP_SECONDS: wait at the entry while the slide ride lands
ParadeLane.WARN_SECONDS = Config.DESPAWN_TELEGRAPH_SECONDS -- ring warn = despawn telegraph window

function ParadeLane.enabled(features: { [string]: boolean }?): boolean
	local f = features or Config.FEATURES
	return f.Parade == true
end

-- Share of the lane still to walk: 1 while hopping on, 0 at expiresAt.
function ParadeLane.remaining(spawnedAt: number, expiresAt: number, now: number): number
	local walk = expiresAt - spawnedAt - ParadeLane.HOP_SECONDS
	if walk <= 0 then
		return if now >= expiresAt then 0 else 1
	end
	return math.clamp((expiresAt - now) / walk, 0, 1)
end

-- Wild angle for a remaining share (1 = entry, 0 = gate centre), in [0, 2pi).
function ParadeLane.angleAt(remaining: number): number
	local a = ParadeLane.GATE_ANGLE + math.clamp(remaining, 0, 1) * ParadeLane.SWEEP
	return a % (math.pi * 2)
end

-- Lane angle / radius of a wild slime at `now`.
function ParadeLane.spot(spawnedAt: number, expiresAt: number, now: number): (number, number)
	return ParadeLane.angleAt(ParadeLane.remaining(spawnedAt, expiresAt, now)), ParadeLane.LANE_RADIUS
end

-- World X, Z offset from the fountain centre.
function ParadeLane.positionOnLane(spawnedAt: number, expiresAt: number, now: number): (number, number)
	local angle, radius = ParadeLane.spot(spawnedAt, expiresAt, now)
	return math.cos(angle) * radius, math.sin(angle) * radius
end

-- Arc (radians) still to walk to the gate centre.
function ParadeLane.arcToGate(spawnedAt: number, expiresAt: number, now: number): number
	return ParadeLane.remaining(spawnedAt, expiresAt, now) * ParadeLane.SWEEP
end

function ParadeLane.inWarnWindow(now: number, expiresAt: number, warnSeconds: number?): boolean
	return DespawnTelegraph.inWarnWindow(now, expiresAt, warnSeconds or ParadeLane.WARN_SECONDS)
end

-- Countdown billboard text: "leaving! 3" on the parade, else just "3".
function ParadeLane.warnText(seconds: number, enabled: boolean): string
	return if enabled then `leaving! {seconds}` else tostring(seconds)
end

-- Puts an uncarried, undropped wild on the lane (Spawner). Others are left alone.
function ParadeLane.place(
	wild: { angle: number, radius: number, position: any?, spawnedAt: number, expiresAt: number },
	now: number
)
	if wild.position ~= nil then
		return
	end
	wild.angle, wild.radius = ParadeLane.spot(wild.spawnedAt, wild.expiresAt, now)
end

return ParadeLane
