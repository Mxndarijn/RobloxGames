--!strict
--[[
	Tutorial

	Step text for the tutorial overlay (Panels/TutorialOverlay). Pure
	(tests/ui/Tutorial.spec.luau).

	Steps are CONTRACT §8.3 (v13): Grab, Deposit, Lock, BuyPad, Merge, Steal,
	Rebirth. `fromState` prefers `State.tutorialStepId` (stable names); without
	it (a v12 server, 6 steps) the numeric `State.tutorialStep` is read in the
	old order (LEGACY_IDS), so the copy never shifts by one. nil / unknown
	means no overlay (finished). The server owns progression; the UI never
	advances it.
]]

local InputKind = if script then require(script.Parent.InputKind) else require("./InputKind")

export type Kind = InputKind.Kind
export type Step = {
	id: string,
	title: string,
	template: string,
	body: string,
	bodies: { [Kind]: string },
}
export type StepView = { id: string, index: number, total: number, title: string, body: string, counter: string }

local Tutorial = {}

Tutorial.KINDS = table.freeze({ "keyboard", "touch", "gamepad" } :: { Kind })

-- The KeyCode names of the prompts the steps name: the server sets KeyboardKeyCode = E on the grab and plot
-- prompts and leaves GamepadKeyCode at the ProximityPrompt default (ButtonX).
Tutorial.PROMPT_KEYS = table.freeze({ keyboard = "E", gamepad = "ButtonX" })
-- Label of the button that brings a hidden tutorial card back.
Tutorial.SHOW_TEXT = "Tutorial"

-- Short names for UserInputService:GetStringForKeyCode on a gamepad (Xbox letters, PlayStation shapes).
local PAD_NAMES = table.freeze({
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonCross = "Cross",
	ButtonCircle = "Circle",
	ButtonSquare = "Square",
	ButtonTriangle = "Triangle",
} :: { [string]: string })

-- The label for a gamepad button string ("ButtonSquare" -> "Square"); unknown names lose their "Button" prefix.
function Tutorial.gamepadLabel(name: string): string
	return PAD_NAMES[name] or (name:gsub("^Button", ""))
end

-- What each device does for a tap ({grab}, {Press}) and for the 0.8 s hold prompts ({hold}, {Hold}); `key` is the
-- shown name of the prompt's key / button on that device.
function Tutorial.words(kind: Kind, key: string?): { [string]: string }
	if kind == "touch" then
		return {
			grab = "tap the prompt",
			Press = "Tap the prompt",
			hold = "tap and hold the prompt",
			Hold = "Tap and hold the prompt",
		}
	end
	local k = if key and key ~= "" then key else Tutorial.gamepadLabel(Tutorial.PROMPT_KEYS[kind])
	return {
		grab = if kind == "keyboard" then `press {k} (or tap the prompt)` else `press {k}`,
		Press = `Press {k}`,
		hold = `hold {k}`,
		Hold = `Hold {k}`,
	}
end

local function render(template: string, kind: Kind, key: string?): string
	return (template:gsub("{(%w+)}", Tutorial.words(kind, key)))
end

-- Every text the card may show for `step`: each device's default wording plus the gamepad one with the longest
-- button name, so the card is sized for all of them (Layout.tutorialHeight).
function Tutorial.texts(step: Step): { string }
	local widest = ""
	for _, name in PAD_NAMES do
		if #name > #widest then
			widest = name
		end
	end
	local out: { string } = {}
	for _, kind: Kind in Tutorial.KINDS :: { Kind } do
		table.insert(out, step.bodies[kind])
	end
	table.insert(out, render(step.template, "gamepad", widest))
	return out
end

local function define(id: string, title: string, template: string): Step
	local bodies = {} :: { [Kind]: string }
	for _, kind: Kind in Tutorial.KINDS :: { Kind } do
		bodies[kind] = render(template, kind)
	end
	local step: Step = {
		id = id,
		title = title,
		template = template,
		body = render(template, "keyboard"),
		bodies = table.freeze(bodies),
	}
	return table.freeze(step)
