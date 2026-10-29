--!strict
--[[
	Carry (pure)

	Picking slimes up (the ProximityPrompt on each slime's Body calls `grab`),
	carrying one at a time, depositing on your own plot (`deposit`, called
	when the carrier enters their HomeZone) and dropping.

	* Wild slime: free or costs its price, charged on every grab (a dropped
	  slime costs its price again, even for whoever paid). Dropped -> it
	  lands where the carrier stood. With FEATURES.Parade it then walks back
	  to the lane and rejoins the flow with its lifetime kept
	  (contract/slime-walk.md); otherwise its lifetime restarts there.
	* Pad slime of another player: StealService.steal. Dropped -> escapes home.
	* The hauled boss (contract/boss-event.md): grabbed only in the haul phase (top contributor first), carried at
	  the boss carry slow, dropped on the spot, and brought home to win (BossCredit.win; no pad needed).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local BossFight = if Shared then require(Shared.BossFight) else require("../shared/BossFight")
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local EggKind = if Shared then require(Shared.EggKind) else require("../shared/EggKind")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Fountain = if Shared then require(Shared.Fountain) else require("../shared/Fountain")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local GrabBlock = if Shared then require(Shared.GrabBlock) else require("../shared/GrabBlock")
local MysteryEgg = if Shared then require(Shared.MysteryEgg) else require("../shared/MysteryEgg")
local ParadeLane = if Shared then require(Shared.ParadeLane) else require("../shared/ParadeLane")
local Perks = if Shared then require(Shared.Perks) else require("../shared/Perks")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Shop = if Shared then require(Shared.Shop) else require("../shared/Shop")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local BossCredit = if script then require(script.Parent.BossCredit) else require("./BossCredit")
local CarryDrop = if script then require(script.Parent.CarryDrop) else require("./CarryDrop")
local GameAnalytics = if script then require(script.Parent.GameAnalytics) else require("./GameAnalytics")
local LuckyShow = if script then require(script.Parent.LuckyShow) else require("./LuckyShow")
local PvpFun = if script then require(script.Parent.PvpFun) else require("./PvpFun")
local PvpSlow = if script then require(script.Parent.PvpSlow) else require("./PvpSlow")
local StealAlert = if Shared then require(Shared.StealAlert) else require("../shared/StealAlert")
local SlimeGuard = if script then require(script.Parent.SlimeGuard) else require("./SlimeGuard")
local StealService = if script then require(script.Parent.StealService) else require("./StealService")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local Carry = {}

-- Bringing home a wild slime of this tier or higher tells every player (Mythic and Secret).
Carry.CATCH_ANNOUNCE_TIER = Config.SECRET_TIER - 1

-- Prompt ActionText for a slime as seen by a non-owner.
-- The depositor's worn Exclusive fanfare (contract/exclusive-shop.md §15) bursts on the slime that just landed.
function Carry.fanfare(world: World.World, session: World.Session, slimeId: string?)
	local id = session.data.wornStyles and session.data.wornStyles.fanfare
	if not id then
		return
	end
	for _, def in (Config.EXCLUSIVE_SHOP :: any).fanfares do
		if def.id == id then
			World.effect(world, def.burst, { slimeId = slimeId, userId = session.userId })
			return
		end
	end
end

function Carry.actionText(price: number?): string
	if price == nil then
		return "Steal"
	end
	if price <= 0 then
		return "Grab"
	end
	return `Buy ${Economy.formatNumber(price)}`
end

-- Hold needed on a slime prompt: only a free grab of a wild slime is instant
-- (costs nothing, takes nothing from anyone); buying or stealing needs a hold.
function Carry.holdDuration(price: number?): number
	if price ~= nil and price <= 0 then
		return 0
	end
	return Config.HOLD_CONFIRM_SECONDS
end

function Carry.grabWild(
	world: World,
	session: Session,
	slimeId: string,
	distance: number,
	now: number
): (boolean, string?)
	local wild = world.wild[slimeId]
	if not wild then
		return false, "slime is gone"
	end
	if session.carry then
		return false, "already carrying a slime"
	end
	if world.carriedBy[slimeId] then
		return false, "someone is already carrying it"
	end
	if wild.smashedAt then
		return false, "the egg smashed"
	end
	if distance ~= distance or distance > Config.STEAL_REACH then
		return false, "too far away"
	end
	local fight = if wild.boss and world.boss then world.boss.fight else nil
	if wild.boss then
		if not fight then
			return false, "slime is gone"
		end
		local priority = fight.priorityUserId
		local ok, reason =
			BossFight.canGrab(fight, session.userId, now, priority ~= nil and world.sessions[priority] ~= nil)
		if not ok then
			return false, reason
		end
		local move = wild.move
		if move and move.kind == "down" and now < move.at + Config.BOSS.SHRINK_SECONDS then
			return false, "it's still shrinking"
		end
	end
	local eggKind = EggKind.of(wild.slime)
	local eggBlock = if eggKind then EggKind.grabBlock(session.data.rebirths, eggKind) else nil
	if eggBlock then
		return false, eggBlock
	end
	if not wild.boss and not PlayerData.freePad(session.data) then
		return false, "plot full" -- it could not be brought home (and a paid one keeps your cash)
	end
	if not wild.boss then
		local need = GrabBlock.rebirthsFor(wild.slime)
		if session.data.rebirths < need then
			return false, `Rebirth {need} to grab this`
		end
	end
	if wild.price > 0 and not PlayerData.spend(session.data, wild.price) then
		return false, `need ${Economy.formatNumber(wild.price)}`
	end
	World.trackCash(world, session, "spend", "WildSlime", wild.price, nil, { GameAnalytics.tierField(wild.slime.tier) })
	-- wild.price stays: dropped, it costs the full price again, also for whoever paid (CONTRACT.md §Carry).
	wild.returning = nil
	wild.choreo = nil -- it walks back with a plain glide (contract/slime-life.md)
	session.carry = {
		slimeId = slimeId,
		kind = "wild",
		ownerUserId = nil,
		timer = Steal.newCarry("wild", EggKind.shownTier(wild.slime), now),
		slime = wild.slime,
		boss = if fight then true else nil,
	}
	world.carriedBy[slimeId] = session.userId
	World.markDirty(session)
	if fight then
		BossFight.grab(fight, session.userId)
		World.markAllDirty(world)
		World.notify(
			world,
			nil,
			`{session.name} grabbed {wild.slime.name}! Bonk them to make them drop it!`,
			"info",
			nil
		)
	end
	World.tutorial(world, session, "Grab")
	return true, nil
end

-- ProximityPrompt entry point: wild slimes are grabbed, pad slimes stolen.
function Carry.grab(world: World, userId: number, slimeId: string, distance: number, now: number): (boolean, string?)
	local session = World.session(world, userId)
	if not session then
		return false, "still loading"
	end
	if now - session.lastDropAt < Config.DROP_PICKUP_COOLDOWN then
		return false, "you just dropped a slime"
	end
	if world.wild[slimeId] then
		return Carry.grabWild(world, session, slimeId, distance, now)
	end
	return StealService.steal(world, session, slimeId, distance, now, SlimeGuard.stealBlock(world, userId, now))
end

-- The boss carrier got home: the fight is won: the carrier wins, helpers are credited (BossCredit.win). The boss slime is
-- removed; it never joins anyone's slimes.
function Carry.depositBoss(world: World, session: Session, carry: World.CarryState, now: number): (boolean, string?)
	world.wild[carry.slimeId] = nil
	world.carriedBy[carry.slimeId] = nil
	session.carry = nil
	local fight = world.boss and world.boss.fight
	if fight then
		BossFight.win(fight, session.userId, now)
	end
	World.markAllDirty(world)
	World.notify(world, nil, `{session.name} brought {carry.slime.name} home!`, "good", "Announce")
	World.notify(world, session.userId, `You brought {carry.slime.name} home!`, "good", "Deposit")
	if fight then
		BossCredit.win(world, fight, session, carry.slime, now)
	end
	World.effect(world, "Collect", { userId = session.userId })
	Carry.fanfare(world, session, carry.slimeId)
	return true, nil
end

--[[
	The carrier reached their own HomeZone. Wild slimes go on a free pad;
	stolen ones move to the thief with Steal.complete. A full plot keeps the
	slime in your arms. A stolen slime goes home instead when either player's
	save is no longer writable (World.canSave).
]]
-- Server toast when a Mythic or Secret wild slime is brought home ("Merijn caught Cosmo!"), else nil.
function Carry.catchText(playerName: string, slime: Genome.Slime): string?
	if slime.egg or slime.tier < Carry.CATCH_ANNOUNCE_TIER then
		return nil
	end
	return `{playerName} caught {slime.name}!`
end

function Carry.deposit(world: World, userId: number, now: number?): (boolean, string?)
	local session = World.session(world, userId)
	local carry = session and session.carry
	if not session or not carry then
		return false, "not carrying"
	end
	local name = Genome.displayName(carry.slime)
	if carry.boss then
		return Carry.depositBoss(world, session, carry, now or 0)
	end
	if carry.kind == "wild" then
		if not PlayerData.freePad(session.data) then
			return false, "plot full"
		end
		world.wild[carry.slimeId] = nil
		world.carriedBy[carry.slimeId] = nil
		session.carry = nil
		local slime = carry.slime
		slime.pad = nil
		-- Lucky Charm (Perks.luckChance): one rarity higher on the way home, as a species of that rarity
		-- (Genome.promote). Never an egg: its slime is sealed.
		local egg = slime.egg ~= nil
		-- only into a rarity this player may already grab (CATCH_REBIRTHS), so luck never skips the ladder
		local nextOpen = slime.tier < Config.MAX_TIER
			and session.data.rebirths >= (Config.CATCH_REBIRTHS[slime.tier + 1] or 0)
		if not egg and nextOpen and world.rng:float() < Perks.luckChance(session.data) then
			local before = Genome.copy(slime)
			Genome.promote(slime, world.rng:float())
			LuckyShow.record(world, userId, before, slime, now)
			name = Genome.displayName(slime)
		end
		if now then
			MysteryEgg.startIncubating(slime, now)
		end
		PlayerData.addSlime(session.data, slime)
		session.data.stats.caught += 1
		World.markDirty(session)
		if egg then
			local kind = EggKind.of(slime)
			local minutes = if kind then math.ceil(kind.hatchSeconds / 60) else 0
			World.notify(
				world,
				userId,
				`{name} is incubating! It hatches in {minutes} min (faster while you're home).`,
				"good",
				"Deposit"
			)
		else
			World.notify(world, userId, `{name} joined your plot!`, "good", "Deposit")
		end
		local caught = Carry.catchText(session.name, slime)
		if caught then
			World.notify(world, nil, caught, "info", nil)
		end
		World.effect(world, "Collect", { userId = userId })
		World.track(
			world,
			userId,
			{ op = "event", name = "SlimeCaught", fields = { GameAnalytics.tierField(slime.tier) } }
		)
		Carry.fanfare(world, session, slime.id)
		World.tutorial(world, session, "Deposit")
		return true, nil
	end

	local owner = if carry.ownerUserId then World.session(world, carry.ownerUserId) else nil
	if not owner then
		session.carry = nil
		world.carriedBy[carry.slimeId] = nil
		World.markDirty(session)
		return false, "slime is gone"
	end
	-- A save that stopped being writable since the grab (lost lock, ...) would dupe or lose the slime: send it home.
	if not World.canSave(world, userId) or not World.canSave(world, owner.userId) then
		StealService.escape(world, session, now or 0, "unsaved")
		return false, "can't be saved"
	end
	local ok, result = Steal.complete(owner.data, session.data, carry.slimeId)
	if not ok then
		return false, result :: string
	end
	if now then
		SlimeGuard.recordSteal(world, userId, owner, result :: Genome.Slime, now)
	end
	session.carry = nil
	world.carriedBy[carry.slimeId] = nil
	World.markDirty(session)
	World.markDirty(owner)
	if Config.FEATURES.StealAlerts then
		StealAlert.record(owner.data.stealLog, session.name, name, os.time())
	end
	World.track(world, userId, {
		op = "event",
		name = "StealDone",
		fields = { GameAnalytics.tierField((result :: Genome.Slime).tier) },
	})
	World.notify(world, userId, `You stole a {name}!`, "good", "Stolen")
	World.notify(world, owner.userId, `{session.name} has stolen one of your slimes`, "bad", "Stolen")
	World.effect(world, "Collect", { userId = userId })
	Carry.fanfare(world, session, carry.slimeId)
	World.tutorial(world, session, "Deposit")
	return true, nil
end

-- Ends any carry without a deposit (CarryDrop.release: wild lands at `position`, the boss lies there, stolen escapes).
Carry.release = CarryDrop.release

-- The walk back planned at `startAt` for a slime nobody carries, or nil (a later drop has its own, or it arrived).
local function walking(world: World, slimeId: string, startAt: number, now: number): (World.Wild?, ParadeLane.Return?)
	local wild = world.wild[slimeId]
	local plan = wild and wild.returning
	if not wild or not plan or plan.startAt ~= startAt or world.carriedBy[slimeId] ~= nil or now >= plan.arriveAt then
		return nil, nil
	end
	return wild, plan
end

--[[
	Swaps a dropped slime's walk back for `route` (ParadeLane.reroute): the path the server found round walls, off a
	ledge, through doorways, or a new one when something got in its way. Any time while it walks, as often as needed:
	`route` starts with the points it already walked (ParadeLane.walkedRoute), so it carries on from where it is.
	Only the walk planned at `startAt`, never a carried slime. Its lane times follow the new length. False when
	nothing changed.
]]
function Carry.replan(world: World, slimeId: string, startAt: number, route: { number }, now: number): boolean
	local wild, plan = walking(world, slimeId, startAt, now)
	if not wild or not plan or #route < 2 then
		return false
	end
	local walk = ParadeLane.reroute(plan, route)
	wild.returning = walk
	wild.spawnedAt, wild.expiresAt = ParadeLane.rejoin(walk.s, Fountain.wildLifetime(wild.slime), walk.arriveAt)
	return true
end

--[[
	A slime with no way back (boxed in, nothing clear to walk) stops walking and is on the lane at once, at the merge
	point its walk was headed for (the adapter puffs it away and back). Same rules as replan. False when nothing
	changed.
]]
function Carry.pop(world: World, slimeId: string, startAt: number, now: number): boolean
	local wild, plan = walking(world, slimeId, startAt, now)
	if not wild or not plan then
		return false
	end
	wild.returning = nil
	wild.position = nil
	wild.spawnedAt, wild.expiresAt = ParadeLane.rejoin(plan.s, Fountain.wildLifetime(wild.slime), now)
	return true
end

-- Ends carries of a slime that no longer exists (sold, merged, wiped).
function Carry.cancelMissing(world: World)
	for slimeId, carrierId in world.carriedBy do
		local carrier = World.session(world, carrierId)
		local carry = carrier and carrier.carry
		local exists = world.wild[slimeId] ~= nil or World.ownerOf(world, slimeId) ~= nil
		if not exists or not carry or carry.slimeId ~= slimeId then
			world.carriedBy[slimeId] = nil
			if carrier and carry and carry.slimeId == slimeId then
				carrier.carry = nil
				World.markDirty(carrier)
			end
		end
	end
end

-- Value of the Player attribute `Carrying` (CONTRACT.md §5.2): the carried slime id, or nil.
function Carry.carryingId(world: World, userId: number): string?
	local session = World.session(world, userId)
	local carry = session and session.carry
	return carry and carry.slimeId
end

-- WalkSpeed while carrying: the carry slowdown applies to the player's own base speed
-- (the Speed Coil only counts while held, and carrying puts tools away, CONTRACT.md §8.10).
-- Strong Arms (Perks.carrySlowFactor) shrinks the slowdown.
-- The hauled boss is the exception: BASE_WALK_SPEED x (1 - BOSS.CARRY_SLOW), no Speed Coil, no Strong Arms.
function Carry.walkSpeed(session: Session): number
	local carry = session.carry
	local base = Shop.walkSpeed(session.data, session.coilHeld)
	if not carry then
		return base
	end
	if carry.boss then
		return Config.BASE_WALK_SPEED * (1 - Config.BOSS.CARRY_SLOW)
	end
	return base * (1 - Steal.carrySlow(carry.timer) * Perks.carrySlowFactor(session.data))
end

-- The WalkSpeed the server enforces right now (Player attribute TargetWalkSpeed).
-- PvP holds / slows (PvpSlow: Goo Traps, Goo Blasters; PvpFun: the Goo Balloon slow; FEATURES.PvP, CONTRACT.md §26)
-- multiply in; 1 with the flag off.
function Carry.targetWalkSpeed(session: Session, now: number): number
	local speed = if session.carry then Carry.walkSpeed(session) else Shop.walkSpeed(session.data, session.coilHeld)
	local goo = session.bossSlow -- a boss goo puddle (BossEvent)
	local bossFactor = if goo and now < goo.untilTime then goo.factor else 1
	return speed * PvpSlow.walkFactor(session, now) * PvpFun.walkFactor(session, now) * bossFactor
end

return Carry
