--!strict
--[[
	StealReach

	Client half of the steal rule "the thief must be inside the base, on the slime's floor" (JarInside.canReach,
	Steal.canSteal's thiefInside): a Steal prompt on another player's pad slime never shows to a player outside that
	base or on another floor of it. The glass lets prompts through, and every pad is within reach of a spot just
	outside it, so without this the prompt would offer a steal the server then refuses.

	It sets the prompt's MaxActivationDistance to 0 locally and puts the server's value back once the player is in
	reach, so Enabled stays the server's (the lock, PromptHide's owner and guest rules). The server checks the same
	rule on every grab; this only keeps the prompt honest.

	Deps come in `opts` (plots folder, root, base walls, plot-local transform), so it runs under Lune with mock
	instances (tests/ui/StealReach.spec.luau). `tick()` runs on the client's 10 Hz loop.
]]

local Shared = if script then (game:GetService("ReplicatedStorage") :: any).Shared else nil
local JarInside = if Shared then require(Shared.JarInside) else require("../shared/JarInside")

type Jar = JarInside.Jar

export type Options = {
	plots: () -> Instance?, -- workspace.Plots
	localUserId: number,
	root: () -> BasePart?, -- the local character's HumanoidRootPart
	jarOf: (plot: Instance) -> Jar, -- the plot's base walls (BaseShapes.get(PlotBase).guard)
	localPoint: (plot: Instance, at: Vector3) -> { number }?, -- plot-local (x, y on floorTop's scale, z)
	slimesFolder: string, -- Constants.PLOT_SLIMES_FOLDER
	promptName: string, -- Constants.GRAB_PROMPT_NAME
	padsAttribute: string, -- Constants.PLOT_PADS_UNLOCKED_ATTRIBUTE
}

export type Handle = {
	tick: () -> (),
	destroy: () -> (),
}

local OWNER_ATTRIBUTE = "OwnerUserId"

local StealReach = {}

-- True when a Steal prompt for a slime at plot-local `slime` should stay hidden from a player at `thief` (nil: no
-- character, or no plot frame).
function StealReach.hidden(thief: { number }?, slime: { number }, jar: Jar, floors: number): boolean
	return thief == nil or not JarInside.canReach(thief, slime, jar, floors)
end

local function promptOf(model: Instance, name: string): (ProximityPrompt?, BasePart?)
	local body = (model :: any).PrimaryPart or model:FindFirstChild("Body")
	if not body or not body:IsA("BasePart") then
		return nil, nil
	end
	local prompt = body:FindFirstChild(name)
	if prompt and prompt:IsA("ProximityPrompt") then
		return prompt, body
	end
	return nil, nil
end

function StealReach.start(opts: Options): Handle
	-- Prompts this client pulled in, with the server's MaxActivationDistance to put back.
	local pulled: { [ProximityPrompt]: number } = setmetatable({}, { __mode = "k" }) :: any

	local function restore(prompt: ProximityPrompt)
		local was = pulled[prompt]
		if was then
			pulled[prompt] = nil
			prompt.MaxActivationDistance = was
		end
	end

	local function pull(prompt: ProximityPrompt)
		if pulled[prompt] == nil then
			pulled[prompt] = prompt.MaxActivationDistance
		end
		if prompt.MaxActivationDistance ~= 0 then
			prompt.MaxActivationDistance = 0
		end
	end

	local function tick()
		local plots = opts.plots()
		if not plots then
			return
		end
		local root = opts.root()
		for _, plot in plots:GetChildren() do
			local slimes = plot:FindFirstChild(opts.slimesFolder)
			if not slimes then
				continue
			end
			local owner = plot:GetAttribute(OWNER_ATTRIBUTE)
			local mine = owner == opts.localUserId
			local jar = if mine then nil else opts.jarOf(plot)
			local pads = plot:GetAttribute(opts.padsAttribute)
			local floors = JarInside.builtFloors(if type(pads) == "number" then pads else 0)
			local thief = if root and not mine then opts.localPoint(plot, root.Position) else nil
			for _, model in slimes:GetChildren() do
				local prompt, body = promptOf(model, opts.promptName)
				if not prompt or not body then
					continue
				end
				local slime = if jar then opts.localPoint(plot, body.Position) else nil
				if jar and slime and StealReach.hidden(thief, slime, jar, floors) then
					pull(prompt)
				else
					restore(prompt)
				end
			end
		end
	end

	return {
		tick = tick,
		destroy = function()
			for prompt in pulled do
				restore(prompt)
			end
		end,
	}
end

return StealReach
