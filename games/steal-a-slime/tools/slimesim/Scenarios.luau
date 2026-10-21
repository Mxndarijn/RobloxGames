--!strict
--[[
	SlimeSim scenarios: what the player (the local character) does while the slimes walk the lane.

	Each scenario: { seed, warmup, player = function(now, poseOf, clients) -> (x, z, look) }.
	  poseOf(id) -> the slime's replicated Body CFrame (nil before its first snapshot)
	  clients    -> { [id]: { w = { species, ... }, body = Part } }
	The player walks like a Roblox character: at most WALK_SPEED studs / s towards where it wants to be.
]]

local Scenarios = {}

local WALK_SPEED = 16

type Walker = { x: number, z: number, t: number?, target: string? }

local function walkTo(st: Walker, x: number, z: number, now: number): (number, number)
	local dt = if st.t then now - st.t else 0
	st.t = now
	local dx, dz = x - st.x, z - st.z
	local d = math.sqrt(dx * dx + dz * dz)
	local step = WALK_SPEED * dt
	if d <= step or d < 1e-6 then
		st.x, st.z = x, z
	else
		st.x += dx / d * step
		st.z += dz / d * step
	end
	return st.x, st.z
end

-- The slime of `species` (else any) nearest the middle of the screen-ish spot (-35, 40), picked once.
local function pick(st: Walker, clients: any, species: string?): string?
	if st.target and clients[st.target] then
		return st.target
	end
	local best, bestD = nil, math.huge
	for id, c in clients do
		local p = c.body.CFrame.Position
		local d = (p.X + 35) ^ 2 + (p.Z - 40) ^ 2
		if species and c.w.species ~= species then
			d += 1e6
		end
		if d < bestD then
			best, bestD = id, d
		end
	end
	st.target = best
	return best
end

-- Walks beside one slime (3.5 studs to its side), like a player sizing up a slime to buy.
local function beside(species: string)
	local st: Walker = { x = -35, z = 55 }
	return function(now: number, poseOf: any, clients: any): (number, number, number)
		local id = pick(st, clients, species)
		local cf = if id then poseOf(id) else nil
		if not cf then
			return st.x, st.z, 0
		end
		local p, look = cf.Position, cf.LookVector
		local sx, sz = -look.Z, look.X
		local x, z = walkTo(st, p.X + sx * 3.5 + look.X * 0.5, p.Z + sz * 3.5 + look.Z * 0.5, now)
		return x, z, math.atan2(-look.X, -look.Z)
	end
end

Scenarios.beside = { seed = 7, player = beside("bubbles") }
Scenarios.besideGummy = { seed = 11, player = beside("gummy") }

-- Stands at the lane's edge while the parade passes.
Scenarios.stand = {
	seed = 7,
	player = function(): (number, number, number)
		return -40, 47, 0
	end,
}

-- Walks back and forth across the lane every 3 s.
Scenarios.cross = {
	seed = 7,
	player = (function()
		local st: Walker = { x = -40, z = 50 }
		return function(now: number): (number, number, number)
			local leg = math.floor(now / 3) % 2
			local x, z = walkTo(st, -40, if leg == 0 then 30 else 50, now)
			return x, z, 0
		end
	end)(),
}

-- Circles one slime at 5 studs, one lap every 4 s.
Scenarios.circle = {
	seed = 7,
	player = (function()
		local st: Walker = { x = -35, z = 45 }
		return function(now: number, poseOf: any, clients: any): (number, number, number)
			local id = pick(st, clients, "bubbles")
			local cf = if id then poseOf(id) else nil
			if not cf then
				return st.x, st.z, 0
			end
			local a = now * 2 * math.pi / 4
			local x, z = walkTo(st, cf.Position.X + math.cos(a) * 5, cf.Position.Z + math.sin(a) * 5, now)
			return x, z, 0
		end
	end)(),
}

-- Nobody near: the parade on its own.
Scenarios.alone = {
	seed = 7,
	player = function(): (number, number, number)
		return 300, 300, 0
	end,
}

function Scenarios.names(): { string }
	local out = {}
	for k, v in Scenarios do
		if type(v) == "table" then
			table.insert(out, k)
		end
	end
	table.sort(out)
	return out
end

return Scenarios
