--!strict
--[[
	SlimeMove (FEATURES.MoveSlime, CONTRACT.md §3 MoveSlime)

	Move mode for one of your own pad slimes, started by its E "Move" prompt (SlimeKeys). Client-only until the
	place: the slime turns see-through for this player, a see-through copy (the ghost) sits on the target pad and
	the pad is tinted by what a place would do:

	  * green: empty pad, the slime moves there;
	  * yellow: another slime sits there, the two swap pads;
	  * red: a locked pad (refused);
	  * grey: the slime's own pad (placing just ends move mode).
	The vat lights green when it takes the slime, yellow when it takes it but the player's rank can't merge that
	rarity yet (Shared.MergeGate: the place goes through), red when it refuses.

	Target: the pad under the mouse / the tap, else the unlocked pad nearest the character. Place: click or tap a
	pad, E, gamepad ButtonX or the Place button, which sends Request MoveSlime(slimeId, pad); a refusal shows its
	reason in the bar and move mode stays on. Cancel: Q, gamepad ButtonB, the Cancel button, leaving your home
	zone, or the slime leaving its pad (stolen, sold, merged). While moving, every ProximityPrompt is off for this
	player and held tools are put away, so a click places instead of swinging the bat.

	Pure helpers (classify, nearest, statusText, hintText) carry the rules and are tested under Lune
	(tests/ui/SlimeMove.spec.luau); `new` builds the bottom bar and runs the mode in the live game.
]]

local UI = script.Parent
local InputKind = require(UI.InputKind)
local Layout = require(UI.Layout)
local Widgets = require(UI.Widgets)

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants") :: any)
local MergeGate = require(Shared:WaitForChild("MergeGate") :: any)
local VatState = require(Shared:WaitForChild("VatState") :: any)

local Theme = Widgets.Theme
local create = Widgets.create

local SlimeMove = {}

export type PadClass = "same" | "empty" | "swap" | "locked" | "vat" | "vatGated" | "vatRefused"
export type PadSpot = { index: number, position: Vector3 }

SlimeMove.FADE = 0.75 -- LocalTransparencyModifier on the picked-up slime
SlimeMove.GHOST_ALPHA = 0.45 -- the ghost keeps this share of each part's opacity
SlimeMove.HIGHLIGHT_FILL = 0.55 -- pad tint fill transparency
SlimeMove.SETTLE_SECONDS = 1.5 -- after a place, the ghost waits at most this long for the slime to move
SlimeMove.VAT = 0 -- target index of the plot's merge vat (pads are 1..)
SlimeMove.PLACE_ACTION = "SlimeMovePlace"
SlimeMove.CANCEL_ACTION = "SlimeMoveCancel"
SlimeMove.BAR = table.freeze({
	pad = 12,
	nameH = 22,
	nameSize = 18,
	statusY = 34,
	statusH = 20,
	statusSize = 15,
	hintY = 56,
	hintH = 18,
	hintSize = 13,
	buttonW = 80,
	gap = 8,
	textReserve = 186, -- room on the right for Place + Cancel
})

-- What placing the slime (now on `fromPad`) on `pad` would do. `occupied[p]` = a slime sits on pad p.
function SlimeMove.classify(
	pad: number,
	fromPad: number?,
	padsUnlocked: number,
	occupied: { [number]: boolean }
): PadClass
	if pad == fromPad then
		return "same"
	end
	if pad < 1 or pad > padsUnlocked then
		return "locked"
	end
	return if occupied[pad] then "swap" else "empty"
end

