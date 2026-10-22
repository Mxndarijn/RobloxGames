--!strict
--[[
	GooIcons (shared)

	Icons drawn from plain frames instead of emoji, so they match the Goo look on any device:
	  GooIcons.upArrow(parent, deps, color, zIndex?) -> Frame   the Upgrade shop's chunky up arrow
	The icon fills `parent` (a square tile or badge) and scales with it. `deps` carries the Roblox
	constructors (Instance, UDim, UDim2, Vector2), so the module touches no Roblox API at require time
	and runs under Lune.
]]

export type Deps = { Instance: any, UDim: any, UDim2: any, Vector2: any }

local GooIcons = {}

-- The up arrow as fractions of its square: two arms meeting at the tip and a shaft under it.
GooIcons.UP_ARROW = table.freeze({
	inset = 0.16, -- empty margin round the arrow
	thick = 0.2, -- bar thickness
	armLength = 0.52,
	tipY = 0.06, -- the tip's top, inside the inset box
	shaftTop = 0.3,
	shaftBottom = 0.96,
})

local function bar(deps: Deps, parent: any, name: string, color: Color3, zIndex: number?): any
	local f = deps.Instance.new("Frame")
	f.Name = name
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.AnchorPoint = deps.Vector2.new(0.5, 0.5)
	if zIndex then
		f.ZIndex = zIndex
	end
	local c = deps.Instance.new("UICorner")
	c.CornerRadius = deps.UDim.new(1, 0)
	c.Parent = f
	f.Parent = parent
	return f
end

function GooIcons.upArrow(parent: any, deps: Deps, color: Color3, zIndex: number?): any
	local a = GooIcons.UP_ARROW
	local box = deps.Instance.new("Frame")
	box.Name = "UpArrow"
	box.BackgroundTransparency = 1
	box.Position = deps.UDim2.fromScale(a.inset, a.inset)
	box.Size = deps.UDim2.fromScale(1 - a.inset * 2, 1 - a.inset * 2)
	if zIndex then
		box.ZIndex = zIndex
	end
	box.Parent = parent
	local shaft = bar(deps, box, "Shaft", color, zIndex)
	shaft.Position = deps.UDim2.fromScale(0.5, (a.shaftTop + a.shaftBottom) / 2)
	shaft.Size = deps.UDim2.fromScale(a.thick, a.shaftBottom - a.shaftTop)
	-- Each arm runs from the tip down and out at 45 degrees; its centre is half an arm from the tip.
	local half = a.armLength / 2 * math.sqrt(0.5)
	local tipY = a.tipY + a.thick / 2
	for _, side in { -1, 1 } do
		local arm = bar(deps, box, if side < 0 then "ArmLeft" else "ArmRight", color, zIndex)
		arm.Position = deps.UDim2.fromScale(0.5 + side * half, tipY + half)
		arm.Size = deps.UDim2.fromScale(a.armLength, a.thick)
		arm.Rotation = side * 45
	end
	return box
end

return table.freeze(GooIcons)
