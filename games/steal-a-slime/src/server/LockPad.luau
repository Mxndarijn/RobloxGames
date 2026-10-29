--!strict
--[[
	LockPad (pure)

	The lock pad round each plot's LockButton (CONTRACT.md §8.5): a shared RingPad on the floor (Config.LOCK_PAD.STYLE,
	lit in SEGMENTS steps). The owner standing in it for STAND_SECONDS starts the same Lock action as the LockPrompt.
	Reads / writes session.lockPadSince (when the owner stepped on). What the ring shows: shared/LockPadRing.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local World = if script then require(script.Parent.World) else require("./World")
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local RingPad = if Lib then require(Lib.pad.RingPad) else require("../../../../shared/luau/src/pad/RingPad")

local PAD = Config.LOCK_PAD

local LockPad = {}

-- The ring's shape, from Config.LOCK_PAD.
LockPad.SHAPE = RingPad.shape({
	style = PAD.STYLE,
	segments = PAD.SEGMENTS,
	curve = PAD.CURVE,
	radius = PAD.RADIUS,
	width = PAD.WIDTH,
	thickness = PAD.THICKNESS,
	lift = PAD.LIFT,
	gap = PAD.GAP,
	reach = PAD.REACH,
	height = PAD.HEIGHT,
})

-- True when a root part `dx`, `dz` studs (flat) from the LockButton's centre and `dy` studs above the floor stands on the pad.
function LockPad.inside(dx: number, dy: number, dz: number): boolean
	return RingPad.inside(LockPad.SHAPE, dx, dy, dz)
end

--[[
	One tick for the owner: `onPad` = standing on their own pad, `locked` = their plot is locked. Returns true when they
	have stood on it for STAND_SECONDS and the caller should run the Lock action. Stepping off, or a running lock, starts
	the count again from zero.
]]
function LockPad.step(session: World.Session, onPad: boolean, locked: boolean, now: number): boolean
	local fired, since = RingPad.hold(session.lockPadSince, onPad, locked, now, PAD.STAND_SECONDS)
	session.lockPadSince = since
	return fired
end

return LockPad
