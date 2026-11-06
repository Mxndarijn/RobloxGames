--!strict
--[[
	Tutorial

	The tutorial card's text (TutorialCard, contract/tutorial.md): per step an icon, a title and one short hint
	that names the current device's control, drawn through Text (Strings/Onboarding "onboarding.tutorial.*").
	Pure (tests/ui/Tutorial.spec.luau).

	Steps follow TutorialProgress.STEPS; `fromState` reads `State.tutorialStepId`. nil / unknown means no card
	(finished). The server owns progression; the UI never advances it.
]]

local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local InputKind = if Lib then require(Lib.ui.InputKind) else require("../../../../shared/luau/src/ui/InputKind")
local Text = if script then require(script.Parent.Text) else require("./Text")

export type Kind = InputKind.Kind
-- `key` names the step's strings ("onboarding.tutorial.<key>.title", ".done", and ".body", or for a step with
-- a prompt ".body_key" with the key's name and ".body_touch"); `prompt` is the prompt the hint names, if any.
export type Step = {
	id: string,
	icon: string,
	key: string,
	prompt: ("press" | "hold")?,
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

-- The mint card when the last step is done (string keys).
Tutorial.FINISHED = "onboarding.tutorial.finished"
Tutorial.FINISHED_SUB = "onboarding.tutorial.finished_sub"

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

local function stringKey(step: Step, field: string): string
	return `onboarding.tutorial.{step.key}.{field}`
end

function Tutorial.title(step: Step): string
	return Text.t(stringKey(step, "title"))
end

-- The short mint card once the step is done.
function Tutorial.done(step: Step): string
	return Text.t(stringKey(step, "done"))
end

-- The hint line on `kind` (default keyboard); `key` is the shown name of the prompt's key / button on that
-- device (default E / X). Touch taps or holds the prompt itself.
function Tutorial.body(step: Step, kind: Kind?, key: string?): string
	if step.prompt == nil then
		return Text.t(stringKey(step, "body"))
	end
	local k: Kind = kind or "keyboard"
	if k == "touch" then
		return Text.t(stringKey(step, "body_touch"))
	end
	local name = if key and key ~= "" then key else Tutorial.gamepadLabel(Tutorial.PROMPT_KEYS[k])
	return Text.t(stringKey(step, "body_key"), { key = name })
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
		table.insert(out, Tutorial.body(step, kind))
	end
	table.insert(out, Tutorial.body(step, "gamepad", widest))
	return out
end

local function define(id: string, icon: string, key: string, prompt: ("press" | "hold")?): Step
	local step: Step = { id = id, icon = icon, key = key, prompt = prompt }
	return table.freeze(step)
end

Tutorial.STEPS = table.freeze({
	define("Grab", "👐", "grab", "press"),
	define("Deposit", "🏠", "deposit"),
	define("Lock", "🔒", "lock"),
	define("Leaderboard", "🏆", "leaderboard"),
	define("Guide", "🧙", "guide", "press"),
	define("BuyPad", "🟩", "buy_pad", "hold"),
	define("Merge", "🧪", "merge"),
	define("BuyItem", "🛒", "buy_item"),
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
		title = Tutorial.title(entry),
		body = Tutorial.body(entry, k, key),
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
