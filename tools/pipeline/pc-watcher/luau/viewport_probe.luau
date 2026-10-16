-- Client datamodel: %%SHOW%% = add / remove PcwProbe, a full-screen magenta ScreenGui (above every
-- other gui, top bar included). The watcher finds it in a window capture to crop frames to the
-- game viewport.
local pg = game:GetService("Players").LocalPlayer.PlayerGui
local old = pg:FindFirstChild("PcwProbe")
if old then
	old:Destroy()
end
if %%SHOW%% then
	local g = Instance.new("ScreenGui")
	g.Name = "PcwProbe"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 2147483647
	pcall(function()
		g.ScreenInsets = Enum.ScreenInsets.None
	end)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.fromRGB(255, 0, 255)
	f.BorderSizePixel = 0
	f.Parent = g
	g.Parent = pg
	task.wait(0.4)
end
local vp = workspace.CurrentCamera.ViewportSize
return { shown = %%SHOW%%, viewport = { vp.X, vp.Y } }
