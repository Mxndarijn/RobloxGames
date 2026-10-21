--!strict
--[[
	SlimeSim metrics: what makes slime motion look jittery or wrong, from a trace (tools/slimesim).

	Per frame of a slime the trace holds
	  1 x, 2 z, 3 lift       drawn foot (lift: above the Body's foot)
	  4 yaw                  drawn facing (radians, from the right vector: stable through a forward flip)
	  5 tx, 6 tz             where the name tag and Buy card hang (TagAnchor; the Body on older code)
	  7 byaw                 the replicated Body's heading
	  8 sy                   skin squash
	  9 stage                gait stage (ground / crouch / air)
	  10 lookYaw, 11 weight  the actor's look turn and how much of it it takes
	  12 emote, 13 near      emote; true = near tier (full life)
	  14 bx, 15 bz           the replicated Body
	Metrics use near-tier frames (what the player looks at closely).
]]

local Metrics = {}

local function pct(list: { number }, p: number): number
	if #list == 0 then
		return 0
	end
	local s = table.clone(list)
	table.sort(s)
	return s[math.clamp(math.floor(#s * p + 0.5), 1, #s)]
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function r3(x: number): number
	return math.floor(x * 1000 + 0.5) / 1000
end

function Metrics.compute(trace: any): any
	local dt = 1 / trace.fps
	local drawnIrr, bodyIrr, offset, crab, turn, liftJerk = {}, {}, {}, {}, {}, {}
	local crabFrames, airFrames, flips = 0, 0, 0
	local overlapFrames, overlapWorst = 0, 0
	local nearFrames = 0
	local playerHits, playerWorst = 0, 0
	-- frame index -> list of near slimes' drawn spots (overlap)
	local byFrame: { [number]: { any } } = {}
	for _, rec in trace.slimes do
		local fr = rec.frames
		for i = 3, #fr do
			local a, b, c = fr[i - 2], fr[i - 1], fr[i]
			if c[13] then
				nearFrames += 1
				-- drawn speed irregularity (gliders only: a hop is meant to start and stop)
				local v1x, v1z = (b[1] - a[1]) / dt, (b[2] - a[2]) / dt
				local v2x, v2z = (c[1] - b[1]) / dt, (c[2] - b[2]) / dt
				local sp = (math.sqrt(v1x * v1x + v1z * v1z) + math.sqrt(v2x * v2x + v2z * v2z)) / 2
				if rec.gait ~= "Hop" and sp > 0.5 then
					table.insert(drawnIrr, math.sqrt((v2x - v1x) ^ 2 + (v2z - v1z) ^ 2) / sp)
				end
				-- the Body (name tag, Buy card)
				local w1x, w1z = (b[5] - a[5]) / dt, (b[6] - a[6]) / dt
				local w2x, w2z = (c[5] - b[5]) / dt, (c[6] - b[6]) / dt
				local bs = (math.sqrt(w1x * w1x + w1z * w1z) + math.sqrt(w2x * w2x + w2z * w2z)) / 2
				if bs > 0.5 then
					table.insert(bodyIrr, math.sqrt((w2x - w1x) ^ 2 + (w2z - w1z) ^ 2) / bs)
				end
				-- how far the drawn slime is from its tag / card
				table.insert(offset, math.sqrt((c[1] - c[5]) ^ 2 + (c[2] - c[6]) ^ 2))
				-- facing vs the way it jumps: travel over a few frames either side, so the foot swinging back as the body
				-- tilts into a jump (a few hundredths of a stud) doesn't count as moving backwards
				local w0, w1 = fr[math.max(1, i - 3)], fr[math.min(#fr, i + 3)]
				local span = (math.min(#fr, i + 3) - math.max(1, i - 3)) * dt
				local tvx, tvz = (w1[1] - w0[1]) / span, (w1[2] - w0[2]) / span
				local csp = math.sqrt(tvx * tvx + tvz * tvz)
				if c[9] == "air" and csp > 2 then
					airFrames += 1
					local travel = math.atan2(-tvx, -tvz)
					local off = math.abs(wrap(c[4] - travel))
					table.insert(crab, off)
					if off > 0.8 then
						crabFrames += 1
					end
				end
				local tr = math.abs(wrap(c[4] - b[4])) / dt
				table.insert(turn, tr)
				if tr > 8 then
					flips += 1
				end
				table.insert(liftJerk, math.abs((c[3] - b[3]) - (b[3] - a[3])) / (dt * dt))
				local k = rec.first + i - 1
				local pl = trace.player[k]
				-- after the first 1.5 s: scenarios put the player down right next to a slime
				if pl and k > 90 and c[3] < rec.radius * 2 then
					local pd = math.sqrt((c[1] - pl[1]) ^ 2 + (c[2] - pl[2]) ^ 2)
					local room = rec.radius + 1.2
					if pd < room * 0.85 then
						playerHits += 1
						playerWorst = math.max(playerWorst, 1 - pd / room)
					end
				end
				byFrame[k] = byFrame[k] or {}
				if k > 90 then -- the first 1.5 s: the server queue warms up from nothing and the player is put down
					table.insert(byFrame[k], { c[1], c[2], rec.radius, c[14], c[15], c[3] })
				end
			end
		end
	end
	local bodyOverlapFrames = 0
	for _, list in byFrame do
		local bodyHit = false
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i], list[j]
				if math.sqrt((a[4] - b[4]) ^ 2 + (a[5] - b[5]) ^ 2) < (a[3] + b[3]) * 0.85 then
					bodyHit = true
				end
			end
		end
		if bodyHit then
			bodyOverlapFrames += 1
		end
		local hit = false
		for i = 1, #list do
			for j = i + 1, #list do
				local a, b = list[i], list[j]
				local d = math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
				local room = a[3] + b[3]
				-- one fully above the other (a hop over it) is no overlap
				local clear = math.abs(a[6] - b[6]) > math.min(a[3], b[3]) * 2
				if d < room * 0.85 and not clear then
					hit = true
					overlapWorst = math.max(overlapWorst, 1 - d / room)
				end
			end
		end
		if hit then
			overlapFrames += 1
		end
	end
	local seconds = nearFrames * dt
	return {
		near_slime_seconds = r3(seconds),
		glide_irregularity = { p50 = r3(pct(drawnIrr, 0.5)), p95 = r3(pct(drawnIrr, 0.95)) },
		tag_irregularity = { p50 = r3(pct(bodyIrr, 0.5)), p95 = r3(pct(bodyIrr, 0.95)) },
		tag_offset = { p50 = r3(pct(offset, 0.5)), p95 = r3(pct(offset, 0.95)), max = r3(pct(offset, 1)) },
		crab = {
			p50 = r3(pct(crab, 0.5)),
			p90 = r3(pct(crab, 0.9)),
			share_over_0_8 = r3(crabFrames / math.max(airFrames, 1)),
		},
		turn = {
			p95 = r3(pct(turn, 0.95)),
			p99 = r3(pct(turn, 0.99)),
			flips_per_s = r3(flips / math.max(seconds, 1e-3)),
		},
		lift_jerk_p99 = r3(pct(liftJerk, 0.99)),
		overlap = { frames = overlapFrames, worst = r3(overlapWorst), body_frames = bodyOverlapFrames },
		player = { frames = playerHits, worst = r3(playerWorst) },
	}
end

function Metrics.report(m: any): string
	return table.concat({
		`near-slime seconds        {m.near_slime_seconds}`,
		`glide irregularity        p50 {m.glide_irregularity.p50}  p95 {m.glide_irregularity.p95}   (|dv|/v per frame; 0 = even glide)`,
		`name tag irregularity     p50 {m.tag_irregularity.p50}  p95 {m.tag_irregularity.p95}   (~2 = moves only every other frame)`,
		`tag / card offset (studs) p50 {m.tag_offset.p50}  p95 {m.tag_offset.p95}  max {m.tag_offset.max}`,
		`crab hops (rad)           p50 {m.crab.p50}  p90 {m.crab.p90}  share > 0.8 rad {m.crab.share_over_0_8}`,
		`turn rate (rad/s)         p95 {m.turn.p95}  p99 {m.turn.p99}  snaps (>8 rad/s) per s {m.turn.flips_per_s}`,
		`lift jerk p99 (studs/s^2) {m.lift_jerk_p99}`,
		`slime inside the player    frames {m.player.frames}  worst {m.player.worst}`,
		`overlap (drawn)           frames {m.overlap.frames}  worst {m.overlap.worst}   (server Bodies overlap in {m.overlap.body_frames} frames)`,
	}, "\n")
end

return Metrics
