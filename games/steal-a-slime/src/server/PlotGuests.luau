--!strict
--[[
	PlotGuests (pure)

	The owner's friends switch (FEATURES.FriendsInBase, CONTRACT.md §42). With data.allowFriends on, the owner's
	Roblox friends in this server (session.friendIds, filled by Friends.refresh) are guests of the owner's plot: a
	guest walks through the locked stopper, may steal there and is never a locked-base intruder. Everyone else is
	blocked as before (PlotLockGuard). The switch is free and saved; it starts off.

	A guest who stops being one (the owner switches it off, or they are no longer friends) is judged like anyone
	else: inside a locked base they got into after the lock began, they are an intruder and SlimeGuard sends them
	home.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local World = if script then require(script.Parent.World) else require("./World")

type World = World.World
type Session = World.Session
export type Features = { [string]: boolean }?

local PlotGuests = {}

-- FEATURES.FriendsInBase, or its override in `features` (tests).
function PlotGuests.enabled(features: Features): boolean
	local override = if features then features.FriendsInBase else nil
	if override ~= nil then
		return override
	end
	return Config.FEATURES.FriendsInBase == true
end

-- True when `visitorId` is a guest of `owner`'s plot: the switch is on and they are friends in this server.
function PlotGuests.isGuest(owner: Session?, visitorId: number, features: Features): boolean
	if not owner or owner.userId == visitorId or not PlotGuests.enabled(features) then
		return false
	end
	if owner.data.allowFriends ~= true then
		return false
	end
	local ids = owner.friendIds
	return ids ~= nil and ids[visitorId] == true
end

-- True when `visitorId` is a guest of plot `plotIndex`'s owner.
function PlotGuests.isGuestOf(world: World, plotIndex: number, visitorId: number, features: Features): boolean
	local ownerId = world.plots[plotIndex]
	local owner = if ownerId then world.sessions[ownerId] else nil
	return PlotGuests.isGuest(owner, visitorId, features)
end

-- The guests of `owner`'s plot who are in the server now, sorted.
function PlotGuests.list(world: World, owner: Session, features: Features): { number }
	local out = {}
	local ids: { [number]: boolean } = owner.friendIds or {}
	for friendId in ids do
		if world.sessions[friendId] and PlotGuests.isGuest(owner, friendId, features) then
			table.insert(out, friendId)
		end
	end
	table.sort(out)
	return out
end

-- The GuestsOnly prompt attribute for a list of user ids: ",1,2," (nil for none), so a client checks ",<id>,".
function PlotGuests.encode(ids: { number }): string?
	if #ids == 0 then
		return nil
	end
	local parts = {}
	for _, id in ids do
		table.insert(parts, tostring(id))
	end
	return `,{table.concat(parts, ",")},`
end

--[[
	Every guest pair right now, by plot: result[i][j] = true when the owner of plot j is a guest of plot i (so plot i's
	stopper lets plot j's owner through). Plots with no guests are left out.
]]
function PlotGuests.pairs(world: World, features: Features): { [number]: { [number]: boolean } }
	local out = {}
	if not PlotGuests.enabled(features) then
		return out
	end
	for _, owner in world.sessions do
		if owner.data.allowFriends == true and owner.friendIds then
			for friendId in owner.friendIds do
				local friend = world.sessions[friendId]
				if friend and PlotGuests.isGuest(owner, friendId, features) then
					local set = out[owner.plotIndex] or {}
					set[friend.plotIndex] = true
					out[owner.plotIndex] = set
				end
			end
		end
	end
	return out
end

-- Flips the owner's switch. Tells the owner, and on switching on, each friend in the server. Never errors.
function PlotGuests.toggle(world: World, session: Session, features: Features): (boolean, string?)
	if not PlotGuests.enabled(features) then
		return false, "unknown action"
	end
	local on = session.data.allowFriends ~= true
	session.data.allowFriends = if on then true else nil
	World.markDirty(session)
	if on then
		World.notify(world, session.userId, "Your friends can now enter your base, even when it's locked", "good")
		local ids: { [number]: boolean } = session.friendIds or {}
		for friendId in ids do
			if world.sessions[friendId] then
				World.notify(world, friendId, `{session.name} lets you into their base`, "good")
			end
		end
	else
		World.notify(world, session.userId, "Friends are blocked from your base again", "info")
	end
	return true
end

return table.freeze(PlotGuests)
