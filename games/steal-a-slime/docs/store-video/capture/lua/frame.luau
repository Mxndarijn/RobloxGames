local RunService = game:GetService("RunService")
workspace:SetAttribute("VClock", %%T%%)
workspace:SetAttribute("VCamPos", Vector3.new(%%P%%))
workspace:SetAttribute("VCamAt", Vector3.new(%%A%%))
%%EXTRA%%
RunService.RenderStepped:Wait()
RunService.RenderStepped:Wait()
RunService.RenderStepped:Wait()
return { ok = true }
