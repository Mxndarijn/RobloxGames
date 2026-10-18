--!strict
--[[
	Client UI performance numbers under Lune: mounts the HUD and every menu card the way
	src/ui/init.client does (tests/ui/UiHarness mock Roblox), then counts what a phone pays for:
	  gui_instances   ScreenGui descendants (idle, and the most with one menu open)
	  tweens          TweenService:Create calls while mounting, opening and closing everything
	  frame_conns     RenderStepped / Heartbeat / Stepped connects minus disconnects (idle, and after
	                  opening + closing every menu once: a growth there is a leak)
	  poll_wakeups    task wakeups per second at idle (virtual clock), and the polling loops behind them
	  frame_sites     static scan: every RenderStepped / Heartbeat / Stepped connect in src/ui + src/visuals/client
	NOT measurable here: real frame time, GPU cost, texture / image memory, layout engine cost.
]]
local fs = require("@lune/fs")

local UiHarness = require("./UiHarness")

local PerfMeasure = {}

local EVENTS = { "RenderStepped", "Heartbeat", "Stepped" }

local function liveConns(): number
	local stats = UiHarness.stats
	local total = 0
	for _, name in EVENTS do
		total += stats.connects[name] - stats.disconnects[name]
	end
	return total
end

local function count(root: any): number
	return #UiHarness.descendants(root)
end

-- Static scan (grep level): `path:line` of every frame-event connect.
function PerfMeasure.frameSites(): { string }
	local sites = {}
	local function scan(dir: string)
		for _, name in fs.readDir(dir) do
			local path = `{dir}/{name}`
			if fs.isDir(path) then
				scan(path)
			elseif string.match(name, "%.luau$") then
				local n = 0
				for line in string.gmatch(fs.readFile(path) .. "\n", "(.-)\n") do
					n += 1
					for _, event in EVENTS do
						if string.find(line, event .. ":Connect", 1, true) and not string.match(line, "^%s*%-%-") then
							table.insert(sites, `{path}:{n}`)
							break
						end
					end
				end
			end
		end
	end
	scan("src/ui")
	scan("src/visuals/client")
	table.sort(sites)
	return sites
end

