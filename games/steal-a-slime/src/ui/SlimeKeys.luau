--!strict
--[[
	SlimeKeys

	Your own slimes are managed at their pads with keys, no card: every slime model on a pad whose `OwnerUserId`
	is the local player gets two client-only ProximityPrompts on its Body:

	  * `FavoritePrompt` (R, gamepad DPadUp; tap): "Favorite" or "Unfavorite", sends Favorite(slimeId) / Favorite(nil). The
	    favourite's prompt shows its follow-pet perk (State.petPerk). Mystery Eggs (models with `EggKind`) get none:
	    an egg can't be the favourite.
	  * `SellPrompt` (X, gamepad DPadDown; hold to confirm): "Sell $450" from State.slimes[i].sellPrice, sends Sell(slimeId).
	    Mystery Eggs get none: an egg can't be sold.
	  * `MovePrompt` (E, gamepad DPadRight; tap), only with `moveKey` / `onMove` (FEATURES.MoveSlime): "Move" calls
	    `onMove(slimeId, model)`, which starts move mode (SlimeMove).

	Hatch stays the server's HatchPrompt (F, gamepad ButtonX). Every key comes from Constants.SLIME_PROMPT_KEYS, where
	no two prompts share one. The server's GrabPrompt on the same
	Body is hidden from the owner (PromptHide). Prompts go when the slime leaves the pad (carried, escaping, sold,
	merged) and come back when it returns. `update(state)` refreshes their texts from the latest State.

	Deps come in `opts` (root, newPrompt, keys, send, formatCash), so it runs under Lune with mock instances
	(tests/ui/SlimeKeys.spec.luau). `destroy` removes every prompt it made.
]]

export type Key = { keyboard: Enum.KeyCode, gamepad: Enum.KeyCode }
export type KeyNames = { keyboard: string, gamepad: string } -- Enum.KeyCode names (Constants.SLIME_PROMPT_KEYS)

export type Options = {
	root: Instance, -- workspace
	localUserId: number,
	newPrompt: () -> ProximityPrompt, -- Instance.new("ProximityPrompt") in the game
	favoriteKey: Key,
	sellKey: Key,
	distance: number, -- studs (Config.PLOT_PAD_PROMPT_DISTANCE)
	holdSeconds: number, -- Sell's hold (Config.HOLD_CONFIRM_SECONDS)
	formatCash: (n: number) -> string, -- Format.formatCash
	send: (action: string, ...any) -> (), -- Request through the client's sender
	style: Enum.ProximityPromptStyle?, -- Custom in the game: SlimeKeyCard draws one card for all of them
	moveKey: Key?, -- FEATURES.MoveSlime: the Move prompt's keys; nil = no Move prompt
	onMove: ((slimeId: string, model: Model) -> ())?,
}

export type Labels = {
	favorite: { action: string, object: string }?, -- nil: no Favorite prompt (an egg)
	sell: { action: string, object: string }?, -- nil: no Sell prompt (an egg)
}

export type Handle = {
	update: (state: any) -> (),
	destroy: () -> (),
}

local SlimeKeys = {}

SlimeKeys.FAVORITE_PROMPT = "FavoritePrompt"
SlimeKeys.SELL_PROMPT = "SellPrompt"
SlimeKeys.MOVE_PROMPT = "MovePrompt"
SlimeKeys.MOVE_TEXT = "Move"
SlimeKeys.PAD_STATE = "Pad"

-- The Enum.KeyCode pair named by `names` (an entry of Constants.SLIME_PROMPT_KEYS).
function SlimeKeys.keyOf(names: KeyNames): Key
	local codes = Enum.KeyCode :: any
	return { keyboard = codes[names.keyboard], gamepad = codes[names.gamepad] }
end

local OWNER_ATTRIBUTE = "OwnerUserId"
local STATE_ATTRIBUTE = "State"
local ID_ATTRIBUTE = "SlimeId"
local EGG_ATTRIBUTE = "EggKind"
local GRAB_PROMPT_NAME = "GrabPrompt"
local HATCH_PROMPT_NAME = "HatchPrompt" -- the server's, on a ready Mystery Egg (Constants.HATCH_PROMPT_NAME)

