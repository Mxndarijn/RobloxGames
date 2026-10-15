--!strict
--[[
	PlotClaim (pure)

	The "Claim plot" ClaimPrompt on a free plot's BuyStand (CONTRACT.md §9.1).
	Plots stay auto-assigned on join, so the prompt mostly explains that and
	sends the player home:
	  * player with a plot: "home" (the adapter teleports them onto their Base),
	    or "carrying" (no teleport: that would deposit a stolen slime for free);
	  * player without a plot yet (data still loading): "reserved", and
	    Sessions.join gives them this plot if it's still free;
	  * otherwise "taken".
	Every outcome queues a Notify for the player.
]]

local World = if script then require(script.Parent.World) else require("./World")

export type Prompt = { actionText: string, objectText: string, enabled: boolean }
export type Outcome = "home" | "carrying" | "reserved" | "taken"

local PlotClaim = {}

PlotClaim.ACTION_TEXT = "Claim plot"
PlotClaim.OBJECT_TEXT = "Free plot: everyone gets one on join"

-- What plot `plotIndex`'s ClaimPrompt shows: enabled only while the plot is free.
function PlotClaim.describe(world: World.World, plotIndex: number): Prompt
	local userId = world.plots[plotIndex]
	local owned = userId ~= nil and world.sessions[userId] ~= nil
	return { actionText = PlotClaim.ACTION_TEXT, objectText = PlotClaim.OBJECT_TEXT, enabled = not owned }
end

--[[
	`userId` triggered plot `plotIndex`'s ClaimPrompt. Returns the outcome and
	the plot it refers to (their own plot for "home" / "carrying").
]]
function PlotClaim.claim(world: World.World, userId: number, plotIndex: number): (Outcome, number)
	local session = world.sessions[userId]
	if session then
		local own = session.plotIndex
		if session.carry then
			World.notify(world, userId, `You're carrying a slime: walk it home to Plot {own}`, "info", nil)
			return "carrying", own
		end
		World.notify(
			world,
			userId,
			`You already own Plot {own}: every player gets one when they join. Taking you there!`,
			"info",
			nil
		)
		return "home", own
	end
	if world.plots[plotIndex] == nil and plotIndex >= 1 and plotIndex <= world.plotCount then
		for other, index in world.claims do
			if index == plotIndex and other ~= userId then
				World.notify(world, userId, `Plot {plotIndex} is taken`, "info", nil)
				return "taken", plotIndex
			end
		end
		world.claims[userId] = plotIndex
		World.notify(world, userId, `Plot {plotIndex} is yours once your data loads`, "good", nil)
		return "reserved", plotIndex
	end
	World.notify(world, userId, `Plot {plotIndex} is taken`, "info", nil)
	return "taken", plotIndex
end

return PlotClaim
