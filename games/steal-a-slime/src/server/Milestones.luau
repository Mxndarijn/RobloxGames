--!strict
--[[
	Milestones (pure)

	Pays goal stages (Shared.Goals) and Slimedex milestones (Shared.Collection)
	the moment they are reached (CONTRACT.md §8.6, §8.8): GameLoop checks every
	session once a second and Sessions.join checks on load, so old saves are
	paid retroactively. Each payment is a Notify with sound "Goal".
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Collection = if Shared then require(Shared.Collection) else require("../shared/Collection")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Goals = if Shared then require(Shared.Goals) else require("../shared/Goals")
local World = if script then require(script.Parent.World) else require("./World")

local Milestones = {}

-- Returns how many rewards were paid.
function Milestones.check(world: World.World, session: World.Session): number
	local n = 0
	for _, paid in Goals.check(session.data) do
		n += 1
		World.notify(
			world,
			session.userId,
			`Goal complete: {paid.title}! +${Economy.formatNumber(paid.reward)}`,
			"good",
			"Goal"
		)
	end
	for _, paid in Collection.check(session.data) do
		n += 1
		World.notify(
			world,
			session.userId,
			`Slimedex {paid.count}: +${Economy.formatNumber(paid.reward)} and +{math.floor(paid.bonus * 100 + 0.5)}% income!`,
			"good",
			"Goal"
		)
	end
	if n > 0 then
		World.markDirty(session)
	end
	return n
end

function Milestones.step(world: World.World)
	for _, session in world.sessions do
		Milestones.check(world, session)
	end
end

return Milestones
