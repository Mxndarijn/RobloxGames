-- Client datamodel: sets graphics quality %%LEVEL%% (1-21) for the perf window, best effort. Two routes, each pcall'd:
-- settings().Rendering.QualityLevel and UserSettings():GetService("UserGameSettings").SavedQualityLevel. Waits 3 s,
-- reads both back and returns {requested, rendering_quality, saved_quality, errors, original}. original holds the
-- values from before (pass them back as RESTORE via a second call with %%LEVEL%% = 0 to restore, see below).
local LEVEL = %%LEVEL%%
local errors, original = {}, {}
local function read()
	local r, s
	local ok1, v1 = pcall(function()
		return settings().Rendering.QualityLevel
	end)
	if ok1 then
		r = v1
	else
		errors.read_rendering = tostring(v1):sub(1, 160)
	end
	local ok2, v2 = pcall(function()
		return UserSettings():GetService("UserGameSettings").SavedQualityLevel
	end)
	if ok2 then
		s = v2
	else
		errors.read_saved = tostring(v2):sub(1, 160)
	end
	return r, s
end
-- the original values live on the DataModel so a LEVEL = 0 call can restore them
local r0, s0 = read()
if LEVEL <= 0 then
	local ro, so = game:GetAttribute("PcwPerfQ0"), game:GetAttribute("PcwPerfQ1")
	if ro then
		pcall(function()
			settings().Rendering.QualityLevel = Enum.QualityLevel:FromName(ro)
		end)
	end
	if so then
		pcall(function()
			UserSettings():GetService("UserGameSettings").SavedQualityLevel = Enum.SavedQualitySetting:FromName(so)
		end)
	end
	return { restored = true, rendering_quality = tostring(select(1, read())) }
end
if game:GetAttribute("PcwPerfQ0") == nil then
	game:SetAttribute("PcwPerfQ0", if r0 then r0.Name else "Automatic")
	game:SetAttribute("PcwPerfQ1", if s0 then s0.Name else "Automatic")
end
original = { rendering = if r0 then tostring(r0) else nil, saved = if s0 then tostring(s0) else nil }
local okR, eR = pcall(function()
	settings().Rendering.QualityLevel = Enum.QualityLevel["Level" .. string.format("%02d", LEVEL)]
end)
if not okR then
	errors.set_rendering = tostring(eR):sub(1, 160)
end
local okS, eS = pcall(function()
	UserSettings():GetService("UserGameSettings").SavedQualityLevel = Enum.SavedQualitySetting["QualityLevel" .. LEVEL]
end)
if not okS then
	errors.set_saved = tostring(eS):sub(1, 160)
end
task.wait(3)
local r, s = read()
return {
	requested = LEVEL,
	rendering_quality = if r then tostring(r) else nil,
	saved_quality = if s then tostring(s) else nil,
	errors = errors,
	original = original,
}
