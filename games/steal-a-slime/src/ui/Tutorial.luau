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

export type Step = { id: string, title: string, body: string }
export type StepView = { id: string, index: number, total: number, title: string, body: string, counter: string }

local Tutorial = {}

Tutorial.STEPS = table.freeze({
	table.freeze({
		id = "Grab",
		title = "Grab a slime",
		body = "Slimes spill from the fountain. Walk up to one and press E (or tap the prompt). "
			.. '"Grab" is free; "Buy $X" costs cash.',
	}),
	table.freeze({
		id = "Deposit",
		title = "Bring it home",
		body = "Walk into your plot while carrying it - no button needed. "
			.. "It hops onto a free pad and earns cash every second.",
	}),
	table.freeze({
		id = "Lock",
		title = "Lock your base",
		body = 'Tap the blue 🔒 Lock button (top bar), or press E on "Lock base" at your plot. '
			.. "While it says LOCKED, nobody can steal. UNLOCKED = vulnerable!",
	}),
	table.freeze({
		id = "BuyPad",
		title = "Buy a pad",
		body = 'More pads = more slimes. Press E on "Buy pad $X" at the glowing pad on your plot, '
			.. 'or tap "Buy next pad" in the top bar.',
	}),
	table.freeze({
		id = "Merge",
		title = "Merge",
		body = "Two slimes of the same rarity merge into a rarer one. "
			.. "Open Merge in the left menu, or press E at the merge vat on your plot.",
	}),
	table.freeze({
		id = "Steal",
		title = "Steal and chase",
		body = 'On an unlocked plot, hold E on "Steal" by a slime. '
			.. "Chase thieves and tap SLAP! "
			.. "Alone here? This step skips itself soon.",
	}),
	table.freeze({
		id = "Rebirth",
		title = "Rebirth",
		body = "Rich enough? Open Rebirth in the left menu for a permanent cash multiplier. "
			.. "Your ★ favourite slime stays.",
	}),
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

local function makeView(entry: Step, index: number, total: number): StepView
	return {
		id = entry.id,
		index = index,
		total = total,
		title = entry.title,
		body = entry.body,
		counter = `Step {index} of {total}`,
	}
end

-- View for a step id (CONTRACT §8.3 order), nil when unknown.
function Tutorial.viewById(id: any): StepView?
	if type(id) ~= "string" then
		return nil
	end
	for index, entry in Tutorial.STEPS do
		if entry.id == id then
			return makeView(entry, index, #Tutorial.STEPS)
		end
	end
	return nil
end

-- View for a 1-based step in `ids` (default: the v13 order), nil outside it.
function Tutorial.view(step: number?, ids: { string }?): StepView?
	local order = ids
	if order == nil then
		order = {}
		for i, entry in Tutorial.STEPS do
			order[i] = entry.id
		end
	end
	if step == nil or step < 1 or step > #order then
		return nil
	end
	local entry = Tutorial.find(order[step])
	return if entry then makeView(entry, step, #order) else nil
end

-- The overlay's view for a State snapshot (see header).
function Tutorial.fromState(state: any): StepView?
	if type(state) ~= "table" then
		return nil
	end
	if state.tutorialStepId ~= nil then
		return Tutorial.viewById(state.tutorialStepId)
	end
	return Tutorial.view(Tutorial.stepOf(state), Tutorial.LEGACY_IDS)
end

return table.freeze(Tutorial)
