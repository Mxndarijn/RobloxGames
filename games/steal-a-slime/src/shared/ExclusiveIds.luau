--!strict
--[[
	ExclusiveIds (generated: the Roblox ids of the Exclusive Shop's products, passes and subscriptions)

	Created on Roblox for the Steal a Slime experience (universe 10770917350) with the Open Cloud Developer
	Products / Game Passes APIs; subscriptions on the Creator Dashboard. Config.EXCLUSIVE_SHOP reads these by key
	(a key without an id stays 0 / "": "Not on sale yet"). Keys are the permanent product / pass / subscription keys.
]]

return table.freeze({
	products = table.freeze({} :: { [string]: number }),
	passes = table.freeze({
		FastBrew = 2061832467,
		Income2x = 2060651077,
		LuckyCharmPlus = 2061094586,
		Offline2x = 2057351938,
		ThiefRadar = 2058767855,
		VIP = 2057345943,
		WarmNest = 2061664509,
	} :: { [string]: number }),
	subscriptions = table.freeze({} :: { [string]: string }),
})
