--!strict
--[[
	WelcomeBack (client, pure, CONTRACT.md §19)

	What the welcome-back card says, from `State.welcomeBack` (the join report) plus the live
	`State.daily` / `State.goals`. `view` returns up to four rows (cash, growth, daily, goal), each
	with an ItemIcons id, so the panel only draws. nil without a report. No Roblox APIs.
]]

local Format = if script then require(script.Parent.Format) else require("./Format")

export type Row = { name: string, icon: string, text: string } -- icon = ItemIcons id
export type View = { title: string, away: string, rows: { Row } }

local WelcomeBack = {}

WelcomeBack.MAX_ROWS = 4

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

function WelcomeBack.view(state: any): View?
	local report = if type(state) == "table" then state.welcomeBack else nil
	if type(report) ~= "table" then
		return nil
	end
	local rows: { Row } = {}
	table.insert(rows, {
		name = "Cash",
		icon = "Cash",
		text = if report.cash <= 0
			then "No cash earned yet"
			elseif report.onPads == true then `+{Format.formatCash(report.cash)} waiting on your cash pads`
			else `+{Format.formatCash(report.cash)} earned while away`,
	})
	table.insert(rows, {
		name = "Growth",
		icon = "Goal_Pads",
		text = if report.grown > 0
			then `{plural(report.grown, "slime")} grew on your pads`
			else "Your slimes are fully grown",
	})
	local daily = state.daily
	if type(daily) == "table" then
		table.insert(rows, {
			name = "Daily",
			icon = "Daily",
			text = if daily.available
				then `Daily reward ready: {Format.formatCash(daily.amount)}`
				else `Daily streak: {plural(daily.streak, "day")}`,
		})
	end
	if type(state.goals) == "table" then
		for _, goal in state.goals do
			if not goal.done then
				table.insert(rows, {
					name = "Goal",
					icon = "Quest",
					text = `{goal.title} ({math.min(goal.progress, goal.target or goal.progress)}/{goal.target or 0})`,
				})
				break
			end
		end
	end
	return { title = "Welcome back", away = `You were away {WelcomeBack.awayText(report.away)}`, rows = rows }
end

return table.freeze(WelcomeBack)
