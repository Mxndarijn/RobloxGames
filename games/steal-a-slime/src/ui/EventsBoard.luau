--!strict
--[[
	EventsBoard (FEATURES.EventsBoard, CONTRACT.md §20)

	HUD board text for what is running on this server and what comes next: the weekly mutation and the
	Saturday trait event (workspace WeeklyEvent attribute, FEATURES.WeeklyEvents), the dawn / dusk or live
	admin modifier (State.modifier, ModifierBadge) and the next weekly event. Pure
	(tests/ui/EventsBoard.spec.luau); `unix` is os.time() (the weekly clock), `now` the server clock.
]]

local Shared = if script then game:GetService("ReplicatedStorage"):WaitForChild("Shared") :: any else nil
local Config = if Shared then require(Shared:WaitForChild("Config")) else require("../shared/Config")
local Format = if script then require(script.Parent.Format) else require("./Format")
local ModifierBadge = if script then require(script.Parent.ModifierBadge) else require("./ModifierBadge")
local WeeklyEvents = if Shared then require(Shared:WaitForChild("WeeklyEvents")) else require("../shared/WeeklyEvents")

local EventsBoard = {}

-- "3d 4h", "5h 12m", then "m:ss".
local function left(seconds: number): string
	local total = math.ceil(seconds)
	if total >= 86400 then
		return string.format("%dd %dh", total // 86400, (total % 86400) // 3600)
	elseif total >= 3600 then
		return string.format("%dh %dm", total // 3600, (total % 3600) // 60)
	end
	return Format.formatDuration(total)
end

local function trait(id: string): { [string]: any }?
	for _, t in Config.WEEKLY.TRAITS do
		if t.id == id then
			return t
		end
	end
	return nil
end

-- One board row: the ItemIcons id drawn at its left, its plain-text (emoji) line, the text shown beside the icon.
export type Row = { icon: string, line: string, text: string }

local function traitIcon(t: { [string]: any }): string
	return if t.luck ~= 1 then "Event_luck" else "Event_mutation"
end

local function traitText(t: { [string]: any }): string
	local parts = {}
	if t.luck ~= 1 then
		table.insert(parts, string.format("x%g luck", t.luck))
	end
	if t.mutation ~= 1 then
		table.insert(parts, string.format("x%g mutations", t.mutation))
	end
	return `{t.label} {table.concat(parts, ", ")}`
end

-- Board rows, title first; nil when the board is off or nothing is running.
function EventsBoard.rows(
	attribute: any,
	modifier: ModifierBadge.View?,
	now: number,
	unix: number,
	enabled: boolean
): { Row }?
	if not enabled then
		return nil
	end
	local rows: { Row } = {}
	local weekly = WeeklyEvents.decode(attribute)
	if weekly then
		if weekly.mutationEndsAt > unix then
			table.insert(rows, {
				icon = "Event_mutation",
				line = `🧪 {weekly.mutation} week - {left(weekly.mutationEndsAt - unix)} left`,
				text = `{weekly.mutation} week - {left(weekly.mutationEndsAt - unix)} left`,
			})
		end
		local active = if weekly.trait then trait(weekly.trait) else nil
		if active and weekly.traitEndsAt and weekly.traitEndsAt > unix then
			table.insert(rows, {
				icon = traitIcon(active),
				line = `{active.icon} {traitText(active)} - {left(weekly.traitEndsAt - unix)} left`,
				text = `{traitText(active)} - {left(weekly.traitEndsAt - unix)} left`,
			})
		end
	end
	local modifierText = ModifierBadge.banner(modifier, now, Config.FEATURES.CycleModifier)
	if modifierText and modifier then
		local plain = if modifier.icon then string.sub(modifierText, #modifier.icon + 2) else modifierText
		table.insert(rows, {
			icon = if modifier.luck ~= 1 then "Event_luck" else "Event_mutation",
			line = modifierText,
			text = plain,
		})
	end
	if #rows == 0 then
		return nil
	end
	if weekly and weekly.nextStartsAt > unix then
		local t = if weekly.nextKind == "trait" then trait(weekly.nextId) else nil
		table.insert(rows, {
			icon = if t then traitIcon(t) else "Event_mutation",
			line = `Next: {if t then `{t.icon} {t.label}` else `🧪 {weekly.nextId} week`} in {left(
				weekly.nextStartsAt - unix
			)}`,
			text = `Next: {if t then t.label else `{weekly.nextId} week`} in {left(weekly.nextStartsAt - unix)}`,
		})
	end
	table.insert(rows, 1, { icon = "Event_rain", line = "📅 Server events", text = "Server events" })
	return rows
end

-- The same rows as plain emoji lines (watcher check, tests).
function EventsBoard.lines(
	attribute: any,
	modifier: ModifierBadge.View?,
	now: number,
	unix: number,
	enabled: boolean
): { string }?
	local rows = EventsBoard.rows(attribute, modifier, now, unix, enabled)
	if not rows then
		return nil
	end
	local lines = {}
	for _, row in rows do
		table.insert(lines, row.line)
	end
	return lines
end

function EventsBoard.text(
	attribute: any,
	modifier: ModifierBadge.View?,
	now: number,
	unix: number,
	enabled: boolean
): string?
	local lines = EventsBoard.lines(attribute, modifier, now, unix, enabled)
	return if lines then table.concat(lines, "\n") else nil
end

return table.freeze(EventsBoard)
