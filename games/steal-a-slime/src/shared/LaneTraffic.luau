--!strict
--[[
	LaneTraffic (pure, contract/slime-life.md)

	Keeps wild slimes from walking into each other.

	  LaneTraffic.step(walkers, state, dt)
	      Lane slimes queue: front to back, a slime never gets closer to the
	      slime ahead of it (when their sideways places overlap) than their two
	      radii plus GAP; it waits and then catches up at most CATCH_SPEED x its
	      pace. It never walks backwards, and `floor` (the caller lets the hold
	      shrink to 0 before the drain) keeps the drain on time. `state[id]` is
	      the lane distance it is drawn at, carried from frame to frame.
	  LaneTraffic.push(x, z, radius, others) -> (dx, dz)
	      An off-lane walker (a slime walking back to the lane) steps out of the
	      way: the smallest move that clears every body in `others`.
	  LaneTraffic.holdLimit(secondsLeft, pace) -> studs
	      How far a lane slime may fall behind its plan with `secondsLeft` of
	      walk to go: none at the drain, so it arrives on time.

	No Roblox APIs; tests/LaneTraffic.spec covers it.
]]

local ParadeChoreo = if script then require(script.Parent.ParadeChoreo) else require("./ParadeChoreo")

local LaneTraffic = {}

LaneTraffic.GAP = 0.6 -- studs of air between two slimes
LaneTraffic.CATCH_SPEED = ParadeChoreo.CATCH_SPEED + 0.2 -- x pace: a held slime catches up a little faster than a beat
LaneTraffic.RESET = 12 -- studs: drawn this far from its plan (a rejoin, a rebuild) it starts over at the plan

export type Walker = {
	id: string,
	s: number, -- planned lane distance (ParadeLane.distance + its beat offset)
	lateral: number, -- sideways place on the lane
	radius: number,
	pace: number, -- studs / s of plain walking
	floor: number?, -- lowest distance it may be drawn at (plan minus holdLimit)
}

export type Body = { x: number, z: number, radius: number }

function LaneTraffic.holdLimit(secondsLeft: number, pace: number): number
	if secondsLeft ~= secondsLeft then
		return 0
	end
	-- What it can still make up at the catch-up speed, with half a second to spare.
	return math.max(0, secondsLeft - 0.5) * pace * (LaneTraffic.CATCH_SPEED - 1)
end

-- Front to back in drawn order; fills state[id] with the distance each slime is drawn at this frame.
function LaneTraffic.step(walkers: { Walker }, state: { [string]: number }, dt: number)
	local list = table.clone(walkers)
	local drawn: { [string]: number } = {}
	for _, w in list do
		local prev = state[w.id]
		if prev == nil or math.abs(prev - w.s) > LaneTraffic.RESET then
			prev = w.s
		end
		drawn[w.id] = prev
	end
	table.sort(list, function(a, b)
		if drawn[a.id] ~= drawn[b.id] then
			return drawn[a.id] > drawn[b.id]
		end
		return a.id < b.id
	end)
	local placed: { Walker } = {}
	for _, w in list do
		local prev = drawn[w.id]
		-- Towards its plan, never faster than the catch-up and never backwards.
		local s = math.min(w.s, prev + LaneTraffic.CATCH_SPEED * w.pace * math.max(dt, 0))
		s = math.max(s, math.min(prev, w.s))
		-- Behind every slime ahead that it would touch sideways.
		for _, o in placed do
			local room = w.radius + o.radius + LaneTraffic.GAP
			if math.abs(w.lateral - o.lateral) < room then
				local limit = state[o.id] - room
				if s > limit and state[o.id] >= prev - 1e-6 then
					s = math.max(limit, math.min(prev, w.s))
				end
			end
		end
		if w.floor and s < w.floor then
			s = math.min(w.floor, w.s)
		end
		state[w.id] = s
		table.insert(placed, w)
	end
	-- Drop slimes that left the lane.
	for id in state do
		if drawn[id] == nil then
			state[id] = nil
		end
	end
end

function LaneTraffic.push(x: number, z: number, radius: number, others: { Body }): (number, number)
	local px, pz = 0, 0
	for _, o in others do
		local dx, dz = x - o.x, z - o.z
		local d = math.sqrt(dx * dx + dz * dz)
		local need = radius + o.radius + LaneTraffic.GAP
		if d < need then
			if d < 1e-6 then
				dx, dz, d = 1, 0, 1
			end
			local k = (need - d) / d
			px += dx * k
			pz += dz * k
		end
	end
	return px, pz
end

return table.freeze(LaneTraffic)
