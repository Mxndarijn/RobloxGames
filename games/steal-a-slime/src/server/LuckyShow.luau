--!strict
--[[
	LuckyShow (contract/lucky-charm.md)

	The Lucky Charm show on the pad: `record` keeps the slime as it was caught, `shown` is what the pad shows (the
	caught slime until LUCKY_SHOW.MORPH_SECONDS, then the promoted one), `step` sends the owner's Notify at the morph
	and forgets a show after LUCKY_SHOW.FX_SECONDS. Runtime only: nothing is saved.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil

local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Slime = Genome.Slime

local LuckyShow = {}

LuckyShow.SOUND = "Lucky"

-- "Lucky! Your Legendary Ninja became a Mythic Seraph!"
function LuckyShow.text(before: Slime, after: Slime): string
	return `Lucky! Your {Genome.displayName(before)} became {Genome.displayName(after)}!`
end

-- Starts the show for `slime` (already promoted), caught as `before`. Without a clock (`now` nil) there is no show:
-- the owner hears it straight away.
function LuckyShow.record(world: World, userId: number, before: Slime, slime: Slime, now: number?)
	local text = LuckyShow.text(before, slime)
	if not now then
		World.notify(world, userId, text, "good", LuckyShow.SOUND)
		return
	end
	world.lucky[slime.id] = { at = now, before = before, userId = userId, text = text, told = false }
end

-- What the pad shows for `slime` at `now`: the caught copy (on the slime's pad) during the morph, else `slime`.
function LuckyShow.shown(world: World, slime: Slime, now: number): Slime
	local show = world.lucky[slime.id]
	if not show or now >= show.at + Config.LUCKY_SHOW.MORPH_SECONDS then
		return slime
	end
	local copy = Genome.copy(show.before)
	copy.pad = slime.pad
	return copy
end

-- The show playing for `slimeId`, if any (WorldView tags the model from it).
function LuckyShow.get(world: World, slimeId: string): World.Lucky?
	return world.lucky[slimeId]
end

function LuckyShow.step(world: World, now: number)
	local cfg = Config.LUCKY_SHOW
	for id, show in world.lucky do
		if not show.told and now >= show.at + cfg.MORPH_SECONDS then
			show.told = true
			World.notify(world, show.userId, show.text, "good", LuckyShow.SOUND)
		end
		if now >= show.at + cfg.FX_SECONDS then
			world.lucky[id] = nil
		end
	end
end

return table.freeze(LuckyShow)
