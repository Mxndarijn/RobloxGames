--!strict
--[[
	MysteryEgg (server)

	`spawnForEvent` is the server-side event hook (boss helper eggs): it
	hatches free eggs onto a player's plot through Shared.MysteryEgg, with no
	remote, no cash and no Robux, and records each hatch for the reveal banner
	(State.egg). Pure: no Roblox APIs.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Genome = if Shared then require(Shared.Genome) else require("../shared/Genome")
local SharedEgg = if Shared then require(Shared.MysteryEgg) else require("../shared/MysteryEgg")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local MysteryEgg = {}

MysteryEgg.MAX_EVENT_EGGS = 16 -- per spawnForEvent call

local function reveal(world: World, session: Session, slime: Genome.Slime, now: number)
	session.egg = { slime = slime, at = now }
	World.markDirty(session)
	World.notify(world, session.userId, `Your egg hatched: {Genome.displayName(slime)}!`, "good", "Cash", "MysteryEgg")
end

--[[
	Event / admin: hatches up to `count` free eggs for `userId` (stops when the
	plot is full). Returns the hatched slimes. Not reachable from any remote.
]]
function MysteryEgg.spawnForEvent(world: World, userId: number, count: number, now: number): { Genome.Slime }
	local hatched: { Genome.Slime } = {}
	local session = World.session(world, userId)
	if not session then
		return hatched
	end
	for _ = 1, math.clamp(math.floor(count), 0, MysteryEgg.MAX_EVENT_EGGS) do
		local ok, value = SharedEgg.hatchInto(session.data, world.rng, world.newId())
		if not ok then
			break
		end
		table.insert(hatched, value :: Genome.Slime)
		reveal(world, session, value :: Genome.Slime, now)
	end
	return hatched
end

return table.freeze(MysteryEgg)
