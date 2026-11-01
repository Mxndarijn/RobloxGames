--!strict
-- Reports Roblox's idle time to the server, which teleports the player back in before the 20-minute idle kick.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Constants = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Constants"))
local IdleRejoinClient =
	require(ReplicatedStorage:WaitForChild("Lib"):WaitForChild("idle"):WaitForChild("IdleRejoinClient"))

local remotes = ReplicatedStorage:WaitForChild(Constants.REMOTES_FOLDER)
IdleRejoinClient.start({
	player = Players.LocalPlayer,
	remote = remotes:WaitForChild(Constants.IDLE_REJOIN) :: RemoteEvent,
})
