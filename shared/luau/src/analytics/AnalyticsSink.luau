--!strict
--[[
	AnalyticsSink: the Roblox adapter for Analytics. Turns sink calls into AnalyticsService calls (with the right
	Enums) and never lets an AnalyticsService error reach game code.

		local sink = AnalyticsSink.new(game:GetService("AnalyticsService"))
		local tracker = Analytics.new({ sink = sink, ... })

	Roblox drops these events in Studio, so in Studio pass a recorder instead (Analytics.recorder()), or wrap the
	real sink with `AnalyticsSink.tee(real, recorder)` to see what would be sent.
]]

local Analytics = if script then require(script.Parent.Analytics) else require("./Analytics")

type Sink = Analytics.Sink

local AnalyticsSink = {}

function AnalyticsSink.new(service: AnalyticsService, onError: ((message: string) -> ())?): Sink
	local function guard(label: string, fn: () -> ())
		local ok, err = pcall(fn)
		if not ok and onError then
			onError(`{label}: {tostring(err)}`)
		end
	end
	local sink: Sink = {
		custom = function(player, name, value, fields)
			guard("LogCustomEvent", function()
				service:LogCustomEvent(player, name, value, fields)
			end)
		end,
		economy = function(player, flow, currency, amount, balance, transaction, sku, fields)
			guard("LogEconomyEvent", function()
				local flowType = if flow == "Source"
					then Enum.AnalyticsEconomyFlowType.Source
					else Enum.AnalyticsEconomyFlowType.Sink
				service:LogEconomyEvent(player, flowType, currency, amount, balance, transaction, sku, fields)
			end)
		end,
		funnel = function(player, funnel, sessionId, step, stepName, fields)
			guard("LogFunnelStepEvent", function()
				service:LogFunnelStepEvent(player, funnel, sessionId, step, stepName, fields)
			end)
		end,
		onboarding = function(player, step, stepName, fields)
			guard("LogOnboardingFunnelStepEvent", function()
				service:LogOnboardingFunnelStepEvent(player, step, stepName, fields)
			end)
		end,
		progression = function(player, path, status, level, levelName, fields)
			guard("LogProgressionEvent", function()
				local kind = (Enum.AnalyticsProgressionType :: any)[status]
				service:LogProgressionEvent(player, path, kind, level, levelName, fields)
			end)
		end,
	}
	return table.freeze(sink)
end

-- A sink that forwards every call to both sinks (for example the real one and a recorder).
function AnalyticsSink.tee(a: Sink, b: Sink): Sink
	local out = {}
	for _, name in { "custom", "economy", "funnel", "onboarding", "progression" } do
		local fa: any, fb: any = (a :: any)[name], (b :: any)[name]
		out[name] = function(...)
			fa(...)
			fb(...)
		end
	end
	return table.freeze(out) :: any
end

return table.freeze(AnalyticsSink)
