--!strict
--[[
	Income (pure)

	Pays every session's plot income (Economy.tickIncome, fractional cash
	kept in `incomeRemainder`). Slimes being carried away pay nothing.
	`applyOffline` pays OFFLINE_RATE of income for at most
	OFFLINE_CAP_SECONDS since the last save (Economy.offlineIncome).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Codes = if Shared then require(Shared.Codes) else require("../shared/Codes")
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

-- Call about once a second with the real elapsed time. `now` (unix seconds)
-- ends redeem-code boosts whose time is up and sets the x2 Weekend multiplier
-- (nil `now` = no weekend, so clock-free tests stay deterministic).
function Income.step(world: World, dt: number, now: number?)
	local seconds = math.clamp(dt, 0, Income.MAX_TICK)
	local carried = World.carriedSet(world)
	local weekend = if now then Weekend.multiplier(now) else 1
	for _, session in world.sessions do
		if now and Codes.expireBoost(session.data, now) then
			World.notify(world, session.userId, "Your income boost ended", "info", nil)
			World.markDirty(session)
		end
		session.data.weekendMult = if weekend > 1 then weekend else nil
		local perSec = PlayerData.incomePerSecond(session.data, World.incomeSkip(world, session))
		Growth.advanceAll(session.data.slimes, seconds, carried)
		if perSec > 0 then
			local paid, remainder = Economy.tickIncome(0, session.incomeRemainder, perSec, seconds)
			session.incomeRemainder = remainder
			PlayerData.earn(session.data, paid)
			World.markDirty(session) -- State at least once a second while earning
		end
	end
end

-- Pays capped offline income once, on load. Returns the amount paid.
function Income.applyOffline(world: World, session: Session, now: number): number
	local data = session.data
	local perSec = PlayerData.incomePerSecond(data, VatState.lockedSet(data)) -- brewing vat slimes earn nothing
	local amount = Economy.offlineIncome(perSec, data.lastOnline, now, Perks.offlineCap(data))
	if amount > 0 then
		PlayerData.earn(data, amount)
		World.notify(
			world,
			session.userId,
			`Your slimes earned ${Economy.formatNumber(amount)} while you were away!`,
			"good",
			"Cash"
		)
	end
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
	session.welcome = WelcomeBack.report(data.lastOnline, now, amount, grown)
	return amount
end

return Income
