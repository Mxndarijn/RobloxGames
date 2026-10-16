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

local function traitText(t: { [string]: any }): string
	local parts = {}
	if t.luck ~= 1 then
		table.insert(parts, string.format("x%g luck", t.luck))
	end
	if t.mutation ~= 1 then
		table.insert(parts, string.format("x%g mutations", t.mutation))
	end
	return `{t.icon} {t.label} {table.concat(parts, ", ")}`
end

-- Board lines, title first; nil when the board is off or nothing is running.
function EventsBoard.lines(
	attribute: any,
	modifier: ModifierBadge.View?,
	now: number,
	unix: number,
	enabled: boolean
): { string }?
	if not enabled then
		return nil
	end
	local lines = {}
	local weekly = WeeklyEvents.decode(attribute)
	if weekly then
		if weekly.mutationEndsAt > unix then
			table.insert(lines, `🧪 {weekly.mutation} week - {left(weekly.mutationEndsAt - unix)} left`)
		end
		local active = if weekly.trait then trait(weekly.trait) else nil
		if active and weekly.traitEndsAt and weekly.traitEndsAt > unix then
			table.insert(lines, `{traitText(active)} - {left(weekly.traitEndsAt - unix)} left`)
		end
	end
	local modifierText = ModifierBadge.banner(modifier, now, Config.FEATURES.CycleModifier)
	if modifierText then
		table.insert(lines, modifierText)
	end
	if #lines == 0 then
		return nil
	end
	if weekly and weekly.nextStartsAt > unix then
		local t = if weekly.nextKind == "trait" then trait(weekly.nextId) else nil
		local name = if t then `{t.icon} {t.label}` else `🧪 {weekly.nextId} week`
		table.insert(lines, `Next: {name} in {left(weekly.nextStartsAt - unix)}`)
	end
	table.insert(lines, 1, "📅 Server events")
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
