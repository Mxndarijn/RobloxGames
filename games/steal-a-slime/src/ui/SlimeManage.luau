--!strict
--[[
	SlimeManage

	Your own slimes are managed at your base: every slime model on a pad whose `OwnerUserId` is the local player
	gets a client-only ProximityPrompt `ManagePrompt` on its Body ("Manage", E). Triggering it calls
	`onManage(slimeId)`, which opens that slime's card (Panels/Plot focus: favourite, sell, hatch).
	The server's GrabPrompt on the same Body is hidden from the owner (PromptHide), so E is free for this one.
	The prompt goes when the slime leaves the pad (carried, escaping, sold, merged) and comes back when it returns.

	Deps come in `opts` (root, localUserId, newPrompt, keyCode), so it runs under Lune with mock instances
	(tests/ui/SlimeManage.spec.luau). `start` returns a stop function that removes every prompt it made.
]]

export type Options = {
	root: Instance, -- workspace
	localUserId: number,
	newPrompt: () -> ProximityPrompt, -- Instance.new("ProximityPrompt") in the game
	keyCode: Enum.KeyCode, -- Enum.KeyCode.E
	distance: number, -- studs (Config.PLOT_PAD_PROMPT_DISTANCE)
	onManage: (slimeId: string) -> (),
}

local SlimeManage = {}

SlimeManage.PROMPT_NAME = "ManagePrompt"
SlimeManage.ACTION_TEXT = "Manage"
SlimeManage.PAD_STATE = "Pad"

local OWNER_ATTRIBUTE = "OwnerUserId"
local STATE_ATTRIBUTE = "State"
local ID_ATTRIBUTE = "SlimeId"
local GRAB_PROMPT_NAME = "GrabPrompt"

-- The slime model a `Body` part belongs to, or nil.
local function slimeModel(body: Instance): Model?
	local parent = body.Parent
	if body.Name ~= "Body" or not body:IsA("BasePart") or not parent or not parent:IsA("Model") then
		return nil
	end
	return if type(parent:GetAttribute(ID_ATTRIBUTE)) == "string" then parent else nil
end

-- True when the local player should see Manage on this slime: theirs, and sitting on a pad.
function SlimeManage.wants(model: Instance, localUserId: number): boolean
	return model:GetAttribute(OWNER_ATTRIBUTE) == localUserId
		and model:GetAttribute(STATE_ATTRIBUTE) == SlimeManage.PAD_STATE
end

function SlimeManage.start(opts: Options): () -> ()
	local bound: { [Instance]: { conns: { RBXScriptConnection }, prompt: ProximityPrompt? } } = {}

	local function apply(body: BasePart, model: Model)
		local entry = bound[body]
		if not entry then
			return
		end
		local want = SlimeManage.wants(model, opts.localUserId)
		if want and not entry.prompt then
			local prompt = opts.newPrompt()
			prompt.Name = SlimeManage.PROMPT_NAME
			prompt.ActionText = SlimeManage.ACTION_TEXT
			local grab = body:FindFirstChild(GRAB_PROMPT_NAME)
			prompt.ObjectText = if grab and grab:IsA("ProximityPrompt") then grab.ObjectText else ""
			prompt.KeyboardKeyCode = opts.keyCode
			prompt.HoldDuration = 0
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = opts.distance
			table.insert(
				entry.conns,
				prompt.Triggered:Connect(function()
					local id = model:GetAttribute(ID_ATTRIBUTE)
					if type(id) == "string" and SlimeManage.wants(model, opts.localUserId) then
						opts.onManage(id)
					end
				end)
			)
			prompt.Parent = body
			entry.prompt = prompt
		elseif not want and entry.prompt then
			entry.prompt:Destroy()
			entry.prompt = nil
		end
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
		if entry.prompt then
			entry.prompt:Destroy()
		end
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
			apply(body, model)
		end
		bound[body] = {
			conns = {
				model:GetAttributeChangedSignal(OWNER_ATTRIBUTE):Connect(refresh),
				model:GetAttributeChangedSignal(STATE_ATTRIBUTE):Connect(refresh),
				body.AncestryChanged:Connect(function()
					if not body:IsDescendantOf(opts.root) then
						unbind(body)
					end
				end),
			},
			prompt = nil,
		}
		refresh()
	end

	local added = opts.root.DescendantAdded:Connect(bind)
	for _, inst in opts.root:GetDescendants() do
		bind(inst)
	end

	return function()
		added:Disconnect()
		for body in table.clone(bound) do
			unbind(body)
		end
	end
end

return table.freeze(SlimeManage)
