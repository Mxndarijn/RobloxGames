-- Server datamodel: v30 C9 proof, wild slimes walk the goo-parade lane at the Config pace. Reads Config and
-- ParadeLane from ReplicatedStorage.Shared, samples the horizontal position of every WildSlimes model now and
-- %%SECONDS%% s later (lane slimes move by PivotTo on a clock, so no physics is involved) and compares the
-- fastest steady walker's speed (units: studs/s, measured and expected alike; fountain riders, model attribute
-- "Riding" = true in EITHER snapshot, move 8-14 studs/s and are skipped; reports `walkers` = non-riding models that
-- moved > 0.1 studs/s and `riders_skipped`) with ParadeLane.walkSpeed(WILD_LIFETIME) (the Config pace). Reports the pace
-- before the change (WILD_BASE_LIFETIME) and `slower_by` = 1 - expected / old. ok = a walker was seen, its
-- speed is within 25% of expected (curved lane: chord <= arc), and the new pace is slower than the old.
local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Shared")
if not shared then
	return { ok = false, error = "ReplicatedStorage.Shared missing" }
end
local Config = require(shared:FindFirstChild("Config"))
local ParadeLane = require(shared:FindFirstChild("ParadeLane"))
local folder = workspace:FindFirstChild("WildSlimes")
if not folder then
	return { ok = false, error = "WildSlimes folder missing" }
end
local function snapshot()
	local out = {}
	for _, m in folder:GetChildren() do
		if m:IsA("Model") then
			local p = m:GetPivot().Position
			out[m] = { pos = Vector3.new(p.X, 0, p.Z), riding = m:GetAttribute("Riding") == true }
		end
	end
	return out
end
local seconds = %%SECONDS%%
local a = snapshot()
task.wait(seconds)
local b = snapshot()
local best, walkers, riders = 0, 0, 0
for m, sa in a do
	local sb = b[m]
	if sb then
		if sa.riding or sb.riding then
			riders += 1
		else
			local v = (sb.pos - sa.pos).Magnitude / seconds
			if v > 0.1 then
				walkers += 1
			end
			best = math.max(best, v)
		end
	end
end
local expected = ParadeLane.walkSpeed(Config.WILD_LIFETIME)
local old = ParadeLane.walkSpeed(Config.WILD_BASE_LIFETIME)
local slower = 1 - expected / old
local ok = best > 0 and best <= expected * 1.25 and best >= expected * 0.5 and expected < old
return { ok = ok, measured = best, expected = expected, old = old, slower_by = slower, mult = Config.SLIME_MOVE_SPEED_MULT, seconds = seconds, walkers = walkers, riders_skipped = riders }
