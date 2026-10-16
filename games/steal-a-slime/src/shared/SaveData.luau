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
	    plus (no bump; missing -> none) redeemed = { code }, boost = { mult, untilAt }
	    v2 -> v3: zero upgrades / goals / dexRewards, stats.caught seeded with
	    max(#slimes, dex count), tutorialStep 4..6 -> 5..7 (BuyPad step).
	  v4 (current): v3 plus slimes[i].mutations = { name } (every mutation, at most
	    Config.MAX_MUTATIONS; combos stored by their combo name). The single
	    `mutation` field is still written (the primary = strongest mutation) so a v3
	    reader keeps working and DataStore keys/field names never change.
	    v3 -> v4 (migrateV3): mutations = {} for "None"/missing, else { mutation };
	    pure, idempotent, never touches a slime that already has a list.
	v5 (current): v4 plus the weather mutations Wet / Frozen (and combos Sleet / Comet). No
	field changes: `mutations` / `mutation` keep their shape and old saves load unchanged.
	v4 -> v5 (migrateV4): drops duplicate / empty / non-string entries from each slime's
	`mutations` and rebuilds a missing or all-invalid list from `mutation`; pure, idempotent.
	Unknown/newer versions are read field-by-field with the v5 sanitizer (both
	`mutations` and the legacy `mutation` are understood, nothing is dropped).
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

-- v3 (or older v2-shaped) -> v4. Pure: returns a copy, never mutates `raw`. Adds
-- `mutations` to every slime table that has none, from the legacy `mutation` field.
-- Idempotent. `migratedFrom` remembers the version it came from (deserialize needs
-- it for the v2 -> v3 steps); it is never serialized.
function SaveData.migrateV3(raw: { [string]: any }): { [string]: any }
	local out = table.clone(raw)
	local from = tonumber(raw.version)
	if from == nil or from ~= from then
		from = 0
	end
	out.migratedFrom = raw.migratedFrom or from
	if type(raw.slimes) == "table" then
		local slimes = {}
		for i, old in raw.slimes do
			if type(old) == "table" and type(old.mutations) ~= "table" then
				local slime = table.clone(old)
				local m = old.mutation
				slime.mutations = if type(m) == "string" and m ~= "None" then { m } else {}
				slimes[i] = slime
			else
				slimes[i] = old
			end
		end
		out.slimes = slimes
	end
	out.version = 4
	return out
end

-- v4 -> v5. Pure copy, idempotent. Normalises each slime's `mutations` list: strings only, no
-- "None", no duplicates, order kept; a missing list (or one with nothing valid) is rebuilt from the
-- legacy `mutation`. Names are NOT checked against Config.MUTATIONS here (Genome.sanitize does
-- that on load), so a name this build does not know yet survives the migration. A slime with a
-- clean list is returned as the same table.
function SaveData.migrateV4(raw: { [string]: any }): { [string]: any }
	local out = table.clone(raw)
	local from = tonumber(raw.version)
	if from == nil or from ~= from then
		from = 0
	end
	out.migratedFrom = raw.migratedFrom or from
	if type(raw.slimes) == "table" then
		local slimes = {}
		for i, old in raw.slimes do
			if type(old) ~= "table" then
				slimes[i] = old
				continue
			end
			local list, seen, dirty = {}, {}, type(old.mutations) ~= "table"
			if not dirty then
				for _, m in old.mutations do
					if type(m) == "string" and m ~= "None" and m ~= "" and not seen[m] then
						seen[m] = true
						table.insert(list, m)
					else
						dirty = true
					end
				end
			end
			if dirty then
				if #list == 0 and type(old.mutation) == "string" and old.mutation ~= "None" and old.mutation ~= "" then
					list = { old.mutation }
				end
				local slime = table.clone(old)
				slime.mutations = list
				slimes[i] = slime
			else
				slimes[i] = old
			end
		end
		out.slimes = slimes
	end
	out.version = 5
	return out
end

-- Returns a v5-shaped raw table (still untrusted) from any stored value. Saves
-- from a newer version than we know are returned as they are.
function SaveData.migrate(raw: any): { [string]: any }?
	if type(raw) ~= "table" then
		return nil
	end
	local version = tonumber(raw.version)
	if version == nil then
		if raw.Cash ~= nil or raw.Slimes ~= nil or raw.Rebirths ~= nil then
			return SaveData.migrateV4(SaveData.migrateV3(SaveData.migrateV1(raw)))
		end
		return nil
	end
	if version < 4 then
		return SaveData.migrateV4(SaveData.migrateV3(raw))
	end
	if version < 5 then
		return SaveData.migrateV4(raw)
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
		if (tonumber(raw.migratedFrom or raw.version) or 0) < 3 and step >= 4 then
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
	if (tonumber(raw.migratedFrom or raw.version) or 0) < 3 then
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

	-- Redeem codes (added without a version bump: missing -> nothing redeemed, no boost).
	if type(raw.redeemed) == "table" then
		local count = 0
		for _, code in raw.redeemed do
			if type(code) == "string" and #code <= Config.CODE_MAX_LENGTH and count < 256 then
				data.redeemed[code] = true
				count += 1
			end
		end
	end
	if type(raw.boost) == "table" then
		local until_ = num(raw.boost.untilAt, 0, 0, 1e11)
		local mult = num(raw.boost.mult, 1, 1, Config.CODE_BOOST_MAX_MULT)
		if until_ > 0 and mult > 1 then
			data.boostMult, data.boostUntil = mult, until_
		end
	end
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
			mutation = Genome.primaryMutation(Genome.mutationList(slime)), -- legacy field, kept for v3 readers
			mutations = Genome.mutationList(slime),
			pad = slime.pad,
			species = slime.species, -- optional (v28), dropped on load if unknown
			growth = slime.growth, -- optional (FEATURES.GrowingSlimes): missing = 0, no version bump
		})
	end
	local dex = {}
	for key in data.dex do
		table.insert(dex, key)
	end
	table.sort(dex)
	local redeemed = {}
	for code in data.redeemed do
		table.insert(redeemed, code)
	end
	table.sort(redeemed)
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
		redeemed = redeemed,
		boost = { mult = data.boostMult, untilAt = math.floor(data.boostUntil) },
	}
end

return SaveData
