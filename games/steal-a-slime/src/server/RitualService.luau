--!strict
--[[
	RitualService (pure, FEATURES.CoopRitual, CONTRACT.md §13)

	Server-authoritative side of the plaza ritual circle. `step` takes where the players stand
	(the Roblox adapter reads HumanoidRootPart positions), keeps only players with a loaded session
	who have a slime (one on their plot, or one they carry), runs the Ritual state machine and
	applies the result: a completed ritual sets data.ritualBonus ("Blessed", runtime only, never
	saved) on each participant, and it is cleared when the blessing ends or the player leaves.
	Players never send anything; there is no remote.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Ritual = if Shared then require(Shared.Ritual) else require("../shared/Ritual")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World

local RitualService = {}

local function hasSlime(session: World.Session): boolean
	return next(session.data.slimes) ~= nil or (session.carry ~= nil and session.carry.slimeId ~= nil)
end

local function minutes(seconds: number): string
	return `{math.max(1, math.floor(seconds / 60 + 0.5))} min`
end

-- One server tick. Returns the Completion when a ritual finished (for the adapter's effects).
function RitualService.step(
	state: Ritual.State,
	world: World,
	positions: { Ritual.Candidate },
	now: number
): Ritual.Completion?
	local eligible: { Ritual.Candidate } = {}
	if Config.FEATURES.CoopRitual then
		for _, c in positions do
			local session = World.session(world, c.userId)
			if session and hasSlime(session) then
				table.insert(eligible, c)
			end
		end
	end
	local spotUsers = Ritual.occupants(state, eligible, now)
	local done, expired = Ritual.step(state, spotUsers, now)
	for _, userId in expired do
		local session = World.session(world, userId)
		if session then
			session.data.ritualBonus = nil
			World.markDirty(session)
			World.notify(world, userId, "Your Blessed income boost ended", "info", nil)
		end
	end
	if done then
		for _, userId in done.userIds do
			local session = World.session(world, userId)
			if session then
				session.data.ritualBonus = done.bonus
				World.markDirty(session)
				World.notify(
					world,
					userId,
					`Blessed! +{math.floor(done.bonus * 100 + 0.5)}% income for {minutes(done.untilAt - now)}`,
					"good",
					"Cash"
				)
			end
		end
	end
	return done
end

-- A player left: drop their blessing (their data goes with the session); the cooldown stays.
function RitualService.leave(state: Ritual.State, userId: number)
	Ritual.forget(state, userId)
end

return RitualService
