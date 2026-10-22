--!strict
--[[
	Economy pacing sim (pure modules, no Roblox): how far players get after N
	hours of play and N calendar days, run on the real World / GameLoop /
	Actions / Sessions code.

	  lune run tools/livetest/pacing [--seeds 1-20] [--days 7] [--mix casual=8,average=5,grinder=3]
	                                 [--profile grinder] [--stagger 3] [--plots 8]
	                                 [--hours 0.5,1,2,4,8,12,20,30] [--no-steal] [--out report.md]
	                                 [--json series.json] [--late casual@5x4] [--friends 3] [--party]
	                                 [--no-codes] [--no-eggs] [--consumables 20] [--merge pair|triple] [--flip full|always] [--set casual.lock=1] [--start-level N]

	Each seed is one server with a population of bots (Profiles) that join and
	leave on daily schedules, take wild slimes, steal from each other, defend,
	lock, merge, buy pads / upgrades and rebirth; offline income is paid on
	every join. `--profile X` fills the server with X only (its share of the
	default 16 bots). `--no-steal` turns stealing off for every profile.
	Profiles: casual, average, grinder (rebirth pacing), casual15 (15 minutes every day), thief, victim.
	`--late casual@5x4` adds 4 casual bots that all join on day 5 (reported as late-casual); use more --days.
	`--friends K` deals the bots into friend groups of K (Friends.refresh counts the ones online together,
	`--party` puts a group on one schedule). `--no-codes` / `--no-eggs` turn off redeeming codes on the first
	join / taking Mystery Eggs (free to grab, can't be sold); `--merge pair|triple` picks the vat bots merge in (default: the 3-slime vat while FEATURES.MergeVat3 is on, as the UI only sends Merge3; `pair` models calling the Merge remote directly); `--flip full|always` makes every bot buy wild slimes to sell at once (profiles flipper / flipall do it for one bot kind; flipprobe + `--start-level N` is a 60 minute flip-only session at rebirth N with unlimited cash); `--consumables N` makes every bot buy and drink Luck Potions that cost under 1/N of its cash.
	Prints Markdown tables (Report); `--out` also writes them to a file; `--json` writes every bot's time
	series, milestones, cash ledger and steal events (Report.json).
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")

local Profiles = require("@self/Profiles")
local Report = require("@self/Report")
local Server = require("@self/Server")

local function fail(message: string): never
	stdio.ewrite(message .. "\n")
	process.exit(2)
	error(message)
end

local function numberList(text: string): { number }
	local out = {}
	for part in string.gmatch(text, "[^,]+") do
		local a, b = string.match(part, "^(%d+)%-(%d+)$")
		if a and b then
			for n = tonumber(a) :: number, tonumber(b) :: number do
				table.insert(out, n)
			end
		else
			table.insert(out, tonumber(part) or fail(`not a number: {part}`))
		end
	end
	return out
end

local args = process.args
local opts = {
	seeds = numberList("1-10"),
	days = 7,
	mix = table.clone(Profiles.DEFAULT_MIX) :: { [string]: number },
	stagger = 3,
	plots = 8,
	checkpoints = { 0.5, 1, 2, 4, 8, 12, 20, 30 },
	out = nil :: string?,
	json = nil :: string?,
	steal = true,
	codes = true,
	eggs = true,
	consumables = nil :: number?,
	merge = nil :: string?,
	flip = nil :: string?,
	startLevel = nil :: number?,
	set = {} :: { { profile: string, field: string, value: number } },
	late = {} :: { Server.Late },
	friends = 0,
	party = false,
}
local i = 1
while i <= #args do
	local flag, value = args[i], args[i + 1]
	if flag == "--no-steal" then
		opts.steal = false
		i += 1
		continue
	elseif flag == "--no-codes" then
		opts.codes = false
		i += 1
		continue
	elseif flag == "--no-eggs" then
		opts.eggs = false
		i += 1
		continue
	elseif flag == "--party" then
		opts.party = true
		i += 1
		continue
	end
	if value == nil then
		fail(`missing value after {flag}`)
	end
	if flag == "--seeds" then
		opts.seeds = numberList(value)
	elseif flag == "--days" then
		opts.days = tonumber(value) or fail("--days needs a number")
	elseif flag == "--stagger" then
		opts.stagger = tonumber(value) or fail("--stagger needs a number")
	elseif flag == "--plots" then
		opts.plots = tonumber(value) or fail("--plots needs a number")
	elseif flag == "--hours" then
		opts.checkpoints = numberList(value)
	elseif flag == "--out" then
		opts.out = value
	elseif flag == "--json" then
		opts.json = value
	elseif flag == "--friends" then
		opts.friends = tonumber(value) or fail("--friends needs a number")
	elseif flag == "--merge" then
		if value ~= "pair" and value ~= "triple" then
			fail("--merge needs pair or triple")
		end
		opts.merge = value
	elseif flag == "--set" then
		-- profile.field=number,... : overrides a number in a profile (sensitivity runs), e.g. casual.lock=1,casual.steal=0.12
		for name, field, number in string.gmatch(value, "(%w+)%.(%w+)=([%d%.]+)") do
			local profile = Profiles.get(name) or fail(`unknown profile {name}`)
			if type((profile :: any)[field]) ~= "number" then
				fail(`{name}.{field} is not a number field`)
			end
			table.insert(opts.set, { profile = profile.name, field = field, value = tonumber(number) :: number })
		end
	elseif flag == "--start-level" then
		opts.startLevel = tonumber(value) or fail("--start-level needs a number")
	elseif flag == "--flip" then
		if value ~= "full" and value ~= "always" then
			fail("--flip needs full or always")
		end
		opts.flip = value
	elseif flag == "--consumables" then
		opts.consumables = tonumber(value) or fail("--consumables needs a number")
	elseif flag == "--late" then
		for name, day, count in string.gmatch(value, "(%w+)@(%d+)x?(%d*)") do
			if not Profiles.get(name) then
				fail(`unknown profile {name}`)
			end
			table.insert(opts.late, {
				profile = (Profiles.get(name) :: Profiles.Profile).name,
				day = tonumber(day) :: number,
				count = tonumber(count) or 4,
			})
		end
	elseif flag == "--profile" then
		if not Profiles.get(value) then
			fail(`unknown profile {value} (have {table.concat(Profiles.names(), ", ")})`)
		end
		local total = 0
		for _, n in Profiles.DEFAULT_MIX do
			total += n
		end
		opts.mix = { [(Profiles.get(value) :: Profiles.Profile).name] = total }
	elseif flag == "--mix" then
		opts.mix = {}
		for name, n in string.gmatch(value, "(%w+)=(%d+)") do
			local profile = Profiles.get(name)
			if not profile then
				fail(`unknown profile {name}`)
			end
			opts.mix[(profile :: Profiles.Profile).name] = tonumber(n) :: number
		end
	else
		fail(`unknown flag {flag}`)
	end
	i += 2
end

for _, p in Profiles.LIST do
	if not opts.steal then
		p.steal = 0
	end
	p.eggs = opts.eggs
	p.consumables = opts.consumables or p.consumables
	p.merge = opts.merge or p.merge
	p.flip = opts.flip or p.flip
end
for _, o in opts.set do
	((Profiles.get(o.profile) :: any) :: { [string]: number })[o.field] = o.value
end

local records = {}
local started = os.clock()
for _, seed in opts.seeds do
	local t = os.clock()
	for _, r in
		Server.run({
			seed = seed,
			days = opts.days,
			mix = opts.mix,
			stagger = opts.stagger,
			checkpoints = opts.checkpoints,
			plots = opts.plots,
			late = opts.late,
			codes = opts.codes,
			friends = opts.friends,
			party = opts.party,
			startLevel = opts.startLevel,
		})
	do
		table.insert(records, r)
	end
	stdio.ewrite(string.format("seed %d done in %.1fs\n", seed, os.clock() - t))
end
stdio.ewrite(string.format("%d seeds in %.1fs\n", #opts.seeds, os.clock() - started))

local text = Report.markdown(records, {
	seeds = opts.seeds,
	days = opts.days,
	mix = opts.mix,
	stagger = opts.stagger,
	checkpoints = opts.checkpoints,
	late = opts.late,
})
if not opts.steal then
	text = string.gsub(text, "\n\n", "\n\nStealing off.\n\n", 1)
end
print(text)
if opts.out then
	fs.writeFile(opts.out, text)
end
if opts.json then
	fs.writeFile(
		opts.json,
		serde.encode(
			"json",
			Report.json(records, {
				seeds = opts.seeds,
				days = opts.days,
				mix = opts.mix,
				stagger = opts.stagger,
				checkpoints = opts.checkpoints,
				late = opts.late,
			})
		)
	)
end
