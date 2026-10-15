--!strict
--[[
	PlotLookup (pure)

	Finds plots and pads by their index attributes (CONTRACT.md §5.3):
	`Plot_<i>` models carry `PlotIndex = i`, `Pad_<j>` parts carry
	`PadIndex = j`. The child's name is only a fallback, so renamed or
	reordered world pieces still resolve. Works on anything with
	GetChildren / GetAttribute / FindFirstChild (Instances, or plain tables
	in tests).
]]

local PlotLookup = {}

-- The child of `parent` whose `attribute` equals `index`, else the child named `fallbackName`.
function PlotLookup.byIndex(parent: any, attribute: string, index: number, fallbackName: string): any?
	if parent == nil then
		return nil
	end
	for _, child in parent:GetChildren() do
		if child:GetAttribute(attribute) == index then
			return child
		end
	end
	return parent:FindFirstChild(fallbackName)
end

return PlotLookup
