-- Client datamodel: bug probes 1 / 2 / 3 (Merijn's 2026-10-17 list, ADVISORY). Scans every BillboardGui / SurfaceGui
-- (workspace + PlayerGui) for a TextLabel / TextButton that is visible (gui Enabled, every GuiObject ancestor Visible,
-- TextTransparency < 1, non-empty) and whose Text contains %%PATTERN%% (case-insensitive plain find). ok = none found.
-- %%SHOW%% = true first re-enables the BillboardGuis shot_camera hid (PcwHidden; shot_camera_reset still restores them),
-- so the captured frame shows the text. For "leaving" the code path is also checked: ParadeLane.warnText(3, enabled)
-- is what DespawnTelegraphFx writes into its billboard, and it is only on screen in the last seconds of a lane slime.
local Players = game:GetService("Players")
local pattern = string.lower(%%PATTERN%%)
local show = %%SHOW%%
local pg = Players.LocalPlayer and Players.LocalPlayer:FindFirstChild("PlayerGui")
local hits, guis, labels, reenabled = {}, 0, 0, 0
local function shown(label, gui)
	local node = label
	while node and node ~= gui do
		if node:IsA("GuiObject") and not node.Visible then
			return false
		end
		node = node.Parent
	end
	return label.TextTransparency < 1 and label.Text ~= ""
end
local function scan(root)
	for _, d in root:GetDescendants() do
		if d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			if show and d:IsA("BillboardGui") and not d.Enabled and d:GetAttribute("PcwHidden") then
				d.Enabled = true
				reenabled += 1
			end
			guis += 1
			if d.Enabled then
				for _, l in d:GetDescendants() do
					if l:IsA("TextLabel") or l:IsA("TextButton") then
						labels += 1
						if string.find(string.lower(l.Text), pattern, 1, true) and shown(l, d) then
							local at = d.Adornee or d.Parent
							local p = at and at:IsA("BasePart") and at.Position
							table.insert(hits, { path = l:GetFullName(), text = l.Text, pos = p and { p.X, p.Y, p.Z } or nil })
						end
					end
				end
			end
		end
	end
end
scan(workspace)
if pg then
	scan(pg)
end
local code
if pattern == "leaving" then
	pcall(function()
		local lane = require(game:GetService("ReplicatedStorage").Shared.ParadeLane)
		local text = lane.warnText(3, lane.enabled())
		code = { warn_text = text, matches = string.find(string.lower(text), pattern, 1, true) ~= nil }
	end)
end
local ok = #hits == 0 and not (code and code.matches)
local summary = if #hits > 0 then string.format("%d visible '%s' label(s), first %s", #hits, pattern, hits[1].path)
	elseif code and code.matches then string.format("no live label now, but ParadeLane.warnText still writes %q", code.warn_text)
	else string.format("no '%s' text (%d gui, %d labels scanned)", pattern, guis, labels)
return {
	ok = ok,
	summary = summary,
	detail = { pattern = pattern, hits = {table.unpack(hits, 1, 8)}, hit_count = #hits, guis = guis, labels = labels, reenabled = reenabled, code = code },
}
