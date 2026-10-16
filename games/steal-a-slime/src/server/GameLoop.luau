--!strict
--[[
	GameLoop (pure)

	Everything time-driven, in one call per frame: the fountain and Slime Rain
	(Spawner), escape bounces and lock expiry (StealService.step), and once a
	second income (Income.step), wriggle / timeout escapes and goal / SlimeDex
	rewards (Milestones.step).
]]

local Income = if script then require(script.Parent.Income) else require("./Income")
local Milestones = if script then require(script.Parent.Milestones) else require("./Milestones")
local Spawner = if script then require(script.Parent.Spawner) else require("./Spawner")
local StealService = if script then require(script.Parent.StealService) else require("./StealService")
local World = if script then require(script.Parent.World) else require("./World")

local GameLoop = {}

function GameLoop.step(world: World.World, now: number)
	Spawner.step(world, now)
	StealService.step(world, now)
	local elapsed = now - world.lastSecondAt
	if elapsed >= 1 then
		world.lastSecondAt = now
		Income.step(world, elapsed, now)
		StealService.tickEscapes(world, now)
		StealService.tickTutorial(world, now)
		Milestones.step(world)
	end
end

return GameLoop
