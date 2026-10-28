--!strict
--[[
	PurchaseService (contract/exclusive-shop.md §3, FEATURES.ExclusiveShop)

	Robux purchases between MarketplaceService and Purchases:
	  * `service(options)` (backend injected, runs under Lune): `processReceipt` decides one Developer Product
	    receipt through the shared ReceiptLedger: player not in this server / data not loaded / unknown product ->
	    NotProcessedYet; a PurchaseId already in `data.receipts` -> PurchaseGranted; else Purchases.grant, record the
	    id and save now (`options.save`, the session-locked Persistence save); only a written save answers
	    PurchaseGranted. `join` checks the Game Passes (UserOwnsGamePassAsync; passId 0 is skipped) and the paid
	    random items policy once per player; `passPurchased` handles PromptGamePassPurchaseFinished. `grantProduct`,
	    `setPass` and `setPaidRandomAllowed` are the same paths for StudioHooks.
	  * `start(service)` (Roblox only): sets the one `MarketplaceService.ProcessReceipt`, connects the Game Pass prompt
	    and runs `join` for every player once their session exists. Does nothing while the flag is off.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Config = if Shared then require(Shared.Config) else require("../shared/Config")
local Economy = if Shared then require(Shared.Economy) else require("../shared/Economy")
local Lib = if script then (game:GetService("ReplicatedStorage") :: any).Lib else nil
local ReceiptLedger = if Lib
	then require(Lib.data.ReceiptLedger)
	else require("../../../../shared/luau/src/data/ReceiptLedger")
local Purchases = if script then require(script.Parent.Purchases) else require("./Purchases")
local World = if script then require(script.Parent.World) else require("./World")

export type Decision = "PurchaseGranted" | "NotProcessedYet"

-- The fields of a MarketplaceService receipt this service reads.
export type Receipt = { PlayerId: number, ProductId: number, PurchaseId: string }

export type Backend = {
	ownsPass: (userId: number, passId: number) -> boolean, -- may error
	paidRandomRestricted: (userId: number) -> boolean, -- PolicyService ArePaidRandomItemsRestricted; may error
}

export type Options = {
	world: World.World,
	backend: Backend,
	save: (userId: number, data: any) -> boolean, -- writes the session's save now (yields); true = written
	now: () -> number,
	wait: (seconds: number) -> (),
	changed: (() -> ())?, -- after a grant or pass change: push the view and State
	ctx: Purchases.Context?,
	attempts: number?, -- tries per Game Pass / policy call (default 3)
}

export type Service = {
	processReceipt: (receipt: Receipt) -> Decision,
	grantProduct: (userId: number, productKey: string, purchaseId: string) -> Decision,
	join: (userId: number) -> (),
	passPurchased: (userId: number, passId: number, purchased: boolean) -> (),
	setPass: (userId: number, passKey: string, owned: boolean) -> boolean,
	setPaidRandomAllowed: (userId: number, allowed: boolean) -> boolean,
	release: (userId: number) -> (),
	enabled: () -> boolean,
	options: Options,
}

local PurchaseService = {}

function PurchaseService.service(options: Options): Service
	local world = options.world
	local attempts = options.attempts or 3
	local pending: { [number]: { [string]: boolean } } = {} -- userId -> PurchaseIds granted but not saved yet
	local owned: { [number]: { [string]: boolean } } = {} -- userId -> pass key -> owned
	local self = {} :: Service
	self.options = options

	function self.enabled(): boolean
		return Purchases.enabled(options.ctx)
	end

	local function changed()
		if options.changed then
			pcall(options.changed) -- a view hiccup never turns a saved grant into an error
		end
	end

	-- Runs `fn` up to `attempts` times, waiting 1, 2, 4 s between tries; nil when every try errored.
	local function try(fn: () -> boolean): boolean?
		local delay = 1
		for i = 1, attempts do
			local ok, result = pcall(fn)
			if ok then
				return result
			end
			if i < attempts then
				options.wait(delay)
				delay *= 2
			end
		end
		return nil
	end

	function self.grantProduct(userId: number, productKey: string, purchaseId: string): Decision
		if not self.enabled() then
			return "NotProcessedYet"
		end
		local session = World.session(world, userId)
		if not session or Purchases.product(productKey) == nil then
			return "NotProcessedYet"
		end
		local mine = pending[userId] or {}
		pending[userId] = mine
		local data = session.data
		local decision = ReceiptLedger.process({
			list = data.receipts,
			id = purchaseId,
			cap = Config.EXCLUSIVE_SHOP.receiptMemory,
			pending = mine,
			grant = function()
				return Purchases.grant(world, session, productKey, options.now(), options.ctx)
			end,
			save = function()
				local ok, written = pcall(options.save, userId, data)
				return ok and written == true
			end,
		})
		changed()
		return if decision == "Granted" then "PurchaseGranted" else "NotProcessedYet"
	end

	function self.processReceipt(receipt: Receipt): Decision
		local key = Purchases.keyForProductId(receipt.ProductId)
		if not key or type(receipt.PlayerId) ~= "number" then
			return "NotProcessedYet"
		end
		return self.grantProduct(receipt.PlayerId, key, tostring(receipt.PurchaseId))
	end

	local function apply(userId: number)
		local session = World.session(world, userId)
		if not session then
			return
		end
		local extra = Purchases.applyPasses(session, owned[userId] or {})
		if extra > 0 then
			World.notify(
				world,
				userId,
				`Offline x2 pass: +${Economy.formatNumber(extra)} more from your time away!`,
				"good",
				"Cash"
			)
		end
		changed()
	end

	-- Checks every Game Pass with an id and the paid random items policy (yields); the session must exist.
	function self.join(userId: number)
		if not self.enabled() or not World.session(world, userId) then
			return
		end
		local mine = owned[userId] or {}
		owned[userId] = mine
		for key, def in Config.EXCLUSIVE_SHOP.passes do
			if def.passId ~= 0 and not mine[key] then
				mine[key] = try(function()
					return options.backend.ownsPass(userId, def.passId)
				end) == true
			end
		end
		local restricted = try(function()
			return options.backend.paidRandomRestricted(userId)
		end)
		local session = World.session(world, userId)
		if session and restricted ~= nil and session.paidRandomAllowed == nil then
			session.paidRandomAllowed = not restricted
		end
		apply(userId)
	end

	function self.setPass(userId: number, passKey: string, has: boolean): boolean
		if not self.enabled() or Config.EXCLUSIVE_SHOP.passes[passKey] == nil or not World.session(world, userId) then
			return false
		end
		local mine = owned[userId] or {}
		owned[userId] = mine
		mine[passKey] = has
		apply(userId)
		return true
	end

	function self.passPurchased(userId: number, passId: number, purchased: boolean)
		local key = Purchases.keyForPassId(passId)
		if purchased and key and self.setPass(userId, key, true) then
			World.notify(world, userId, "Game Pass unlocked. Thank you!", "good", "Gift")
			changed()
		end
	end

	function self.setPaidRandomAllowed(userId: number, allowed: boolean): boolean
		local session = World.session(world, userId)
		if not self.enabled() or not session then
			return false
		end
		session.paidRandomAllowed = allowed
		World.markDirty(session)
		changed()
		return true
	end

	function self.release(userId: number)
		pending[userId] = nil
		owned[userId] = nil
	end

	return self
end

-- The Roblox calls behind Backend (Roblox only).
function PurchaseService.robloxBackend(): Backend
	return {
		ownsPass = function(userId: number, passId: number): boolean
			return game:GetService("MarketplaceService"):UserOwnsGamePassAsync(userId, passId)
		end,
		paidRandomRestricted = function(userId: number): boolean
			local PolicyService = game:GetService("PolicyService")
			local player = game:GetService("Players"):GetPlayerByUserId(userId)
			if not player then
				error("player left")
			end
			return PolicyService:GetPolicyInfoForPlayerAsync(player).ArePaidRandomItemsRestricted == true
		end,
	}
end

-- Roblox wiring: the one ProcessReceipt, the Game Pass prompt, and `join` for each player once their data loaded.
function PurchaseService.start(service: Service)
	if not service.enabled() then
		return
	end
	local MarketplaceService = game:GetService("MarketplaceService")
	local Players = game:GetService("Players")
	MarketplaceService.ProcessReceipt = function(receipt: any)
		local decision = service.processReceipt(receipt)
		return if decision == "PurchaseGranted"
			then Enum.ProductPurchaseDecision.PurchaseGranted
			else Enum.ProductPurchaseDecision.NotProcessedYet
	end
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(
		function(player: Player, passId: number, purchased: boolean)
			service.passPurchased(player.UserId, passId, purchased)
		end
	)
	local function joined(player: Player)
		local world = service.options.world
		local deadline = os.clock() + 120
		while player.Parent and not World.session(world, player.UserId) and os.clock() < deadline do
			task.wait(0.5)
		end
		if player.Parent then
			service.join(player.UserId)
		end
	end
	Players.PlayerAdded:Connect(function(player)
		task.spawn(joined, player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		service.release(player.UserId)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(joined, player)
	end
end

return PurchaseService
