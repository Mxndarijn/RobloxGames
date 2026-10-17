--!strict
--[[
	PvpHudLogic (FEATURES.PvP, pure; tests/ui/PvpHudLogic.spec.luau, PvpHudLayout.spec.luau)

	The numbers behind the PvP HUD (PvpHud draws them): the cooldown ring math, the mm:ss shield text, the
	safe-zone text and the hotbar's boxes in Layout.screen design px. No Instances, no Roblox APIs.

	Cooldown ring (UI only, no images): two half masks. Each half is a square frame the size of the slot,
	clipped to the left / right half of the slot, filled with a UIGradient whose transparency is a hard step
	at 50 %. Rotating the gradient turns that half-plane around the slot centre, so the visible part of a half
	is a wedge. `ring(fraction)` is the share of the cooldown still left, drawn clockwise from 12 o'clock:
	the right half shows angles 0..180 (Rotation 0..180), the left half 180..360 (Rotation 180..360).
]]

local Layout = if script then require(script.Parent.Layout) else require("./Layout")

export type Rect = Layout.Rect
export type Ring = { rightRotation: number, leftRotation: number, showRight: boolean, showLeft: boolean }
export type Placement = {
	box: Rect, -- the visible strip
	slots: { Rect }, -- visible slots, in order, screen design px (box.x + ...)
	visible: number, -- how many slots show at once
	scrolls: boolean, -- more slots than fit: the strip scrolls sideways
	canvasW: number, -- full width of all slots (the scroll canvas)
}

local PvpHudLogic = {}

PvpHudLogic.SLOT = Layout.BUTTON -- design px; Layout.BUTTON * MIN_SCALE >= MIN_TOUCH
PvpHudLogic.SLOT_GAP = 6
PvpHudLogic.MAX_VISIBLE = 9 -- keybinds 1..9; the rest scrolls
PvpHudLogic.BANNER_RESERVE = 46 -- banner stack height kept free under the HUD: one chip row + one more banner line
PvpHudLogic.CHIP_ORDER_SHIELD = 11 -- Banners stack LayoutOrders 1..10 are taken (Hud)
PvpHudLogic.CHIP_ORDER_ZONE = 12
PvpHudLogic.CHIP_HEIGHT = 30

-- Hard-step transparency of a ring half (offset, transparency): visible first half, hidden second.
PvpHudLogic.RING_STEP = table.freeze({
	table.freeze({ 0, 0 }),
	table.freeze({ 0.4999, 0 }),
	table.freeze({ 0.5, 1 }),
	table.freeze({ 1, 1 }),
})

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v > -math.huge and v < math.huge
end

-- Gradient rotations (degrees) of the two ring halves for `fraction` of the cooldown left. NaN, nil and
-- out-of-range inputs clamp (NaN = nothing left).
function PvpHudLogic.ring(fraction: any): Ring
	local f = if finite(fraction) then math.clamp(fraction :: number, 0, 1) else 0
	local deg = f * 360
	return {
		rightRotation = math.min(deg, 180),
		leftRotation = 180 + math.clamp(deg - 180, 0, 180),
		showRight = f > 0,
		showLeft = f > 0.5,
	}
end

-- "m:ss" for a shield with `seconds` left (rounded up, never negative / NaN).
function PvpHudLogic.clock(seconds: any): string
	local total = if finite(seconds) then math.max(0, math.ceil((seconds :: number) - 1e-9)) else 0
	return string.format("%d:%02d", total // 60, total % 60)
end

-- Seconds text on a slot: whole seconds (rounded up) while more than one second is left, else "".
function PvpHudLogic.cooldownText(seconds: any): string
	if not finite(seconds) or (seconds :: number) <= 1 then
		return ""
	end
	return tostring(math.ceil((seconds :: number) - 1e-9))
end

function PvpHudLogic.shieldText(active: boolean, seconds: number): string?
	if not active then
		return nil
	end
	return `Shield {PvpHudLogic.clock(seconds)}`
end

function PvpHudLogic.zoneText(zone: string?): string?
	if type(zone) ~= "string" or zone == "" then
		return nil
	end
	return `Safe zone: {zone}`
end

local KEY_NUMBERS: { [string]: number } = {
	One = 1,
	Two = 2,
	Three = 3,
	Four = 4,
	Five = 5,
	Six = 6,
	Seven = 7,
	Eight = 8,
	Nine = 9,
}

-- Slot number for an Enum.KeyCode name (top-row digits and the keypad), nil for any other key.
function PvpHudLogic.keyNumber(keyName: any): number?
	if type(keyName) ~= "string" then
		return nil
	end
	return KEY_NUMBERS[string.gsub(keyName, "^Keypad", "")]
end

-- The hotbar's boxes for `count` slots on `screen` (Layout.screen). It sits just above the highest bottom card
-- (tutorial, tutorial while carrying, carry, so Carry / SLAP! / the tutorial never lose a tap), right of the nav,
-- left of the toast column when they share rows, and never into the banner stack's first BANNER_RESERVE px.
-- Slots that do not fit scroll. `slots` and `box` are in design px from the ScreenGui's top-left.
function PvpHudLogic.hotbar(screen: Layout.Screen, count: number): Placement
	local slot, gap, m = PvpHudLogic.SLOT, PvpHudLogic.SLOT_GAP, Layout.MARGIN
	local n = math.max(0, math.floor(count))
	local bottom = math.min(screen.tutorial.y, screen.tutorialCarrying.y, screen.carry.y) - Layout.GAP
	local y = bottom - slot
	local left = screen.nav.x + screen.nav.w + Layout.GAP
	local right = screen.width - m
	-- The toast column draws over the hotbar's rows: keep right of it out of the way when they share rows.
	local t = screen.toasts
	if y < t.y + t.h and y + slot > t.y then
		right = math.min(right, t.x - Layout.GAP)
	end
	local avail = math.max(right - left, 0)
	local fit = math.max(math.floor((avail + gap) / (slot + gap)), 0)
	local visible = math.min(n, PvpHudLogic.MAX_VISIBLE, fit)
	local boxW = if visible > 0 then visible * slot + (visible - 1) * gap else 0
	local x = math.clamp((screen.width - boxW) / 2, left, math.max(right - boxW, left))
	local slots: { Rect } = {}
	for i = 1, visible do
		table.insert(slots, Layout.rect(x + (i - 1) * (slot + gap), y, slot, slot))
	end
	return {
		box = Layout.rect(x, y, boxW, slot),
		slots = slots,
		visible = visible,
		scrolls = n > visible,
		canvasW = if n > 0 then n * slot + (n - 1) * gap else 0,
	}
end

return PvpHudLogic
