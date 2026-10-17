--!strict
--[[
	Snapshot (pure)

	Builds the `State` payload (Types.State, CONTRACT.md §5.1) for one
	session and decides when to push it: only when dirty, at most once per
	STATE_MIN_INTERVAL. Income marks sessions dirty every second, so earning
	players get at least one push a second.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Appraise = if Shared then require(Shared.Appraise) else require("../shared/Appraise")
local Codes = if Shared then require(Shared.Codes) else require("../shared/Codes")
local Collection = if Shared then require(Shared.Collection) else require("../shared/Collection")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Weekend = if Shared then require(Shared.Weekend) else require("../shared/Weekend")
local Goals = if Shared then require(Shared.Goals) else require("../shared/Goals")
local Quests = if Shared then require(Shared.Quests) else require("../shared/Quests")
local Perks = if Shared then require(Shared.Perks) else require("../shared/Perks")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local PlotSkins = if Shared then require(Shared.PlotSkins) else require("../shared/PlotSkins")
local Progression = if Shared then require(Shared.Progression) else require("../shared/Progression")
local Shop = if Shared then require(Shared.Shop) else require("../shared/Shop")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local StealAlert = if Shared then require(Shared.StealAlert) else require("../shared/StealAlert")
local TutorialProgress = if Shared then require(Shared.TutorialProgress) else require("../shared/TutorialProgress")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")
local Upgrades = if Shared then require(Shared.Upgrades) else require("../shared/Upgrades")
local MysteryEgg = if Shared then require(Shared.MysteryEgg) else require("../shared/MysteryEgg")
local Carry = if script then require(script.Parent.Carry) else require("./Carry")
local Revenge = if script then require(script.Parent.Revenge) else require("./Revenge")
local Spawner = if script then require(script.Parent.Spawner) else require("./Spawner")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local Snapshot = {}

-- tiers x (None + mutations + combos with FEATURES.MutationStacking) x patterns x eyes.
-- A stacked slime counts as its primary mutation, so the total stays fixed.
Snapshot.DEX_TOTAL = Config.MAX_TIER
	* (#Config.MUTATIONS + 1 + (if Config.FEATURES.MutationStacking then #Config.COMBOS else 0))
	* #Config.PATTERNS
	* #Config.EYES

function Snapshot.build(world: World, session: Session, now: number): Types.State
	local data = session.data
	local rebirths = data.rebirths

	local slimes: { Types.SlimeView } = {}
	for _, slime in data.slimes do
		local carrier = world.carriedBy[slime.id]
		table.insert(slimes, {
			slime = slime,
			income = if carrier then 0 else PlayerData.slimeIncome(data, slime),
			sellPrice = Economy.sellPrice(slime, rebirths),
			appraiseCost = if Config.FEATURES.Appraise then Appraise.cost(slime, rebirths) else nil,
			stolenBy = carrier,
		})
	end

	local carrying: Types.CarryView? = nil
	local carry = session.carry
	if carry then
		carrying = {
			slime = carry.slime,
			kind = carry.kind,
			ownerUserId = carry.ownerUserId,
			startedAt = carry.timer.startedAt,
			escapeAt = carry.timer.escapeAt,
			walkSpeed = Carry.walkSpeed(session, now),
		}
	end

	local dex = {}
	for key in data.dex do
		table.insert(dex, key)
	end
	table.sort(dex)

	local rainActive, endsAt, nextAt = Spawner.rain(world, now)
	local bossActive, bossEndsAt = Spawner.boss(world)
	local canRebirth = Progression.canRebirth(data)
	local income = World.incomeOf(world, session)
	local dailyAvailable = Progression.dailyAvailable(data.daily, now)
	local nextStreak = if data.daily.lastDay == Progression.dayNumber(now) - 1 then data.daily.streak + 1 else 1
	local dailyDay = math.clamp(if dailyAvailable then nextStreak else data.daily.streak, 1, Config.DAILY_STREAK_CAP)

	return {
		serverTime = now,
		plotIndex = session.plotIndex,
		cash = data.cash,
		incomePerSec = income,
		rebirths = rebirths,
		rebirthMultiplier = Economy.rebirthMultiplier(rebirths),
		rebirthCost = Economy.rebirthCost(rebirths),
		canRebirth = canRebirth,
		rebirthSlime = Progression.requiredSlime(data),
		padsUnlocked = data.padsUnlocked,
		padsMax = Config.PADS_MAX,
		nextPadCost = Economy.padCost(data.padsUnlocked),
		slimes = slimes,
		favoriteId = data.favoriteId,
		lockUntil = session.lockUntil,
		lockStartedAt = session.lockStartedAt,
		lockCost = Economy.lockCost(income) * Revenge.lockMultiplier(world, session.userId, now),
		lockDuration = Steal.lockDuration(rebirths, data.lockLevel),
		carrying = carrying,
		rain = { active = rainActive, endsAt = endsAt, nextAt = nextAt },
		dex = dex,
		dexTotal = Snapshot.DEX_TOTAL,
		daily = {
			available = dailyAvailable,
			streak = data.daily.streak,
			amount = Progression.dailyAmount(dailyDay, rebirths),
			day = dailyDay,
		},
		codes = Codes.view(data),
		shop = Shop.view(data),
		egg = MysteryEgg.view(data, session.egg),
		tutorialStep = TutorialProgress.current(data),
		walkSpeed = Shop.walkSpeed(data),
		tutorialStepId = TutorialProgress.currentId(data),
		incomeMultiplier = Perks.incomeMultiplier(data),
		petPerk = Perks.petPassive(data),
		weekend = Weekend.view(now),
		plotSkin = if Config.FEATURES.PlotSkins then PlotSkins.current(data) else nil,
		plotSkins = if Config.FEATURES.PlotSkins then PlotSkins.view(data) else nil,
		stealAway = if Config.FEATURES.StealAlerts then StealAlert.summary(session.awayLog) else nil,
		friends = { count = session.friends or 0, bonus = data.friendBonus or 0 },
		rebirthTitle = Perks.title(rebirths),
		rebirthTiers = Snapshot.rebirthTiers(rebirths),
		nextRebirthTier = Snapshot.nextRebirthTier(rebirths),
		upgrades = Upgrades.view(data),
		goals = Goals.view(data),
		dailyQuests = Quests.view(data, now),
		dexRewards = Collection.view(data),
		dexBonus = Perks.dexBonus(data),
		stats = {
			caught = data.stats.caught,
			merges = data.stats.merges,
			locks = data.stats.locks,
			sold = data.stats.sold,
			stolen = data.totalStolen,
			earned = data.totalEarned,
			rebirths = rebirths,
		},
		boss = { active = bossActive, endsAt = bossEndsAt },
		modifier = {
			name = world.modifier.name,
			label = world.modifier.label,
			luck = world.modifier.luck,
			mutation = world.modifier.mutation,
			endsAt = world.modifierEndsAt,
			icon = if world.adminEvent then world.adminEvent.def.icon else nil,
		},
	}
end

function Snapshot.rebirthTiers(rebirths: number): { Types.RebirthTierView }
	local out = {}
	for _, tier in Config.REBIRTH_TIERS do
		table.insert(out, {
			rebirths = tier.rebirths,
			title = tier.title,
			text = Perks.tierText(tier),
			unlocked = rebirths >= tier.rebirths,
		})
	end
	return out
end

function Snapshot.nextRebirthTier(rebirths: number): Types.NextRebirthTier?
	local tier = Perks.nextTier(rebirths)
	if not tier then
		return nil
	end
	return { rebirths = tier.rebirths, title = tier.title, text = Perks.tierText(tier) }
end

-- True when a push is due; the caller then sends `build` and calls `pushed`.
function Snapshot.due(session: Session, now: number): boolean
	return session.dirty and now - session.lastPushAt >= Config.STATE_MIN_INTERVAL
end

function Snapshot.pushed(session: Session, now: number)
	session.dirty = false
	session.lastPushAt = now
end

return Snapshot
