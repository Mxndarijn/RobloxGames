--!strict
--[[
	BrokeTopUp (pure)

	The safety net against a dead end: a player with no slime and too little cash to buy one earns nothing and can
	buy nothing. GameLoop checks every session once a second. A player is broke when they
	- own no slime at all: no pad or hotbar slime, no Mystery Egg (it hatches into income), nothing in the merge
	  vat (the brew gives a slime back) and no slime a thief is carrying away right now (it may still escape home;
	  if the steal lands, the next check sees it gone),
	- carry no slime themselves (a wild or stolen slime on its way to their base), and
	- have less than Config.BROKE_TOPUP_CASH in cash plus uncollected cash pad piles.
	A fixed bar is used instead of "less than the cheapest wild slime": the fountain's prices change from drop to
	drop, and a player who can buy one Common but would be broke again after one theft still needs the push.
	Once broke for BROKE_TOPUP_GRACE_SECONDS in a row (so a purchase or a steal in progress settles first), their
	cash goes up to BROKE_TOPUP_CASH (a top-up, not a bonus on top) with one toast, at most once per
	BROKE_TOPUP_COOLDOWN_SECONDS. The top-up itself ends the broke spell, so an AFK player gets it once.
	State is runtime only (session.brokeSince, brokeToppedAt, brokeTopUps): a rejoin starts the clocks again.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local CashPads = if Shared then require(Shared.CashPads) else require("../shared/CashPads")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local BrokeTopUp = {}

BrokeTopUp.TEXT = `Here's {Economy.formatNumber(Config.BROKE_TOPUP_CASH)} cash to get you going!`

-- True when `session` has no slime, carries none and has less than BROKE_TOPUP_CASH (cash pads included).
function BrokeTopUp.isBroke(session: Session): boolean
	local data = session.data
	if session.carry or #data.slimes > 0 then
		return false
	end
	return data.cash + CashPads.total(data) < Config.BROKE_TOPUP_CASH
end

-- Tops `session` up when it has been broke long enough. Returns the cash given (0 = none).
function BrokeTopUp.check(world: World, session: Session, now: number): number
	if not BrokeTopUp.isBroke(session) then
		session.brokeSince = nil
		return 0
	end
	local since = session.brokeSince
	if not since or since > now then -- a new spell, or the clock stepped back
		session.brokeSince = now
		return 0
	end
	if now - since < Config.BROKE_TOPUP_GRACE_SECONDS then
		return 0
	end
	local last = session.brokeToppedAt
	if last and last <= now and now - last < Config.BROKE_TOPUP_COOLDOWN_SECONDS then
		return 0
	end
	local data = session.data
	local given = math.max(0, Config.BROKE_TOPUP_CASH - CashPads.total(data) - data.cash)
	data.cash += given
	session.brokeSince = nil
	session.brokeToppedAt = now
	session.brokeTopUps = (session.brokeTopUps or 0) + 1
	World.markDirty(session)
	World.notify(world, session.userId, BrokeTopUp.TEXT, "good", "Goal")
	-- A custom event, not an economy source: the dashboard's 20 transaction names are all taken.
	World.track(world, session.userId, {
		op = "event",
		name = "BrokeTopUp",
		value = given,
		fields = { `TopUps - {if session.brokeTopUps >= 3 then "3+" else tostring(session.brokeTopUps)}` },
	})
	return given
end

function BrokeTopUp.step(world: World, now: number)
	for _, session in world.sessions do
		BrokeTopUp.check(world, session, now)
	end
end

return BrokeTopUp
