--!strict
--[[
	HudClusters (H1 HUD, hud_design_ref.png)

	What the two bottom clusters show. Pure (tests/ui/HudClusters.spec.luau); Hud mounts them, Layout places them.

	* Money (bottom-left): the cash amount on the coin plate, with the income/s and rebirths chips under it.
	* Status (bottom-right): one icon + timer slot per running thing, packed to the right edge, left to right:
	    Rain   Slime Rain (workspace RainActive / RainEndsAt / RainNextAt, else State.rain): the time left while it
	           rains, a dimmed countdown for the last RainTimer.SOON_SECONDS before the next one;
	    Event  the live server modifier (State.modifier: dawn / dusk modifier, admin Luck / Mutation event) with the
	           time left;
	    Friend the friend income bonus ("+10%", no timer).
	  The weekend boost is never a slot (Merijn, HUD-DESIGN.md: "Weekend boost: NOT shown").
	Tooltip (B8, 2026-10-18): each slot also carries its name and what it does; `tooltip` turns that plus the
	live timer into the 3 lines of the card (name, effect, time left), and `nextTooltip` is the open / close
	rule: mouse hover on PC, tap on touch (a second tap or a tap elsewhere closes it).
]]

local Format = if script then require(script.Parent.Format) else require("./Format")
local FriendBadge = if script then require(script.Parent.FriendBadge) else require("./FriendBadge")
local ModifierBadge = if script then require(script.Parent.ModifierBadge) else require("./ModifierBadge")
local RainTimer = if script then require(script.Parent.RainTimer) else require("./RainTimer")

export type Money = { cash: string, income: string, rebirths: string, rebirthCount: string, multiplier: string }
export type Slot = {
	id: string, -- "Rain" | "Event" | "Friend"
	icon: string, -- ItemIcons id
	text: string, -- the timer, or "+10%"
	kind: string, -- "active" | "soon" | "boost"
	name: string, -- tooltip title: "Slime Rain"
	effect: string, -- tooltip body: what the event does
}
export type Tooltip = { title: string, body: string, time: string }
export type Inputs = {
	rain: RainTimer.Rain?,
	modifier: ModifierBadge.View?,
	modifierEnabled: boolean,
	friends: FriendBadge.View?,
	friendsEnabled: boolean,
}

local HudClusters = {}

-- Slot ids in display order, left to right (Layout.STATUS_SLOTS).
HudClusters.STATUS_IDS = table.freeze({ "Rain", "Event", "Friend" })

HudClusters.ICONS = table.freeze({
	Cash = "Cash",
	Income = "Income",
	Rebirths = "Rebirth",
	Rain = "Event_rain",
	Friend = "FriendBoost",
})

HudClusters.RAIN_EFFECT = "Slimes pour from the sky and rarer ones show up more often. Grab them!"

local function num(value: any): number
	return if type(value) == "number" and value == value then value else 0
end

function HudClusters.money(state: any): Money
	local count = tostring(num(state.rebirths))
	local multiplier =
		Format.formatMultiplier(if type(state.rebirthMultiplier) == "number" then state.rebirthMultiplier else 1)
	return {
		cash = Format.formatCash(num(state.cash)),
		income = Format.formatRate(num(state.incomePerSec)),
		rebirths = `{count} {multiplier}`,
		rebirthCount = count,
		multiplier = multiplier,
	}
end

-- Slime Rain slot; nil when it is neither raining nor about to.
function HudClusters.rain(rain: RainTimer.Rain?, now: number): Slot?
	if rain == nil then
		return nil
	end
	if rain.active then
		local text = if rain.endsAt then Format.formatDuration(Format.remainingSeconds(rain.endsAt, now)) else "Now"
		return {
			id = "Rain",
			icon = HudClusters.ICONS.Rain,
			text = text,
			kind = "active",
			name = "Slime Rain",
			effect = HudClusters.RAIN_EFFECT,
		}
	end
	if rain.nextAt then
		local wait = Format.remainingSeconds(rain.nextAt, now)
		if wait > 0 and wait <= RainTimer.SOON_SECONDS then
			return {
				id = "Rain",
				icon = HudClusters.ICONS.Rain,
				text = Format.formatDuration(wait),
				kind = "soon",
				name = "Slime Rain",
				effect = HudClusters.RAIN_EFFECT,
			}
		end
	end
	return nil
end

-- The live modifier slot; nil for "None", the feature off or a finished modifier.
function HudClusters.event(view: ModifierBadge.View?, now: number, enabled: boolean): Slot?
	if ModifierBadge.banner(view, now, enabled) == nil or view == nil then
		return nil
	end
	local text
	if view.endsAt then
		text = Format.formatDuration(Format.remainingSeconds(view.endsAt, now))
	else
		text = string.format("x%g", if view.luck ~= 1 then view.luck else view.mutation)
	end
	return {
		id = "Event",
		icon = if view.luck ~= 1 then "Event_luck" else "Event_mutation",
		text = text,
		kind = "active",
		name = view.label,
		effect = if view.luck ~= 1
			then `x{string.format("%g", view.luck)} luck: rarer slimes show up more often.`
			else `x{string.format("%g", view.mutation)} mutations: slimes mutate more often.`,
	}
end

-- The friend boost slot; nil with no friends or the feature off.
function HudClusters.friend(view: FriendBadge.View?, enabled: boolean): Slot?
	local label = FriendBadge.label(view, enabled)
	if label == nil then
		return nil
	end
	return {
		id = "Friend",
		icon = HudClusters.ICONS.Friend,
		text = label,
		kind = "boost",
		name = "Friend boost",
		effect = `{label} income while your friends play on this server.`,
	}
end

-- The shown slots, left to right (never more than Layout.STATUS.count).
function HudClusters.status(input: Inputs, now: number): { Slot }
	local out: { Slot } = {}
	local rain = HudClusters.rain(input.rain, now)
	if rain then
		table.insert(out, rain)
	end
	local event = HudClusters.event(input.modifier, now, input.modifierEnabled)
	if event then
		table.insert(out, event)
	end
	local friend = HudClusters.friend(input.friends, input.friendsEnabled)
	if friend then
		table.insert(out, friend)
	end
	return out
end

-- The tooltip card text for a shown slot: name, what it does, and the time left (the slot's live timer).
function HudClusters.tooltip(slot: Slot): Tooltip
	local time
	if slot.kind == "boost" then
		time = "Active while friends are here"
	elseif string.find(slot.text, ":", 1, true) == nil then
		time = "Active now" -- an untimed modifier ("x3") or a rain without an end time ("Now")
	elseif slot.kind == "soon" then
		time = `Starts in {slot.text}`
	else
		time = `Time left: {slot.text}`
	end
	return { title = slot.name, body = slot.effect, time = time }
end

-- Which slot id's tooltip is open after `event` (nil = none). `touch`: the last input was a touch.
--   "hover" / "leave"  mouse enter / leave an icon: open / close on PC, ignored on touch (a tap fires both).
--   "tap"              icon activated: touch toggles it (2nd tap closes); a mouse click keeps it open.
--   "press"            any press: closes the card unless it landed on the open icon (its own tap handles that).
function HudClusters.nextTooltip(current: string?, event: string, id: string?, touch: boolean): string?
	if event == "hover" then
		return if touch then current else id
	elseif event == "leave" then
		return if not touch and current == id then nil else current
	elseif event == "tap" then
		return if touch and current == id then nil else id
	elseif event == "press" then
		return if id ~= nil and id == current then current else nil
	end
	return current
end

return table.freeze(HudClusters)
