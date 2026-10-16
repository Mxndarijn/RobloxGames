-- Client datamodel: plots this client sees as owned (replicated OwnerUserId attributes).
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
local p = game:GetService("Players").LocalPlayer
return { me = if p then p.UserId else nil, players = #game:GetService("Players"):GetPlayers(), plot_owners = owners }
