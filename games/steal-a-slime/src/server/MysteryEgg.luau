--!strict
--[[
	MysteryEgg (server)

	`spawnForEvent` is the server-side event hook (boss helper eggs): it
	hatches free eggs onto a player's plot through Shared.MysteryEgg, with no
	remote, no cash and no Robux, and records each hatch for the reveal banner
	(State.egg).

	Wild Mystery Eggs (contract/mystery-egg.md): `hatch` is the `HatchEgg`
	action and the owner's HatchPrompt; `step` (once a second) starts the clock
	of any pad egg without one, warms the eggs of owners standing at home and
	toasts the owner once when an egg turns ready. Pure: no Roblox APIs.
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

--[[
	The owner hatches their ready egg `slimeId` (Request HatchEgg / HatchPrompt).
	Returns (ok, reason?).
]]
function MysteryEgg.hatch(world: World, session: Session, slimeId: string, now: number): (boolean, string?)
	if World.isBusy(world, slimeId) then
		return false, "egg is being stolen"
	end
	local ok, value = SharedEgg.hatchEgg(session.data, slimeId, now)
	if not ok then
		return false, value :: string
	end
	local slime = value :: Genome.Slime
	if session.eggsReady then
		session.eggsReady[slimeId] = nil
	end
	reveal(world, session, slime, now)
	World.effect(world, "Merge", { slimeId = slimeId, userId = session.userId })
	if slime.tier >= Config.MYSTERY_EGG.HATCH_ANNOUNCE_TIER then
		local sound = if slime.tier >= Config.SECRET_TIER then "Secret" else "Rare"
		World.notify(
			world,
			nil,
			`{session.name} hatched a {Genome.displayName(slime)} from a Mystery Egg!`,
			"good",
			sound
		)
	end
	return true, nil
end

--[[
	Once a second: every pad egg gets a hatch clock, the eggs of owners at home
	(`session.home`) incubate WARM_SPEED x, and an owner hears once when one of
	their eggs is ready. Eggs being carried off are left alone.
]]
function MysteryEgg.step(world: World, seconds: number, now: number)
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
					World.notify(
						world,
						session.userId,
						`Your {Genome.displayName(slime)} is ready to hatch! Hold Hatch on it.`,
						"good",
						"Rare",
						"MysteryEgg"
					)
				end
			end
		end
	end
end

return table.freeze(MysteryEgg)
