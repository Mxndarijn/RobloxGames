local req = game.ReplicatedStorage.Remotes.Request
local log = {}
local function A(id, text, amount)
	local t0 = os.clock() while os.clock() - t0 < 0.3 do end
	local ok, r1, r2 = pcall(function() return req:InvokeServer("Admin", id, text, amount) end)
	table.insert(log, id .. " " .. tostring(text) .. " -> " .. tostring(ok) .. " " .. (type(r1)=="table" and game:GetService("HttpService"):JSONEncode(r1) or tostring(r1)))
end
%%BODY%%
return { log = log }
