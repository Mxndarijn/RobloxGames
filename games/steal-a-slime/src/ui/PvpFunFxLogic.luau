--!strict
--[[
	PvpFunFxLogic (pure, CONTRACT.md §26.8): the numbers behind the Fun item effects in ui/PvpFunFx.

	  PvpFunFxLogic.FUN_IDS / isFun(itemId)          the Fun item ids (PvpEffects hands their events to PvpFunFx)
	  PvpFunFxLogic.useAnim(effect)                  the user's ui/PvpAnim clip for a use Effect (nil = not a use)
	  PvpFunFxLogic.slimeSquash(combo)               proxy keys: squash flat, wobble, spring, excited bounce
	  PvpFunFxLogic.pancake(combo) / spring(combo)   proxy keys: a player squashed flat, then springing back
	  PvpFunFxLogic.float(lift, seconds, land)       proxy keys: a bubbled slime floats up, drifts, lands
	  PvpFunFxLogic.hop(height, hops)                proxy keys: cheer hops / a pad bounce
	  PvpFunFxLogic.seconds(keys)                    how long a key list plays
	  PvpFunFxLogic.axisScale(axes, scale)           a part's size factors when its proxy is scaled
	  PvpFunFxLogic.ballistic(from, to, t, g)        launch velocity of a lob that lands at `to` after `t` s
	  PvpFunFxLogic.hatPath(seed, start, hops, step) the hops of a missed hat-slime (deterministic)
	  PvpFunFxLogic.queue(max)                       bounded effect list: pushing past `max` evicts the oldest
	  PvpFunFxLogic.count(n, low)                    particle counts at low graphics quality
	A key is { seconds, scale = { x, y, z }, offset = { x, y, z }, style, dir }: the proxy tweens from the previous
	key's pose to this one over `seconds`. Every list ends at scale 1 (offset 0, except a float that ends where it
	landed), so nothing stays deformed.
	No Roblox API: Lune tests it.
]]

local PvpFunFxLogic = {}

export type V3 = { number }
export type Key = { seconds: number, scale: V3, offset: V3, style: string, dir: string }
export type Vec = { X: number, Y: number, Z: number }

PvpFunFxLogic.FUN_IDS = table.freeze({
	FunConfetti = true,
	FunBalloon = true,
	FunBubbles = true,
	FunBouncePad = true,
	FunSqueaky = true,
	FunHatLauncher = true,
	FunDanceBomb = true,
	FunFireworks = true,
})

PvpFunFxLogic.CONFETTI_COLORS = table.freeze({
	{ 1, 0.3, 0.4 },
	{ 1, 0.85, 0.2 },
	{ 0.3, 0.8, 1 },
	{ 0.5, 1, 0.4 },
	{ 0.8, 0.4, 1 },
	{ 1, 0.55, 0.15 },
})
PvpFunFxLogic.DISCO_COLORS = table.freeze({ { 1, 0.25, 0.6 }, { 0.3, 0.6, 1 }, { 1, 0.9, 0.2 }, { 0.4, 1, 0.5 } })
PvpFunFxLogic.GOO = table.freeze({ 0.35, 0.9, 0.3 })
PvpFunFxLogic.BUBBLE = table.freeze({ 0.7, 0.9, 1 })

-- The user's pose for each use Effect (ui/PvpAnim clip names). Effects on others (Paint, Dance, Boing...) have none.
local USE_ANIM: { [string]: string } = {
	Confetti = "pop",
	Balloon = "throw",
	Bubbles = "blow",
	Squash = "bonk",
	Hat = "blast",
	Disco = "throw",
	Firework = "throw",
}

function PvpFunFxLogic.isFun(itemId: any): boolean
	return type(itemId) == "string" and PvpFunFxLogic.FUN_IDS[itemId] == true
end

function PvpFunFxLogic.useAnim(effect: any): string?
	return if type(effect) == "string" then USE_ANIM[effect] else nil
end

function PvpFunFxLogic.count(n: number, low: boolean): number
	return math.max(1, if low then math.floor(n / 2) else n)
end

local REST: V3 = table.freeze({ 1, 1, 1 })
local ZERO: V3 = table.freeze({ 0, 0, 0 })

local function key(seconds: number, scale: V3, offset: V3?, style: string?, dir: string?): Key
	return { seconds = seconds, scale = scale, offset = offset or ZERO, style = style or "Quad", dir = dir or "Out" }
end

-- Flatter is wider: the side scale that keeps the volume roughly the same.
local function flat(sy: number, cap: number): V3
	local side = math.min(1 / math.sqrt(sy), cap)
	return { side, sy, side }
end

-- A slime bonked by the Squeaky Hammer: squash flat, wobble, spring up and an excited bounce back to rest.
function PvpFunFxLogic.slimeSquash(combo: boolean): { Key }
	local sy = if combo then 0.14 else 0.3
	return {
		key(0.07, flat(sy, if combo then 2.4 else 1.9)),
		key(0.22, flat(sy * 1.1, if combo then 2.3 else 1.8), nil, "Linear"),
		key(0.11, flat(0.55, 1.5), nil, "Sine", "InOut"),
		key(0.11, flat(sy * 1.3, 1.8), nil, "Sine", "InOut"),
		key(0.14, { 0.8, 1.4, 0.8 }, { 0, 0.5, 0 }, "Back"),
		key(0.17, { 0.92, 1.12, 0.92 }, { 0, if combo then 3 else 2, 0 }, "Quad", "Out"),
		key(0.15, { 1.15, 0.85, 1.15 }, ZERO, "Quad", "In"),
		key(0.13, REST, ZERO, "Back"),
	}
