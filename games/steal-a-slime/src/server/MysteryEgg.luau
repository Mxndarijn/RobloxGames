--!strict
--[[
	MysteryEgg (server)

	Wild Mystery Eggs (contract/mystery-egg.md): `hatch` is the `HatchEgg`
	action and the owner's HatchPrompt. It records the hatch in
	`world.hatches` for the hatch show (WorldView tags the new slime model with
	HatchedAt / HatchedFrom / HatchLucky) and holds the toasts until the show
	reveals the slime. `step` (once a second) sends those toasts, forgets old
	hatches, starts the clock of any pad egg without one, warms the eggs of
	owners standing at home and toasts the owner once when an egg turns ready.
	Pure: no Roblox APIs.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local EggKind = if Shared then require(Shared.EggKind) else require("../shared/EggKind")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local SharedEgg = if Shared then require(Shared.MysteryEgg) else require("../shared/MysteryEgg")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local MysteryEgg = {}

-- The owner's toast for a hatch: "Lucky egg! Your egg hatched: Legendary Honey Queen!".
function MysteryEgg.hatchText(slime: Genome.Slime, hatch: SharedEgg.Hatch): string
	local prefix = if hatch.guaranteed then "Lucky meter full! " elseif hatch.lucky then "Lucky egg! " else ""
	return `{prefix}Your egg hatched: {Genome.displayName(slime)}!`
end

-- The owner's toast when an egg turns ready; it names a full lucky meter.
function MysteryEgg.readyText(data: any, slime: Genome.Slime): string
	local text = `Your {Genome.displayName(slime)} is ready to hatch! Hold Hatch on it.`
	local kind = EggKind.of(slime)
	if kind and SharedEgg.guaranteed(data, kind) then
		local top = Genome.rarity(EggKind.topTier(kind)).name
		text ..= ` Your lucky meter is full: it hatches a {top} or better!`
	end
	return text
end

--[[
	The owner hatches their ready egg `slimeId` (Request HatchEgg / HatchPrompt).
	Returns (ok, reason?).
]]
function MysteryEgg.hatch(world: World, session: Session, slimeId: string, now: number): (boolean, string?)
	if World.isBusy(world, slimeId) then
		return false, "egg is being stolen"
	end
	local ok, value, info = SharedEgg.hatchEgg(session.data, slimeId, now, world.eggRng)
	if not ok or not info then
		return false, value :: string
	end
	local slime = value :: Genome.Slime
	if session.eggsReady then
		session.eggsReady[slimeId] = nil
	end
	session.egg = { slime = slime, at = now }
	World.markDirty(session)
	world.hatches[slimeId] = {
		at = now,
		kind = info.kind,
		lucky = info.lucky or info.guaranteed,
		userId = session.userId,
		text = MysteryEgg.hatchText(slime, info),
		announce = if slime.tier >= Config.MYSTERY_EGG.HATCH_ANNOUNCE_TIER
			then `{session.name} hatched a {Genome.displayName(slime)} from a Mystery Egg!`
			else nil,
		sound = if slime.tier >= Config.SECRET_TIER then "Secret" else "Rare",
		told = false,
	}
	return true, nil
end

-- Sends the toasts of hatches the show has revealed and forgets hatches whose show is over.
function MysteryEgg.stepHatches(world: World, now: number)
	local cfg = Config.MYSTERY_EGG
	for id, hatch in world.hatches do
		if not hatch.told and now >= hatch.at + cfg.HATCH_REVEAL_SECONDS then
			hatch.told = true
			World.notify(world, hatch.userId, hatch.text, "good", hatch.sound, "MysteryEgg")
			if hatch.announce then
				World.notify(world, nil, hatch.announce, "good", hatch.sound)
			end
		end
		if hatch.told and now >= hatch.at + cfg.HATCH_FX_SECONDS then
			world.hatches[id] = nil
		end
	end
end

--[[
	Once a second: revealed hatches are toasted, every pad egg gets a hatch clock,
	the eggs of owners at home (`session.home`) incubate WARM_SPEED x, and an owner
	hears once when one of their eggs is ready. Eggs being carried off are left alone.
]]
function MysteryEgg.step(world: World, seconds: number, now: number)
	MysteryEgg.stepHatches(world, now)
	for _, session in world.sessions do
		local data = session.data
		local any = false
		for _, slime in data.slimes do
			if slime.egg and slime.pad then
				any = true
				SharedEgg.startIncubating(slime, now)
			end
		end
		if any then
			if session.home then
				SharedEgg.warm(data, seconds, now, world.carriedBy)
			end
			local told = session.eggsReady or {}
			session.eggsReady = told
			for _, slime in data.slimes do
				if EggKind.isReady(slime, now) and not told[slime.id] and not world.carriedBy[slime.id] then
					told[slime.id] = true
					World.markDirty(session)
					World.notify(world, session.userId, MysteryEgg.readyText(data, slime), "good", "Rare", "MysteryEgg")
				end
			end
		end
	end
end

return table.freeze(MysteryEgg)
