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
local AudioSettings = if Shared then require(Shared.AudioSettings) else require("../shared/AudioSettings")
local Codes = if Shared then require(Shared.Codes) else require("../shared/Codes")
local Collection = if Shared then require(Shared.Collection) else require("../shared/Collection")
local Consumables = if Shared then require(Shared.Consumables) else require("../shared/Consumables")
local EggKind = if Shared then require(Shared.EggKind) else require("../shared/EggKind")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Weekend = if Shared then require(Shared.Weekend) else require("../shared/Weekend")
local EventSecrets = if Shared then require(Shared.EventSecrets) else require("../shared/EventSecrets")
local Goals = if Shared then require(Shared.Goals) else require("../shared/Goals")
local Quests = if Shared then require(Shared.Quests) else require("../shared/Quests")
local Perks = if Shared then require(Shared.Perks) else require("../shared/Perks")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local PlotSkins = if Shared then require(Shared.PlotSkins) else require("../shared/PlotSkins")
local Progression = if Shared then require(Shared.Progression) else require("../shared/Progression")
local Shop = if Shared then require(Shared.Shop) else require("../shared/Shop")
local SpeciesDex = if Shared then require(Shared.SpeciesDex) else require("../shared/SpeciesDex")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local StealAlert = if Shared then require(Shared.StealAlert) else require("../shared/StealAlert")
local TutorialProgress = if Shared then require(Shared.TutorialProgress) else require("../shared/TutorialProgress")
local Types = if Shared then require(Shared.Types) else require("../shared/Types")
local Upgrades = if Shared then require(Shared.Upgrades) else require("../shared/Upgrades")
local MysteryEgg = if Shared then require(Shared.MysteryEgg) else require("../shared/MysteryEgg")
local BossEvent = if script then require(script.Parent.BossEvent) else require("./BossEvent")
local Carry = if script then require(script.Parent.Carry) else require("./Carry")
local DexSources = if script then require(script.Parent.DexSources) else require("./DexSources")
local PvpService = if script then require(script.Parent.PvpService) else require("./PvpService")
local Revenge = if script then require(script.Parent.Revenge) else require("./Revenge")
local Spawner = if script then require(script.Parent.Spawner) else require("./Spawner")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local Snapshot = {}

function Snapshot.build(world: World, session: Session, now: number): Types.State
	local data = session.data
	local rebirths = data.rebirths

	local slimes: { Types.SlimeView } = {}
	for _, slime in data.slimes do
		local carrier = world.carriedBy[slime.id]
		table.insert(slimes, {
			slime = EggKind.mask(slime), -- an egg never shows the slime inside (contract/mystery-egg.md)
			income = if carrier then 0 else PlayerData.slimeIncome(data, slime),
			sellPrice = Economy.sellPrice(slime, rebirths),
			stolenBy = carrier,
		})
	end

	local carrying: Types.CarryView? = nil
	local carry = session.carry
	if carry then
		carrying = {
			slime = EggKind.mask(carry.slime),
			kind = carry.kind,
			ownerUserId = carry.ownerUserId,
			startedAt = carry.timer.startedAt,
			escapeAt = carry.timer.escapeAt,
			walkSpeed = Carry.walkSpeed(session, now),
		}
	end

	local rainActive, endsAt, nextAt = Spawner.rain(world, now)
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
		dex = SpeciesDex.view(data, now, DexSources),
		daily = {
			available = dailyAvailable,
			streak = data.daily.streak,
			amount = Progression.dailyAmount(dailyDay, rebirths),
			day = dailyDay,
		},
		codes = Codes.view(data),
		shop = Shop.view(data),
		egg = MysteryEgg.view(session.egg),
		consumables = Consumables.view(data, now, Config.FEATURES.Weather, world.potionUntil),
		pvp = PvpService.view(session, now),
		tutorialStep = TutorialProgress.current(data),
		walkSpeed = Shop.walkSpeed(data),
		tutorialStepId = TutorialProgress.currentId(data),
		incomeMultiplier = Perks.incomeMultiplier(data),
		petPerk = Perks.petPassive(data),
		weekend = Weekend.view(now),
		featuredSecret = EventSecrets.view(now),
		settings = if Config.FEATURES.Audio then AudioSettings.clean(data.settings) else nil,
		plotSkin = if Config.FEATURES.PlotSkins then PlotSkins.current(data) else nil,
		plotSkins = if Config.FEATURES.PlotSkins then PlotSkins.view(data) else nil,
		stealAway = if Config.FEATURES.StealAlerts then StealAlert.summary(session.awayLog) else nil,
		welcomeBack = session.welcome,
		hotbar = if data.hotbar then table.clone(data.hotbar) else nil,
		friends = { count = session.friends or 0, bonus = data.friendBonus or 0 },
		blessed = if data.ritualBonus and session.blessedUntil
			then { bonus = data.ritualBonus, endsAt = session.blessedUntil }
			else nil,
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
		boss = BossEvent.view(world, session, now),
		modifier = {
			name = world.modifier.name,
			label = world.modifier.label,
			luck = world.modifier.luck,
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
