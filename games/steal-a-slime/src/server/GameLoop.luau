--!strict
--[[
	GameLoop (pure)

	Everything time-driven, in one call per frame: the fountain and Slime Rain
	(Spawner), the boss event (BossEvent), escape bounces and lock expiry (StealService.step), lock breaks that
	ended (LockBreak.step), and once a
	second income (Income.step), goal / SlimeDex
	rewards (Milestones.step) and Mystery Egg incubation (MysteryEgg.step).
]]

local BossCredit = if script then require(script.Parent.BossCredit) else require("./BossCredit")
local BossEvent = if script then require(script.Parent.BossEvent) else require("./BossEvent")
local Income = if script then require(script.Parent.Income) else require("./Income")
local LockBreak = if script then require(script.Parent.LockBreak) else require("./LockBreak")
local LuckyShow = if script then require(script.Parent.LuckyShow) else require("./LuckyShow")
local Milestones = if script then require(script.Parent.Milestones) else require("./Milestones")
local MysteryEgg = if script then require(script.Parent.MysteryEgg) else require("./MysteryEgg")
local Spawner = if script then require(script.Parent.Spawner) else require("./Spawner")
local StealService = if script then require(script.Parent.StealService) else require("./StealService")
local World = if script then require(script.Parent.World) else require("./World")

local GameLoop = {}

-- `ctx` (optional) gives the boss the players' positions (BossEvent.Context).
function GameLoop.step(world: World.World, now: number, ctx: BossEvent.Context?)
	Spawner.step(world, now)
	BossEvent.step(world, now, ctx)
	BossCredit.expire(world, now)
	StealService.step(world, now)
	LockBreak.step(world, now)
	LuckyShow.step(world, now)
	local elapsed = now - world.lastSecondAt
	if elapsed < 0 then
		world.lastSecondAt = now -- the clock stepped back: restart the one-second tick from here
	elseif elapsed >= 1 then
		world.lastSecondAt = now
		Income.step(world, elapsed, now)
		StealService.tickTutorial(world, now)
		Milestones.step(world, now)
		MysteryEgg.step(world, elapsed, now)
	end
end

return GameLoop
