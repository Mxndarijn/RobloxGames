--!strict
--[[
	GameLoop (pure)

	Everything time-driven, in one call per frame: the fountain and Slime Rain
	(Spawner), the boss event (BossEvent), escape bounces and lock expiry (StealService.step), lock breaks that
	ended (LockBreak.step), and once a
	second income (Income.step), the tutorial's Leaderboard step (TutorialService.tick), goal / SlimeDex
	rewards (Milestones.step), Mystery Egg incubation (MysteryEgg.step), the Slime Club's daily credits
	(Purchases.stepDaily) and the Thief Radar (ThiefRadar.step).
]]

local BossCredit = if script then require(script.Parent.BossCredit) else require("./BossCredit")
local BossEvent = if script then require(script.Parent.BossEvent) else require("./BossEvent")
local Income = if script then require(script.Parent.Income) else require("./Income")
local LockBreak = if script then require(script.Parent.LockBreak) else require("./LockBreak")
local LuckyShow = if script then require(script.Parent.LuckyShow) else require("./LuckyShow")
local Milestones = if script then require(script.Parent.Milestones) else require("./Milestones")
local MysteryEgg = if script then require(script.Parent.MysteryEgg) else require("./MysteryEgg")
local ObbyService = if script then require(script.Parent.ObbyService) else require("./ObbyService")
local Purchases = if script then require(script.Parent.Purchases) else require("./Purchases")
local Spawner = if script then require(script.Parent.Spawner) else require("./Spawner")
local StealService = if script then require(script.Parent.StealService) else require("./StealService")
local ThiefRadar = if script then require(script.Parent.ThiefRadar) else require("./ThiefRadar")
local TutorialService = if script then require(script.Parent.TutorialService) else require("./TutorialService")
local World = if script then require(script.Parent.World) else require("./World")

local GameLoop = {}

-- `ctx` (optional) gives the boss and the tutorial the players' positions (BossEvent.Context, TutorialService.Context).
function GameLoop.step(world: World.World, now: number, ctx: (BossEvent.Context & TutorialService.Context)?)
	Spawner.step(world, now)
	BossEvent.step(world, now, ctx)
	BossCredit.expire(world, now)
	ObbyService.refresh(world, now)
	StealService.step(world, now)
	LockBreak.step(world, now)
	LuckyShow.step(world, now)
	local elapsed = now - world.lastSecondAt
	if elapsed < 0 then
		world.lastSecondAt = now -- the clock stepped back: restart the one-second tick from here
	elseif elapsed >= 1 then
		world.lastSecondAt = now
		for _, session in world.sessions do
			local stats = session.data.stats
			stats.playSeconds = (stats.playSeconds or 0) + math.min(elapsed, 5) -- a long server hitch is not play time
		end
		Income.step(world, elapsed, now)
		TutorialService.tick(world, ctx)
		Milestones.step(world, now)
		MysteryEgg.step(world, elapsed, now)
		for _, session in world.sessions do
			Purchases.stepDaily(world, session, now)
		end
		ThiefRadar.step(world, if ctx then (ctx :: any).features else nil)
	end
end

return GameLoop
