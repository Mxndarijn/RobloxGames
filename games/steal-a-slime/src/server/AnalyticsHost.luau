--!strict
--[[
	AnalyticsHost (Roblox adapter)

	Builds the shared Analytics tracker for GameAnalytics and runs it: AnalyticsService in a live server, a
	recorder in Studio (Roblox drops analytics events sent from Studio). In Studio, set the workspace attribute
	`AnalyticsLog = true` to print every call as `[Analytics] ...`. Batches go out from a Heartbeat update.
]]

local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Analytics = require(ReplicatedStorage.Lib.analytics.Analytics)
local AnalyticsSink = require(ReplicatedStorage.Lib.analytics.AnalyticsSink)
local GameAnalytics = require(script.Parent.GameAnalytics)
local World = require(script.Parent.World)

export type Host = {
	state: GameAnalytics.State,
	track: (player: Player, track: World.Track) -> (),
	join: (player: Player, session: World.Session) -> (),
	leave: (player: Player, session: World.Session?) -> (),
	stop: () -> (),
}

local AnalyticsHost = {}

-- A recorder sink that also prints each call while workspace.AnalyticsLog is true.
local function studioSink(): Analytics.Sink
	local recorder = Analytics.recorder(200)
	local out = {}
	for _, name in { "custom", "economy", "funnel", "onboarding", "progression" } do
		local record: any = (recorder :: any)[name]
		out[name] = function(player: any, ...: any)
			record(player, ...)
			if workspace:GetAttribute("AnalyticsLog") == true then
				local parts = {}
				for i = 1, select("#", ...) do
					local v = select(i, ...)
					parts[i] = if type(v) == "table" then HttpService:JSONEncode(v) else tostring(v)
				end
				print(`[Analytics] {name} {player.Name}: {table.concat(parts, " | ")}`)
			end
		end
	end
	return out :: any
end

function AnalyticsHost.start(warn: (string) -> ()): Host
	local sink = if RunService:IsStudio()
		then studioSink()
		else AnalyticsSink.new(AnalyticsService, function(message)
			warn(`[Analytics] {message}`)
		end)
	local tracker = Analytics.new({
		sink = sink,
		catalog = GameAnalytics.CATALOG :: any,
		now = os.clock,
		newId = function()
			return HttpService:GenerateGUID(false)
		end,
		playerCount = function()
			return #Players:GetPlayers()
		end,
		onDrop = function(reason, kind, name)
			-- Wrong names are programming errors worth seeing; over-budget drops are expected under load.
			if reason ~= "OverBudget" then
				warn(`[Analytics] dropped {kind} {name}: {reason}`)
			end
		end,
	})
	local state = GameAnalytics.new(tracker :: any)
	local connection = RunService.Heartbeat:Connect(function()
		tracker:update()
	end)
	return {
		state = state,
		track = function(player, track)
			GameAnalytics.play(state, player, track)
		end,
		join = function(player, session)
			GameAnalytics.join(state, player, session.data, os.clock())
		end,
		leave = function(player, session)
			GameAnalytics.leave(state, player, if session then session.data else nil, os.clock())
		end,
		stop = function()
			connection:Disconnect()
		end,
	}
end

return AnalyticsHost
