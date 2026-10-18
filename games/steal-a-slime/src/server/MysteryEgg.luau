--!strict
--[[
	MysteryEgg (server)

	`buy` is the `BuyEgg` action: validates cash and the free pad through
	Shared.MysteryEgg, hatches the slime onto the buyer's plot and records it
	for the reveal banner (State.egg). `spawnForEvent` is the server-side
	admin / event hook: it hatches free eggs for a player with no remote, no
	cash and no Robux. Pure: no Roblox APIs.
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

-- Returns (ok, reason?). Charges cash.
function MysteryEgg.buy(world: World, session: Session, now: number): (boolean, string?)
	local ok, value = SharedEgg.buy(session.data, world.rng, world.newId())
	if not ok then
		return false, value :: string
	end
	reveal(world, session, value :: Genome.Slime, now)
	return true, nil
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
