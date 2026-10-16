--!strict
--[[
	FriendBonus

	+Config.FRIEND_BONUS_PER_FRIEND income per friend in the same server, at
	most Config.FRIEND_BONUS_CAP (CONTRACT.md §11). Plain math; the server
	(src/server/Friends) counts the friends and stores the result in
	data.friendBonus, which Perks.bonusMultiplier applies. Pure: no Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

local FriendBonus = {}

-- The bonus for `friends` friends in the server (0.2 = +20%). 0 with the feature off.
function FriendBonus.bonus(friends: number): number
	if Config.FEATURES.FriendBonus ~= true or type(friends) ~= "number" or friends ~= friends or friends < 1 then
		return 0
	end
	local raw = math.floor(friends) * Config.FRIEND_BONUS_PER_FRIEND
	-- round to 1e-6 so 3 * 0.1 is 0.3 and not 0.30000000000000004
	return math.min(math.floor(raw * 1e6 + 0.5) / 1e6, Config.FRIEND_BONUS_CAP)
end

function FriendBonus.multiplier(friends: number): number
	return 1 + FriendBonus.bonus(friends)
end

-- Friends it takes to reach the cap.
function FriendBonus.maxFriends(): number
	return math.ceil(Config.FRIEND_BONUS_CAP / Config.FRIEND_BONUS_PER_FRIEND - 1e-9)
end

return table.freeze(FriendBonus)
