-- Any datamodel: best-effort device emulation for the phone perf pass, only run when the rbx-device-simulator-lua
-- skill text documents a Luau device emulator API. Every call is pcall'd and recorded exactly as it went:
-- attempts = [{call, ok, result_or_error}]. %%DEVICE%% is the emulator device id / name ("" = just list what the
-- service offers). emulated = some call to set the device succeeded. Nothing here needs input or a visible window.
local attempts = {}
local function try(call, f)
	local ok, v = pcall(f)
	table.insert(attempts, { call = call, ok = ok, result = tostring(v):sub(1, 300) })
	return ok, v
end
local DEVICE = %%DEVICE%%
local okSvc, svc = try("GetService(StudioDeviceEmulatorService)", function()
	return game:GetService("StudioDeviceEmulatorService")
end)
local emulated = false
if okSvc and svc then
	if DEVICE ~= "" then
		local ok = try("SetDeviceById(" .. DEVICE .. ")", function()
			return (svc :: any):SetDeviceById(DEVICE)
		end)
		emulated = ok
		if not ok then
			emulated = (try("SetDevice(" .. DEVICE .. ")", function()
				return (svc :: any):SetDevice(DEVICE)
			end))
		end
	end
	try("GetDevices", function()
		local list = {}
		for _, d in (svc :: any):GetDevices() do
			table.insert(list, typeof(d) == "table" and tostring(d.Id or d.Name) or tostring(d))
		end
		return table.concat(list, ",")
	end)
end
return { emulated = emulated, device = DEVICE, attempts = attempts }
