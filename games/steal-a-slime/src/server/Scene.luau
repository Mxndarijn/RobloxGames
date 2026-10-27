--!strict
--[[
	Scene (pure)

	Describes every slime model that should exist right now, so the Roblox
	adapter (WorldView) only has to reconcile Instances against this list:
	which models exist, where they sit, their attributes (CONTRACT.md §4) and
	their ProximityPrompt.

	State "Wild"     -> workspace.WildSlimes, prompt "Grab" / "Buy $<price>"
	State "Pad"      -> Plot_<plotIndex>.Slimes on Pad_<pad>, prompt "Steal"
	                    (enabled only while the plot is unlocked; hidden from
	                    the owner via hideFromUserId, CONTRACT.md §2)
	State "Carried"  -> welded to carrierUserId's character, no prompt
	State "Escaping" -> bouncing back to its pad, no prompt
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local DespawnTelegraph = if Shared then require(Shared.DespawnTelegraph) else require("../shared/DespawnTelegraph")
local EggKind = if Shared then require(Shared.EggKind) else require("../shared/EggKind")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local MysteryEgg = if Shared then require(Shared.MysteryEgg) else require("../shared/MysteryEgg")
local PlayerData = if Shared then require(Shared.PlayerData) else require("../shared/PlayerData")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local VatState = if Shared then require(Shared.VatState) else require("../shared/VatState")
local Carry = if script then require(script.Parent.Carry) else require("./Carry")
local LuckyShow = if script then require(script.Parent.LuckyShow) else require("./LuckyShow")
local PlotGuests = if script then require(script.Parent.PlotGuests) else require("./PlotGuests")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World

export type SlimeState = "Wild" | "Pad" | "Carried" | "Escaping"

export type Entry = {
	id: string,
	slime: Genome.Slime,
	state: SlimeState,
	ownerUserId: number, -- 0 = wild
	price: number?, -- wild only
	income: number, -- cash/sec for the label: the owner's PlayerData.slimeIncome, wild = no rebirths (contract/slime-labels.md)
	plotIndex: number?, -- Pad / Escaping / (Carried when stolen)
	pad: number?,
	carrierUserId: number?,
	wild: World.Wild?, -- wild only: landing angle / radius / dropped position
	promptText: string,
	promptHold: number, -- ProximityPrompt.HoldDuration (B1)
	promptEnabled: boolean,
	hideFromUserId: number?, -- the owner, on Steal prompts; nil = visible to everyone
	guestsOnly: string?, -- on a locked base's Steal prompts while it has guests: only they see it (PlotGuests.encode)
	boss: boolean, -- the boss of the boss event (model attribute Boss)
	bossScale: number?, -- model scale of the fighting boss (Config.BOSS.SCALE); nil = 1
	rare: number?, -- tier of an announced Legendary+ wild drop (model attribute RareSpawn)
	despawnAt: number?, -- uncarried wild only, inside the telegraph window (model attribute DespawnAt)
	hatchReady: boolean, -- a ready Mystery Egg resting on its owner's pad: the owner-only HatchPrompt is on
	hatchText: string?, -- a ready egg: the HatchPrompt ObjectText, the egg name and the owner's lucky meter
	hatch: World.Hatch?, -- a slime hatched moments ago: its show (model attributes HatchedAt / HatchedFrom / HatchLucky)
	lucky: World.Lucky?, -- a slime the Lucky Charm just upgraded: its show (model attributes LuckyAt / LuckyFromTier)
	key: string, -- changes whenever the model must be re-placed
}

local Scene = {}

function Scene.describe(world: World, now: number): { [string]: Entry }
	local entries: { [string]: Entry } = {}

	local bossPhase = if world.boss then world.boss.fight.phase else nil
	for id, wild in world.wild do
		-- A drop waiting for its slide slot (Spawner.slot) has no model yet.
		if wild.spawnedAt > now and not world.carriedBy[id] then
			continue
		end
		local carrier = world.carriedBy[id]
		local state: SlimeState = if carrier then "Carried" else "Wild"
		local boss = wild.boss == true
		-- The boss fights at BOSS.SCALE and never despawns on its own. When the meter fills it shrinks for
		-- BOSS.SHRINK_SECONDS (clients draw that), then it is carry size and grabbable.
		local move = wild.move
		local shrinking = boss
			and bossPhase == "haul"
			and move ~= nil
			and move.kind == "down"
			and now < move.at + Config.BOSS.SHRINK_SECONDS
		local bossScale = if boss and (bossPhase == "fight" or shrinking) then Config.BOSS.SCALE else nil
		entries[id] = {
			id = id,
			slime = wild.slime,
			state = state,
			ownerUserId = 0,
			price = if carrier then 0 else wild.price, -- only for sale while nobody carries it
			income = Economy.slimeIncome(wild.slime, 0),
			plotIndex = nil,
			pad = nil,
			carrierUserId = carrier,
			wild = wild,
			promptText = Carry.actionText(wild.price),
			promptHold = Carry.holdDuration(wild.price),
			promptEnabled = carrier == nil and (not boss or (bossPhase == "haul" and not shrinking)),
			hideFromUserId = nil,
			guestsOnly = nil,
			boss = boss,
			bossScale = bossScale,
			rare = wild.rare,
			despawnAt = if carrier or boss
				then nil
				else DespawnTelegraph.attributeValue(
					now,
					wild.expiresAt,
					Config.DESPAWN_TELEGRAPH_SECONDS,
					Config.FEATURES.DespawnTelegraph
				),
			hatchReady = false,
			hatchText = nil,
			hatch = nil,
			lucky = nil,
			key = `{state}|{carrier or 0}|{wild.position ~= nil}|{wild.spawnedAt}|{bossScale or 1}`,
		}
	end

	for _, session in world.sessions do
		local unlocked = not Steal.isLocked(session.lockUntil, now)
		-- A locked base with guests keeps its Steal prompts on, for the guests only (PromptHide hides them for the rest).
		local guestsOnly = if unlocked then nil else PlotGuests.encode(PlotGuests.list(world, session))
		for _, slime in session.data.slimes do
			local carrier = world.carriedBy[slime.id]
			local state: SlimeState = if carrier
				then "Carried"
				elseif world.escaping[slime.id] then "Escaping"
				else "Pad"
			-- A slime hatched moments ago still shows as its egg until the show's burst (contract/mystery-egg.md §40.6).
			local hatch = world.hatches[slime.id]
			-- A slime the Lucky Charm just upgraded still shows as it was caught until the morph (contract/lucky-charm.md).
			local shown = if hatch and now < hatch.at + Config.MYSTERY_EGG.HATCH_BURST_SECONDS
				then MysteryEgg.shell(slime, hatch.kind, hatch.at)
				else LuckyShow.shown(world, slime, now)
			local ready = shown == slime and state == "Pad" and EggKind.isReady(slime, now)
			local kind = EggKind.of(slime)
			entries[slime.id] = {
				id = slime.id,
				slime = shown,
				state = state,
				ownerUserId = session.userId,
				price = nil,
				income = if VatState.isLocked(session.data, slime.id)
					then 0
					else PlayerData.slimeIncome(session.data, shown),
				plotIndex = session.plotIndex,
				pad = slime.pad,
				carrierUserId = carrier,
				wild = nil,
				promptText = Carry.actionText(nil),
				promptHold = Carry.holdDuration(nil),
				promptEnabled = state == "Pad"
					and (unlocked or guestsOnly ~= nil)
					and not VatState.isLocked(session.data, slime.id),
				hideFromUserId = if state == "Pad" then session.userId else nil,
				guestsOnly = if state == "Pad" then guestsOnly else nil,
				boss = false,
				bossScale = nil,
				rare = nil,
				despawnAt = nil,
				hatchReady = ready,
				hatchText = if ready and kind
					then `{EggKind.displayName(kind)} · {MysteryEgg.meterText(session.data, kind)}`
					else nil,
				hatch = hatch,
				lucky = LuckyShow.get(world, slime.id),
				key = `{state}|{carrier or 0}|{session.plotIndex}|{slime.pad or 0}`,
			}
		end
	end

	return entries
end

return Scene
