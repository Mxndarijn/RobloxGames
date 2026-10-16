-- Client datamodel: can VirtualInputManager click from here? (Expected: blocked, "lacking capability".)
local ok, err = pcall(function()
	local vim = game:GetService("VirtualInputManager")
	vim:SendMouseButtonEvent(%%X%%, %%Y%%, 0, true, game, 0)
	task.wait(0.1)
	vim:SendMouseButtonEvent(%%X%%, %%Y%%, 0, false, game, 0)
end)
task.wait(0.4)
return { ok = ok, error = if ok then nil else tostring(err) }
