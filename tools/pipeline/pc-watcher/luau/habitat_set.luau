-- Client datamodel: morph proof shot. Sets the Habitat attribute of the pad at %%PATH%% (the Server
-- shot_find path of the shots.json target) on THIS client only, so HabitatFx tweens the look. First
-- puts the pad back to base for 1.3 s (the revert tween is 1 s), then sets %%HABITAT%% and waits
-- %%WAIT%% s so the capture lands mid-morph (short wait) or after it (>= 1.2 s).
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
node:SetAttribute(ATTR, "base")
task.wait(1.3)
node:SetAttribute(ATTR, %%HABITAT%%)
task.wait(%%WAIT%%)
return { ok = true, before = before, now = node:GetAttribute(ATTR) }
