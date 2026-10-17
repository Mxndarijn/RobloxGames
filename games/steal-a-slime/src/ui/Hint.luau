--!strict
--[[
	Hint

	First-minutes "where do I tap" hint (v18). Pure (tests/ui/Hint.spec.luau);
	Panels/HintOverlay draws it. While a tutorial step asks for a button in
	the UI chrome (Lock / Buy pad in the top bar, Rebirth in the left
	menu; the Merge step has no button any more, it is the vat in the world), a ring goes round that button with a short bubble next to it
	("Tap 🔒 Lock in the top bar"). Steps that happen in the world (Grab,
	Deposit, Steal) get no hint: Archer's TutorialArrow points there.

	Reads Tutorial.fromState only; the server owns progression.
]]

local Layout = if script then require(script.Parent.Layout) else require("./Layout")
local Nav = if script then require(script.Parent.Nav) else require("./Nav")
local Tutorial = if script then require(script.Parent.Tutorial) else require("./Tutorial")

type Rect = Layout.Rect

export type Target = { kind: "hud" | "nav", name: string }
export type View = { id: string, text: string, target: Target }
export type Placement = { target: Rect, ring: Rect, bubble: Rect, side: "below" | "right" }

local Hint = {}

local function navEntry(key: string): Nav.Entry
	for _, entry in Nav.ENTRIES do
		if entry.key == key then
			return entry
		end
	end
	error(`no nav entry {key}`)
end

local function navText(key: string): string
	local entry = navEntry(key)
	return `Tap {entry.icon} {entry.label} in the left menu`
end

-- Tutorial step id -> what to point at.
Hint.STEPS = table.freeze({
	Lock = table.freeze({
		text = "Tap 🔒 Lock in the top bar",
		target = table.freeze({ kind = "hud", name = "Lock" }),
	}),
	BuyPad = table.freeze({
		text = "Tap Buy pad in the top bar",
		target = table.freeze({ kind = "hud", name = "BuyPad" }),
	}),
	Rebirth = table.freeze({ text = navText("Rebirth"), target = table.freeze({ kind = "nav", name = "Rebirth" }) }),
} :: { [string]: { text: string, target: Target } })

Hint.TEXT_SIZE = 16
Hint.PAD_X = 12
Hint.MIN_HEIGHT = 36
Hint.GAP = 8
Hint.RING = 4 -- the ring sits this far outside the target

-- The hint for a State snapshot; nil when the tutorial is finished, the step
-- is in the world, or the panel it points at is already open (`openPanel`).
function Hint.fromState(state: any, openPanel: string?): View?
	local step = Tutorial.fromState(state)
	if step == nil then
		return nil
	end
	local hint = Hint.STEPS[step.id]
	if hint == nil or (hint.target.kind == "nav" and hint.target.name == openPanel) then
		return nil
	end
	return { id = step.id, text = hint.text, target = hint.target }
end

-- The target's box on `screen` (`hud` = the HUD as laid out, hidden items
-- missing); nil when it isn't shown.
function Hint.targetRect(screen: Layout.Screen, hud: Layout.HudLayout, target: Target): Rect?
	if target.kind == "hud" then
		return hud.items[target.name]
	end
	for i, entry in Nav.ENTRIES do
		if entry.key == target.name then
			return screen.navButtons[i + 1] -- [1] is the collapse toggle
		end
	end
	return nil
end

-- Bubble size for `text` at most `maxW` wide (wraps onto more lines).
function Hint.bubbleSize(text: string, maxW: number): (number, number)
	local w = math.min(math.ceil(Layout.lineWidth(text, Hint.TEXT_SIZE, true)) + Hint.PAD_X * 2, maxW)
	local h =
		math.max(Hint.MIN_HEIGHT, math.ceil(Layout.wrappedHeight(text, Hint.TEXT_SIZE, w - Hint.PAD_X * 2, true) + 12))
	return w, h
end

-- Ring + bubble boxes: below the HUD for top-bar targets, right of the nav
-- for menu targets. Bubbles stay MARGIN inside the screen.
function Hint.place(screen: Layout.Screen, hud: Layout.HudLayout, view: View): Placement?
	local target = Hint.targetRect(screen, hud, view.target)
	if target == nil then
		return nil
	end
	local m, r = Layout.MARGIN, Hint.RING
	local ring = Layout.rect(target.x - r, target.y - r, target.w + r * 2, target.h + r * 2)
	if view.target.kind == "hud" then
		local y = hud.rect.y + hud.rect.h + Hint.GAP
		-- Right of the nav when the bubble reaches down beside it. Left of a
		-- menu's close X: top-bar hints stay up while a menu is open.
		local left = screen.nav.x + screen.nav.w + Hint.GAP
		local right = Layout.panelClose(screen.panel).x - Hint.GAP
		local w, h = Hint.bubbleSize(view.text, right - left)
		if y + h <= screen.nav.y then
			left = m
			w, h = Hint.bubbleSize(view.text, right - m)
		end
		local x = math.clamp(target.x + target.w / 2 - w / 2, left, math.max(left, right - w))
		-- v28 menus are centred cards: when the highest card's X would sit
		-- under the bubble, keep left of that X column instead.
		local cardClose = Layout.panelClose(Layout.panelFor(screen, ""))
		if Layout.overlaps(Layout.rect(x, y, w, h), cardClose) then
			right = math.min(right, cardClose.x - Hint.GAP)
			left = math.min(left, right)
			w, h = Hint.bubbleSize(view.text, right - left)
			x = math.clamp(target.x + target.w / 2 - w / 2, left, math.max(left, right - w))
		end
		return { target = target, ring = ring, bubble = Layout.rect(x, y, w, h), side = "below" }
	end
	local x = screen.nav.x + screen.nav.w + Hint.GAP
	local w, h = Hint.bubbleSize(view.text, screen.width - m - x)
	local y = math.clamp(target.y + target.h / 2 - h / 2, m, screen.height - m - h)
	return { target = target, ring = ring, bubble = Layout.rect(x, y, w, h), side = "right" }
end

return table.freeze(Hint)