end

-- A player squashed flat like a pancake (the hold until the spring is the proxy simply staying there).
function PvpFunFxLogic.pancake(combo: boolean): { Key }
	return { key(0.06, flat(if combo then 0.07 else 0.12, if combo then 2.2 else 1.8)) }
end

-- ...and springing back up with a BOING.
function PvpFunFxLogic.spring(combo: boolean): { Key }
	return {
		key(0.12, { 0.8, if combo then 1.6 else 1.4, 0.8 }, { 0, 0.6, 0 }, "Back"),
		key(0.16, REST, ZERO, "Quad", "Out"),
	}
end

-- A bubbled wild slime: floats up `lift` studs, drifts to above `land` (proxy-space x, z), drops and squishes.
function PvpFunFxLogic.float(lift: number, seconds: number, land: { number }): { Key }
	local rise, fall, squish = 0.55, 0.4, 0.25
	local drift = math.max(0.2, seconds - rise - fall - squish)
	local x, z = land[1] or 0, land[2] or 0
	return {
		key(rise, { 1.05, 0.95, 1.05 }, { x * 0.2, lift, z * 0.2 }, "Sine", "Out"),
		key(drift, REST, { x, lift + 1, z }, "Sine", "InOut"),
		key(fall, { 0.9, 1.15, 0.9 }, { x, 0, z }, "Quad", "In"),
		key(squish * 0.4, { 1.25, 0.7, 1.25 }, { x, 0, z }),
		key(squish * 0.6, REST, { x, 0, z }, "Back"),
	}
end

-- `hops` hops of `height` studs (wild slimes cheering at fireworks, or bouncing on a pad).
function PvpFunFxLogic.hop(height: number, hops: number): { Key }
	local keys: { Key } = {}
	for _ = 1, math.max(1, hops) do
		table.insert(keys, key(0.07, { 1.15, 0.8, 1.15 }))
		table.insert(keys, key(0.17, { 0.9, 1.18, 0.9 }, { 0, height, 0 }, "Quad", "Out"))
		table.insert(keys, key(0.15, { 0.95, 1.08, 0.95 }, ZERO, "Quad", "In"))
	end
	table.insert(keys, key(0.1, REST, ZERO, "Back"))
	return keys
end

function PvpFunFxLogic.seconds(keys: { Key }): number
	local total = 0
	for _, k in keys do
		total += k.seconds
	end
	return total
end

--[[
	Size factors of a part whose proxy is scaled by `scale` ({ x, y, z } in the proxy's upright frame). `axes` are the
	part's own right / up / back unit vectors in that frame (CFrame.XVector / YVector / ZVector relative to it).
]]
function PvpFunFxLogic.axisScale(axes: { V3 }, scale: V3): V3
	local out: V3 = {}
	for i = 1, 3 do
		local a = axes[i]
		local x, y, z = a[1] * scale[1], a[2] * scale[2], a[3] * scale[3]
		out[i] = math.sqrt(x * x + y * y + z * z)
	end
	return out
end

-- Velocity that carries a free-falling body from `from` to `to` in `t` seconds under gravity `g` (studs/s^2).
function PvpFunFxLogic.ballistic(from: Vec, to: Vec, t: number, g: number): Vec
	local s = math.max(t, 0.05)
	return {
		X = (to.X - from.X) / s,
		Y = (to.Y - from.Y) / s + 0.5 * g * s,
		Z = (to.Z - from.Z) / s,
	}
end

-- A small deterministic random walk (LCG): `hops` points `step` studs apart starting at `start` (XZ only).
function PvpFunFxLogic.hatPath(seed: number, start: Vec, hops: number, step: number): { Vec }
	local state = (math.floor(math.abs(seed)) * 1103515245 + 12345) % 2147483648
	local function rand(): number
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
	local points: { Vec } = {}
	local x, z = start.X, start.Z
	local heading = rand() * 2 * math.pi
	for _ = 1, hops do
		heading += (rand() - 0.5) * 2.2
		x += math.cos(heading) * step
		z += math.sin(heading) * step
		table.insert(points, { X = x, Y = start.Y, Z = z })
	end
	return points
end

-- An ordered, bounded list. `push(item)` returns the evicted oldest item when the list was full.
export type Queue<T> = {
	push: (item: T) -> T?,
	remove: (item: T) -> boolean,
	count: () -> number,
	items: () -> { T },
}
function PvpFunFxLogic.queue<T>(max: number): Queue<T>
	local list: { T } = {}
	local self = {}
	function self.push(item: T): T?
		table.insert(list, item)
		if #list > max then
			return table.remove(list, 1)
		end
		return nil
	end
	function self.remove(item: T): boolean
		local i = table.find(list, item)
		if i then
			table.remove(list, i)
			return true
		end
		return false
	end
	function self.count(): number
		return #list
	end
	function self.items(): { T }
		return table.clone(list)
	end
	return self :: Queue<T>
end

return PvpFunFxLogic
