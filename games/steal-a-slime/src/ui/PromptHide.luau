--!strict
--[[
	PromptHide

	Client half of the owner-hidden Steal prompt (CONTRACT §5.2): keeps every
	`GrabPrompt` whose `HideFromUserId` attribute equals the local UserId
	disabled locally. Roblox has no per-player prompt visibility, so the
	server sets the attribute and each client honours it.

	Deps are injected (root, localUserId, attribute name) so it runs under
	Lune with mock instances (tests/ui/PromptHide.spec.luau); the runner is
	PromptHideRunner.client.luau.

	Re-show choice: when the attribute stops matching, Enabled is set back to
	true only if *we* hid the prompt; otherwise Enabled is left to the server.
	A server Enabled flip that replicates over our local false while the
	attribute still matches is re-hidden by the Enabled watcher.

	v13 (CONTRACT §8.4 / §8.5), with `ownerAttribute` set: owner-only prompts
	(LockPrompt, BuyPadPrompt, MergePrompt; any ProximityPrompt carrying it)
	stay disabled locally unless `ShowOnlyToUserId` is the local UserId. When
	it becomes nil (free plot) the server has disabled the prompt, so a prompt
	we hid for this rule is not re-enabled; it is when it becomes us.
]]

export type Options = {
	root: Instance,
	localUserId: number,
	attribute: string, -- HideFromUserId (GrabPrompt only)
	ownerAttribute: string?, -- ShowOnlyToUserId (any prompt), v13
}

local PROMPT_NAME = "GrabPrompt"

local PromptHide = {}

function PromptHide.isGrabPrompt(inst: Instance): boolean
	return inst.Name == PROMPT_NAME and inst:IsA("ProximityPrompt")
end

-- Which rule hides `p` for this client: "grab", "owner" or nil.
function PromptHide.reason(opts: Options, p: Instance): ("grab" | "owner")?
	if PromptHide.isGrabPrompt(p) and p:GetAttribute(opts.attribute) == opts.localUserId then
		return "grab"
	end
	if opts.ownerAttribute then
		local owner = p:GetAttribute(opts.ownerAttribute)
		if owner ~= nil and owner ~= opts.localUserId then
			return "owner"
		end
	end
	return nil
end

-- Returns a function applying the hide rules to one prompt. `hidden` tracks
-- prompts this client disabled (and why), so it only re-enables those.
function PromptHide.applier(opts: Options, hidden: { [Instance]: string }): (ProximityPrompt) -> ()
	return function(p: ProximityPrompt)
		local why = PromptHide.reason(opts, p)
		if why then
			hidden[p] = why
			if p.Enabled then
				p.Enabled = false
			end
		elseif hidden[p] then
			local was = hidden[p]
			hidden[p] = nil
			-- Owner prompt on a now-free plot: the server keeps it disabled.
			local freed = was == "owner" and opts.ownerAttribute ~= nil and p:GetAttribute(opts.ownerAttribute) == nil
			if not freed then
				p.Enabled = true
			end
		end
	end
end

local function watched(opts: Options, inst: Instance): boolean
	if opts.ownerAttribute then
		return inst:IsA("ProximityPrompt")
	end
	return PromptHide.isGrabPrompt(inst)
end

-- Hides matching prompts under `opts.root` now and as they appear or change.
-- Returns a stop function that disconnects everything.
function PromptHide.start(opts: Options): () -> ()
	local hidden: { [Instance]: string } = setmetatable({}, { __mode = "k" }) :: any
	local bound: { [Instance]: { RBXScriptConnection } } = setmetatable({}, { __mode = "k" }) :: any
	local apply = PromptHide.applier(opts, hidden)

	local function bind(inst: Instance)
		if bound[inst] or not watched(opts, inst) then
			return
		end
		local p = inst :: ProximityPrompt
		local conns = {
			p:GetAttributeChangedSignal(opts.attribute):Connect(function()
				apply(p)
			end),
			p:GetPropertyChangedSignal("Enabled"):Connect(function()
				apply(p)
			end),
		}
		if opts.ownerAttribute then
			table.insert(
				conns,
				p:GetAttributeChangedSignal(opts.ownerAttribute):Connect(function()
					apply(p)
				end)
			)
		end
		bound[p] = conns
		apply(p)
	end

	local added = opts.root.DescendantAdded:Connect(bind)
	for _, inst in opts.root:GetDescendants() do
		bind(inst)
	end

	return function()
		added:Disconnect()
		for _, conns in bound do
			for _, conn in conns do
				conn:Disconnect()
			end
		end
		table.clear(bound)
	end
end

return PromptHide
