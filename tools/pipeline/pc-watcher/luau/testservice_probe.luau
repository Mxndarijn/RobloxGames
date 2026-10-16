-- Edit datamodel: does any scriptable multi-client test API exist? Only probes (indexing), never calls.
local out = {}
for _, svc in { "StudioTestService", "TestService" } do
	local okS, s = pcall(function()
		return game:GetService(svc)
	end)
	local members = {}
	if okS and s then
		for _, m in {
			"ExecutePlayModeAsync", "ExecuteRunModeAsync", "ExecuteMultiplayerAsync", "StartMultiplayerTest",
			"ExecuteTeamTestAsync", "NumberOfPlayers", "Run", "EndTest", "GetTestArgs",
		} do
			local okM, v = pcall(function()
				return (s :: any)[m]
			end)
			if okM and v ~= nil then
				table.insert(members, m .. ":" .. typeof(v))
			end
		end
	end
	out[svc] = { available = okS and s ~= nil, members = members }
end
return out
