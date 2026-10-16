-- Server datamodel of a Studio play session: two stand-in sessions on a fresh, pure World
-- (the real server modules, nothing replicated, no DataStore), victim's slime stolen and
-- deposited by the thief. Same calls as tests/Integration.spec stealSetup + Carry.
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local Server = SSS:FindFirstChild("Server")
assert(Server, "ServerScriptService.Server missing")
local World = require(Server:FindFirstChild("World"))
local Sessions = require(Server:FindFirstChild("Sessions"))
local Carry = require(Server:FindFirstChild("Carry"))
local PlayerData = require(RS.Shared.PlayerData)
local Config = require(RS.Shared.Config)

local T0 = os.time()
local VICTIM, THIEF = -2001, -2002 -- negative: never a real user
local world = World.new({ now = T0, seed = 7 })
local victimData = PlayerData.new()
victimData.padsUnlocked = Config.PADS_MAX
PlayerData.addSlime(victimData, {
	id = "pcw-gem", name = "Blorp", tier = 4, color = { 200, 50, 100 }, size = 1,
	pattern = "Plain", eyes = "Round", mouth = "Smile", mutation = "None",
} :: any)
local thiefData = PlayerData.new()
thiefData.padsUnlocked = Config.PADS_MAX
local victim = assert(Sessions.join(world, VICTIM, "PCW Victim", victimData, T0))
local thief = assert(Sessions.join(world, THIEF, "PCW Thief", thiefData, T0))
victim.lockUntil = 0 -- lift the join lock

local grabOk, grabWhy = Carry.grab(world, THIEF, "pcw-gem", 1, T0 + 1)
local depOk, depWhy = Carry.deposit(world, THIEF)
local plotsFolder = workspace:FindFirstChild("Plots")
local realOwners = 0
if plotsFolder then
	for _, plot in plotsFolder:GetChildren() do
		local owner = plot:GetAttribute("OwnerUserId")
		if type(owner) == "number" and owner ~= 0 then
			realOwners += 1
		end
	end
end
return {
	distinct_plots = victim.plotIndex ~= thief.plotIndex,
	grab_ok = grabOk,
	grab_why = grabWhy,
	deposit_ok = depOk,
	deposit_why = depWhy,
	thief_has = PlayerData.findSlime(thief.data, "pcw-gem") ~= nil,
	victim_has = PlayerData.findSlime(victim.data, "pcw-gem") ~= nil,
	thief_stolen = thief.data.totalStolen,
	real_players = #game:GetService("Players"):GetPlayers(),
	real_owned_plots = realOwners,
}
