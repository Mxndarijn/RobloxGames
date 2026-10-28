--!strict
--[[
	CarouselRide (pure, FEATURES.ExclusiveShop, contract/exclusive-shop.md §7)

	How the Exclusive Shop carousel moves at a server time `t` (seconds), so every client shows the same turn. The
	client (visuals/client/CarouselFx) turns the spin half and seats the riders with it. No Roblox APIs.

	Spin frame: the spin mesh slot's own frame at the stand's scale (Roblox axes, kit (x, y, z) -> (x, z, -y)), with its
	origin at the spin mesh's bottom centre, on the spin axis. A pose is in that frame; rotations about Y commute, so
	the client puts a pose into the world with the slot's unturned bottom CFrame.

	  angle(t)        the turn (radians, 0..2pi): Config.EXCLUSIVE_SHOP.spinRpm, positive about +Y
	  riderSeats(f)   the seat id on each of the 8 poles: the featured seats in order, each twice, the two copies of a
	                  seat on opposite poles
	  phase(i)        rider i's bob phase (radians): neighbours 135 degrees apart, opposite riders half a cycle apart
	  bob(i, t)       rider i's height offset, within +-riderBob, one cycle every riderBobSeconds
	  spot(i)         rider i's saddle top in the spin frame, before the turn
	  pose(i, t)      rider i's position (its bottom) and yaw at t: the turned saddle top plus the bob, local -Z
	                  facing along the turn
	  riderScale(s)   the factor that makes a rider of size s (native studs) WorldLayout's riderWidth across
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

export type Pose = { x: number, y: number, z: number, yaw: number }

local CarouselRide = {}

local TAU = 2 * math.pi
local LAYOUT = WorldLayout.EXCLUSIVE_CAROUSEL
local SHOP = Config.EXCLUSIVE_SHOP

CarouselRide.RIDERS = #LAYOUT.riders
CarouselRide.PHASE_STEP = 0.75 * math.pi -- bob phase between neighbouring riders

function CarouselRide.angle(t: number): number
	return (TAU * SHOP.spinRpm / 60 * t) % TAU
end

function CarouselRide.riderSeats(featured: { string }): { string }
	local out = {}
	if #featured == 0 then
		return out
	end
	for i = 1, CarouselRide.RIDERS do
		out[i] = featured[(i - 1) % #featured + 1]
	end
	return out
end

function CarouselRide.phase(i: number): number
	return ((i - 1) * CarouselRide.PHASE_STEP) % TAU
end

function CarouselRide.bob(i: number, t: number): number
	return SHOP.riderBob * math.sin(TAU * t / SHOP.riderBobSeconds + CarouselRide.phase(i))
end

function CarouselRide.spot(i: number): { number }
	local p = LAYOUT.riders[i]
	local k = LAYOUT.scale
	return { p[1] * k, p[3] * k, -p[2] * k }
end

function CarouselRide.pose(i: number, t: number): Pose
	local p = CarouselRide.spot(i)
	local a = CarouselRide.angle(t)
	local c, s = math.cos(a), math.sin(a)
	-- The turn about +Y (Roblox CFrame.Angles(0, a, 0)); its direction of travel at the turned point is (z, -x).
	local x, z = p[1] * c + p[3] * s, -p[1] * s + p[3] * c
	return { x = x, y = p[2] + CarouselRide.bob(i, t), z = z, yaw = math.atan2(-z, x) }
end

function CarouselRide.riderScale(size: { number }): number
	local widest = math.max(size[1], size[3])
	if not (widest > 0) then
		return 1
	end
	return LAYOUT.riderWidth / widest
end

return table.freeze(CarouselRide)
