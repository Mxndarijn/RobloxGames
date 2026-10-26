--!strict
--[[
	BossCredit (pure, contract/boss-event.md)

	Credits players for their part in a boss event: counts the event in `session.data.boss` (Shared.BossBadges),
	grants the boss badges it reaches, toasts each new one to that player and marks the session dirty.
	`win` credits everyone when the boss is brought home: wins for players with enough of the hits, a haul for the
	carrier, an MVP for the top contributor.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local BossBadges = if Shared then require(Shared.BossBadges) else require("../shared/BossBadges")
local BossFight = if Shared then require(Shared.BossFight) else require("../shared/BossFight")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local World = if script then require(script.Parent.World) else require("./World")

local BOSS = Config.BOSS

type World = World.World
type Session = World.Session

local BossCredit = {}

-- Grants every boss badge `session` has reached and toasts the new ones. Returns the new keys.
function BossCredit.grant(world: World, session: Session, now: number): { string }
	local fresh = BossBadges.grant(session.data, now)
	for _, key in fresh do
		local badge = BossBadges.get(key)
		World.notify(world, session.userId, `Badge earned: {if badge then badge.name else key}!`, "badge", "Goal")
	end
	if #fresh > 0 then
		World.markDirty(session)
	end
	return fresh
end

-- Counts `event` for `session` and grants what it reaches. Returns whether the event counted.
function BossCredit.record(world: World, session: Session, event: BossBadges.Event, now: number): boolean
	local counted = BossBadges.record(session.data, event)
	if counted then
		BossCredit.grant(world, session, now)
	end
	return counted
end

--[[
	The boss `slime` of `fight` was brought home by `carrier`. Only the carrier wins: a win of that species (its boss
	badge), a haul and the species in their SlimeDex. The top contributor (if still on the server) counts an MVP and
	gets the Boss MVP boost: +BOSS.MVP_BONUS income for BOSS.MVP_SECONDS (data.mvpBonus, session.mvpUntil).
]]
function BossCredit.win(world: World, fight: BossFight.State, carrier: Session, slime: Genome.Slime, now: number)
	local top = BossFight.top(fight)
	for _, session in world.sessions do
		local isCarrier = session.userId == carrier.userId
		if isCarrier then
			BossBadges.record(session.data, { kind = "win", species = fight.species })
			BossBadges.record(session.data, { kind = "haul" })
		end
		if top ~= nil and session.userId == top then
			BossBadges.record(session.data, { kind = "mvp" })
			session.data.mvpBonus = BOSS.MVP_BONUS
			session.mvpUntil = now + BOSS.MVP_SECONDS
			World.markDirty(session)
			World.notify(
				world,
				session.userId,
				`Boss MVP! +{math.floor(BOSS.MVP_BONUS * 100 + 0.5)}% income for {math.floor(
					BOSS.MVP_SECONDS / 60 + 0.5
				)} min`,
				"good",
				"BossMvp"
			)
		end
		if isCarrier then
			PlayerData.discover(session.data, slime)
		end
		BossCredit.grant(world, session, now)
	end
end

-- Ends every Boss MVP boost that has run out by `now`. Call every step (GameLoop).
function BossCredit.expire(world: World, now: number)
	for _, session in world.sessions do
		local untilAt = session.mvpUntil
		if untilAt and now >= untilAt then
			session.mvpUntil = nil
			session.data.mvpBonus = nil
			World.markDirty(session)
			World.notify(world, session.userId, "Your Boss MVP income boost ended", "info", nil)
		end
	end
end

return BossCredit
