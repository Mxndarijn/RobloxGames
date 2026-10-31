--!strict
--[[
	GooTubePrompt

	Client rule for the goo tube's DropPrompt (CONTRACT.md §5.3): it shows only when it can be used. Roblox has no
	per-player prompt visibility, so the server marks each prompt (TubeOpen: the top jar's hatch; TubeOwner: the
	plot owner) and every client sets Enabled locally to

	    open  and  owner == me  and  I carry nothing (Player attribute Carrying is nil)

	A server Enabled write that replicates over the local value is set back by the Enabled watcher. The server still
	refuses a drop it should not run (Actions.useDropTube); this only hides the prompt.

	Deps are injected (root, player, localUserId) so it runs under Lune with mock instances
	(tests/ui/GooTubePrompt.spec.luau).
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local Constants = if Shared then require(Shared.Constants) else require("../shared/Constants")

export type Options = {
	root: Instance, -- searched for DropPrompts (workspace)
	player: Instance, -- the local Player: its Carrying attribute
	localUserId: number,
}

local GooTubePrompt = {}

-- Whether this client may see a tube prompt.
function GooTubePrompt.shown(open: any, owner: any, localUserId: number, carrying: any): boolean
	return open == true and owner == localUserId and carrying == nil
end

local function isTubePrompt(inst: Instance): boolean
	return inst.Name == Constants.DROP_PROMPT_NAME and inst:IsA("ProximityPrompt")
end

-- Keeps every DropPrompt under `opts.root` in step, now and as prompts appear or change. Returns a stop function.
function GooTubePrompt.start(opts: Options): () -> ()
	local bound: { [Instance]: { RBXScriptConnection } } = setmetatable({}, { __mode = "k" }) :: any

	local function apply(p: ProximityPrompt)
		local want = GooTubePrompt.shown(
			p:GetAttribute(Constants.DROP_PROMPT_OPEN_ATTRIBUTE),
			p:GetAttribute(Constants.DROP_PROMPT_OWNER_ATTRIBUTE),
			opts.localUserId,
			opts.player:GetAttribute(Constants.CARRYING_ATTRIBUTE)
		)
		if p.Enabled ~= want then
			p.Enabled = want
		end
	end

	local function bind(inst: Instance)
		if bound[inst] or not isTubePrompt(inst) then
			return
		end
		local p = inst :: ProximityPrompt
		local function reapply()
			apply(p)
		end
		bound[p] = {
			p:GetAttributeChangedSignal(Constants.DROP_PROMPT_OPEN_ATTRIBUTE):Connect(reapply),
			p:GetAttributeChangedSignal(Constants.DROP_PROMPT_OWNER_ATTRIBUTE):Connect(reapply),
			p:GetPropertyChangedSignal("Enabled"):Connect(reapply),
		}
		apply(p)
	end

	local added = opts.root.DescendantAdded:Connect(bind)
	local carry = opts.player:GetAttributeChangedSignal(Constants.CARRYING_ATTRIBUTE):Connect(function()
		for p in bound do
			apply(p :: ProximityPrompt)
		end
	end)
	for _, inst in opts.root:GetDescendants() do
		bind(inst)
	end

	return function()
		added:Disconnect()
		carry:Disconnect()
		for _, conns in bound do
			for _, conn in conns do
				conn:Disconnect()
			end
		end
		table.clear(bound)
	end
end

return GooTubePrompt
