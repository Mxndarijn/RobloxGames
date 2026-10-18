--!strict
--[[
	MenuClose

	Gamepad B (and Esc while Layout.CLOSE_WITH_ESCAPE) closes whichever menu
	is open: the nav menus, the Shop opened from the ShopStand prompt and the
	Guide card all go through the one setOpen(nil) the client passes in.
	Bound through ContextActionService (not UserInputService) so it fires
	whether or not Roblox already processed the key (gameProcessedEvent), and
	it Sinks the key only while a menu is open, so Esc still reaches Roblox's
	own menu otherwise. Takes the service as an argument so
	tests/ui/MenuClose.spec.luau can drive it with a fake.
]]

local MenuClose = {}

-- Prompt name -> menu key: "Open Shop" at the ShopStand, "Talk" at the Guide NPC. With the world shops the server
-- opens a shop at its stand (ShopEvent Open), so the shop prompt opens no menu from here.
function MenuClose.promptMenus(shopPrompt: string, guidePrompt: string, worldShops: boolean?): { [string]: string }
	if worldShops then
		return { [guidePrompt] = "Guide" }
	end
	return { [shopPrompt] = "Shop", [guidePrompt] = "Guide" }
end

-- What Esc / B closes: the Daily popup sits over every card, so it wins; the bag panel only shows with no card open.
function MenuClose.topKey(openKey: string?, dailyOpen: boolean, bagOpen: boolean?): string?
	if dailyOpen then
		return "Daily"
	end
	return openKey or (if bagOpen then MenuClose.BAG else nil)
end

export type Service = {
	BindAction: (
		self: any,
		name: string,
		handler: (string, Enum.UserInputState, any) -> any,
		touch: boolean,
		...any
	) -> (),
}

MenuClose.ACTION = "CloseMenu"
MenuClose.BAG = "Bag"

function MenuClose.bind(service: Service, withEscape: boolean, getOpen: () -> string?, close: () -> ())
	local function handler(_: string, inputState: Enum.UserInputState)
		if inputState ~= Enum.UserInputState.Begin or getOpen() == nil then
			return Enum.ContextActionResult.Pass
		end
		close()
		return Enum.ContextActionResult.Sink
	end
	if withEscape then
		service:BindAction(MenuClose.ACTION, handler, false, Enum.KeyCode.ButtonB, Enum.KeyCode.Escape)
	else
		service:BindAction(MenuClose.ACTION, handler, false, Enum.KeyCode.ButtonB)
	end
	return handler
end

return MenuClose
