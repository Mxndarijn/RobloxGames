--!strict
--[[
	Milestones (pure)

	Pays goal stages (Shared.Goals) and SlimeDex milestones (Shared.Collection)
	the moment they are reached (CONTRACT.md §8.6, §8.8): GameLoop checks every
	session once a second and Sessions.join checks on load, so old saves are
	paid retroactively. Each payment is a Notify with sound "Goal".
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Badges = if script then require(script.Parent.Badges) else require("./Badges")
local Collection = if Shared then require(Shared.Collection) else require("../shared/Collection")
local Quests = if Shared then require(Shared.Quests) else require("../shared/Quests")
local SpeciesDex = if Shared then require(Shared.SpeciesDex) else require("../shared/SpeciesDex")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Goals = if Shared then require(Shared.Goals) else require("../shared/Goals")
local World = if script then require(script.Parent.World) else require("./World")

local Milestones = {}

-- Returns how many rewards were paid. Also rolls the day's daily quests (they pay on claim, not here).
function Milestones.check(world: World.World, session: World.Session, now: number?): number
	local n = 0
	if Quests.sync(session.data, now or os.time(), session.userId) then
		World.markDirty(session)
	end
	for _, paid in Goals.check(session.data) do
		n += 1
		World.trackCash(world, session, "source", "Goal", paid.reward, paid.id)
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
		World.trackCash(world, session, "source", "DexMilestone", paid.reward)
		World.notify(
			world,
			session.userId,
			`SlimeDex {paid.count} {paid.ladder}: +${Economy.formatNumber(paid.reward)} and +{math.floor(
				paid.bonus * 100 + 0.5
			)}% income!`,
			"good",
			"Goal"
		)
	end
	if n > 0 then
		World.markDirty(session)
	end
	-- New SlimeDex species since the last check (the first check of a session only sets the baseline).
	local species = SpeciesDex.count(session.data)
	if session.dexSeen and species > session.dexSeen then
		World.track(world, session.userId, { op = "event", name = "SpeciesFound", value = species })
	end
	session.dexSeen = species
	return n
end

function Milestones.step(world: World.World, now: number?)
	for _, session in world.sessions do
		Milestones.check(world, session, now)
		Badges.check(world, session)
	end
end

return Milestones
