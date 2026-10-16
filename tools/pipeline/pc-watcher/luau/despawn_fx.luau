-- Client datamodel: despawn-telegraph proof shot (v30 C8: removal has no fade / blink). Finds the slime nearest
-- the pad at %%PATH%% (<= 14 studs; slime_seat put one there), makes it look like a wild slime inside its
-- despawn window on THIS client only (State = "Wild", DespawnAt = server now + %%WAIT%% + 2; attributes set on
-- the client never replicate), samples every BasePart's Transparency + LocalTransparencyModifier and any
-- Highlight on it for %%WAIT%% s (DespawnTelegraphFx would blink / pulse them if the old fade were back), and
-- restores the attributes. The capture lands inside the window. ok = nothing ever faded and no Highlight.
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
local origin = if node:IsA("Model") then node:GetPivot().Position else (node :: BasePart).Position
local slime, best = nil, 14
for _, m in game:GetService("CollectionService"):GetTagged("Slime") do
	local body = m:IsA("Model") and (m.PrimaryPart or m:FindFirstChild("Body"))
	if body then
		local d = (body.Position - origin).Magnitude
		if d < best then
			slime, best = m, d
		end
	end
end
if not slime then
	return { ok = false, error = "no slime near the pad" }
end
local oldState, oldAt = slime:GetAttribute("State"), slime:GetAttribute("DespawnAt")
local base = {}
for _, d in slime:GetDescendants() do
	if d:IsA("BasePart") then
		base[d] = d.Transparency
	end
end
slime:SetAttribute("State", "Wild")
slime:SetAttribute("DespawnAt", workspace:GetServerTimeNow() + %%WAIT%% + 2)
local samples, faded, highlights, countdown = 0, 0, 0, false
local t0 = os.clock()
while os.clock() - t0 < %%WAIT%% do
	task.wait(0.05)
	samples += 1
	for p, was in base do
		if p.Parent and (p.Transparency ~= was or p.LocalTransparencyModifier ~= 0) then
			faded += 1
		end
	end
	for _, d in slime:GetDescendants() do
		if d:IsA("Highlight") then
			highlights += 1
		elseif d:IsA("BillboardGui") and d.Name == "DespawnCountdown" then
			countdown = true
		end
	end
end
slime:SetAttribute("State", oldState)
slime:SetAttribute("DespawnAt", oldAt)
return { ok = samples > 0 and faded == 0 and highlights == 0, samples = samples, faded = faded, highlights = highlights, countdown = countdown, slime = slime:GetFullName() }
