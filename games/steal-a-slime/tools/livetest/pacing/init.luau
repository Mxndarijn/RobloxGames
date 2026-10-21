--!strict
--[[
	Economy pacing sim (pure modules, no Roblox): how far players get after N
	hours of play and N calendar days, run on the real World / GameLoop /
	Actions / Sessions code.

	  lune run tools/livetest/pacing [--seeds 1-20] [--days 7] [--mix casual=8,regular=5,grinder=3]
	                                 [--profile grinder] [--stagger 3] [--plots 8]
	                                 [--hours 0.5,1,2,4,8,12,20,30] [--no-steal] [--out report.md]

	Each seed is one server with a population of bots (Profiles) that join and
	leave on daily schedules, take wild slimes, steal from each other, defend,
	lock, merge, buy pads / upgrades and rebirth; offline income is paid on
	every join. `--profile X` fills the server with X only (its share of the
	default 16 bots). `--no-steal` turns stealing off for every profile.
	Prints Markdown tables (Report); `--out` also writes them to a file.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
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
	steal = true,
}
local i = 1
while i <= #args do
	local flag, value = args[i], args[i + 1]
	if flag == "--no-steal" then
		opts.steal = false
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
	elseif flag == "--profile" then
		if not Profiles.get(value) then
			fail(`unknown profile {value} (have {table.concat(Profiles.names(), ", ")})`)
		end
		local total = 0
		for _, n in Profiles.DEFAULT_MIX do
			total += n
		end
		opts.mix = { [value] = total }
	elseif flag == "--mix" then
		opts.mix = {}
		for name, n in string.gmatch(value, "(%w+)=(%d+)") do
			if not Profiles.get(name) then
				fail(`unknown profile {name}`)
			end
			opts.mix[name] = tonumber(n) :: number
		end
	else
		fail(`unknown flag {flag}`)
	end
	i += 2
end

if not opts.steal then
	for _, p in Profiles.LIST do
		p.steal = 0
	end
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
})
if not opts.steal then
	text = string.gsub(text, "\n\n", "\n\nStealing off.\n\n", 1)
end
print(text)
if opts.out then
	fs.writeFile(opts.out, text)
end
