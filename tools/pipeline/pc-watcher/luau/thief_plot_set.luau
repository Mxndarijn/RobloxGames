-- Client datamodel: thief plot proof shot. Sets the client-only Player attribute ThiefPlots to
-- plot %%PLOT%% (0 clears it) as the server would while a thief carries the victim's slime, waits %%WAIT%% s for ThiefPlotFx and reports the
-- ThiefPlotHighlight instances. Never replicated, so no other player and not the server sees it.
local player = game:GetService("Players").LocalPlayer
local plot = %%PLOT%%
player:SetAttribute("ThiefPlots", if plot > 0 then tostring(plot) else nil)
task.wait(%%WAIT%%)
local folder = workspace:FindFirstChild("ThiefPlotFx")
local found = {}
if folder then
	for _, h in folder:GetChildren() do
		if h:IsA("Highlight") and h.Name == "ThiefPlotHighlight" then
			table.insert(found, { plot = h:GetAttribute("PlotIndex"), adornee = h.Adornee and h.Adornee:GetFullName() or nil, always_on_top = h.DepthMode == Enum.HighlightDepthMode.AlwaysOnTop })
		end
	end
end
local ok = if plot > 0 then #found == 1 and found[1].plot == plot and found[1].adornee ~= nil else #found == 0
return { ok = ok, folder = folder ~= nil, highlights = found, attr = player:GetAttribute("ThiefPlots") }
