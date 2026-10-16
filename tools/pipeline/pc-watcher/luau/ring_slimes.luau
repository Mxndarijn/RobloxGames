-- Server datamodel: v30 C3 proof, no wild slime stands inside the plaza's landing ring (Plaza.LandingRing curbs,
-- r 33.5..44.3, visual-only: slimes are anchored and script moved). Samples every tagged wild slime (State
-- "Wild", not carried) 16 times over 4 s and flags any whose pivot is closer to the fountain axis than the ring's
-- outer edge (44.4) plus the slime's half size. Slimes still riding the slide out (inside the +-14 degree wedge
-- on +Z before the straight exit ends) are skipped: that gap is the slide's own exit. Slimes still on the fountain ride
-- (server attribute "Riding", Constants.RIDING_ATTRIBUTE: emerge, spiral, mouth, run-out to the landing) are skipped
-- too and counted in `riding`: they cross the ring band by design; the C3 rule only binds resting wilds. Reports the number of
-- samples / distinct slimes, the minimum radius seen and the violations. `ok` is false on ANY violation.
local CollectionService = game:GetService("CollectionService")
local OUTER = 44.4
local WEDGE = math.rad(14)
local samples, ids, minR, bad, riding = 0, {}, math.huge, {}, 0
for _ = 1, 16 do
	for _, m in CollectionService:GetTagged("Slime") do
		if m:IsA("Model") and m:GetAttribute("State") == "Wild" and not m:GetAttribute("PcwFill") then
			local p = m:GetPivot().Position
			local r = math.sqrt(p.X * p.X + p.Z * p.Z)
			local inWedge = p.Z > 0 and math.abs(math.atan2(p.X, p.Z)) < WEDGE
			local half = math.max(m:GetExtentsSize().X, m:GetExtentsSize().Z) / 2
			if m:GetAttribute("Riding") then
				riding += 1
				continue
			end
			samples += 1
			ids[m:GetAttribute("SlimeId") or m.Name] = true
			if not inWedge then
				minR = math.min(minR, r)
				if r < OUTER + half then
					table.insert(bad, `{m.Name} r={math.floor(r * 10) / 10}`)
				end
			end
		end
	end
	task.wait(0.25)
end
local distinct = 0
for _ in ids do
	distinct += 1
end
return { ok = #bad == 0, samples = samples, slimes = distinct, riding = riding, min_radius = if minR == math.huge then nil else minR, violations = bad }
