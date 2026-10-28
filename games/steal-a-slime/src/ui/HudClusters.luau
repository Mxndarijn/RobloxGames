--!strict
--[[
	HudClusters (H1 HUD, hud_design_ref.png)

	What the two bottom clusters show. Pure (tests/ui/HudClusters.spec.luau); Hud mounts them, Layout places them.

	* Money (bottom-left): the cash amount on the coin plate, with the income/s and rebirths chips under it.
	* Status (bottom-right): one icon + timer slot per running thing, packed to the right edge, left to right:
	    LockBreak a running lock break (State.exclusiveShop.lockBreak) with the time left to pass that locked door;
	    Rain  Slime Rain (workspace RainActive / RainEndsAt / RainNextAt, else State.rain): the time left while it
	           rains, a dimmed countdown for the last RainTimer.SOON_SECONDS before the next one;
	    Event  the live server modifier (State.modifier: dawn / dusk modifier, admin Luck event) with the
	           time left;
	    Friend the friend income bonus ("+10%", no timer);
	    Blessed the co-op ritual's Blessed income bonus (State.blessed) with the time left;
	    Mvp     the Boss Champion boost (State.mvpBoost) with the time left;
	    Pet    the follow pet's perk (State.petPerk: "+3%", no timer) while the favourite rides along on its cloud;
	    Secret this week's featured event Secret (State.featuredSecret) with the time until it rotates ("4h 6m").
	  The row has Layout.STATUS.count places, fewer than there are slots: the week-long Secret makes way
	  first, then the last ones in the order above (the always-on Pet next; the others last minutes).
	  The weekend boost is never a slot (Merijn, HUD-DESIGN.md: "Weekend boost: NOT shown").
	Tooltip (B8, 2026-10-18): each slot also carries its name and what it does; `tooltip` turns that plus the
	live timer into the 3 lines of the card (name, effect, time left), and `nextTooltip` is the open / close
	rule: mouse hover on PC, tap on touch (a second tap or a tap elsewhere closes it).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Format = if script then require(script.Parent.Format) else require("./Format")
local FriendBadge = if script then require(script.Parent.FriendBadge) else require("./FriendBadge")
local ModifierBadge = if script then require(script.Parent.ModifierBadge) else require("./ModifierBadge")
local RainTimer = if script then require(script.Parent.RainTimer) else require("./RainTimer")

export type Money = { cash: string, income: string, rebirths: string, rebirthCount: string, multiplier: string }
export type Slot = {
	id: string, -- "Rain" | "Event" | "Friend" | "Blessed" | "Mvp" | "Pet" | "Secret"
	icon: string, -- ItemIcons id
	text: string, -- the timer, or "+10%"
	kind: string, -- "active" | "soon" | "boost" | "pet" | "week"
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
	blessed: Blessed?,
	mvpBoost: Blessed?,
	petPerk: PetPerk?,
	featuredSecret: FeaturedSecret?,
	lockBreak: LockBreak?,
}
-- State.exclusiveShop.lockBreak: the running lock break (contract/exclusive-shop.md §11), `untilTime` in server time.
export type LockBreak = { plot: number, untilTime: number }
-- State.blessed: the ritual's Blessed income bonus, `endsAt` in server time. State.mvpBoost (the Boss MVP boost) has
-- the same shape.
export type Blessed = { bonus: number, endsAt: number }
-- State.petPerk: the favourite follow pet's passive (Perks.petPassive), `value` 0.03 = +3 %.
export type PetPerk = { kind: string, value: number, icon: string, text: string }
-- State.featuredSecret: this week's event Secret, `endsAt` in server time.
export type FeaturedSecret = { id: string, name: string, endsAt: number }

local HudClusters = {}

-- Slot ids in display order, left to right (Layout.STATUS_SLOTS).
HudClusters.STATUS_IDS = table.freeze({ "LockBreak", "Rain", "Event", "Friend", "Blessed", "Mvp", "Pet", "Secret" })

HudClusters.ICONS = table.freeze({
	Cash = "Cash",
	Income = "Income",
	Rebirths = "Rebirth",
	Rain = "Event_rain",
	Friend = "FriendBoost",
	Blessed = "Boost_Blessed",
	Mvp = "Boost_Mvp",
	Pet = "Pet",
	Secret = "Badge_FirstSecret",
	LockBreak = "Lock",
})

HudClusters.LOCK_BREAK_NAME = "Lock break"
HudClusters.LOCK_BREAK_EFFECT = "You can walk through that base's locked door. It stays locked for everyone else."

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
		text = string.format("x%g", view.luck)
	end
	return {
		id = "Event",
		icon = "Event_luck",
		text = text,
		kind = "active",
		name = view.label,
		effect = `x{string.format("%g", view.luck)} luck: rarer slimes show up more often.`,
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

-- The ritual's Blessed slot; nil when not blessed, malformed or over.
function HudClusters.blessed(view: Blessed?, now: number): Slot?
	if type(view) ~= "table" or type(view.bonus) ~= "number" or view.bonus ~= view.bonus or view.bonus <= 0 then
		return nil
	end
	if type(view.endsAt) ~= "number" or view.endsAt ~= view.endsAt then
		return nil
	end
	local remaining = Format.remainingSeconds(view.endsAt, now)
	if remaining <= 0 then
		return nil
	end
	return {
		id = "Blessed",
		icon = HudClusters.ICONS.Blessed,
		text = Format.formatDuration(remaining),
		kind = "active",
		name = "Blessed",
		effect = `+{math.floor(view.bonus * 100 + 0.5)}% income from the Slime Ritual.`,
	}
end

-- The Boss Champion slot (State.mvpBoost); nil when absent, malformed or over.
function HudClusters.mvp(view: Blessed?, now: number): Slot?
	local slot = HudClusters.blessed(view, now)
	if not slot or type(view) ~= "table" then
		return nil
	end
	slot.id = "Mvp"
	slot.icon = HudClusters.ICONS.Mvp
	slot.name = "Boss Champion"
	slot.effect =
		`+{math.floor(view.bonus * 100 + 0.5)}% income and +{math.floor(Config.BOSS.MVP_SPEED * 100 + 0.5)}% speed for bringing a boss home.`
	return slot
end

-- The follow pet's perk slot; nil without a favourite, an unknown kind or a malformed value.
function HudClusters.pet(view: PetPerk?): Slot?
	if type(view) ~= "table" or type(view.value) ~= "number" or view.value ~= view.value or view.value <= 0 then
		return nil
	end
	if view.kind ~= "income" and view.kind ~= "luck" then
		return nil
	end
	local percent = `+{math.floor(view.value * 100 + 0.5)}%`
	return {
		id = "Pet",
		icon = HudClusters.ICONS.Pet,
		text = percent,
		kind = "pet",
		name = "Pet bonus",
		effect = if view.kind == "income"
			then `{percent} income from your favourite slime riding along with you.`
			else `{percent} luck from your favourite slime riding along with you: rarer slimes show up more often.`,
	}
end

-- The featured event Secret slot; nil when absent, malformed or over.
function HudClusters.secret(view: FeaturedSecret?, now: number): Slot?
	if type(view) ~= "table" or type(view.name) ~= "string" or view.name == "" then
		return nil
	end
	if type(view.endsAt) ~= "number" or view.endsAt ~= view.endsAt then
		return nil
	end
	local remaining = Format.remainingSeconds(view.endsAt, now)
	if remaining <= 0 then
		return nil
	end
	return {
		id = "Secret",
		icon = HudClusters.ICONS.Secret,
		text = Format.formatTimeLeft(remaining),
		kind = "week",
		name = `Featured Secret: {view.name}`,
		effect = "Can spawn as a Secret this week.",
	}
end

-- The lock break slot (State.exclusiveShop.lockBreak) while it runs: "0:42" left to pass that base's locked door.
function HudClusters.lockBreak(view: LockBreak?, now: number): Slot?
	if type(view) ~= "table" or type(view.untilTime) ~= "number" or view.untilTime ~= view.untilTime then
		return nil
	end
	local remaining = Format.remainingSeconds(view.untilTime, now)
	if remaining <= 0 then
		return nil
	end
	return {
		id = "LockBreak",
		icon = HudClusters.ICONS.LockBreak,
		text = Format.formatDuration(remaining),
		kind = "active",
		name = HudClusters.LOCK_BREAK_NAME,
		effect = HudClusters.LOCK_BREAK_EFFECT,
	}
end

-- The shown slots, left to right; at most `places` (Layout.STATUS.count), the featured Secret dropped first.
function HudClusters.status(input: Inputs, now: number, places: number): { Slot }
	local out: { Slot } = {}
	local lockBreak = HudClusters.lockBreak(input.lockBreak, now)
	if lockBreak then
		table.insert(out, lockBreak)
	end
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
	local blessed = HudClusters.blessed(input.blessed, now)
	if blessed then
		table.insert(out, blessed)
	end
	local mvp = HudClusters.mvp(input.mvpBoost, now)
	if mvp then
		table.insert(out, mvp)
	end
	local pet = HudClusters.pet(input.petPerk)
	if pet then
		table.insert(out, pet)
	end
	local secret = HudClusters.secret(input.featuredSecret, now)
	if secret and #out < places then
		table.insert(out, secret)
	end
	while #out > places do
		table.remove(out)
	end
	return out
end

-- The tooltip card text for a shown slot: name, what it does, and the time left (the slot's live timer).
function HudClusters.tooltip(slot: Slot): Tooltip
	local time
	if slot.kind == "week" then
		time = `Ends in {slot.text}`
	elseif slot.kind == "boost" then
		time = "Active while friends are here"
	elseif slot.kind == "pet" then
		time = "Active while your pet follows you"
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
