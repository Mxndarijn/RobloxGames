--!strict
--[[
	SaveData

	Converts PlayerData to and from the JSON-safe table stored in the
	DataStore, migrating old formats and sanitizing anything untrusted.

	Format history:
	  v1 (legacy prototype, PascalCase):
	    { Cash, Rebirths, LastOnline, Slimes = { { Id, Rarity = "Epic", Size, Color = {r,g,b} } } }
	  v2 (v9-v12):
	    { version = 2, cash, rebirths, padsUnlocked, slimes = { Slime }, favoriteId,
	      lastOnline, daily = { lastDay, streak }, dex = { key }, totalEarned, totalStolen,
	      lockLevel, speedCoil, tutorialStep }
	    (lockLevel / speedCoil / tutorialStep were added later without a version
	    bump: missing -> 0 / false / 1 for an empty profile, else 0 = done)
	  v3 (current, CONTRACT.md §8.9): v2 plus
	    upgrades = { [id] = level }, stats = { caught, merges, locks, sold },
	    goals = { [goalId] = stagesPaid }, dexRewards = n
	    v2 -> v3: zero upgrades / goals / dexRewards, stats.caught seeded with
	    max(#slimes, dex count), tutorialStep 4..6 -> 5..7 (BuyPad step).
	Unknown/newer versions are read field-by-field with the v3 sanitizer.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local TutorialProgress = if script then require(script.Parent.TutorialProgress) else require("./TutorialProgress")

type Data = PlayerData.Data
type Slime = Genome.Slime

local SaveData = {}

local function num(value: any, default: number, min: number, max: number): number
	local n = tonumber(value)
	if not n or n ~= n then
		return default
	end
	return math.clamp(math.floor(n), min, max)
end

local MAX_CASH = 1e15

-- v1 -> v2. Pure function of the raw v1 table.
function SaveData.migrateV1(raw: { [string]: any }): { [string]: any }
	local slimes = {}
	if type(raw.Slimes) == "table" then
		for i, old in raw.Slimes do
			if type(old) == "table" then
				local tier = 1
				for _, rarity in Config.RARITIES do
					if rarity.name == old.Rarity then
						tier = rarity.tier
					end
				end
				table.insert(slimes, {
					id = if type(old.Id) == "string" then old.Id else `legacy-{i}`,
					name = "Oldie",
					tier = tier,
					color = old.Color,
					size = old.Size,
					pattern = "Plain",
					eyes = "Round",
					mouth = "Smile",
					mutation = "None",
				})
			end
		end
	end
	return {
		version = 2,
		cash = raw.Cash,
		rebirths = raw.Rebirths,
		padsUnlocked = Config.PADS_START,
		slimes = slimes,
		lastOnline = raw.LastOnline,
	}
end

-- Returns a v2-shaped raw table (still untrusted) from any stored value.
function SaveData.migrate(raw: any): { [string]: any }?
	if type(raw) ~= "table" then
		return nil
	end
	local version = tonumber(raw.version)
	if version == nil then
		if raw.Cash ~= nil or raw.Slimes ~= nil or raw.Rebirths ~= nil then
			return SaveData.migrateV1(raw)
		end
		return nil
	end
	return raw
end

--[[
	Builds trusted PlayerData from a stored value. Never errors. nil, garbage
	or empty input gives a fresh profile. Slimes with missing, duplicate or
	out-of-range pads are moved to free pads; pads are unlocked to fit them
	(up to PADS_MAX), and anything beyond that is dropped.
]]
function SaveData.deserialize(stored: any): Data
	local data = PlayerData.new()
	local raw = SaveData.migrate(stored)
	if not raw then
		return data
	end

	data.cash = num(raw.cash, Config.STARTING_CASH, 0, MAX_CASH)
	data.rebirths = num(raw.rebirths, 0, 0, Config.MAX_REBIRTHS)
	data.padsUnlocked = num(raw.padsUnlocked, Config.PADS_START, Config.PADS_START, Config.PADS_MAX)
	data.lastOnline = num(raw.lastOnline, 0, 0, 1e11)
	data.totalEarned = num(raw.totalEarned, 0, 0, MAX_CASH)
	data.totalStolen = num(raw.totalStolen, 0, 0, 1e9)
	if type(raw.daily) == "table" then
		data.daily = {
			lastDay = num(raw.daily.lastDay, 0, 0, 1e7),
			streak = num(raw.daily.streak, 0, 0, 1e6),
		}
	end
	if type(raw.dex) == "table" then
		for _, key in raw.dex do
			if type(key) == "string" and #key <= 64 then
				data.dex[key] = true
			end
		end
	end

	local clean: { Slime } = {}
	local seen: { [string]: boolean } = {}
	if type(raw.slimes) == "table" then
		for _, rawSlime in raw.slimes do
			local slime = Genome.sanitize(rawSlime)
			if slime and not seen[slime.id] and #clean < Config.PADS_MAX then
				seen[slime.id] = true
				table.insert(clean, slime)
			end
		end
	end
	data.padsUnlocked = math.max(data.padsUnlocked, math.min(#clean, Config.PADS_MAX))

	-- First keep slimes whose pad is valid and unique, then re-home the rest.
	local homeless = {}
	for _, slime in clean do
		local pad = slime.pad
		if pad and pad <= data.padsUnlocked and not PlayerData.slimeOnPad(data, pad) then
			table.insert(data.slimes, slime)
			PlayerData.discover(data, slime)
		else
			table.insert(homeless, slime)
		end
	end
	for _, slime in homeless do
		slime.pad = nil
		PlayerData.addSlime(data, slime)
	end

	if type(raw.favoriteId) == "string" and PlayerData.findSlime(data, raw.favoriteId) then
		data.favoriteId = raw.favoriteId
	end

	data.lockLevel = num(raw.lockLevel, 0, 0, Config.LOCK_UPGRADE_MAX)
	data.speedCoil = raw.speedCoil == true
	if raw.tutorialStep ~= nil then
		local step = num(raw.tutorialStep, 0, 0, #TutorialProgress.STEPS)
		-- v3 inserted "BuyPad" as step 4: an older save's Merge / Steal / Rebirth (4..6) moves up one.
		if (tonumber(raw.version) or 0) < 3 and step >= 4 then
			step = math.min(step + 1, #TutorialProgress.STEPS)
		end
		data.tutorialStep = step
	else
		-- Saved before the tutorial existed: only brand-new profiles get it.
		data.tutorialStep = if #data.slimes == 0 and data.rebirths == 0 then 1 else 0
	end

	-- v3 progression (missing in v1 / v2 saves -> zeros).
	if type(raw.upgrades) == "table" then
		for _, def in Config.UPGRADES do
			local level = num(raw.upgrades[def.id], 0, 0, def.maxLevel)
			if level > 0 then
				data.upgrades[def.id] = level
			end
		end
	end
	local stats = if type(raw.stats) == "table" then raw.stats else {}
	data.stats = {
		caught = num(stats.caught, 0, 0, 1e9),
		merges = num(stats.merges, 0, 0, 1e9),
		locks = num(stats.locks, 0, 0, 1e9),
		sold = num(stats.sold, 0, 0, 1e9),
	}
	if (tonumber(raw.version) or 0) < 3 then
		-- v2 never counted catches: every slime on the plot / dex entry was caught or merged at least.
		data.stats.caught = math.max(#data.slimes, PlayerData.dexCount(data))
	end
	if type(raw.goals) == "table" then
		for _, goal in Config.GOALS do
			local stage = num(raw.goals[goal.id], 0, 0, #goal.targets)
			if stage > 0 then
				data.goals[goal.id] = stage
			end
		end
	end
	data.dexRewards = num(raw.dexRewards, 0, 0, #Config.DEX_MILESTONES)
	return data
end

-- JSON-safe table for DataStore:SetAsync / UpdateAsync.
function SaveData.serialize(data: Data, now: number?): { [string]: any }
	local slimes = {}
	for i, slime in data.slimes do
		if i > Config.MAX_SLIMES_SAVED then
			break
		end
		table.insert(slimes, {
			id = slime.id,
			name = slime.name,
			tier = slime.tier,
			color = { slime.color[1], slime.color[2], slime.color[3] },
			size = slime.size,
			pattern = slime.pattern,
			eyes = slime.eyes,
			mouth = slime.mouth,
			mutation = slime.mutation,
			pad = slime.pad,
		})
	end
	local dex = {}
	for key in data.dex do
		table.insert(dex, key)
	end
	table.sort(dex)
	return {
		version = Config.SAVE_VERSION,
		cash = math.floor(data.cash),
		rebirths = data.rebirths,
		padsUnlocked = data.padsUnlocked,
		slimes = slimes,
		favoriteId = data.favoriteId,
		lastOnline = math.floor(now or data.lastOnline),
		daily = { lastDay = data.daily.lastDay, streak = data.daily.streak },
		dex = dex,
		totalEarned = math.floor(data.totalEarned),
		totalStolen = data.totalStolen,
		lockLevel = data.lockLevel,
		speedCoil = data.speedCoil,
		tutorialStep = data.tutorialStep,
		upgrades = table.clone(data.upgrades),
		stats = {
			caught = data.stats.caught,
			merges = data.stats.merges,
			locks = data.stats.locks,
			sold = data.stats.sold,
		},
		goals = table.clone(data.goals),
		dexRewards = data.dexRewards,
	}
end

return SaveData