-- The slime model a `Body` part belongs to, or nil.
local function slimeModel(body: Instance): Model?
	local parent = body.Parent
	if body.Name ~= "Body" or not body:IsA("BasePart") or not parent or not parent:IsA("Model") then
		return nil
	end
	return if type(parent:GetAttribute(ID_ATTRIBUTE)) == "string" then parent else nil
end

-- True when the local player should see the keys on this slime: theirs, and sitting on a pad.
function SlimeKeys.wants(model: Instance, localUserId: number): boolean
	return model:GetAttribute(OWNER_ATTRIBUTE) == localUserId
		and model:GetAttribute(STATE_ATTRIBUTE) == SlimeKeys.PAD_STATE
end

-- The view of slime `id` in `state` (State.slimes), or nil.
local function viewOf(state: any, id: string): any?
	if type(state) ~= "table" or type(state.slimes) ~= "table" then
		return nil
	end
	for _, view in state.slimes do
		if type(view) == "table" and type(view.slime) == "table" and view.slime.id == id then
			return view
		end
	end
	return nil
end

-- Prompt texts for slime `id` named `name` (`isEgg` from the model) in `state` (nil before the first State). An egg
-- gets neither prompt: it can't be the favourite or be sold.
function SlimeKeys.labels(id: string, name: string, isEgg: boolean, state: any, formatCash: (number) -> string): Labels
	if isEgg then
		return { favorite = nil, sell = nil }
	end
	local view = viewOf(state, id)
	local price = if view and type(view.sellPrice) == "number" then view.sellPrice else nil
	local isFav = type(state) == "table" and state.favoriteId == id
	local perk = if isFav and type(state.petPerk) == "table" then state.petPerk else nil
	return {
		favorite = {
			action = if isFav then "Unfavorite" else "Favorite",
			object = if perk then `{perk.icon} {perk.text}` else name,
		},
		sell = { action = if price then `Sell {formatCash(price)}` else "Sell", object = "" },
	}
end