-- What placing `slime` in the merge vat would do, from State.vat (VatState.checkLoad, the server's rules):
-- "vat" (it goes in), "vatGated" (it goes in, but `rebirths` can't merge its rarity yet; the reason is
-- MergeGate.opensText) or "vatRefused" with the reason ("The vat is full", "The vat takes Common slimes", ...).
function SlimeMove.vatClass(vat: any, slime: any, rebirths: number?): (PadClass, string?)
	if type(slime) ~= "table" then
		return "vatRefused", "Pick one of your slimes"
	end
	local ids = if type(vat) == "table" and type(vat.ids) == "table" then vat.ids else {}
	local tier = if type(vat) == "table" and type(vat.tier) == "number" then vat.tier else nil
	local brewing = type(vat) == "table" and type(vat.endsAt) == "number"
	local ok, reason = VatState.checkLoad(ids, tier, brewing, slime)
	if not ok then
		return "vatRefused", reason
	end
	if rebirths and not MergeGate.allows(slime.tier, rebirths) then
		return "vatGated", MergeGate.opensText(slime.tier)
	end
	return "vat", nil
end

-- The bar's status line for the vat as the target: what goes in and the load after it, or why it can't.
function SlimeMove.vatStatus(class: PadClass, slimeName: string, count: number, reason: string?): string
	if class == "vat" then
		return `Merge vat: adds {slimeName} ({count + 1}/{VatState.SIZE})`
	elseif class == "vatGated" then
		return `Merge vat: adds {slimeName} ({count + 1}/{VatState.SIZE}). {reason or ""}.`
	end
	return reason or "The vat can't take this slime"
end

-- The target nearest `point`: an unlocked pad (1..padsUnlocked) or the vat (SlimeMove.VAT); nil when none.
function SlimeMove.nearest(pads: { PadSpot }, point: Vector3, padsUnlocked: number): number?
	local best, bestDist = nil, math.huge
	for _, spot in pads do
		if spot.index == SlimeMove.VAT or (spot.index >= 1 and spot.index <= padsUnlocked) then
			local d = (spot.position - point).Magnitude
			if d < bestDist then
				best, bestDist = spot.index, d
			end
		end
	end
	return best
end

-- The bar's status line for a target pad (`otherName` = the slime a swap would trade with).
function SlimeMove.statusText(class: PadClass?, pad: number?, otherName: string?): string
	if class == nil or pad == nil then
		return "Point at one of your pads"
	elseif class == "same" then
		return `Pad {pad}: this slime's own pad`
	elseif class == "locked" then
		return `Pad {pad} is locked: buy it first`
	elseif class == "swap" then
		return `Pad {pad}: swaps with {otherName or "that slime"}`
	end
	return `Pad {pad}: empty`
end

-- The bar's controls line for the player's input.
function SlimeMove.hintText(input: "keyboard" | "touch" | "gamepad"): string
	if input == "touch" then
		return "Tap a pad or the vat to place it there"
	elseif input == "gamepad" then
		return "X: place on the lit pad or vat · B: cancel"
	end
	return "Click a pad or the vat, or press E to place · Q to cancel"
end

local function classColor(class: PadClass?): Color3
	if class == "empty" or class == "vat" then
		return Theme.Good
	elseif class == "swap" or class == "vatGated" then
		return Theme.Warn
	elseif class == "locked" or class == "vatRefused" then
		return Theme.Bad
	end
	return Theme.Muted
end

export type Deps = {
	plots: Instance, -- workspace.Plots
	player: Player,
	camera: () -> Camera?,
	ghostParent: () -> Instance, -- where the ghost and the pad tint live (the camera: client-only)
	raycast: (origin: Vector3, direction: Vector3, params: RaycastParams) -> RaycastResult?,
	uis: UserInputService,
	cas: ContextActionService,
	prompts: ProximityPromptService,
	onActive: ((active: boolean) -> ())?, -- move mode started (true) / ended (false): the hotbar steps aside
}

-- A Move ghost part's transparency from the slime part's `transparency` and its own one before the merge vat's fade
-- (`own`, Constants.OWN_TRANSPARENCY_ATTRIBUTE): a slime in the vat would otherwise be faded twice into nothing.
function SlimeMove.ghostTransparency(transparency: number, own: any): number
	local base = if type(own) == "number" then own else transparency
	return 1 - (1 - base) * SlimeMove.GHOST_ALPHA
end

-- A see-through, inert copy of `model`: no prompts, scripts, labels, tags or attributes (so no client runner
-- binds it), anchored and not collidable. nil when the model can't be cloned.
local function makeGhost(model: Model): Model?
	local ok, clone = pcall(function()
		return model:Clone()
	end)
	if not ok or clone == nil then
		return nil
	end
	local ghost = clone :: Model
	local function scrub(inst: Instance)
		for _, tag in inst:GetTags() do
			inst:RemoveTag(tag)
		end
		for key in inst:GetAttributes() do
			inst:SetAttribute(key, nil)
		end
	end
	scrub(ghost)
	for _, d in ghost:GetDescendants() do
		if
			d:IsA("ProximityPrompt")
			or d:IsA("LuaSourceContainer")
			or d:IsA("LayerCollector")
			or d:IsA("Highlight")
			or d:IsA("Sound")
		then
			d:Destroy()
		elseif d.Parent then
			local own = d:GetAttribute(Constants.OWN_TRANSPARENCY_ATTRIBUTE)
			scrub(d)
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
				d.Transparency = SlimeMove.ghostTransparency(d.Transparency, own)
			elseif d:IsA("Decal") then
				d.Transparency = SlimeMove.ghostTransparency(d.Transparency, own)
			end
		end
	end
	ghost.Name = "SlimeMoveGhost"
	return ghost
end

-- The top of `pad`, where a slime model (pivot at its bottom centre) rests.
local function padTop(pad: BasePart): CFrame
	local mesh = pad:FindFirstChild("VatMesh")
	if mesh and mesh:IsA("Model") then
		-- The vat: the ghost rests on its goo.
		local box, size = mesh:GetBoundingBox()
		return CFrame.new(box.Position + Vector3.new(0, size.Y / 2, 0))
	elseif mesh and mesh:IsA("BasePart") then
		return CFrame.new(mesh.Position + Vector3.new(0, mesh.Size.Y / 2, 0))
	end
	return pad.CFrame * CFrame.new(0, pad.Size.Y / 2, 0)
end

-- True when zone-local point `p` is inside a HomeZone of half-size `half`, the same box the server uses
-- (WorldView.pointInHomeZone): a little slack below and above, and `reachUp` (the zone's ReachUp attribute) more
-- above so the upper jars of the tower count as home.
function SlimeMove.withinZone(p: Vector3, half: Vector3, reachUp: number?): boolean
	local top = half.Y + 8 + (if type(reachUp) == "number" then reachUp else 0)
	return math.abs(p.X) <= half.X and math.abs(p.Z) <= half.Z and p.Y >= -half.Y - 4 and p.Y <= top
end

-- True when `position` is inside the plot's HomeZone (no zone = true).
local function inHomeZone(plot: Instance, position: Vector3): boolean
	local zone = plot:FindFirstChild("HomeZone")
	if not zone or not zone:IsA("BasePart") then
		return true
	end
	local p = zone.CFrame:PointToObjectSpace(position)
	return SlimeMove.withinZone(p, zone.Size / 2, zone:GetAttribute("ReachUp"))
end

function SlimeMove.new(parent: Instance, ctx: any, deps: Deps)
	local B = SlimeMove.BAR
	local frame = create("Frame", {
		Name = "MoveBar",
		Visible = false,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -24),
		Size = UDim2.fromOffset(460, 84),
		BackgroundColor3 = Theme.Bg,
		BackgroundTransparency = 0.1,
		ZIndex = Layout.ZINDEX.Carry,
		Parent = parent,
	}, { Widgets.corner(12), Widgets.stroke(Theme.Good, 2) })
	local name = Widgets.label({
		Name = "SlimeName",
		Font = Theme.Font,
		TextSize = B.nameSize,
		Position = UDim2.fromOffset(B.pad, 8),
		Size = UDim2.new(1, -B.textReserve, 0, B.nameH),
		Parent = frame,
	})
	local status = Widgets.label({
		Name = "Status",
		TextSize = B.statusSize,
		Position = UDim2.fromOffset(B.pad, B.statusY),
		Size = UDim2.new(1, -B.textReserve, 0, B.statusH),
		Parent = frame,
	})
	local hint = Widgets.label({
		Name = "Hint",
		TextSize = B.hintSize,
		TextColor3 = Theme.Muted,
		Position = UDim2.fromOffset(B.pad, B.hintY),
		Size = UDim2.new(1, -B.textReserve, 0, B.hintH),
		Parent = frame,
	})

	local place: () -> ()
	local cancel: () -> ()
	local placeBtn = Widgets.button(
		{
			Name = "Place",
			Text = "Place",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -(B.pad + B.buttonW + B.gap), 0.5, 0),
			Size = UDim2.fromOffset(B.buttonW, Layout.BUTTON),
		},
		Theme.Good,
		function()
			place()
		end
	)
	placeBtn.instance.Parent = frame
	local cancelBtn = Widgets.button(
		{
			Name = "Cancel",
			Text = "Cancel",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -B.pad, 0.5, 0),
			Size = UDim2.fromOffset(B.buttonW, Layout.BUTTON),
		},
		Theme.Bad,
		function()
			cancel()
		end
	)
	cancelBtn.instance.Parent = frame

	local state: any = nil -- the latest State
	type Active = {
		id: string,
		model: Model,
		plot: Instance,
		pads: { [number]: BasePart },
		faded: { Instance },
		ghost: Model?,
		tint: Highlight,
		hover: number?, -- pad under the mouse / tap
		target: number?,
		conns: { RBXScriptConnection },
		promptsWere: boolean,
		pending: boolean, -- a MoveSlime request is in flight
		error: string?,
	}
	local active: Active? = nil

	local function myPlot(): Instance?
		for _, plot in deps.plots:GetChildren() do
			if plot:GetAttribute("OwnerUserId") == deps.player.UserId then
				return plot
			end
		end
		return nil
	end

	local function padsOf(plot: Instance): { [number]: BasePart }
		local out = {}
		for _, child in plot:GetChildren() do
			local index = child:GetAttribute("PadIndex")
			if child:IsA("BasePart") and type(index) == "number" then
				out[index] = child
			end
		end
		local vat = plot:FindFirstChild("MergeVat")
		if vat and vat:IsA("BasePart") then
			out[SlimeMove.VAT] = vat
		end
		return out
	end

	-- From State: the slime's pad, which pads hold a slime, and their names.
	local function layoutOf(id: string): (number?, { [number]: boolean }, { [number]: string }, number)
		local occupied, names = {}, {}
		local fromPad = nil
		local slimes = if type(state) == "table" and type(state.slimes) == "table" then state.slimes else {}
		for _, view in slimes do
			local slime = view.slime
			if type(slime) == "table" and type(slime.pad) == "number" then
				occupied[slime.pad] = true
				names[slime.pad] = ctx.Genome.displayName(slime)
				if slime.id == id then
					fromPad = slime.pad
				end
			end
		end
		local unlocked = if type(state) == "table" and type(state.padsUnlocked) == "number"
			then state.padsUnlocked
			else 0
		return fromPad, occupied, names, unlocked
	end

	-- The slime `id` from State, and State.vat.
	local function slimeOf(id: string): any?
		local slimes = if type(state) == "table" and type(state.slimes) == "table" then state.slimes else {}
		for _, view in slimes do
			if type(view.slime) == "table" and view.slime.id == id then
				return view.slime
			end
		end
		return nil
	end

	local function vatOf(): any?
		return if type(state) == "table" then state.vat else nil
	end

	local function rebirthsOf(): number?
		return if type(state) == "table" and type(state.rebirths) == "number" then state.rebirths else nil
	end

	local function rootPart(): BasePart?
		local character = deps.player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		return if root and root:IsA("BasePart") then root else nil
	end

	local function inputKind(): InputKind.Kind
		return InputKind.kind(deps.uis)
	end

	-- Ends move mode and puts everything back (`keepGhost` = the server is moving the slime: the ghost and the
	-- faded slime stay until the model lands or SETTLE_SECONDS pass).
	local function finish(keepGhost: boolean?)
		local a = active
		if not a then
			return
		end
		active = nil
		frame.Visible = false
		if deps.onActive then
			deps.onActive(false)
		end
		for _, c in a.conns do
			c:Disconnect()
		end
		deps.cas:UnbindAction(SlimeMove.PLACE_ACTION)
		deps.cas:UnbindAction(SlimeMove.CANCEL_ACTION)
		deps.prompts.Enabled = a.promptsWere
		a.tint:Destroy()
		local function restore()
			for _, inst in a.faded do
				(inst :: any).LocalTransparencyModifier = 0
			end
			if a.ghost then
				a.ghost:Destroy()
			end
		end
		local body = a.model:FindFirstChild("Body")
		if keepGhost and body and body:IsA("BasePart") then
			local done = false
			local conn: RBXScriptConnection? = nil
			local function settle()
				if done then
					return
				end
				done = true
				if conn then
					conn:Disconnect()
				end
				restore()
			end
			conn = body:GetPropertyChangedSignal("CFrame"):Connect(settle)
			task.delay(SlimeMove.SETTLE_SECONDS, settle)
		else
			restore()
		end
	end

	-- Re-picks the target pad and redraws the ghost, the tint and the bar.
	local function refresh()
		local a = active
		if not a then
			return
		end
		local fromPad, occupied, names, unlocked = layoutOf(a.id)
		local target = a.hover
		if target == nil then
			local root = rootPart()
			if root then
				local spots = {}
				for index, pad in a.pads do
					table.insert(spots, { index = index, position = pad.Position })
				end
				target = SlimeMove.nearest(spots, root.Position, unlocked)
			end
		end
		a.target = target
		local pad = target and a.pads[target]
		local class: PadClass?, vatReason: string? = nil, nil
		if target == SlimeMove.VAT then
			class, vatReason = SlimeMove.vatClass(vatOf(), slimeOf(a.id), rebirthsOf())
		elseif target then
			class = SlimeMove.classify(target, fromPad, unlocked, occupied)
		end
		if pad then
			a.tint.Adornee = pad
			a.tint.FillColor = classColor(class)
			a.tint.OutlineColor = classColor(class)
			if a.ghost then
				a.ghost:PivotTo(padTop(pad))
			end
		else
			a.tint.Adornee = nil
		end
		if a.error then
			status.Text = a.error
			status.TextColor3 = Theme.Bad
		elseif a.pending then
			status.Text = "Moving..."
			status.TextColor3 = Theme.Muted
		elseif target == SlimeMove.VAT and class then
			local slime = slimeOf(a.id)
			local vat = vatOf()
			local count = if type(vat) == "table" and type(vat.ids) == "table" then #vat.ids else 0
			local slimeName = if slime then ctx.Genome.displayName(slime) else "this slime"
			status.Text = SlimeMove.vatStatus(class, slimeName, count, vatReason)
			status.TextColor3 = classColor(class)
		else
			status.Text = SlimeMove.statusText(class, target, if target then names[target] else nil)
			status.TextColor3 = classColor(class)
		end
		placeBtn.setEnabled(not a.pending and class ~= nil and class ~= "locked" and class ~= "vatRefused")
	end

	-- The pad under screen point `position` (mouse or touch), or nil.
	local function padAt(a: Active, position: Vector3): number?
		local camera = deps.camera()
		if not camera then
			return nil
		end
		local ray = camera:ScreenPointToRay(position.X, position.Y)
		local list = {}
		for _, pad in a.pads do
			table.insert(list, pad)
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = list
		local hit = deps.raycast(ray.Origin, ray.Direction * 1000, params)
		local vat = a.pads[SlimeMove.VAT]
		if hit and vat and (hit.Instance == vat or hit.Instance:IsDescendantOf(vat)) then
			return SlimeMove.VAT
		end
		local index = hit and hit.Instance:GetAttribute("PadIndex")
		return if type(index) == "number" then index else nil
	end

	place = function()
		local a = active
		if not a or a.pending then
			return
		end
		refresh()
		local target = a.target
		if target == nil then
			return
		end
		if target == SlimeMove.VAT then
			local vatClass, reason = SlimeMove.vatClass(vatOf(), slimeOf(a.id))
			if vatClass == "vatRefused" then
				a.error = reason
				refresh()
				a.error = nil
				return
			end
			a.pending = true
			a.error = nil
			refresh()
			ctx.ask("VatAdd", function(result: any)
				if active ~= a then
					return
				end
				if type(result) == "table" and result.ok ~= false then
					finish()
				else
					a.pending = false
					a.error = if type(result) == "table" and type(result.message) == "string"
						then result.message
						else "the vat didn't take it"
					refresh()
					a.error = nil
				end
			end, a.id)
			return
		end
		local fromPad, occupied, _, unlocked = layoutOf(a.id)
		local class = SlimeMove.classify(target, fromPad, unlocked, occupied)
		if class == "locked" then
			a.error = SlimeMove.statusText(class, target)
			refresh()
			a.error = nil
			return
		elseif class == "same" then
			finish()
			return
		end
		a.pending = true
		a.error = nil
		refresh()
		ctx.ask("MoveSlime", function(result: any)
			if active ~= a then
				return
			end
			if type(result) == "table" and result.ok ~= false then
				finish(true)
			else
				a.pending = false
				local message = if type(result) == "table" and type(result.message) == "string"
					then result.message
					else "the move didn't go through"
				a.error = `Can't move: {message}`
				refresh()
				a.error = nil
			end
		end, a.id, target)
	end

	cancel = function()
		finish()
	end

	local self = {}

	-- Starts moving slime `id` (its model on your pad). A move already running is cancelled first.
	function self.start(id: string, model: Model)
		finish()
		if deps.player:GetAttribute("Carrying") ~= nil then
			return
		end
		local plot = myPlot()
		if not plot or not model:IsDescendantOf(plot) then
			return
		end
		local faded = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") or d:IsA("Decal") then
				(d :: any).LocalTransparencyModifier = SlimeMove.FADE
				table.insert(faded, d)
			end
		end
		local ghost = makeGhost(model)
		if ghost then
			ghost.Parent = deps.ghostParent()
		end
		local tint = create("Highlight", {
			Name = "SlimeMovePadTint",
			FillTransparency = SlimeMove.HIGHLIGHT_FILL,
			OutlineTransparency = 0,
			DepthMode = Enum.HighlightDepthMode.Occluded,
			Parent = deps.ghostParent(),
		}) :: Highlight
		local a: Active = {
			id = id,
			model = model,
			plot = plot,
			pads = padsOf(plot),
			faded = faded,
			ghost = ghost,
			tint = tint,
			hover = nil,
			target = nil,
			conns = {},
			promptsWere = deps.prompts.Enabled,
			pending = false,
			error = nil,
		}
		active = a
		deps.prompts.Enabled = false
		if deps.onActive then
			deps.onActive(true)
		end
		local character = deps.player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid:UnequipTools()
		end

		local priority = Enum.ContextActionPriority.High.Value + 1
		deps.cas:BindActionAtPriority(SlimeMove.PLACE_ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				place()
			end
			return Enum.ContextActionResult.Sink
		end, false, priority, Enum.KeyCode.E, Enum.KeyCode.ButtonX)
		deps.cas:BindActionAtPriority(SlimeMove.CANCEL_ACTION, function(_, inputState)
			if inputState == Enum.UserInputState.Begin then
				cancel()
			end
			return Enum.ContextActionResult.Sink
		end, false, priority, Enum.KeyCode.Q, Enum.KeyCode.ButtonB)

		table.insert(
			a.conns,
			deps.uis.InputChanged:Connect(function(input: InputObject)
				if input.UserInputType == Enum.UserInputType.MouseMovement and active == a then
					a.hover = padAt(a, input.Position)
					refresh()
				end
			end)
		)
		table.insert(
			a.conns,
			deps.uis.InputBegan:Connect(function(input: InputObject, processed: boolean)
				if processed or active ~= a then
					return
				end
				local kind = input.UserInputType
				if kind == Enum.UserInputType.MouseButton1 or kind == Enum.UserInputType.Touch then
					local index = padAt(a, input.Position)
					if index then
						a.hover = index
						place()
					end
				end
			end)
		)
		table.insert(
			a.conns,
			model:GetAttributeChangedSignal("State"):Connect(function()
				if model:GetAttribute("State") ~= "Pad" and active == a and not a.pending then
					finish()
				end
			end)
		)
		table.insert(
			a.conns,
			model.AncestryChanged:Connect(function()
				if not model:IsDescendantOf(plot) and active == a then
					finish()
				end
			end)
		)

		local fromPad = layoutOf(id)
		local view = nil
		for _, v in (if type(state) == "table" and type(state.slimes) == "table" then state.slimes else {}) do
			if v.slime and v.slime.id == id then
				view = v
			end
		end
		name.Text = if view then `Moving {ctx.Genome.displayName(view.slime)}` else "Moving slime"
		if fromPad then
			name.Text ..= ` (pad {fromPad})`
		end
		hint.Text = SlimeMove.hintText(inputKind())
		frame.Visible = true
		refresh()
	end

	-- Called by the client's 10 Hz loop: re-picks the nearest pad as the character walks, cancels on leaving home.
	function self.tick()
		local a = active
		if not a then
			return
		end
		local root = rootPart()
		if not root or not inHomeZone(a.plot, root.Position) then
			finish()
			return
		end
		refresh()
	end

	function self.update(next: any)
		state = next
		refresh()
	end

	-- Bottom card box from Layout.screen (the carry overlay's slot: you can't move a slime while carrying one).
	function self.layout(screen: Layout.Screen)
		frame.AnchorPoint = Vector2.zero
		frame.Position = UDim2.fromOffset(screen.carry.x, screen.carry.y)
		frame.Size = UDim2.fromOffset(screen.carry.w, screen.carry.h)
	end

	function self.isActive(): boolean
		return active ~= nil
	end

	self.cancel = cancel
	self.place = place
	self.frame = frame

	return self
end

return SlimeMove
