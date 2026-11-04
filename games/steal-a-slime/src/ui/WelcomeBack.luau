--!strict
--[[
	WelcomeBack (client, pure, contract/welcome-back.md)

	What the one welcome back / daily reward card shows. `mode` says why it opened:
	- "join": the join report (`State.welcomeBack`) after a long break: a cash row, the daily row and, when
	  slimes grew, a growth row, titled "Welcome back".
	- "daily": a daily claim became ready, or Goals "Open": only the daily row, titled "Daily reward".
	The main button claims the daily reward while one is ready, else it only closes the card. The away cash is
	never claimed here: the server paid it (or put it on the cash pads) at join. No Roblox APIs.
]]

local Daily = if script then require(script.Parent.Daily) else require("./Daily")
local Format = if script then require(script.Parent.Format) else require("./Format")

export type Mode = "join" | "daily"
export type Row = { name: string, desc: string }
-- amount: the day's reward on the tile ("$1K", "Egg", "Mint Fizz"); icon: its ItemIcons id; skin: a trail or seat day.
export type Tile = {
	day: number,
	state: "claimed" | "today" | "upcoming",
	label: string,
	amount: string,
	icon: string,
	skin: boolean,
}
-- amount: today's claim (nil once claimed); amountShown: drawn in the row (the join card; the daily card's title
-- and Claim button already say it).
export type DailyRow = { name: string, amount: string?, amountShown: boolean, status: string, tiles: { Tile } }
export type Action = { kind: "claim" | "close", text: string }
export type View = {
	mode: Mode,
	title: string,
	icon: string,
	cash: Row?,
	daily: DailyRow?,
	growth: Row?,
	action: Action,
}

local WelcomeBack = {}

WelcomeBack.TITLES = table.freeze({
	join = table.freeze({ title = "Welcome back", icon = "👋" }),
	daily = table.freeze({ title = "Daily reward", icon = "📅" }),
})

local function plural(n: number, word: string): string
	return `{n} {word}{if n == 1 then "" else "s"}`
end

-- 19200 -> "5h 20m", 90000 -> "1d 1h", under an hour -> "12m".
function WelcomeBack.awayText(seconds: number): string
	local minutes = math.max(0, math.floor(seconds / 60))
	local hours = minutes // 60
	if hours >= 24 then
		return `{hours // 24}d {hours % 24}h`
	end
	return if hours > 0 then `{hours}h {minutes % 60}m` else `{minutes}m`
end

-- The cash row: where the offline cash went (on the cash pads, or already in your cash).
function WelcomeBack.cashRow(report: any): Row
	local away = WelcomeBack.awayText(report.away)
	if report.cash <= 0 then
		return { name = `Away {away}`, desc = "No cash earned while you were away" }
	end
	local where = if report.onPads == true then "waiting on your cash pads" else "added to your cash"
	return { name = `+{Format.formatCash(report.cash)}`, desc = `Earned in {away}, {where}` }
end

local function streakBroke(state: any): boolean
	local shop = state.exclusiveShop
	return type(shop) == "table" and shop.streakKeepable == true
end

-- The daily row from `State.daily`: today's reward, a status line and one tile per day of `daily.track`. In the
-- daily card (`alone`) the card title already says "Daily reward", so the row leads with the streak instead.
function WelcomeBack.dailyRow(state: any, config: any, alone: boolean?): DailyRow?
	local daily = state.daily
	if type(daily) ~= "table" or type(daily.day) ~= "number" then
		return nil
	end
	local cap: number = config.DAILY_STREAK_CAP or 30
	local available = daily.available == true
	local tiles: { Tile } = {}
	for _, cell in Daily.track(daily) do
		table.insert(tiles, {
			day = cell.day,
			state = cell.state,
			label = Daily.dayLabel(cell),
			amount = cell.reward.short,
			icon = cell.reward.icon,
			skin = cell.reward.skin == true,
		})
	end
	local nextSkin = if type(daily.nextSkin) == "table" then daily.nextSkin else nil
	local status = if nextSkin then `Next skin: {nextSkin.label} on day {nextSkin.day}` else "Come back tomorrow"
	local reward = if type(daily.reward) == "table" then daily.reward else nil
	if available and reward then
		local streak = if streakBroke(state)
			then (if daily.streak > 1 then `Your {daily.streak}-day streak broke` else "Your streak broke")
			else `Day {daily.day} of {cap}`
		return {
			name = if alone then streak else "Daily reward",
			amount = reward.label,
			amountShown = not alone,
			status = if alone then status else streak,
			tiles = tiles,
		}
	end
	return {
		name = if alone then "Claimed today" else "Daily reward claimed",
		amountShown = false,
		status = status,
		tiles = tiles,
	}
end

-- The card for `mode`; "join" without a report falls back to "daily". nil when there is nothing to show.
function WelcomeBack.view(state: any, mode: Mode, config: any): View?
	if type(state) ~= "table" then
		return nil
	end
	local report = if type(state.welcomeBack) == "table" then state.welcomeBack else nil
	local m: Mode = if mode == "join" and report then "join" else "daily"
	local daily = WelcomeBack.dailyRow(state, config or {}, m == "daily")
	if m == "daily" and daily == nil then
		return nil
	end
	local cash, growth = nil, nil
	if m == "join" then
		cash = WelcomeBack.cashRow(report)
		if type(report.grown) == "number" and report.grown > 0 then
			growth = { name = `{plural(report.grown, "slime")} grew`, desc = "on your pads while you were gone" }
		end
	end
	local action: Action = if daily and daily.amount
		then { kind = "claim", text = `Claim {daily.amount}` }
		else { kind = "close", text = "Got it" }
	local titles = WelcomeBack.TITLES[m]
	return {
		mode = m,
		title = titles.title,
		icon = titles.icon,
		cash = cash,
		daily = daily,
		growth = growth,
		action = action,
	}
end

return table.freeze(WelcomeBack)
