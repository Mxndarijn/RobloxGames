-- Server datamodel: v30 C9 proof, wild slimes walk the goo-parade lane at the Config pace. Reads Config and
-- ParadeLane from ReplicatedStorage.Shared, samples the horizontal position of every WildSlimes model now and
-- %%SECONDS%% s later (lane slimes move by PivotTo on a clock, so no physics is involved) and compares the
-- fastest steady walker's speed with ParadeLane.walkSpeed(WILD_LIFETIME) (the Config pace). Reports the pace
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
			out[m] = Vector3.new(p.X, 0, p.Z)
		end
	end
	return out
end
local seconds = %%SECONDS%%
local a = snapshot()
task.wait(seconds)
local b = snapshot()
local best = 0
for m, pa in a do
	local pb = b[m]
	if pb then
		best = math.max(best, (pb - pa).Magnitude / seconds)
	end
end
local expected = ParadeLane.walkSpeed(Config.WILD_LIFETIME)
local old = ParadeLane.walkSpeed(Config.WILD_BASE_LIFETIME)
local slower = 1 - expected / old
local ok = best > 0 and best <= expected * 1.25 and best >= expected * 0.5 and expected < old
return { ok = ok, measured = best, expected = expected, old = old, slower_by = slower, mult = Config.SLIME_MOVE_SPEED_MULT, seconds = seconds }
