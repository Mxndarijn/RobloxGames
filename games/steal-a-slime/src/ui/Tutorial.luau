--!strict
--[[
	Tutorial

	The tutorial card's text (TutorialCard, contract/tutorial.md): per step an icon, a title and one short hint
	that names the current device's control. Pure (tests/ui/Tutorial.spec.luau).

	Steps follow TutorialProgress.STEPS; `fromState` reads `State.tutorialStepId`. nil / unknown means no card
	(finished). The server owns progression; the UI never advances it.
]]

local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local InputKind = if Lib then require(Lib.ui.InputKind) else require("../../../../shared/luau/src/ui/InputKind")

export type Kind = InputKind.Kind
export type Step = {
	id: string,
	icon: string,
	title: string,
	done: string, -- the short mint card once the step is done
	template: string,
	body: string,
	bodies: { [Kind]: string },
}
export type StepView = {
	id: string,
	index: number,
	total: number,
	icon: string,
	title: string,
	body: string,
	counter: string,
}

local Tutorial = {}

Tutorial.KINDS = table.freeze({ "keyboard", "touch", "gamepad" } :: { Kind })

-- The KeyCode names of the prompts the steps name: the server sets KeyboardKeyCode = E on the grab and plot
-- prompts and leaves GamepadKeyCode at the ProximityPrompt default (ButtonX).
Tutorial.PROMPT_KEYS = table.freeze({ keyboard = "E", gamepad = "ButtonX" })

-- The mint card when the last step is done.
Tutorial.FINISHED = "Tutorial done"
Tutorial.FINISHED_SUB = "Next things to do are in Goals"

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

-- What each device does for a tap ({press}, {Press}) and for the hold prompts ({hold}, {Hold}); `key` is the
-- shown name of the prompt's key / button on that device.
function Tutorial.words(kind: Kind, key: string?): { [string]: string }
	if kind == "touch" then
		return { press = "tap the prompt", Press = "Tap the prompt", hold = "hold the prompt", Hold = "Hold the prompt" }
	end
	local k = if key and key ~= "" then key else Tutorial.gamepadLabel(Tutorial.PROMPT_KEYS[kind])
	return { press = `press {k}`, Press = `Press {k}`, hold = `hold {k}`, Hold = `Hold {k}` }
end

local function render(template: string, kind: Kind, key: string?): string
	return (template:gsub("{(%w+)}", Tutorial.words(kind, key)))
end

-- Every text the card may show for `step`: each device's default wording plus the gamepad one with the longest
-- button name, so the card is sized for all of them.
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

local function define(id: string, icon: string, title: string, done: string, template: string): Step
	local bodies = {} :: { [Kind]: string }
	for _, kind: Kind in Tutorial.KINDS :: { Kind } do
		bodies[kind] = render(template, kind)
	end
	local step: Step = {
		id = id,
		icon = icon,
		title = title,
		done = done,
		template = template,
		body = render(template, "keyboard"),
		bodies = table.freeze(bodies),
	}
	return table.freeze(step)
end

Tutorial.STEPS = table.freeze({
	define("Grab", "👐", "Grab a slime", "Slime grabbed", "Go to a free slime and {press}"),
	define("Deposit", "🏠", "Bring it home", "Slime home", "Walk into your plot while you carry it"),
	define("Lock", "🔒", "Lock your base", "Base locked", "Stand on your lock pad"),
	define("Leaderboard", "🏆", "Check the leaderboard", "Leaderboard found", "Walk to the Top Earners board"),
	define("Guide", "🧙", "Meet the Guide", "Guide met", "{Press} at the Guide to talk"),
	define("BuyPad", "🟩", "Buy a pad", "Pad bought", "{Hold} at the glowing pad"),
	define("Merge", "🧪", "Merge slimes", "First merge", "Brew 3 alike in your merge vat"),
	define("BuyItem", "🛒", "Buy an item", "Item bought", "Buy anything at a shop"),
} :: { Step })

function Tutorial.find(id: string): Step?
	for _, step in Tutorial.STEPS do
		if step.id == id then
			return step
		end
	end
	return nil
end

local function makeView(entry: Step, index: number, total: number, kind: Kind?, key: string?): StepView
	local k: Kind = kind or "keyboard"
	return {
		id = entry.id,
		index = index,
		total = total,
		icon = entry.icon,
		title = entry.title,
		body = if key then render(entry.template, k, key) else entry.bodies[k],
		counter = `{index}/{total}`,
	}
end

-- View for a step id, nil when unknown. `key` (optional) is the shown name of the prompt key / button on `kind`
-- (default E / X).
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

-- View for a 1-based step, nil outside the list.
function Tutorial.view(stepNo: number?, kind: Kind?, key: string?): StepView?
	local entry = if stepNo then Tutorial.STEPS[stepNo] else nil
	return if entry then makeView(entry, stepNo :: number, #Tutorial.STEPS, kind, key) else nil
end

-- The card's view for a State snapshot (see header).
function Tutorial.fromState(state: any, kind: Kind?, key: string?): StepView?
	if type(state) ~= "table" then
		return nil
	end
	return Tutorial.viewById(state.tutorialStepId, kind, key)
end

return table.freeze(Tutorial)
