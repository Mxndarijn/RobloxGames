--!strict
--[[
	LockBreakPrompt

	"Open locked door" on other players' locked bases (contract/exclusive-shop.md §11, FEATURES.ExclusiveShop). A
	client-only ProximityPrompt on each base's door (Plot_<i>.LockBarrier.Stopper, the cork in jar 1's doorway) reads
	"Open locked door · R$499", or "Use lock break" while State has a saved lock break. ExclusiveShopView.lockBreakQuickBuy
	decides when it shows: someone else's base, locked now, not already letting you through, with the shop on. Your
	own base, a free or open base and a running lock break on that door show nothing.

	A press (hold HOLD_CONFIRM_SECONDS) with a credit asks UseCredit("lockBreak", plot). Otherwise it aims first:
	AimLockBreak(plot), and only once the server takes the aim does Roblox's prompt for LockBreak open (the receipt
	can't name the door). A refused aim (a breather lock, a friend's base, ...) shows the server's reason on the prompt
	for a few seconds instead. A product without a Roblox id yet reads "Not on sale yet" and does nothing.

	Event driven on plot attributes (OwnerUserId, Locked, LockUntil, Guests) plus `update(state)`; `tick()` (the
	client's 10 Hz loop) catches a lock running out and a refusal fading. Deps come in `opts`, so it runs under Lune
	with mock instances (tests/ui/LockBreakPrompt.spec.luau). `destroy` removes every prompt it made.
]]

local ExclusiveShopView = if script then require(script.Parent.ExclusiveShopView) else require("./ExclusiveShopView")

export type Options = {
	plots: Instance, -- workspace.Plots
	localUserId: number,
	newPrompt: () -> ProximityPrompt, -- Instance.new("ProximityPrompt") in the game
	config: any, -- Shared Config
	serverNow: () -> number,
	clock: () -> number, -- os.clock: how long a refusal stays on the prompt
	holdSeconds: number, -- Config.HOLD_CONFIRM_SECONDS
	canAim: boolean, -- Request AimLockBreak exists
	canUseCredit: boolean, -- Request UseCredit takes "lockBreak"
	creditArg: (plotIndex: number) -> any, -- UseCredit's second argument for a plot (LockBreakPrompt.creditArg)
	-- Like ctx.ask: `done` gets the RequestResult or the refusal ({ ok = false, message }).
	ask: (action: string, done: (any) -> (), ...any) -> (),
	purchase: any, -- the PurchasePrompt adapter
	attributes: { owner: string, locked: string, lockUntil: string, guests: string, index: string },
}

export type Handle = {
	update: (state: any) -> (),
	tick: () -> (),
	prompts: { [Instance]: ProximityPrompt }, -- plot -> its prompt (tests)
	destroy: () -> (),
}

local LockBreakPrompt = {}

LockBreakPrompt.PROMPT = "LockBreakPrompt"
LockBreakPrompt.STYLE = table.freeze({
	distance = 10, -- studs from the door
	refusalSeconds = 4, -- a refused aim's reason stays on the prompt this long
	pendingSeconds = 5, -- a request without an answer blocks another press this long at most
})

-- UseCredit's second argument for `plotIndex`: the number ("target?" and "number?" take one), or its text where
-- Remotes only takes an id string ("string?").
function LockBreakPrompt.creditArg(argType: string?, plotIndex: number): any
	if argType == "string?" or argType == "string" then
		return tostring(plotIndex)
	end
	return plotIndex
end

-- The prompt texts for quick-buy `q`: { action, object }.
function LockBreakPrompt.texts(q: ExclusiveShopView.QuickBuy, refusal: string?): (string, string)
	if refusal then
		return ExclusiveShopView.OPEN_LOCKED_DOOR, refusal
	end
	if q.mode == "offsale" then
		return ExclusiveShopView.OFF_SALE, ExclusiveShopView.OPEN_LOCKED_DOOR
	end
	return q.text, ""
end

