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

-- Every child of `parent` for indexes 1..`count`, resolved like byIndex but with a single scan of the children:
-- `{ [index] = child }` (missing indexes are absent). The first child carrying an index wins, then the child named
-- `<namePrefix><index>`.
function PlotLookup.allByIndex(parent: any, attribute: string, count: number, namePrefix: string): { [number]: any }
	local found: { [number]: any } = {}
	if parent == nil then
		return found
	end
	for _, child in parent:GetChildren() do
		local index = child:GetAttribute(attribute)
		if type(index) == "number" and index >= 1 and index <= count and found[index] == nil then
			found[index] = child
		end
	end
	for index = 1, count do
		if found[index] == nil then
			found[index] = parent:FindFirstChild(`{namePrefix}{index}`)
		end
	end
	return found
end

return PlotLookup
