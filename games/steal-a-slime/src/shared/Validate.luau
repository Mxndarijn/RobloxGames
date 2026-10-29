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
	VatAdd = 0.25,
	VatRemove = 0.25,
	VatStart = 0.5,
	VatCancel = 0.5,
	VatCollect = 0.5,
	Lock = 0.5,
	ToggleFriends = 0.5,
	Rebirth = 2,
	Sell = 0.25,
	Favorite = 0.25,
	MoveSlime = 0.25,
	HatchEgg = 0.5,
	BuyPad = 0.5,
	Daily = 1,
	SkipTutorial = 1,
	ClaimQuest = 0.3,
	BuySpeedCoil = 0.5,
	BuyUpgrade = 0.5,
	Drop = 0.3,
	Redeem = 2,
	EquipPlotSkin = 0.5,
	EquipPlotBase = 3, -- a swap rebuilds the whole plot
	EquipPetSeat = 0.5,
	BuyConsumable = 0.5,
	UseConsumable = 0.5,
	SetAudioSettings = 0.5,
	BuyPvpItem = 0.5,
	EquipPvpItem = 0.5,
	UsePvpItem = 0.2,
	OpenShop = 0.5,
	CloseShop = 0.5,
	ShopBuy = 0.5,
	UseCredit = 0.5,
	AimHatch = 0.5,
	EquipTrail = 0.5,
	EquipBatSkin = 0.5,
	AimLockBreak = 0.5,
	AimGift = 0.5,
	SendGift = 0.5,
	SetHotbar = 0.3,
	RequestKits = 0.25,
	Admin = 0.25,
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

local DAMAGE_KEYS = { "damage", "dmg", "health", "kill", "hurt" }

--[[
	Config.PVP_TOOLS rules (CONTRACT.md §26). Returns the list of problems (empty = fine); Config asserts it
	is empty at load. `pvp` = Config.PVP, `ranks` = Config.REBIRTH_TIERS.
]]
function Validate.pvpTools(tools: { any }, pvp: any, ranks: { any }): { string }
	local problems: { string } = {}
	local gates: { [number]: boolean } = {}
	for _, rank in ranks do
		gates[rank.rebirths] = true
	end
	local seen: { [string]: boolean } = {}
	for _, tool in tools do
		local id = tostring(tool.id)
		if seen[id] then
			table.insert(problems, `{id}: duplicate id`)
		end
		seen[id] = true
		if type(tool.cooldown) ~= "number" or tool.cooldown < pvp.MIN_COOLDOWN then
			table.insert(problems, `{id}: cooldown below {pvp.MIN_COOLDOWN}`)
		end
		if not gates[tool.rebirths] then
			table.insert(problems, `{id}: gate {tostring(tool.rebirths)} is not a rank threshold`)
		end
		if tool.control ~= nil and not (type(tool.control) == "number" and tool.control <= pvp.CONTROL_MAX_SECONDS) then
			table.insert(problems, `{id}: control longer than {pvp.CONTROL_MAX_SECONDS}s`)
		end
		if
			tool.slowSeconds ~= nil
			and not (type(tool.slowSeconds) == "number" and tool.slowSeconds <= pvp.SLOW_MAX_SECONDS)
		then
			table.insert(problems, `{id}: slow longer than {pvp.SLOW_MAX_SECONDS}s`)
		end
		if
			tool.shotGap ~= nil
			and not (type(tool.shotGap) == "number" and tool.shotGap >= Validate.ACTIONS.UsePvpItem)
		then
			table.insert(problems, `{id}: shot gap below the UsePvpItem rate limit`)
		end
		if tool.kind ~= "tool" and tool.kind ~= "fun" then
			table.insert(problems, `{id}: bad kind`)
		end
		if type(tool.cosmetic) ~= "boolean" then
			table.insert(problems, `{id}: cosmetic must be a boolean`)
		end
		for _, key in DAMAGE_KEYS do
			if tool[key] ~= nil then
				table.insert(problems, `{id}: has a {key} field (PvP never deals damage)`)
			end
		end
	end
	return problems
end

return Validate