function SlimeKeys.start(opts: Options): Handle
	type Entry = {
		model: Model,
		conns: { RBXScriptConnection },
		favorite: ProximityPrompt?,
		sell: ProximityPrompt?,
		move: ProximityPrompt?,
		triggers: { [string]: RBXScriptConnection }, -- each prompt's Triggered, by entry key
	}
	local bound: { [Instance]: Entry } = {}
	local state: any = nil

	local function idOf(model: Model): string?
		local id = model:GetAttribute(ID_ATTRIBUTE)
		return if type(id) == "string" then id else nil
	end

	local function nameOf(body: BasePart): string
		local grab = body:FindFirstChild(GRAB_PROMPT_NAME)
		return if grab and grab:IsA("ProximityPrompt") then grab.ObjectText else ""
	end

	local function makePrompt(
		body: BasePart,
		name: string,
		key: Key,
		hold: number,
		onTrigger: () -> ()
	): (ProximityPrompt, RBXScriptConnection)
		local prompt = opts.newPrompt()
		prompt.Name = name
		prompt.KeyboardKeyCode = key.keyboard
		prompt.GamepadKeyCode = key.gamepad
		prompt.HoldDuration = hold
		if opts.style then
			prompt.Style = opts.style
		end
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = opts.distance
		local conn = prompt.Triggered:Connect(onTrigger)
		prompt.Parent = body
		return prompt, conn
	end

	-- Sets the prompts' texts from the latest State.
	local function label(body: BasePart, entry: Entry)
		local id = idOf(entry.model)
		if not id then
			return
		end
		local isEgg = entry.model:GetAttribute(EGG_ATTRIBUTE) ~= nil
		local l = SlimeKeys.labels(id, nameOf(body), isEgg, state, opts.formatCash)
		if entry.favorite and l.favorite then
			entry.favorite.ActionText = l.favorite.action
			entry.favorite.ObjectText = l.favorite.object
		end
		if entry.sell and l.sell then
			entry.sell.ActionText = l.sell.action
			entry.sell.ObjectText = l.sell.object
		end
	end

	local function drop(entry: Entry, key: "favorite" | "sell" | "move")
		local prompt: ProximityPrompt? = (entry :: any)[key]
		if prompt then
			prompt:Destroy();
			(entry :: any)[key] = nil
		end
		local trigger = entry.triggers[key]
		if trigger then
			trigger:Disconnect()
			entry.triggers[key] = nil
		end
	end

	local function clear(entry: Entry)
		drop(entry, "favorite")
		drop(entry, "sell")
		drop(entry, "move")
	end

	local function apply(body: BasePart)
		local entry = bound[body]
		if not entry then
			return
		end
		local model = entry.model
		local want = SlimeKeys.wants(model, opts.localUserId)
		if not want then
			clear(entry)
			return
		end
		local isEgg = model:GetAttribute(EGG_ATTRIBUTE) ~= nil
		if isEgg then
			drop(entry, "favorite")
			drop(entry, "sell")
		end
		if not isEgg and not entry.favorite then
			local prompt, conn = makePrompt(body, SlimeKeys.FAVORITE_PROMPT, opts.favoriteKey, 0, function()
				local id = idOf(model)
				if id and SlimeKeys.wants(model, opts.localUserId) and model:GetAttribute(EGG_ATTRIBUTE) == nil then
					local isFav = type(state) == "table" and state.favoriteId == id
					if isFav then
						opts.send("Favorite", nil)
					else
						opts.send("Favorite", id)
					end
				end
			end)
			entry.favorite = prompt
			entry.triggers.favorite = conn
		end
		if not isEgg and not entry.sell then
			local prompt, conn = makePrompt(body, SlimeKeys.SELL_PROMPT, opts.sellKey, opts.holdSeconds, function()
				local id = idOf(model)
				if id and SlimeKeys.wants(model, opts.localUserId) and model:GetAttribute(EGG_ATTRIBUTE) == nil then
					opts.send("Sell", id)
				end
			end)
			entry.sell = prompt
			entry.triggers.sell = conn
		end
		local moveKey, onMove = opts.moveKey, opts.onMove
		if moveKey and onMove and not entry.move then
			local prompt, conn = makePrompt(body, SlimeKeys.MOVE_PROMPT, moveKey, 0, function()
				local id = idOf(model)
				if id and SlimeKeys.wants(model, opts.localUserId) then
					onMove(id, model)
				end
			end)
			prompt.ActionText = SlimeKeys.MOVE_TEXT
			prompt.ObjectText = ""
			entry.move = prompt
			entry.triggers.move = conn
		end
		-- The server's HatchPrompt (on only while the egg can hatch) joins the card: same style as ours.
		local hatch = body:FindFirstChild(HATCH_PROMPT_NAME)
		if opts.style and hatch and hatch:IsA("ProximityPrompt") then
			hatch.Style = opts.style
		end
		label(body, entry)
	end

	local function unbind(body: Instance)
		local entry = bound[body]
		if not entry then
			return
		end
		bound[body] = nil
		for _, c in entry.conns do
			c:Disconnect()
		end
		clear(entry)
	end

	local function bind(inst: Instance)
		if bound[inst] then
			return
		end
		local model = slimeModel(inst)
		if not model then
			return
		end
		local body = inst :: BasePart
		local function refresh()
			apply(body)
		end
		bound[body] = {
			model = model,
			triggers = {},
			conns = {
				model:GetAttributeChangedSignal(OWNER_ATTRIBUTE):Connect(refresh),
				model:GetAttributeChangedSignal(STATE_ATTRIBUTE):Connect(refresh),
				model:GetAttributeChangedSignal(EGG_ATTRIBUTE):Connect(refresh),
				body.ChildAdded:Connect(function(child: Instance)
					if child.Name == HATCH_PROMPT_NAME then
						refresh()
					end
				end),
				body.AncestryChanged:Connect(function()
					if not body:IsDescendantOf(opts.root) then
						unbind(body)
					end
				end),
			},
		}
		refresh()
	end

	local added = opts.root.DescendantAdded:Connect(bind)
	for _, inst in opts.root:GetDescendants() do
		bind(inst)
	end

	local handle: Handle = {
		update = function(next: any)
			state = next
			for body, entry in bound do
				label(body :: BasePart, entry)
			end
		end,
		destroy = function()
			added:Disconnect()
			for body in table.clone(bound) do
				unbind(body)
			end
		end,
	}
	return handle
end

return table.freeze(SlimeKeys)
