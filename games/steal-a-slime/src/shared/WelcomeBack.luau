--!strict
--[[
	WelcomeBack (pure, FEATURES.WelcomeBack, CONTRACT.md §19)

	The join report behind the welcome-back card: how long the player was away, the offline cash
	already paid (Income.applyOffline) and how many pad slimes grew meanwhile (Growth.applyOffline).
	nil when the feature is off, the player was away less than Config.WELCOME_BACK_MIN_SECONDS, or
	lastOnline is missing / garbage / in the future. Nothing is saved. No Roblox APIs.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")

export type Report = { away: number, cash: number, grown: number }

local WelcomeBack = {}

function WelcomeBack.report(lastOnline: number, now: number, cash: number, grown: number): Report?
	if not Config.FEATURES.WelcomeBack then
		return nil
	end
	if type(lastOnline) ~= "number" or lastOnline ~= lastOnline or lastOnline <= 0 then
		return nil
	end
	local away = now - lastOnline
	if away ~= away or away < Config.WELCOME_BACK_MIN_SECONDS then
		return nil
	end
	return { away = math.floor(away), cash = math.max(0, cash), grown = math.max(0, grown) }
end

return table.freeze(WelcomeBack)
