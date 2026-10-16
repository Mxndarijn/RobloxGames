-- Client datamodel: v30 C11 night-streak probe. Scans the whole workspace for Beams, Trails and Neon parts that
-- are longer than %%MAX%% studs (rare-spawn beams once stood 150 studs tall). RareSpawn's own cap is 24 and the TutorialArrow Beam shares it (Props.ARROW_MAX_LENGTH),
-- so any hit is a regression. Reports the offenders and the largest sizes seen; ok = none.
local max = %%MAX%%
local bad, longest, beams, trails = {}, 0, 0, 0
for _, d in workspace:GetDescendants() do
	if d:IsA("Beam") then
		beams += 1
		local a0, a1 = d.Attachment0, d.Attachment1
		if a0 and a1 then
			local len = (a0.WorldPosition - a1.WorldPosition).Magnitude
			longest = math.max(longest, len)
			if len > max then
				table.insert(bad, { path = d:GetFullName(), kind = "Beam", len = len })
			end
		end
	elseif d:IsA("Trail") then
		trails += 1
		if d.Lifetime > 2 then
			table.insert(bad, { path = d:GetFullName(), kind = "Trail", lifetime = d.Lifetime })
		end
	elseif d:IsA("BasePart") and d.Material == Enum.Material.Neon and d.Transparency < 1 then
		local s = d.Size
		local len = math.max(s.X, s.Y, s.Z)
		longest = math.max(longest, len)
		if len > max then
			table.insert(bad, { path = d:GetFullName(), kind = "Neon", len = len, size = tostring(s) })
		end
	end
end
return { ok = #bad == 0, max = max, longest = longest, beams = beams, trails = trails, bad = { table.unpack(bad, 1, 10) }, clock = game:GetService("Lighting").ClockTime }