function LockBreakPrompt.start(opts: Options): Handle
	local A = opts.attributes
	local latest: any = nil
	-- `pending`: os.clock of a request in flight (a call that never answers stops blocking after pendingSeconds).
	type Entry = { prompt: ProximityPrompt?, conns: { RBXScriptConnection }, pending: number? }
	local entries: { [Instance]: Entry } = {}
	local refusals: { [Instance]: { text: string, at: number } } = {}
	local prompts: { [Instance]: ProximityPrompt } = {}

	local function door(plot: Instance): ExclusiveShopView.Door
		local index = plot:GetAttribute(A.index)
		local owner = plot:GetAttribute(A.owner)
		local lockUntil = plot:GetAttribute(A.lockUntil)
		local guests = plot:GetAttribute(A.guests)
		return {
			index = if type(index) == "number" then index else 0,
			owner = if type(owner) == "number" then owner else nil,
			locked = plot:GetAttribute(A.locked) == true,
			lockUntil = if type(lockUntil) == "number" and lockUntil > 0 then lockUntil else nil,
			guests = if type(guests) == "string" then guests else nil,
		}
	end

	local function quick(plot: Instance): ExclusiveShopView.QuickBuy?
		return ExclusiveShopView.lockBreakQuickBuy(
			latest,
			door(plot),
			opts.localUserId,
			opts.serverNow(),
			opts.config,
			opts.canAim,
			opts.canUseCredit
		)
	end

	local function stopperOf(plot: Instance): BasePart?
		local barrier = plot:FindFirstChild("LockBarrier")
		local stopper = barrier and barrier:FindFirstChild("Stopper")
		return if stopper and stopper:IsA("BasePart") then stopper else nil
	end

	local apply: (plot: Instance) -> ()

	local function trigger(plot: Instance)
		local entry = entries[plot]
		local q = quick(plot)
		if entry == nil or q == nil then
			return
		end
		if entry.pending and opts.clock() - entry.pending < LockBreakPrompt.STYLE.pendingSeconds then
			return
		end
		local index = door(plot).index
		-- `then_` runs once the server took the request; a refusal shows its reason on the prompt instead.
		local function call(action: string, then_: (() -> ())?, ...: any)
			entry.pending = opts.clock()
			opts.ask(action, function(result: any)
				entry.pending = nil
				if type(result) == "table" and result.ok == false then
					local text = if type(result.message) == "string" and result.message ~= ""
						then result.message
						else ExclusiveShopView.LOCK_BREAK_REFUSED
					refusals[plot] = { text = text, at = opts.clock() }
					apply(plot)
				elseif then_ then
					then_()
				end
			end, ...)
		end
		if q.mode == "credit" then
			call("UseCredit", nil, "lockBreak", opts.creditArg(index))
		elseif q.mode == "buy" and q.purchase then
			local purchase = q.purchase
			call("AimLockBreak", function()
				if opts.purchase then
					opts.purchase.prompt(purchase)
				end
			end, index)
		end
	end

	function apply(plot: Instance)
		local entry = entries[plot]
		if entry == nil then
			return
		end
		local refusal = refusals[plot]
		if refusal and opts.clock() - refusal.at >= LockBreakPrompt.STYLE.refusalSeconds then
			refusals[plot] = nil
			refusal = nil
		end
		local q = quick(plot)
		if q and entry.prompt == nil then
			local stopper = stopperOf(plot)
			if stopper then
				local prompt = opts.newPrompt()
				prompt.Name = LockBreakPrompt.PROMPT
				prompt.RequiresLineOfSight = false
				prompt.MaxActivationDistance = LockBreakPrompt.STYLE.distance
				prompt.HoldDuration = opts.holdSeconds
				prompt.Parent = stopper
				table.insert(
					entry.conns,
					prompt.Triggered:Connect(function()
						trigger(plot)
					end)
				)
				entry.prompt = prompt
				prompts[plot] = prompt
			end
		end
		local prompt = entry.prompt
		if prompt then
			if q then
				local action, object = LockBreakPrompt.texts(q, if refusal then refusal.text else nil)
				if prompt.ActionText ~= action then
					prompt.ActionText = action
				end
				if prompt.ObjectText ~= object then
					prompt.ObjectText = object
				end
			end
			local on = q ~= nil
			if prompt.Enabled ~= on then
				prompt.Enabled = on
			end
		end
	end

	local function track(plot: Instance)
		if entries[plot] or not plot:IsA("Model") then
			return
		end
		local entry: Entry = { prompt = nil, conns = {}, pending = nil }
		entries[plot] = entry
		for _, name in { A.owner, A.locked, A.lockUntil, A.guests } do
			table.insert(
				entry.conns,
				plot:GetAttributeChangedSignal(name):Connect(function()
					apply(plot)
				end)
			)
		end
		apply(plot)
	end

	local function untrack(plot: Instance)
		local entry = entries[plot]
		if not entry then
			return
		end
		entries[plot] = nil
		refusals[plot] = nil
		prompts[plot] = nil
		for _, c in entry.conns do
			c:Disconnect()
		end
		if entry.prompt then
			entry.prompt:Destroy()
		end
	end

	local conns = {
		opts.plots.ChildAdded:Connect(track),
		opts.plots.ChildRemoved:Connect(untrack),
	}
	for _, plot in opts.plots:GetChildren() do
		track(plot)
	end

	local handle: Handle = {
		prompts = prompts,
		update = function(state: any)
			latest = state
			for plot in entries do
				apply(plot)
			end
		end,
		tick = function()
			for plot in entries do
				apply(plot)
			end
		end,
		destroy = function()
			for _, c in conns do
				c:Disconnect()
			end
			for plot in table.clone(entries) do
				untrack(plot)
			end
		end,
	}
	return handle
end

return table.freeze(LockBreakPrompt)
