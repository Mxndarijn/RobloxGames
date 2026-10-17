--!strict
--[[
	Validate

	Guards for untrusted client input and a tiny per-player rate limiter.
	Every remote argument goes through here before the server touches state.
	Pure: no Roblox APIs.
]]

local Validate = {}

export type Limiter = { [string]: number } -- action -> last allowed time

Validate.ACTIONS = table.freeze({
	Merge = 0.5,
	Merge3 = 0.5,
	Lock = 0.5,
	Rebirth = 2,
	Sell = 0.25,
	Favorite = 0.25,
	BuyPad = 0.5,
	Daily = 1,
	ClaimQuest = 0.3,
	BuyLockUpgrade = 0.5,
	BuySpeedCoil = 0.5,
	BuyUpgrade = 0.5,
	BuyEgg = 1,
	Slap = 0.3,
	Drop = 0.3,
	Appraise = 0.5,
	Redeem = 2,
	EquipPlotSkin = 0.5,
})

function Validate.slimeId(value: any): string?
	if type(value) ~= "string" or #value == 0 or #value > 64 then
		return nil
	end
	if string.find(value, "[^%w%-_{}]") then
		return nil
	end
	return value
end

function Validate.action(value: any): string?
	if type(value) == "string" and Validate.ACTIONS[value] ~= nil then
		return value
	end
	return nil
end

-- Returns true (and records `now`) if `action` may run again.
function Validate.allow(limiter: Limiter, action: string, now: number): boolean
	local interval = Validate.ACTIONS[action]
	if interval == nil then
		return false
	end
	local last = limiter[action]
	if last and now - last < interval then
		return false
	end
	limiter[action] = now
	return true
end

return Validate
