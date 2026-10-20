--!strict
--[[
	Rebirth (pure)

	Request("Rebirth"): Shared.Progression.rebirth uses up the required slimes,
	wipes cash and the other slimes but keeps the favourite (or the best slime)
	and adds income multiplier and lock time. Slimes being carried or bouncing
	home can't be the keeper, and any carry of a wiped slime ends.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Perks = if Shared then require(Shared.Perks) else require("../shared/Perks")
local Progression = if Shared then require(Shared.Progression) else require("../shared/Progression")
local Carry = if script then require(script.Parent.Carry) else require("./Carry")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local Rebirth = {}

function Rebirth.rebirth(world: World, session: Session): (boolean, string?)
	local rank = Perks.tierIndex(session.data.rebirths)
	local ok, result = Progression.rebirth(session.data, World.busySet(world))
	if not ok then
		return false, result :: string
	end
	session.incomeRemainder = 0
	for id in world.escaping do
		if World.ownerOf(world, id) == nil then
			world.escaping[id] = nil
		end
	end
	Carry.cancelMissing(world)
	World.markDirty(session)
	local mult = Economy.rebirthMultiplier(session.data.rebirths)
	World.notify(world, session.userId, `Rebirth {session.data.rebirths}! Income x{mult}`, "good", "Rebirth", "Rebirth")
	if Perks.tierIndex(session.data.rebirths) > rank then
		local tier = Perks.tier(session.data.rebirths)
		World.notify(world, session.userId, `New rank: {tier.title}! {Perks.tierText(tier)}`, "good", "Rebirth")
	end
	World.effect(world, "Rebirth", { userId = session.userId })
	World.tutorial(world, session, "Rebirth")
	return true, nil
end

return Rebirth
