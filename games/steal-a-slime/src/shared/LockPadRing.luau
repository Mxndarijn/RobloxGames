--!strict
--[[
	LockPadRing (pure)

	What the lock pad ring round a plot's LockButton shows (CONTRACT.md §8.5) and its looks, for the server's
	LockPadView and the clients' charge sweep (visuals LockMotion). `ring` says how many segments are lit and in
	which mode:
	  ready   the owner can lock: the whole ring (green);
	  charge  the owner is standing on it: the light sweeps round over STAND_SECONDS;
	  locked  the plot is locked: the lit share is the share of the lock still to run;
	  idle    nobody can use it (a free plot): none lit.
	The server draws every mode but the charge (it passes no `since`, so the ring stays green); each client paints
	the charge on the same parts from the plot's LockPadSince, every frame, so it fills smoothly.

	LOOKS are { rgb, material (Enum.Material name), transparency }; REST names the look of the unlit segments per
	mode (default "dim").
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local RingPad = if Lib then require(Lib.pad.RingPad) else require("../../../../shared/luau/src/pad/RingPad")

export type Mode = "idle" | "charge" | "locked" | "ready"
export type Ring = { mode: Mode, lit: number }
export type Look = { rgb: { number }, material: string, transparency: number }

local PAD = Config.LOCK_PAD

local LockPadRing = {}

local function look(r: number, g: number, b: number, material: string): Look
	return table.freeze({ rgb = table.freeze({ r, g, b }), material = material, transparency = 0 })
end

-- Lit segments wear the mode's look, the rest REST[mode]: while charging the rest stays green (ready), while locked
-- the run-down part is dark red (lockedRest), so a locked pad is red all round.
LockPadRing.LOOKS = table.freeze({
	lockedRest = look(110, 28, 34, "SmoothPlastic"),
	dim = look(31, 111, 120, "SmoothPlastic"),
	charge = look(225, 255, 235, "Neon"),
	locked = look(229, 72, 77, "Neon"),
	ready = look(40, 150, 25, "Neon"),
} :: { [string]: Look })
LockPadRing.REST = table.freeze({ charge = "ready", locked = "lockedRest" } :: { [string]: string })

export type PartLook = { color: Color3, material: Enum.Material, transparency: number }

-- LOOKS as part properties (Color3, Enum.Material): RingPadView's looks. Builds with the Roblox API, so call it at
-- run time, not at load.
function LockPadRing.partLooks(): { [string]: PartLook }
	local out: { [string]: PartLook } = {}
	for name, l in LockPadRing.LOOKS do
		out[name] = {
			color = Color3.fromRGB(l.rgb[1], l.rgb[2], l.rgb[3]),
			material = (Enum.Material :: any)[l.material],
			transparency = l.transparency,
		}
	end
	return out
end

--[[
	What the ring shows for a plot: `owned` = the plot has an owner, `lockUntil` / `lockStartedAt` of their current
	lock, `since` = when the owner stepped onto the pad (nil = off it, or the server's own draw).
]]
function LockPadRing.ring(owned: boolean, now: number, lockUntil: number, lockStartedAt: number, since: number?): Ring
	if not owned then
		return { mode = "idle", lit = 0 }
	end
	local n = PAD.SEGMENTS
	if now < lockUntil then
		return { mode = "locked", lit = RingPad.countdown(n, lockStartedAt, lockUntil, now) }
	end
	if since ~= nil then
		return { mode = "charge", lit = RingPad.charge(n, since, now, PAD.STAND_SECONDS) }
	end
	return { mode = "ready", lit = n }
end

return table.freeze(LockPadRing)
