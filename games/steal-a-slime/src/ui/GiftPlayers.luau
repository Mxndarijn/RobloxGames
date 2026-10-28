--!strict
--[[
	GiftPlayers

	The players the Exclusive shop's gift picker can offer (contract/exclusive-shop.md §12): everyone on this server
	with their display name and whether they are the local player's friend. Friendship is looked up once per player
	when they join (Player:IsFriendsWith yields), so `list()` never waits; a player whose answer is not in yet counts
	as not a friend. ExclusiveShopView.giftTargets drops the local player and puts friends first.

	`start(players, localPlayer, spawn)` takes the Players service, the local player and task.spawn, so specs pass
	fakes. It returns `list` and `stop`.
]]

export type Target = { userId: number, name: string, friend: boolean }

export type Handle = {
	list: () -> { Target },
	stop: () -> (),
}

local GiftPlayers = {}

function GiftPlayers.start(players: any, localPlayer: any, spawn: (fn: () -> ()) -> ()): Handle
	local friends: { [number]: boolean } = {}
	local function check(p: any)
		if p == localPlayer or friends[p.UserId] ~= nil then
			return
		end
		friends[p.UserId] = false
		spawn(function()
			local ok, yes = pcall(function()
				return localPlayer:IsFriendsWith(p.UserId)
			end)
			friends[p.UserId] = ok and yes == true
		end)
	end
	local conns = {
		players.PlayerAdded:Connect(check),
		players.PlayerRemoving:Connect(function(p: any)
			friends[p.UserId] = nil
		end),
	}
	for _, p in players:GetPlayers() do
		check(p)
	end
	return {
		list = function(): { Target }
			local out: { Target } = {}
			for _, p in players:GetPlayers() do
				table.insert(out, { userId = p.UserId, name = p.DisplayName, friend = friends[p.UserId] == true })
			end
			return out
		end,
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
		end,
	}
end

return table.freeze(GiftPlayers)
