--!strict
--[[
	TutorialService (pure)

	The tutorial steps that no other system finishes (contract/tutorial.md): Leaderboard (walk up to the Top Earners
	board; `tick` checks once a second through `ctx.pose` / `ctx.propPosition`), Guide (the Guide NPC's Talk prompt,
	`talkedToGuide`), and skipping the tutorial from the Guide panel (`skip`). Every change goes through
	World.tutorial / TutorialProgress; nothing here pays out.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")
local TutorialProgress = if Shared then require(Shared.TutorialProgress) else require("../shared/TutorialProgress")
local World = if script then require(script.Parent.World) else require("./World")

type Vec = { X: number, Y: number, Z: number }

export type Context = {
	pose: ((userId: number) -> (Vec?, Vec?))?, -- a character's root position (and look)
	propPosition: ((name: string) -> Vec?)?, -- a world prop's position under workspace.Map, nil if missing
}

local TutorialService = {}

-- Call once per second: a player on the Leaderboard step who stands near the Top Earners board finishes it.
function TutorialService.tick(world: World.World, ctx: Context?)
	local pose = ctx and ctx.pose
	local propPosition = ctx and ctx.propPosition
	if not pose or not propPosition then
		return
	end
	local board: Vec? = nil
	for _, session in world.sessions do
		if TutorialProgress.currentId(session.data) == "Leaderboard" then
			board = board or propPosition(Constants.LEADERBOARD_BOARD)
			local at = pose(session.userId)
			if board and at then
				local dx, dz = at.X - board.X, at.Z - board.Z
				if dx * dx + dz * dz <= Config.TUTORIAL_LEADERBOARD_RADIUS ^ 2 then
					World.tutorial(world, session, "Leaderboard")
				end
			end
		end
	end
end

-- The player triggered the Guide NPC's Talk prompt.
function TutorialService.talkedToGuide(world: World.World, userId: number)
	local session = world.sessions[userId]
	if session then
		World.tutorial(world, session, "Guide")
	end
end

-- Request SkipTutorial: ends the tutorial. Returns (ok, reason).
function TutorialService.skip(_world: World.World, session: World.Session): (boolean, string?)
	if not TutorialProgress.skip(session.data) then
		return false, "the tutorial is already done"
	end
	World.markDirty(session)
	return true, nil
end

return TutorialService
