-- Server datamodel: players and claimed plots (Plots.Plot_N attribute OwnerUserId).
local Players = game:GetService("Players")
local plotsFolder = workspace:FindFirstChild("Plots")
local owners = {}
if plotsFolder then
	for _, plot in plotsFolder:GetChildren() do
		local owner = plot:GetAttribute("OwnerUserId")
		if type(owner) == "number" and owner ~= 0 then
			table.insert(owners, owner)
		end
	end
end
local players = {}
for _, pl in Players:GetPlayers() do
	table.insert(players, { name = pl.Name, userId = pl.UserId })
end
return { players = players, plot_owners = owners, store_status = workspace:GetAttribute("DataStoreStatus") }