end

Tutorial.STEPS = table.freeze({
	define(
		"Grab",
		"Grab a slime",
		"Slimes spill from the fountain. Walk up to one and {grab}. " .. '"Grab" is free; "Buy $X" costs cash.'
	),
	define(
		"Deposit",
		"Bring it home",
		"Walk into your plot while carrying it - no button needed. "
			.. "It hops onto a free pad and earns cash every second."
	),
	define(
		"Lock",
		"Lock your base",
		'{Hold} on "Lock base" at your plot. ' .. "While it says LOCKED, nobody can steal. UNLOCKED = vulnerable!"
	),
	define("BuyPad", "Buy a pad", 'More pads = more slimes. {Hold} on "Buy pad $X" at the glowing pad on your plot.'),
	define(
		"Merge",
		"Merge",
		"Slimes of the same rarity merge into a rarer one. {Press} at the merge vat on your plot to pick them."
	),
	define(
		"Steal",
		"Steal and chase",
		'On an unlocked plot, {hold} on "Steal" by a slime. '
			.. "Chase thieves and hit them with your bat! "
			.. "Alone here? This step skips itself soon."
	),
	define(
		"Rebirth",
		"Rebirth",
		"Rich enough? Open Rebirth in the left menu for a permanent cash multiplier. "
			.. "Your ★ favourite slime stays."
	),
} :: { Step })

-- v12 servers (no tutorialStepId): numeric steps in this order.
Tutorial.LEGACY_IDS = table.freeze({ "Grab", "Deposit", "Lock", "Merge", "Steal", "Rebirth" })

function Tutorial.find(id: string): Step?
	for _, step in Tutorial.STEPS do
		if step.id == id then
			return step
		end
	end
	return nil
end

-- Defensive read of State.tutorialStep (ignores junk values).
function Tutorial.stepOf(state: any): number?
	if type(state) ~= "table" then
		return nil
	end
	local step = state.tutorialStep
	if type(step) ~= "number" or step ~= step then
		return nil
	end
	return math.floor(step)
end

local function makeView(entry: Step, index: number, total: number, kind: Kind?, key: string?): StepView
	local k: Kind = kind or "keyboard"
	return {
		id = entry.id,
		index = index,
		total = total,
		title = entry.title,
		body = if key then render(entry.template, k, key) else entry.bodies[k],
		counter = `Step {index} of {total}`,
	}
end

-- View for a step id (CONTRACT §8.3 order), nil when unknown. `key` (optional) is the shown name of the
-- prompt key / button on `kind` (default E / X).
function Tutorial.viewById(id: any, kind: Kind?, key: string?): StepView?
	if type(id) ~= "string" then
		return nil
	end
	for index, entry in Tutorial.STEPS do
		if entry.id == id then
			return makeView(entry, index, #Tutorial.STEPS, kind, key)
		end
	end
	return nil
end

-- View for a 1-based step in `ids` (default: the v13 order), nil outside it.
function Tutorial.view(stepNo: number?, ids: { string }?, kind: Kind?, key: string?): StepView?
	local order: { string } = {}
	if ids then
		order = ids
	else
		for i, entry in Tutorial.STEPS do
			order[i] = entry.id
		end
	end
	if stepNo == nil or stepNo < 1 or stepNo > #order then
		return nil
	end
	local entry = Tutorial.find(order[stepNo])
	return if entry then makeView(entry, stepNo, #order, kind, key) else nil
end

-- The overlay's view for a State snapshot (see header).
function Tutorial.fromState(state: any, kind: Kind?, key: string?): StepView?
	if type(state) ~= "table" then
		return nil
	end
	if state.tutorialStepId ~= nil then
		return Tutorial.viewById(state.tutorialStepId, kind, key)
	end
	return Tutorial.view(Tutorial.stepOf(state), Tutorial.LEGACY_IDS, kind, key)
end

return table.freeze(Tutorial)
