--!strict
--[[
	Income (pure)

	Pays every session's plot income (Economy.tickIncome, fractional cash
	kept in `incomeRemainder`). Slimes being carried away pay nothing.
	`applyOffline` pays OFFLINE_RATE of income (the Offline2x Game Pass rate,
	`data.passOfflineRate`, when owned) for at most OFFLINE_CAP_SECONDS since the
	last save (Economy.offlineIncome) and records the payout in
	`data.offlineDouble` for the Exclusive Shop's "Double it".
	With FEATURES.CashPads on, both go onto the slimes' cash pads instead of
	into cash (CashPads); the owner collects them there (CashPadService).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local CashPads = if Shared then require(Shared.CashPads) else require("../shared/CashPads")
local Codes = if Shared then require(Shared.Codes) else require("../shared/Codes")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local Growth = if Shared then require(Shared.Growth) else require("../shared/Growth")
local Perks = if Shared then require(Shared.Perks) else require("../shared/Perks")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Weekend = if Shared then require(Shared.Weekend) else require("../shared/Weekend")
local WelcomeBack = if Shared then require(Shared.WelcomeBack) else require("../shared/WelcomeBack")
local VatState = if Shared then require(Shared.VatState) else require("../shared/VatState")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local Income = {}

Income.MAX_TICK = 5 -- seconds: a stalled server doesn't pay a huge lump
-- FEATURES.CashPads: told once a session, while the tutorial runs, when Config.CASH_PAD.HINT_AT cash waits on the pads.
Income.CASH_PAD_HINT = "Your slimes' cash piles up on the gold pads in front of them. Walk over a pad to collect it!"

-- Call about once a second with the real elapsed time. `now` (unix seconds)
-- ends redeem-code boosts whose time is up and sets the x2 Weekend multiplier
-- (nil `now` = no weekend, so clock-free tests stay deterministic). `features` overrides Config.FEATURES (tests).
function Income.step(world: World, dt: number, now: number?, features: { [string]: any }?)
	local pads = CashPads.enabled(features)
	local seconds = math.clamp(dt, 0, Income.MAX_TICK)
	local carried = World.carriedSet(world)
	local weekend = if now then Weekend.multiplier(now) else 1
	for _, session in world.sessions do
		if now and Codes.expireBoost(session.data, now) then
			World.notify(world, session.userId, "Your income boost ended", "info", nil)
			World.markDirty(session)
		end
		session.data.weekendMult = if weekend > 1 then weekend else nil
		local skip = World.incomeSkip(world, session)
		Growth.advanceAll(session.data.slimes, seconds, carried)
		if pads then
			if CashPads.accrue(session.data, seconds, skip) > 0 then
				World.markDirty(session) -- State at least once a second while earning, as without the pads
			end
			local learning = session.data.tutorialStep ~= 0 -- veterans know the pads; only the tutorial gets the hint
			if learning and not session.cashPadHinted and CashPads.total(session.data) >= Config.CASH_PAD.HINT_AT then
				session.cashPadHinted = true
				World.notify(world, session.userId, Income.CASH_PAD_HINT, "info", nil)
			end
			continue
		end
		local perSec = PlayerData.incomePerSecond(session.data, skip)
		if perSec > 0 then
			local paid, remainder = Economy.tickIncome(0, session.incomeRemainder, perSec, seconds)
			session.incomeRemainder = remainder
			PlayerData.earn(session.data, paid)
			World.markDirty(session) -- State at least once a second while earning
		end
	end
end

-- The share of income paid while offline: the Offline2x Game Pass rate when owned, else Config.OFFLINE_RATE.
function Income.offlineRate(data: PlayerData.Data): number
	return math.max(data.passOfflineRate or 0, Config.OFFLINE_RATE)
end

-- Pays offline income (for at most the offline cap time) once, on load. Returns the amount paid, or piled onto the
-- cash pads with FEATURES.CashPads.
function Income.applyOffline(world: World, session: Session, now: number, features: { [string]: any }?): number
	local data = session.data
	local skip = VatState.lockedSet(data) -- brewing vat slimes earn nothing
	local rate = Income.offlineRate(data)
	if CashPads.enabled(features) then
		local piled = math.floor(CashPads.accrueOffline(data, data.lastOnline, now, skip, rate))
		session.offlineRate, session.offlinePaid = rate, piled
		if piled > 0 then
			data.offlineDouble = { cash = piled, at = now, used = false }
			World.notify(
				world,
				session.userId,
				`Your slimes earned ${Economy.formatNumber(piled)} while you were away! Walk over your cash pads to collect it.`,
				"good",
				"Cash"
			)
		end
		Income.applyOfflineGrowth(session, now, piled, true)
		return piled
	end
	local perSec = PlayerData.incomePerSecond(data, skip)
	local amount = Economy.offlineIncome(perSec, data.lastOnline, now, Perks.offlineCap(data), rate)
	session.offlineRate, session.offlinePaid = rate, amount
	if amount > 0 then
		PlayerData.earn(data, amount)
		data.offlineDouble = { cash = amount, at = now, used = false }
		World.notify(
			world,
			session.userId,
			`Your slimes earned ${Economy.formatNumber(amount)} while you were away!`,
			"good",
			"Cash"
		)
	end
	Income.applyOfflineGrowth(session, now, amount)
	return amount
end

-- Offline slime growth and the welcome-back report (`amount` = the offline cash earned, `onPads` = it waits on the cash pads).
function Income.applyOfflineGrowth(session: Session, now: number, amount: number, onPads: boolean?)
	local data = session.data
	local before = {}
	for _, slime in data.slimes do
		before[slime.id] = Genome.growthFraction(slime)
	end
	Growth.applyOffline(data.slimes, data.lastOnline, now)
	local grown = 0
	for _, slime in data.slimes do
		if Genome.growthFraction(slime) > (before[slime.id] or 0) then
			grown += 1
		end
	end
	session.welcome = WelcomeBack.report(data.lastOnline, now, amount, grown, onPads)
end

return Income
