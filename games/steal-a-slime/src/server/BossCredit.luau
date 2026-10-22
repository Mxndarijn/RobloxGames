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
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local World = if script then require(script.Parent.World) else require("./World")

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
	The boss `slime` of `fight` was brought home by `carrier`. Every player on the server with at least
	Config.BOSS.WIN_SHARE of the top hits gets a win of that species; the carrier gets a haul; the top contributor
	(if still on the server) gets an MVP. Winners and the carrier count the species in their SlimeDex.
]]
function BossCredit.win(world: World, fight: BossFight.State, carrier: Session, slime: Genome.Slime, now: number)
	local top = BossFight.top(fight)
	for _, session in world.sessions do
		local won = BossBadges.record(
			session.data,
			{ kind = "win", species = fight.species, share = BossFight.share(fight, session.userId) }
		)
		if session.userId == carrier.userId then
			BossBadges.record(session.data, { kind = "haul" })
		end
		if top ~= nil and session.userId == top then
			BossBadges.record(session.data, { kind = "mvp" })
		end
		if won or session.userId == carrier.userId then
			PlayerData.discover(session.data, slime)
		end
		BossCredit.grant(world, session, now)
	end
end

return BossCredit