-- Static: task.wait( sites in src/ui (each is a polling loop or a delayed call) and the rate of the
-- init.client "Local countdowns" tick (Hz), the one loop that runs for the whole session.
function PerfMeasure.pollScan(): (number, number)
	local sites = 0
	for _, name in fs.readDir("src/ui") do
		local path = `src/ui/{name}`
		if string.match(name, "%.luau$") then
			for line in string.gmatch(fs.readFile(path) .. "\n", "(.-)\n") do
				if string.find(line, "task.wait(", 1, true) and not string.match(line, "^%s*%-%-") then
					sites += 1
				end
			end
		elseif fs.isDir(path) then
			for _, sub in fs.readDir(path) do
				for line in string.gmatch(fs.readFile(`{path}/{sub}`) .. "\n", "(.-)\n") do
					if string.find(line, "task.wait(", 1, true) and not string.match(line, "^%s*%-%-") then
						sites += 1
					end
				end
			end
		end
	end
	local client = fs.readFile("src/ui/init.client.luau")
	local _, from = string.find(client, "Local countdowns", 1, true)
	local interval = tonumber(string.match(client, "task%.wait%(([%d%.]+)%)", from or 1)) or 1
	return sites, 1 / interval
end

function PerfMeasure.measure(): { [string]: any }
	local Config = require("../../src/shared/Config")
	local Constants = require("../../src/shared/Constants")
	local Genome = require("../../src/shared/Genome")
	local Remotes = require("../../src/shared/Remotes")

	-- Fresh virtual clock: no sleepers or timers carried over from earlier specs.
	UiHarness.virtualTime(false)
	UiHarness.virtualTime(true)
	local stats = UiHarness.stats
	local base = {
		tweens = stats.tweensCreated,
		conns = liveConns(),
	}
	local gui = UiHarness.root()
	local ItemIcons = UiHarness.ui("ItemIcons")
	local itemIcons = ItemIcons.build(Config)
	local ctx: { [string]: any } = {
		Config = Config,
		Constants = Constants,
		Genome = Genome,
		TripleMerge = require("../../src/shared/TripleMerge"),
		vat3Forced = function()
			return false
		end,
		actions = Remotes.ACTIONS,
		send = function() end,
		request = function() end,
		serverNow = function()
			return 1000
		end,
		playerName = function()
			return "Tester"
		end,
		itemIcons = itemIcons,
	}
	UiHarness.ui("Hud").new(gui, ctx)
	local panels: { [string]: any } = {}
	for _, key in { "Plot", "Merge", "Shop", "Rebirth", "Goals", "Dex", "Leaderboard", "Codes", "Guide", "Welcome" } do
		local module = UiHarness.ui(`Panels/{key}`)
		panels[key] = module.new(gui, ctx)
	end
	UiHarness.ui("StealAlertFx").new(gui, {
		Config = Config,
		Constants = Constants,
		StealAlert = require("../../src/shared/StealAlert"),
		serverNow = ctx.serverNow,
	})
	UiHarness.ui("Panels/Carry").new(gui, ctx)
	UiHarness.ui("Panels/DailyPopup").new(gui, ctx)
	UiHarness.ui("Panels/TutorialOverlay").new(gui, ctx)
	UiHarness.ui("Panels/HintOverlay").new(gui)

	local idleInstances = count(gui)
	local idleConns = liveConns() - base.conns
	UiHarness.advance(0.1)
	local wakeStart = stats.wakeups
	UiHarness.advance(10)
	local wakeupsPerSec = (stats.wakeups - wakeStart) / 10
	local loops = UiHarness.sleepers()
	local loopCount = 0
	for _, n in loops do
		loopCount += n
	end

	local maxOpen = idleInstances
	for key, panel in panels do
		if panel.setOpen then
			panel.setOpen(true)
			UiHarness.advance(1)
			maxOpen = math.max(maxOpen, count(gui))
			panel.setOpen(false)
			UiHarness.advance(1)
			_ = key
		end
	end
	local afterConns = liveConns() - base.conns
	local waitSites, clientTickHz = PerfMeasure.pollScan()
	local result = {
		gui_instances_idle = idleInstances,
		gui_instances_menu_open_max = maxOpen,
		gui_instances_after_close = count(gui),
		tweens_created = stats.tweensCreated - base.tweens,
		frame_conns_idle = idleConns,
		frame_conns_after_menus = afterConns,
		poll_wakeups_per_sec = wakeupsPerSec,
		poll_loops = loopCount,
		poll_loop_intervals = loops,
		frame_connect_sites = #PerfMeasure.frameSites(),
		poll_wait_sites = waitSites,
		client_tick_hz = clientTickHz,
	}
	UiHarness.virtualTime(false)
	return result
end

-- Budget keys that may sit above this many percent of the measured value before the ratchet asks for
-- a lower budget (instance counts drift with every UI tweak; connections and loops must match exactly).
local RATCHET_SLACK_PCT: { [string]: number } =
	{ gui_instances_idle = 3, gui_instances_menu_open_max = 3, gui_instances_after_close = 3 }

-- Problems (empty = green): a number above its budget fails; a number that dropped below it asks to
-- lower the budget (ratchet), so a win is locked in by the same PR.
function PerfMeasure.compare(result: { [string]: any }, limits: { [string]: number }): { string }
	local problems = {}
	local keys = {}
	for key in limits do
		table.insert(keys, key)
	end
	table.sort(keys)
	for _, key in keys do
		local limit, value = limits[key], result[key]
		if type(value) ~= "number" then
			table.insert(problems, `{key}: not measured`)
		elseif value > limit then
			table.insert(problems, `{key}: {value} is over the budget {limit}`)
		elseif value < limit * (1 - (RATCHET_SLACK_PCT[key] or 0) / 100) then
			table.insert(
				problems,
				`{key}: {value} is under the budget {limit}, lower it in ui-perf-budget.json (ratchet)`
			)
		end
	end
	return problems
end

return PerfMeasure
