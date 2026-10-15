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
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local Steal = if Shared then require(Shared.Steal) else require("../shared/Steal")
local Carry = if script then require(script.Parent.Carry) else require("./Carry")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World

export type SlimeState = "Wild" | "Pad" | "Carried" | "Escaping"

export type Entry = {
	id: string,
	slime: Genome.Slime,
	state: SlimeState,
	ownerUserId: number, -- 0 = wild
	price: number?, -- wild only
	plotIndex: number?, -- Pad / Escaping / (Carried when stolen)
	pad: number?,
	carrierUserId: number?,
	wild: World.Wild?, -- wild only: landing angle / radius / dropped position
	promptText: string,
	promptEnabled: boolean,
	hideFromUserId: number?, -- the owner, on Steal prompts; nil = visible to everyone
	boss: boolean, -- wild Boss Slime (model attribute Boss)
	rare: number?, -- tier of an announced Legendary+ wild drop (model attribute RareSpawn)
	despawnAt: number?, -- uncarried wild only, inside the telegraph window (model attribute DespawnAt)
	key: string, -- changes whenever the model must be re-placed
}

local Scene = {}

function Scene.describe(world: World, now: number): { [string]: Entry }
	local entries: { [string]: Entry } = {}

	for id, wild in world.wild do
		local carrier = world.carriedBy[id]
		local state: SlimeState = if carrier then "Carried" else "Wild"
		entries[id] = {
			id = id,
			slime = wild.slime,
			state = state,
			ownerUserId = 0,
			price = wild.price,
			plotIndex = nil,
			pad = nil,
			carrierUserId = carrier,
			wild = wild,
			promptText = Carry.actionText(wild.price),
			promptEnabled = carrier == nil,
			hideFromUserId = nil,
			boss = wild.boss == true,
			rare = wild.rare,
			despawnAt = if carrier
				then nil
				else DespawnTelegraph.attributeValue(
					now,
					wild.expiresAt,
					Config.DESPAWN_TELEGRAPH_SECONDS,
					Config.FEATURES.DespawnTelegraph
				),
			key = `{state}|{carrier or 0}|{wild.position ~= nil}|{wild.spawnedAt}`,
		}
	end

	for _, session in world.sessions do
		local unlocked = not Steal.isLocked(session.lockUntil, now)
		for _, slime in session.data.slimes do
			local carrier = world.carriedBy[slime.id]
			local state: SlimeState = if carrier
				then "Carried"
				elseif world.escaping[slime.id] then "Escaping"
				else "Pad"
			entries[slime.id] = {
				id = slime.id,
				slime = slime,
				state = state,
				ownerUserId = session.userId,
				price = nil,
				plotIndex = session.plotIndex,
				pad = slime.pad,
				carrierUserId = carrier,
				wild = nil,
				promptText = Carry.actionText(nil),
				promptEnabled = state == "Pad" and unlocked,
				hideFromUserId = if state == "Pad" then session.userId else nil,
				boss = false,
				rare = nil,
				despawnAt = nil,
				key = `{state}|{carrier or 0}|{session.plotIndex}|{slime.pad or 0}`,
			}
		end
	end

	return entries
end

return Scene
