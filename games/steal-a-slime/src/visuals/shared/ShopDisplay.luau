--!strict
--[[
	ShopDisplay (pure, FEATURES.ExclusiveShop, contract/exclusive-shop.md §7)

	Where the featured seats float in the Exclusive Shop's jar at a server time `t` (seconds), so every client shows
	the same pose. The client (visuals/client/ShopDisplayFx) puts them into the world with the stand's pivot. No Roblox
	APIs.

	Stand frame: the ExclusiveShopStand's own frame (Roblox axes, origin on the ground, front -Z, WorldLayout.jarPoint).

	  COUNT          the display spots in the jar (WorldLayout.EXCLUSIVE_JAR.displays)
	  seats(f)       the seat id on each spot: the first COUNT featured seats, in order
	  phase(i)       spot i's phase (radians): the spots a third of a cycle apart
	  angle(i, t)    spot i's yaw (radians, 0..2pi): Config.EXCLUSIVE_SHOP.displayRpm turns a minute, positive about +Y
	  lift(i, t)     spot i's height over its pedestal, 0..displayBob, one cycle every displayBobSeconds
	  spot(i)        spot i's pedestal top (the seat's bottom at rest) in the stand frame
	  pose(i, t)     spot i's seat bottom and yaw at t
	  scale(size)    the factor that makes a seat of size `size` (studs) WorldLayout's displayWidth across
]]

local Config = if script then require(script.Parent.Parent.Shared.Config) else require("../../shared/Config")
local WorldLayout = if script then require(script.Parent.WorldLayout) else require("./WorldLayout")

export type Pose = { x: number, y: number, z: number, yaw: number }

local ShopDisplay = {}

local TAU = 2 * math.pi
local LAYOUT = WorldLayout.EXCLUSIVE_JAR
local SHOP = Config.EXCLUSIVE_SHOP

ShopDisplay.COUNT = #LAYOUT.displays

function ShopDisplay.seats(featured: { string }): { string }
	local out = {}
	for i = 1, math.min(ShopDisplay.COUNT, #featured) do
		out[i] = featured[i]
	end
	return out
end

function ShopDisplay.phase(i: number): number
	return ((i - 1) * TAU / ShopDisplay.COUNT) % TAU
end

function ShopDisplay.angle(i: number, t: number): number
	return (TAU * SHOP.displayRpm / 60 * t + ShopDisplay.phase(i)) % TAU
end

function ShopDisplay.lift(i: number, t: number): number
	return SHOP.displayBob * (0.5 + 0.5 * math.sin(TAU * t / SHOP.displayBobSeconds + ShopDisplay.phase(i)))
end

function ShopDisplay.spot(i: number): { number }
	return WorldLayout.jarPoint(LAYOUT.displays[i])
end

function ShopDisplay.pose(i: number, t: number): Pose
	local p = ShopDisplay.spot(i)
	return { x = p[1], y = p[2] + ShopDisplay.lift(i, t), z = p[3], yaw = ShopDisplay.angle(i, t) }
end

function ShopDisplay.scale(size: { number }): number
	local widest = math.max(size[1], size[3])
	if not (widest > 0) then
		return 1
	end
	return LAYOUT.displayWidth * LAYOUT.scale / widest
end

return table.freeze(ShopDisplay)
