--!strict
--[[
	PurchasePrompt

	The client's one door to Roblox's purchase prompts (contract/exclusive-shop.md §3, §8). A Buy button hands it
	a `Purchase` (a Developer Product, Game Pass or subscription id from Config.EXCLUSIVE_SHOP) and it opens Roblox's
	own prompt with MarketplaceService:PromptProductPurchase / PromptGamePassPurchase / PromptSubscriptionPurchase. It grants nothing: the server's
	ProcessReceipt does, and the UI follows State. An id of 0 (not created on the Creator Dashboard yet) never
	reaches Roblox. `onClosed` tells the shop a prompt closed (bought or not), so its "Waiting for Roblox" well
	can go back to Buy.

	`new(market, player)` takes MarketplaceService and the local player, so UI specs pass a fake market.
]]

export type Purchase = { kind: "product" | "pass" | "subscription", id: number, subscriptionId: string? }

export type Adapter = {
	-- Opens Roblox's prompt; false when there is nothing to prompt (id 0, no market) or the call failed.
	prompt: (purchase: Purchase) -> boolean,
	-- `fn(bought)` runs when a prompt this client opened closes.
	onClosed: (fn: (bought: boolean) -> ()) -> (),
	-- Roblox's price text for a subscription for this player ("R$ 99": regional pricing), asked once and cached;
	-- `done(text)` runs when it is known (nil when Roblox can't say). Yields inside its own thread only.
	subscriptionPrice: ((subscriptionId: string, done: (text: string?) -> ()) -> ())?,
}

local PurchasePrompt = {}

-- True for a purchase Roblox can sell: a positive whole id.
function PurchasePrompt.onSale(purchase: Purchase?): boolean
	if purchase ~= nil and purchase.kind == "subscription" then
		return type(purchase.subscriptionId) == "string" and purchase.subscriptionId ~= ""
	end
	return purchase ~= nil and type(purchase.id) == "number" and purchase.id > 0 and purchase.id % 1 == 0
end

function PurchasePrompt.new(market: any, player: any): Adapter
	local listeners: { (boolean) -> () } = {}
	local prices: { [string]: string | false } = {} -- subscription id -> DisplayPrice (false: Roblox couldn't say)
	local function closed(bought: boolean)
		for _, fn in table.clone(listeners) do
			fn(bought)
		end
	end
	if market ~= nil then
		local userId = if player then player.UserId else nil
		market.PromptProductPurchaseFinished:Connect(function(who: any, _productId: number, bought: boolean)
			if who == userId then
				closed(bought == true)
			end
		end)
		market.PromptGamePassPurchaseFinished:Connect(function(who: any, _passId: number, bought: boolean)
			if who == player then
				closed(bought == true)
			end
		end)
	end
	return {
		prompt = function(purchase: Purchase): boolean
			if market == nil or not PurchasePrompt.onSale(purchase) then
				return false
			end
			local ok = pcall(function()
				if purchase.kind == "subscription" then
					market:PromptSubscriptionPurchase(player, purchase.subscriptionId)
				elseif purchase.kind == "pass" then
					market:PromptGamePassPurchase(player, purchase.id)
				else
					market:PromptProductPurchase(player, purchase.id)
				end
			end)
			return ok
		end,
		onClosed = function(fn: (boolean) -> ())
			table.insert(listeners, fn)
		end,
		subscriptionPrice = function(subscriptionId: string, done: (string?) -> ())
			if market == nil or type(subscriptionId) ~= "string" or subscriptionId == "" then
				done(nil)
				return
			end
			local cached = prices[subscriptionId]
			if cached ~= nil then
				done(if cached == false then nil else cached :: string)
				return
			end
			-- its own thread in Roblox (the lookup yields); inline where there is no task library (Lune specs)
			local run = if typeof(task) == "table"
				then task.spawn
				else function(fn: () -> ())
					fn()
				end
			run(function()
				local ok, info = pcall(function()
					return market:GetSubscriptionProductInfoAsync(subscriptionId)
				end)
				local text = if ok
						and type(info) == "table"
						and type(info.DisplayPrice) == "string"
					then info.DisplayPrice
					else nil
				prices[subscriptionId] = text or false
				done(text)
			end)
		end,
	}
end

return table.freeze(PurchasePrompt)
