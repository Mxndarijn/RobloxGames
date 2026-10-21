--!strict
--[[
	SlimeSpacing (pure, contract/slime-life.md "Clean lane")

	Keeps drawn slimes from overlapping. The server queues lane slimes by their Bodies, but what the player sees is
	the drawn slime: a hopper waits and leaps, a slime leans towards you, beats run ahead, so two drawn slimes can
	sink into each other even when their Bodies don't. Once a frame, after every actor has placed its slime, this
	eases each overlapping pair apart: the push each slime needs (half the overlap, along the line between them)
	is the target of a filter that grows fast and eases back slowly, so a slime slides aside instead of sinking in
	and slides back when the other has passed. No Roblox APIs; tests/ui/SlimeSpacing.spec covers it.

	  SlimeSpacing.step(items, dt)   items: { { x, z, r, px, pz } }: drawn spot (before the push), radius, and the
	                                 push carried from the last frame (filled in place)
]]

local SlimeSpacing = {}

SlimeSpacing.GAP = 0.2 -- studs of air kept between two drawn slimes
SlimeSpacing.RATE = 40 -- 1 / s: how fast a push grows while an overlap grows (a leap closes in fast)
SlimeSpacing.RELAX = 6 -- 1 / s: how fast it eases back once the other slime has passed
SlimeSpacing.MAX_PUSH = 2.5 -- studs: never pushed further than this from where the actor drew it

export type Item = { x: number, z: number, r: number, px: number, pz: number }

function SlimeSpacing.step(items: { Item }, dt: number)
	local n = #items
	local wantX, wantZ = table.create(n, 0), table.create(n, 0)
	for i = 1, n do
		local a = items[i]
		for j = i + 1, n do
			local b = items[j]
			local dx, dz = a.x - b.x, a.z - b.z
			local room = a.r + b.r + SlimeSpacing.GAP
			local d2 = dx * dx + dz * dz
			if d2 < room * room then
				local d = math.sqrt(d2)
				local share = (room - d) / 2
				local ux, uz = 1, 0 -- right on top of each other: part them along x, the earlier one to +x
				if d > 1e-4 then
					ux, uz = dx / d, dz / d
				end
				wantX[i] += ux * share
				wantZ[i] += uz * share
				wantX[j] -= ux * share
				wantZ[j] -= uz * share
			end
		end
	end
	local grow = 1 - math.exp(-math.max(dt, 0) * SlimeSpacing.RATE)
	local relax = 1 - math.exp(-math.max(dt, 0) * SlimeSpacing.RELAX)
	for i = 1, n do
		local it = items[i]
		local wx, wz = wantX[i], wantZ[i]
		local len = math.sqrt(wx * wx + wz * wz)
		if len > SlimeSpacing.MAX_PUSH then
			wx, wz, len = wx / len * SlimeSpacing.MAX_PUSH, wz / len * SlimeSpacing.MAX_PUSH, SlimeSpacing.MAX_PUSH
		end
		-- grows fast (no slime sinks in), eases back slowly (no snap when the other has gone)
		local k = if len * len > it.px * it.px + it.pz * it.pz then grow else relax
		it.px += (wx - it.px) * k
		it.pz += (wz - it.pz) * k
	end
end

return SlimeSpacing
