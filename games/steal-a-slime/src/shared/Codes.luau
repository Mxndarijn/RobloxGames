--!strict
--[[
	Codes (pure)

	Redeem codes (CONTRACT.md §10). The server checks a typed code against
	Config.CODES (case-insensitive, once per player, optional expiry) and pays
	its reward: cash, or a timed income boost kept in the save (boostMult /
	boostUntil; Perks.bonusMultiplier applies it). Statuses are the only thing
	the UI needs to word a toast: "ok" | "used" | "invalid" | "expired".
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")

type Data = PlayerData.Data

export type Reward = { kind: string, amount: number?, mult: number?, minutes: number? }
export type Status = "ok" | "used" | "invalid" | "expired"
export type CodesView = { boostMult: number, boostEndsAt: number, redeemed: number }

local Codes = {}

Codes.MESSAGES = table.freeze({
	used = "You already used that code",
	invalid = "That code doesn't exist",
	expired = "That code has expired",
})

-- Trimmed, upper-cased code, or nil when the text can't be a code (empty, too
-- long, or anything but letters, digits, "-" and "_").
function Codes.normalize(text: any): string?
	if type(text) ~= "string" then
		return nil
	end
	local code = string.upper((string.gsub(text, "^%s+", "")))
	code = string.gsub(code, "%s+$", "")
	if #code == 0 or #code > Config.CODE_MAX_LENGTH or string.find(code, "[^%w%-_]") then
		return nil
	end
	return code
end

-- Applies a boost: the higher multiplier wins, and the time adds up.
local function addBoost(data: Data, mult: number, minutes: number, now: number)
	data.boostMult = math.max(data.boostMult, math.clamp(mult, 1, Config.CODE_BOOST_MAX_MULT))
	data.boostUntil = math.max(data.boostUntil, now) + minutes * 60
end

-- Redeems `text` for `data`. Returns (ok, status, reward). Never errors.
function Codes.redeem(data: Data, text: any, now: number): (boolean, Status, Reward?)
	local code = Codes.normalize(text)
	local def = if code then (Config.CODES :: any)[code] else nil
	if not code or not def then
		return false, "invalid", nil
	end
	if data.redeemed[code] then
		return false, "used", nil
	end
	if def.expiresAt and now >= def.expiresAt then
		return false, "expired", nil
	end
	local reward: Reward = def.reward
	if reward.kind == "cash" then
		PlayerData.earn(data, reward.amount or 0)
	elseif reward.kind == "boost" then
		addBoost(data, reward.mult or 1, reward.minutes or 0, now)
	else
		return false, "invalid", nil
	end
	data.redeemed[code] = true
	return true, "ok", reward
end

-- Ends the boost once its time is up. True when it just ended.
function Codes.expireBoost(data: Data, now: number): boolean
	if data.boostUntil > 0 and now >= data.boostUntil then
		data.boostMult, data.boostUntil = 1, 0
		return true
	end
	return false
end

-- State.codes: the active boost (1 / 0 when none) and how many codes were used.
function Codes.view(data: Data): CodesView
	local count = 0
	for _ in data.redeemed do
		count += 1
	end
	return { boostMult = data.boostMult, boostEndsAt = data.boostUntil, redeemed = count }
end

return table.freeze(Codes)
