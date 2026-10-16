-- Client datamodel: the Esc test without any input injection. Calls the game's own "CloseMenu" action
-- handler (src/ui/MenuClose, bound through ContextActionService) with a Begin state and no InputObject.
local CAS = game:GetService("ContextActionService")
local ok, err = pcall(function()
	CAS:CallFunction("CloseMenu", Enum.UserInputState.Begin, nil)
end)
return { called = ok, error = if ok then nil else tostring(err), bound = CAS:GetAllBoundActionInfo().CloseMenu ~= nil }
