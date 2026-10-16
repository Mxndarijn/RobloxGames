--!strict
--[[
	MenuState

	What is on screen for the open menu key (nil = idle HUD): the dimmed
	backdrop, each card and its nav highlight all follow the one key, so with
	no menu open nothing of the menu layer shows. init.client applies this in
	setOpen; tests/ui/IdleHud.spec.luau checks the idle case at every gate size.
]]

local MenuState = {}

export type Rect = { x: number, y: number, w: number, h: number }

export type View = { backdrop: boolean, cards: { [string]: boolean }, nav: { [string]: boolean } }

function MenuState.view(openKey: string?, keys: { string }): View
	local cards, nav = {}, {}
	for _, key in keys do
		cards[key] = key == openKey
		nav[key] = key == openKey
	end
	return { backdrop = openKey ~= nil, cards = cards, nav = nav }
end

-- A card hidden from outside (its Visible set false by a script, not setOpen)
-- closes the menu with it: true when the open key must drop to nil.
function MenuState.cardHidden(openKey: string?, key: string, visible: boolean): boolean
	return openKey == key and not visible
end

-- Every HUD banner (steal alert, rare / Secret drop, rain, modifier, weather,
-- admin event, egg, friend, pad hint) sits top-centre, right over a
-- content-sized card's title and X on phones: the whole stack shows only with
-- no menu open.
function MenuState.bannersVisible(openKey: string?): boolean
	return openKey == nil
end

-- The banner stack's box for the open key: nil (nothing drawn) while a menu is open.
function MenuState.bannerRect(openKey: string?, idleRect: Rect): Rect?
	if MenuState.bannersVisible(openKey) then
		return idleRect
	end
	return nil
end

return MenuState
