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
local Text = if script then require(script.Parent.Text) else require("./Text")
local Tutorial = if script then require(script.Parent.Tutorial) else require("./Tutorial")

export type Tip = { id: string, icon: string, text: string }
export type GeneralTip = { id: string, icon: string, key: string } -- key: the tip's string key
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

-- Short tutorial goal lines' string keys (the tutorial card has the long text); other steps show their title.
GuideTips.STEP_GOALS = table.freeze({
	Grab = "onboarding.guide.goal.grab",
	Deposit = "onboarding.guide.goal.deposit",
	Lock = "onboarding.guide.goal.lock",
	BuyPad = "onboarding.guide.goal.buy_pad",
	Merge = "onboarding.guide.goal.merge",
})

GuideTips.GENERAL = table.freeze({
	table.freeze({ id = "Fountain", icon = "⛲", key = "onboarding.guide.tip.fountain" }),
	table.freeze({ id = "Slap", icon = "🏏", key = "onboarding.guide.tip.slap" }),
	table.freeze({ id = "Dex", icon = "📖", key = "onboarding.guide.tip.dex" }),
} :: { GeneralTip })

-- A tip with its text in the player's language.
local function tip(id: string, icon: string, key: string): Tip
	return { id = id, icon = icon, text = Text.t(key) }
end

local function num(value: any): number
	return if type(value) == "number" and value == value then value else 0
end

local function nextGoal(state: any, rarityNames: { string }, config: any?): (string, string, string)
	local step = Tutorial.fromState(state)
	if step then
		local key = (GuideTips.STEP_GOALS :: any)[step.id]
		local goal = if key then Text.t(key) else step.title
		return (GuideTips.STEP_ICONS :: any)[step.id] or "🎯", goal, step.counter
	end
	local goals = Goals.fromServer(state.goals, config) or Goals.derive(state, rarityNames)
	for _, g in Goals.sorted(goals) do
		if not g.done then
			return "🎯", g.title, g.detail
		end
	end
	return "🌟", Text.t("onboarding.guide.keep_collecting"), Text.t("onboarding.guide.all_done")
end

-- The Guide card for a State snapshot. `now` = server time (lock check); `config` (Config) names the goals in
-- the player's language.
function GuideTips.view(state: any, rarityNames: { string }, now: number, config: any?): View
	if type(state) ~= "table" then
		return { goalIcon = "🎯", goal = Text.t(GuideTips.STEP_GOALS.Grab), goalDetail = "", tips = {} }
	end
	local icon, goal, detail = nextGoal(state, rarityNames, config)
	local tips: { Tip } = {}
	local function add(t: Tip)
		if #tips < GuideTips.MAX_TIPS then
			table.insert(tips, t)
		end
	end
	local slimes = if type(state.slimes) == "table" then state.slimes else {}
	for _, view in slimes do
		if type(view) == "table" and view.stolenBy ~= nil then
			add(tip("Stolen", "🚨", "onboarding.guide.tip.stolen"))
			break
		end
	end
	if #slimes > 0 and num(state.lockUntil) <= now then
		add(tip("Lock", "🔒", "onboarding.guide.tip.lock"))
	end
	if state.canRebirth == true then
		add(tip("Rebirth", "♻️", "onboarding.guide.tip.rebirth"))
	end
	local vat = if type(state.vat) == "table" then state.vat else nil
	if vat and type(vat.endsAt) == "number" and vat.endsAt <= now then
		add(tip("Merge", "🧪", "onboarding.guide.tip.vat_done"))
	elseif not (vat and type(vat.endsAt) == "number") and Nav.canMerge(slimes) then
		add(tip("Merge", "🧪", "onboarding.guide.tip.merge_match"))
	end
	if Nav.shopAffordable(state) then
		add(tip("Shop", "🛒", "onboarding.guide.tip.shop"))
	end
	if #slimes < num(state.padsUnlocked) then
		add(tip("Pads", "🟢", "onboarding.guide.tip.pads"))
	end
	for _, general in GuideTips.GENERAL do
		add(tip(general.id, general.icon, general.key))
	end
	return { goalIcon = icon, goal = goal, goalDetail = detail, tips = tips }
end

return table.freeze(GuideTips)
