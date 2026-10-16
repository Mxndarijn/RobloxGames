-- Client datamodel: hold-to-confirm proof shot (B1). %%ON%% = true sets the PcwHold attribute (0.5) on the first
-- visible SlimeUI button named %%NAME%%; Widgets.holdButton (Studio hook) then runs its real hold routine and
-- pauses at that fill without confirming. Returns the MEASURED fill fraction (fill AbsoluteSize.X / button
-- AbsoluteSize.X) and whether the bar is on screen; false clears the attribute (normal release path, no confirm).
-- This script only sets/clears the attribute: it never touches the fill Frame.
local gui = game:GetService("Players").LocalPlayer.PlayerGui:FindFirstChild("SlimeUI")
if not gui then
	return { found = false }
end
local function shown(d: Instance): boolean
	local n = d
	while n and n ~= gui do
		if n:IsA("GuiObject") and not n.Visible then
			return false
		end
		n = n.Parent
	end
	return gui:IsA("LayerCollector") and gui.Enabled
end
local seconds, fill, button = nil, nil, nil
local touched = 0
for _, d in gui:GetDescendants() do
	local f = d.Name == %%NAME%% and d:IsA("GuiButton") and d:FindFirstChild("HoldFill")
	if f and f:IsA("GuiObject") then
		touched += 1
		seconds = d:GetAttribute("HoldConfirm")
		if not %%ON%% then
			d:SetAttribute("PcwHold", nil)
		elseif not button and shown(d) and d.AbsoluteSize.X > 0 then
			button, fill = d, f
		end
	end
end
if not %%ON%% then
	return { found = touched > 0, touched = touched, hold_seconds = seconds }
end
if not fill then
	return { found = false, touched = touched }
end
button:SetAttribute("PcwHold", 0.5)
-- the hold advances at the real rate (HoldConfirm seconds for 1.0); wait until it has paused at 0.5
local deadline = os.clock() + (tonumber(seconds) or 1) + 2
repeat
	game:GetService("RunService").RenderStepped:Wait()
until (fill.Visible and fill.AbsoluteSize.X >= button.AbsoluteSize.X * 0.5 - 0.5) or os.clock() > deadline
game:GetService("RunService").RenderStepped:Wait()
game:GetService("RunService").RenderStepped:Wait()
local vp = workspace.CurrentCamera.ViewportSize
local pos, size = fill.AbsolutePosition, fill.AbsoluteSize
local bsize = button.AbsoluteSize
return {
	found = true,
	touched = touched,
	hold_seconds = seconds,
	fraction = if bsize.X > 0 then size.X / bsize.X else 0,
	fill_px = { size.X, size.Y },
	button_px = { bsize.X, bsize.Y },
	on_screen = pos.X >= 0 and pos.Y >= 0 and pos.X + size.X <= vp.X and pos.Y + size.Y <= vp.Y and size.X > 0,
	visible = fill.Visible,
}
