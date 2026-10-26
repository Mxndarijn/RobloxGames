--!strict
--[[
	GuideTips

	What the Guide NPC says (v28 item 5: the Guide used to do nothing). Press
	E on "Talk" at the TutorialNpc (Constants.GUIDE_PROMPT) and the Guide card
	(Panels/Guide) shows ONE next goal and up to MAX_TIPS short tips picked
	for the player's State. Pure (tests/ui/GuideTips.spec.luau).

	Next goal, first match: the current tutorial step (Tutorial.fromState),
	else the first unfinished goal (server goals, else Goals.derive), else
	"keep collecting". Tips, in priority order: being stolen from, plot
	unlocked, a rebirth / merge / shop upgrade that's possible now, an empty
	pad; then general tips to fill up.
]]

local Goals = if script then require(script.Parent.Goals) else require("./Goals")
local Nav = if script then require(script.Parent.Nav) else require("./Nav")
local Tutorial = if script then require(script.Parent.Tutorial) else require("./Tutorial")

export type Tip = { id: string, icon: string, text: string }
export type View = { goalIcon: string, goal: string, goalDetail: string, tips: { Tip } }

local GuideTips = {}

GuideTips.MAX_TIPS = 3

-- Icon per tutorial step id.
GuideTips.STEP_ICONS = table.freeze({
	Grab = "🖐️",
	Deposit = "🏠",
	Lock = "🔒",
	BuyPad = "🟢",
	Merge = "🧪",
	Steal = "🦹",
	Rebirth = "♻️",
})

-- Short tutorial goal lines (the overlay card has the long text).
GuideTips.STEP_GOALS = table.freeze({
	Grab = "Grab a slime at the fountain",
	Deposit = "Carry it home to your plot",
	Lock = "Lock your base",
	BuyPad = "Buy another pad",
	Merge = "Merge two slimes",
	Steal = "Steal a slime from an open plot",
	Rebirth = "Rebirth for a cash multiplier",
})

GuideTips.GENERAL = table.freeze({
	table.freeze({ id = "Fountain", icon = "⛲", text = "Rare slimes spill from the fountain" }),
	table.freeze({ id = "Slap", icon = "🏏", text = "Bat thieves to get your slimes back" }),
	table.freeze({ id = "Dex", icon = "📖", text = "New slimes fill your SlimeDex" }),
} :: { Tip })

local function num(value: any): number
	return if type(value) == "number" and value == value then value else 0
end

local function nextGoal(state: any, rarityNames: { string }): (string, string, string)
	local step = Tutorial.fromState(state)
	if step then
		local goal = (GuideTips.STEP_GOALS :: any)[step.id] or step.title
		return (GuideTips.STEP_ICONS :: any)[step.id] or "🎯", goal, step.counter
	end
	local goals = Goals.fromServer(state.goals) or Goals.derive(state, rarityNames)
	for _, g in Goals.sorted(goals) do
		if not g.done then
			return "🎯", g.title, g.detail
		end
	end
	return "🌟", "Keep collecting slimes", "Every goal done. Nice!"
end

-- The Guide card for a State snapshot. `now` = server time (lock check).
function GuideTips.view(state: any, rarityNames: { string }, now: number): View
	if type(state) ~= "table" then
		return { goalIcon = "🎯", goal = "Grab a slime at the fountain", goalDetail = "", tips = {} }
	end
	local icon, goal, detail = nextGoal(state, rarityNames)
	local tips: { Tip } = {}
	local function add(tip: Tip)
		if #tips < GuideTips.MAX_TIPS then
			table.insert(tips, tip)
		end
	end
	local slimes = if type(state.slimes) == "table" then state.slimes else {}
	for _, view in slimes do
		if type(view) == "table" and view.stolenBy ~= nil then
			add({ id = "Stolen", icon = "🚨", text = "Thief has your slime: use your bat!" })
			break
		end
	end
	if #slimes > 0 and num(state.lockUntil) <= now then
		add({ id = "Lock", icon = "🔒", text = "Your plot is open: lock it" })
	end
	if state.canRebirth == true then
		add({ id = "Rebirth", icon = "♻️", text = "Rebirth is ready" })
	end
	local vat = if type(state.vat) == "table" then state.vat else nil
	if vat and type(vat.endsAt) == "number" and vat.endsAt <= now then
		add({ id = "Merge", icon = "🧪", text = "Your merge vat is done: collect it" })
	elseif not (vat and type(vat.endsAt) == "number") and Nav.canMerge(slimes) then
		add({ id = "Merge", icon = "🧪", text = "Three slimes match: Move them into the vat" })
	end
	if Nav.shopAffordable(state) then
		add({ id = "Shop", icon = "🛒", text = "You can afford a shop upgrade" })
	end
	if #slimes < num(state.padsUnlocked) then
		add({ id = "Pads", icon = "🟢", text = "Free pad: bring home another slime" })
	end
	for _, tip in GuideTips.GENERAL do
		add(tip)
	end
	return { goalIcon = icon, goal = goal, goalDetail = detail, tips = tips }
end

return table.freeze(GuideTips)
