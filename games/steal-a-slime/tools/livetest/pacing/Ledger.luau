--!strict
--[[
	Where each bot's cash came from and went to. PlayerData.earn / PlayerData.spend are wrapped once; the
	caller's module and function name (debug.info) pick the source, so the game code stays untouched and
	every payout, wherever it is paid from, is counted.

	Earned: active (Income.step), offline (Income.applyOffline), sell, goal, dex, quest, daily, code, other.
	Spent: pad, upgrade, coil, lock, wild (price of a wild slime), consumable, pvp, other; the rebirth price
	is noted by the bot (Progression.rebirth sets the cash back directly).
]]

local PlayerData = require("../../../src/shared/PlayerData")

type Data = PlayerData.Data

export type Book = { earned: { [string]: number }, spent: { [string]: number } }

local Ledger = {}

local books: { [Data]: Book } = setmetatable({}, { __mode = "k" }) :: any
local installed = false

function Ledger.book(data: Data): Book
	local book = books[data]
	if not book then
		book = { earned = {}, spent = {} }
		books[data] = book
	end
	return book
end

local modules: { [string]: string } = {}

-- The module a chunk name belongs to ("…/Goals.luau" -> "Goals"), remembered per chunk name.
local function moduleOf(source: string?): string
	local key = source or ""
	local module = modules[key]
	if not module then
		module = string.match(key, "([%w_]+)%.luau$") or string.match(key, "([%w_]+)$") or "?"
		modules[key] = module
	end
	return module
end

local EARN_BY_MODULE: { [string]: string } = {
	Goals = "goal",
	Collection = "dex",
	Quests = "quest",
	Progression = "daily",
	Codes = "code",
}

local function earnSource(source: string?, name: string?): string
	local module = moduleOf(source)
	if module == "Income" then
		return if name == "applyOffline" then "offline" else "active"
	elseif module == "PlayerData" and name == "sell" then
		return "sell"
	end
	return EARN_BY_MODULE[module] or "other"
end

local SPEND_BY_MODULE: { [string]: string } = {
	Upgrades = "upgrade",
	Shop = "coil",
	Steal = "lock",
	Carry = "wild",
	ConsumableShop = "consumable",
	Consumables = "consumable",
	PvpService = "pvp",
	PlayerData = "pad",
}

-- Wrap earn and spend (idempotent). Call before any bot plays.
function Ledger.install()
	if installed then
		return
	end
	installed = true
	local earn, spend = PlayerData.earn, PlayerData.spend
	PlayerData.earn = function(data: Data, amount: number)
		if amount > 0 then
			local source, name = debug.info(2, "sn")
			local earned = Ledger.book(data).earned
			local key = earnSource(source, name)
			earned[key] = (earned[key] or 0) + amount
		end
		earn(data, amount)
	end
	PlayerData.spend = function(data: Data, amount: number): boolean
		local ok = spend(data, amount)
		if ok and amount > 0 then
			local source = debug.info(2, "s")
			local spent = Ledger.book(data).spent
			local key = SPEND_BY_MODULE[moduleOf(source)] or "other"
			spent[key] = (spent[key] or 0) + amount
		end
		return ok
	end
end

function Ledger.note(data: Data, kind: "earned" | "spent", key: string, amount: number)
	local table_ = Ledger.book(data)[kind]
	table_[key] = (table_[key] or 0) + amount
end

return Ledger
