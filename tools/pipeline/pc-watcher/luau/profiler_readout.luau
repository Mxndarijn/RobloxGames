-- Server datamodel: waits up to %%WAIT%% s for the workspace attribute ProfilerSummary (set by the server
-- Profiler every Config.PROFILER.LOG_INTERVAL s while FEATURES.ServerProfiler is on) and returns it. Read only.
local deadline = os.clock() + %%WAIT%%
local line = workspace:GetAttribute("ProfilerSummary")
while line == nil and os.clock() < deadline do
	task.wait(1)
	line = workspace:GetAttribute("ProfilerSummary")
end
return { ok = type(line) == "string" and line ~= "", raw = line }
