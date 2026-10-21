--!strict
--[[
	Revenge (pure, FEATURES.Revenge, CONTRACT.md §16)

	* While a thief is carrying one of your slimes, you see the thief's plot
	  highlighted (Player attribute RevengePlots, drawn by VisualsClient/RevengeFx
	  for the victim only). It clears the moment the carry ends: the slime is
	  stolen, goes home, or either side leaves.
	* When a thief finishes robbing a player (Carry.deposit of a stolen slime),
	  the victim gets a window of Config.REVENGE_SECONDS against that thief: the
	  thief's lock costs Config.REVENGE_LOCK_COST_MULT x while any victim's window
	  on them is open (not stacked: two victims still x2).
	Marks live in world.revenge[victimId][thiefId] = window end. Robbing the
	same victim again refreshes (does not add up). Windows end by expiry or
	when either side leaves (Revenge.forget).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World

local Revenge = {}

function Revenge.enabled(): boolean
	return Config.FEATURES.Revenge == true
end

-- Opens (or refreshes) the victim's window on the thief.
function Revenge.mark(world: World, victimId: number, thiefId: number, now: number)
	if not Revenge.enabled() or victimId == thiefId then
		return
	end
	local marks = world.revenge[victimId]
	if not marks then
		marks = {}
		world.revenge[victimId] = marks
	end
	marks[thiefId] = now + Config.REVENGE_SECONDS
end

-- True while the victim's window on the thief is open: [mark, mark + REVENGE_SECONDS).
function Revenge.isActive(world: World, victimId: number, thiefId: number, now: number): boolean
	local marks = world.revenge[victimId]
	local untilT = marks and marks[thiefId]
	return Revenge.enabled() and untilT ~= nil and now < untilT
end

-- Lock price multiplier for `thiefId`: REVENGE_LOCK_COST_MULT inside any open window, else 1.
function Revenge.lockMultiplier(world: World, thiefId: number, now: number): number
	if not Revenge.enabled() then
		return 1
	end
	for victimId in world.revenge do
		if Revenge.isActive(world, victimId, thiefId, now) then
			return Config.REVENGE_LOCK_COST_MULT
		end
	end
	return 1
end

-- Plot indexes (ascending) of the players carrying one of the victim's slimes right now.
function Revenge.plotsFor(world: World, victimId: number): { number }
	local plots = {}
	if not Revenge.enabled() then
		return plots
	end
	for _, session in world.sessions do
		local carry = session.carry
		if carry and carry.kind == "stolen" and carry.ownerUserId == victimId and session.userId ~= victimId then
			table.insert(plots, session.plotIndex)
		end
	end
	table.sort(plots)
	return plots
end

-- Drops expired marks and pushes State to the thief whose lock price changed (call every frame).
function Revenge.prune(world: World, now: number)
	for victimId, marks in world.revenge do
		for thiefId, untilT in marks do
			if now >= untilT then
				marks[thiefId] = nil
				World.markDirty(world.sessions[thiefId]) -- State.lockCost drops back
			end
		end
		if next(marks) == nil then
			world.revenge[victimId] = nil
		end
	end
end

-- A player left: closes every window they were victim or thief in.
function Revenge.forget(world: World, userId: number)
	local asVictim = world.revenge[userId]
	if asVictim then
		for thiefId in asVictim do
			World.markDirty(world.sessions[thiefId]) -- State.lockCost drops back
		end
	end
	world.revenge[userId] = nil
	for victimId, marks in world.revenge do
		marks[userId] = nil
		if next(marks) == nil then
			world.revenge[victimId] = nil
		end
	end
end

return Revenge
