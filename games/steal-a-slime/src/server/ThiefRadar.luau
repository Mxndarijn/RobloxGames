--!strict
--[[
	ThiefRadar (pure, contract/exclusive-shop.md §13)

	The Thief Radar Game Pass: who is inside your base right now. It reads the plot visits SlimeGuard already tracks
	(`world.guard[userId].plot`, set every view tick by SlimeGuard.trackPlot) and writes, for every owner with the
	pass, `session.radar` (the visitors' userIds, at most Config.EXCLUSIVE_SHOP.radar.maxShown, longest inside first)
	for State.exclusiveShop.radar. A visitor is told to the owner once per visit while the owner is away from home.
	Friends the base lets in (PlotGuests) are not visitors. Information only: nobody is slowed, moved or stopped.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local PlotGuests = if script then require(script.Parent.PlotGuests) else require("./PlotGuests")
local Purchases = if script then require(script.Parent.Purchases) else require("./Purchases")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session

local ThiefRadar = {}

local function sameList(a: { number }?, b: { number }): boolean
	if a == nil or #a ~= #b then
		return a == nil and #b == 0
	end
	for i, v in b do
		if a[i] ~= v then
			return false
		end
	end
	return true
end

-- The players inside `owner`'s base now, longest inside first, friends the base lets in left out.
function ThiefRadar.visitors(world: World, owner: Session, features: { [string]: boolean }?): { number }
	local found: { { id: number, since: number } } = {}
	for userId, entry in world.guard do
		local plot = entry.plot
		if
			plot
			and plot.index == owner.plotIndex
			and userId ~= owner.userId
			and world.sessions[userId] ~= nil
			and not PlotGuests.isGuest(owner, userId, features)
		then
			table.insert(found, { id = userId, since = plot.since })
		end
	end
	table.sort(found, function(a, b)
		if a.since ~= b.since then
			return a.since < b.since
		end
		return a.id < b.id
	end)
	local out: { number } = {}
	for i, v in found do
		if i > Config.EXCLUSIVE_SHOP.radar.maxShown then
			break
		end
		table.insert(out, v.id)
	end
	return out
end

-- Once a second: refreshes every radar owner's visitor list and tells an away owner about each new visitor.
function ThiefRadar.step(world: World, features: { [string]: boolean }?)
	for _, owner in world.sessions do
		if not Purchases.hasEffect(owner, "radar") then
			if owner.radar ~= nil then
				owner.radar, owner.radarSeen = nil, nil
				World.markDirty(owner)
			end
			continue
		end
		local now = ThiefRadar.visitors(world, owner, features)
		local seen = owner.radarSeen or {}
		local next: { [number]: boolean } = {}
		for _, id in now do
			next[id] = true
			if not seen[id] and not owner.home then
				local visitor = world.sessions[id]
				local name = if visitor then visitor.name else "Someone"
				World.notify(world, owner.userId, `Thief Radar: {name} is in your base!`, "bad", "Alarm")
			end
		end
		owner.radarSeen = next
		if not sameList(owner.radar, now) then
			owner.radar = now
			World.markDirty(owner)
		end
	end
end

return table.freeze(ThiefRadar)
