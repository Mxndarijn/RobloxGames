--!strict
--[[
	Hint

	The "where do I tap" ring round a left-menu button (Pure, tests/ui/Hint.spec.luau; Panels/HintOverlay draws
	it). Every tutorial step happens in the world, where the TutorialArrow trail leads, so the only hint is the one
	after the last step: while the "Tutorial done" card shows, a ring round Goals with a short bubble.

	Reads Tutorial.fromState only; the server owns progression.
]]

local Layout = if script then require(script.Parent.Layout) else require("./Layout")
local Nav = if script then require(script.Parent.Nav) else require("./Nav")
local Tutorial = if script then require(script.Parent.Tutorial) else require("./Tutorial")

type Rect = Layout.Rect

export type Target = { kind: "nav", name: string }
export type View = { id: string, text: string, target: Target }
export type Placement = { target: Rect, ring: Rect, bubble: Rect, side: "right" }

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

-- Tutorial step id -> what to point at. "Finished": while the "Tutorial done" card shows, Goals has what's next.
Hint.STEPS = table.freeze({
	Finished = table.freeze({ text = navText("Goals"), target = table.freeze({ kind = "nav", name = "Goals" }) }),
} :: { [string]: { text: string, target: Target } })

Hint.TEXT_SIZE = 16
Hint.PAD_X = 12
Hint.MIN_HEIGHT = 36
Hint.GAP = 8
Hint.RING = 4 -- the ring sits this far outside the target

-- The hint for a State snapshot; nil when the step is in the world, the tutorial is over and its "Tutorial done"
-- card is gone (`finished` false), or the panel it points at is already open (`openPanel`).
function Hint.fromState(state: any, openPanel: string?, finished: boolean?): View?
	local step = Tutorial.fromState(state)
	local id = if step then step.id elseif finished then "Finished" else nil
	if id == nil then
		return nil
	end
	local hint = Hint.STEPS[id]
	if hint == nil or hint.target.name == openPanel then
		return nil
	end
	return { id = id, text = hint.text, target = hint.target }
end

-- The target's box on `screen`; nil when it isn't shown.
function Hint.targetRect(screen: Layout.Screen, target: Target): Rect?
	for i, entry in Nav.ENTRIES do
		if entry.key == target.name then
			return screen.navButtons[i]
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

-- Ring + bubble boxes: right of the nav. Bubbles stay MARGIN inside the screen.
function Hint.place(screen: Layout.Screen, view: View): Placement?
	local target = Hint.targetRect(screen, view.target)
	if target == nil then
		return nil
	end
	local m, r = Layout.MARGIN, Hint.RING
	local ring = Layout.rect(target.x - r, target.y - r, target.w + r * 2, target.h + r * 2)
	local x = screen.nav.x + screen.nav.w + Hint.GAP
	local w, h = Hint.bubbleSize(view.text, screen.width - m - x)
	local y = math.clamp(target.y + target.h / 2 - h / 2, m, screen.height - m - h)
	return { target = target, ring = ring, bubble = Layout.rect(x, y, w, h), side = "right" }
end

return table.freeze(Hint)
