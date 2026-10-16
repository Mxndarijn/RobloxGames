-- Client datamodel: morph proof shot. Sets the Habitat attribute of the pad at %%PATH%% (the Server
-- shot_find path of the shots/*.json target) on THIS client only, so HabitatFx tweens the look. First
-- puts the pad back to base for 1.3 s (the revert tween is 1 s), then sets %%HABITAT%% and waits
-- %%WAIT%% s so the capture lands mid-morph (short wait) or after it (>= 1.2 s).
-- %%LEAVE%% = true: the slime leaves instead: sets %%HABITAT%% and lets it settle (1.4 s), then puts the
-- pad back to base and waits %%WAIT%% s (short = mid-shrink, >= 1.2 s = the exact base pad again).
local node = game
for part in string.gmatch(%%PATH%%, "[^.]+") do
	if node == game and part == "Workspace" then
		node = workspace
	else
		node = node and node:FindFirstChild(part)
	end
end
if not node then
	return { ok = false, error = "pad not found" }
end
local ATTR = "Habitat"
local before = node:GetAttribute(ATTR)
local LEAVE = %%LEAVE%%
if LEAVE then
	node:SetAttribute(ATTR, %%HABITAT%%)
	task.wait(1.4)
	node:SetAttribute(ATTR, "base")
else
	node:SetAttribute(ATTR, "base")
	task.wait(1.3)
	node:SetAttribute(ATTR, %%HABITAT%%)
end
task.wait(%%WAIT%%)
-- Seat height: bottom Y of the pad_seat slime (PcwPad) vs top Y of the habitat look model HabitatFx
-- built (client-side, named <plot>_<pad>_<habitat>); seat_delta > 0 = slime floats above the habitat.
local slime
for _, m in game:GetService("CollectionService"):GetTagged("Slime") do
	if m:GetAttribute("PcwPad") then
		slime = m
	end
end
local look = workspace:FindFirstChild(node.Parent.Name .. "_" .. node.Name .. "_" .. %%HABITAT%%, true)
local seat
if not LEAVE and slime and look and look:IsA("Model") then
	local sc, ss = slime:GetBoundingBox()
	local lc, ls = look:GetBoundingBox()
	local bottom, top = sc.Position.Y - ss.Y / 2, lc.Position.Y + ls.Y / 2
	seat = { slime_bottom_y = bottom, habitat_top_y = top, seat_delta = bottom - top }
end
return { ok = true, before = before, now = node:GetAttribute(ATTR), seat = seat, slime_found = slime ~= nil, look_found = look ~= nil }
