--!strict
--[[
	MenuState

	What is on screen for the open menu key (nil = idle HUD): the dimmed
	backdrop, each card and its nav highlight all follow the one key, so with
	no menu open nothing of the menu layer shows. init.client applies this in
	setOpen; tests/ui/IdleHud.spec.luau checks the idle case at every gate size.
]]

local MenuState = {}

export type View = { backdrop: boolean, cards: { [string]: boolean }, nav: { [string]: boolean } }

function MenuState.view(openKey: string?, keys: { string }): View
	local cards, nav = {}, {}
	for _, key in keys do
		cards[key] = key == openKey
		nav[key] = key == openKey
	end
	return { backdrop = openKey ~= nil, cards = cards, nav = nav }
end

-- Every HUD banner (steal alert, rare / Secret drop, rain, modifier, weather,
-- admin event, egg, friend, pad hint) sits top-centre, right over a
-- content-sized card's title and X on phones: the whole stack shows only with
-- no menu open.
function MenuState.bannersVisible(openKey: string?): boolean
	return openKey == nil
end

-- The tutorial card and its hint ring / bubble sit over a content-sized card's
-- inputs on phone landscape (Codes box + Redeem): they show only with no menu
-- open. The step itself is untouched; closing the menu brings the same card back.
function MenuState.tutorialVisible(openKey: string?): boolean
	return openKey == nil
end

-- The daily popup is not a menu key, but its card (z 5) sits under the tutorial
-- card (z 15) and the card would cover its Claim button: it hides while the
-- popup is open too. (The welcome-back card is a menu key, so tutorialVisible
-- already covers it.)
function MenuState.tutorialShown(openKey: string?, dailyOpen: boolean): boolean
	return MenuState.tutorialVisible(openKey) and not dailyOpen
end

return MenuState
