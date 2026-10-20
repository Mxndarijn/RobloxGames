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
	  v3 (CONTRACT.md §8.9): v2 plus
	    upgrades = { [id] = level }, stats = { caught, merges, locks, sold },
	    goals = { [goalId] = stagesPaid }, dexRewards = n
	    plus (no bump; missing -> none) redeemed = { code }, boost = { mult, untilAt }
	    v2 -> v3: zero upgrades / goals / dexRewards, stats.caught seeded with
	    #slimes, tutorialStep 4..6 -> 5..7 (BuyPad step).
	  v4 / v5: slime mutation lists (SaveData.migrateV3 / migrateV4); stripped again by v7 (migrateV6).
	plotSkin (FEATURES.PlotSkins, CONTRACT.md §15): missing / unknown / not unlocked -> "classic"
	(SaveData.migratePlotSkin, run by deserialize). stealLog (FEATURES.StealAlerts, CONTRACT.md §17):
	a capped list of { thief, slime, at }; missing / junk -> empty. Both were unversioned before v6.
	v6: v5 plus `settings = { musicVolume, sfxVolume, muted }` (AudioSettings, FEATURES.Audio) and
	the two unversioned fields above are now versioned: v5 -> v6 (migrateV5) keeps a known plotSkin id and
	cleans stealLog / settings, junk or missing -> classic / empty / defaults. Pure, idempotent and
	independent of every feature flag: a flag that is off leaves its field stored, just unused.
	v7: v6 minus everything mutation related: slimes[i].mutation / .mutations, the Dex `stamps` and
	`stampRewards`, the MutationSpray consumable and the RainMagnet upgrade level. v6 -> v7 (migrateV6) strips them
	from the stored table; pure, idempotent. Unknown or legacy values never error.
	v8 (current): Goo Traps are charges, not an owned tier: pvp.traps = { [GooTrapN] = charges }. v7 -> v8
	(migrateV7) turns an owned trap tier (pvp.tiers.Trap = n) into Config.PVP.TRAP_MAX_HELD charges of GooTrap<n>
	and drops tiers.Trap; pure, idempotent.
	SlimeDex (CONTRACT.md §36.2, no version bump): found = { speciesId }, speciesRewards = milestones paid;
	missing -> empty / 0, unknown ids dropped, owned slimes always count as found. The combination Dex fields `dex` / `dexRewards` of older saves are ignored.
	pvp (FEATURES.PvP, CONTRACT.md §26) is optional: { tiers = { Knockback = tier, Blaster = tier }, traps = { [id] = charges },
	fun = { id } }; missing / junk -> nothing owned, ids that are not Config.PVP_TOOLS are ignored,
	numbers are clamped (SaveData.cleanPvp).
	hotbar (CONTRACT.md §5.1) is optional and needs no version bump: 9 slot keys, "" = empty; missing / not a list -> nil,
	bad or repeated keys -> empty slots, entries past slot 9 dropped (HotbarOrder.clean).
	Unknown/newer versions are read field-by-field with the current sanitizer.
	SaveData.check tells DataService whether a stored record may be overwritten:
	"newer" (version above Config.SAVE_VERSION, e.g. a rolling update) and
	"unreadable" (not a save we recognise) are loaded best-effort but never saved over.
]]

local Config = if script then require(script.Parent.Config) else require("./Config")
local AudioSettings = if script then require(script.Parent.AudioSettings) else require("./AudioSettings")
local Genome = if script then require(script.Parent.Genome) else require("./Genome")
local HotbarOrder = if script then require(script.Parent.HotbarOrder) else require("./HotbarOrder")
local PlayerData = if script then require(script.Parent.PlayerData) else require("./PlayerData")
local PlotSkins = if script then require(script.Parent.PlotSkins) else require("./PlotSkins")
local SlimeRoster = if script then require(script.Parent.SlimeRoster) else require("./SlimeRoster")
local SpeciesDex = if script then require(script.Parent.SpeciesDex) else require("./SpeciesDex")
local StealAlert = if script then require(script.Parent.StealAlert) else require("./StealAlert")
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

-- Lines saved as a best tier; Goo Traps (TRAP_LINE) are saved as charges per trap id.
local PVP_LINES = { "Knockback", "Blaster" }
local TRAP_LINE = "Trap"

-- Boss trophies of a raw save (read) or of PlayerData (write): sanitized slimes of a boss species (SlimeRoster kind
-- "boss"), the first one per species, never on a pad. Missing / junk -> none.
function SaveData.cleanTrophies(raw: any): { Slime }
	local out: { Slime } = {}
	if type(raw) ~= "table" then
		return out
	end
	local seen: { [string]: boolean } = {}
	for _, rawSlime in raw do
		local slime = Genome.sanitize(rawSlime)
		local species = slime and slime.species
		local entry = if species then SlimeRoster.get(species) else nil
		if slime and species and entry and entry.kind == "boss" and not seen[species] then
			seen[species] = true
			slime.pad = nil
			slime.keep = nil
			table.insert(out, slime)
		end
	end
	return out
end

-- Sanitizes the pvp field of a raw save (read) or of PlayerData (write; `fun` is a set there, a list in the save).
function SaveData.cleanPvp(raw: any): PlayerData.Pvp
	local out: PlayerData.Pvp = { tiers = {}, traps = {}, fun = {} }
	if type(raw) ~= "table" then
		return out
	end
	if type(raw.traps) == "table" then
		for _, tool in Config.PVP_TOOLS do
			if tool.line == TRAP_LINE then
				local n = num(raw.traps[tool.id], 0, 0, Config.PVP.TRAP_MAX_HELD)
				if n > 0 then
					out.traps[tool.id] = n
				end
			end
		end
	end
	if type(raw.tiers) == "table" then
		for _, line in PVP_LINES do
			local top = 0
			for _, tool in Config.PVP_TOOLS do
				if tool.line == line then
					top = math.max(top, tool.tier)
				end
			end
			local tier = num(raw.tiers[line], 0, 0, top)
			if tier > 0 then
				out.tiers[line] = tier
			end
		end
	end
	if type(raw.fun) == "table" then
		for key, value in raw.fun do
			-- a list of ids (save) or an id -> true set (PlayerData)
			local id = if type(value) == "string" then value elseif value == true then key else nil
			if type(id) == "string" then
				for _, tool in Config.PVP_TOOLS do
					if tool.kind == "fun" and tool.id == id then
						out.fun[id] = true
					end
				end
			end
		end
	end
	return out
end

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
-- legacy `mutation`. Names are not checked. A slime with a clean list is returned as the same table.
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

-- v5 -> v6. Pure copy, idempotent, flag-independent. Normalises the three fields that were added
-- without a version: plotSkin (a known skin id is kept, anything else -> "classic"; whether it is
-- unlocked is decided on load), stealLog (StealAlert.clean) and settings (AudioSettings.clean,
-- missing -> defaults).
function SaveData.migrateV5(raw: { [string]: any }): { [string]: any }
	local out = table.clone(raw)
	local from = tonumber(raw.version)
	if from == nil or from ~= from then
		from = 0
	end
	out.migratedFrom = raw.migratedFrom or from
	out.plotSkin = if PlotSkins.get(raw.plotSkin) then raw.plotSkin else Config.PLOT_SKIN_DEFAULT
	out.stealLog = StealAlert.clean(raw.stealLog)
	out.settings = AudioSettings.clean(raw.settings)
	out.version = 6
	return out
end

-- Equipped plot skin of a stored profile: the saved id when it is a known skin the player has
-- unlocked in `data` (so the dex must already be loaded), else "classic". Pure.
function SaveData.migratePlotSkin(raw: any, data: Data): string
	local skin = if type(raw) == "table" then PlotSkins.get(raw.plotSkin) else nil
	if skin and PlotSkins.unlocked(data, skin) then
		return skin.id
	end
	return Config.PLOT_SKIN_DEFAULT
end

-- v6 -> v7. Pure copy, idempotent, flag-independent. Strips what mutations left in a save: `mutation` /
-- `mutations` on every stored slime and trophy, the Dex `stamps` and `stampRewards`, MutationSpray stock
-- and the RainMagnet upgrade level. Never touches `raw`; anything of an unexpected shape is left for deserialize.
local function stripSlimes(list: any): any
	if type(list) ~= "table" then
		return list
	end
	local out = {}
	for i, old in list do
		if type(old) == "table" and (old.mutation ~= nil or old.mutations ~= nil) then
			local slime = table.clone(old)
			slime.mutation = nil
			slime.mutations = nil
			out[i] = slime
		else
			out[i] = old
		end
	end
	return out
end

local function stripKey(map: any, key: string): any
	if type(map) ~= "table" or map[key] == nil then
		return map
	end
	local out = table.clone(map)
	out[key] = nil
	return out
end

function SaveData.migrateV6(raw: { [string]: any }): { [string]: any }
	local out = table.clone(raw)
	local from = tonumber(raw.version)
	if from == nil or from ~= from then
		from = 0
	end
	out.migratedFrom = raw.migratedFrom or from
	out.slimes = stripSlimes(raw.slimes)
	out.trophies = stripSlimes(raw.trophies)
	out.stamps = nil
	out.stampRewards = nil
	out.upgrades = stripKey(raw.upgrades, "RainMagnet")
	if type(raw.consumables) == "table" then
		local consumables = table.clone(raw.consumables)
		consumables.bought = stripKey(consumables.bought, "MutationSpray")
		consumables.held = stripKey(consumables.held, "MutationSpray")
		out.consumables = consumables
	end
	out.version = 7
	return out
end

-- v7 -> v8: an owned Goo Trap tier becomes a full stack of charges of that tier (the trap it owned; lower tiers
-- were only superseded). Saved trap ids never change, so the id is GooTrap<tier>.
function SaveData.migrateV7(raw: { [string]: any }): { [string]: any }
	local out = table.clone(raw)
	local from = tonumber(raw.version)
	if from == nil or from ~= from then
		from = 0
	end
	out.migratedFrom = raw.migratedFrom or from
	if type(raw.pvp) == "table" then
		local pvp = table.clone(raw.pvp)
		local tiers = if type(pvp.tiers) == "table" then table.clone(pvp.tiers) else nil
		local tier = if tiers then tonumber(tiers.Trap) else nil
		if tiers then
			tiers.Trap = nil
			pvp.tiers = tiers
		end
		if tier and tier == tier and tier >= 1 then
			local traps = if type(pvp.traps) == "table" then table.clone(pvp.traps) else {}
			local id = `GooTrap{math.floor(tier)}`
			traps[id] = math.max(tonumber(traps[id]) or 0, Config.PVP.TRAP_MAX_HELD)
			pvp.traps = traps
		end
		out.pvp = pvp
	end
	out.version = 8
	return out
end

-- Daily quests: keeps only slots whose pool id still exists (a rolled day with none left re-rolls).
function SaveData.cleanQuests(raw: any): PlayerData.DailyQuests
	local out: PlayerData.DailyQuests = { day = 0, slots = {} }
	if type(raw) ~= "table" then
		return out
	end
	out.day = num(raw.day, 0, 0, 1e7)
	if type(raw.slots) == "table" then
		for _, slot in raw.slots do
			if type(slot) == "table" and type(slot.id) == "string" and #out.slots < Config.DAILY_QUESTS.count then
				for _, def in Config.DAILY_QUESTS.pool do
					if def.id == slot.id then
						table.insert(out.slots, {
							id = def.id,
							target = num(slot.target, def.choices[1], 1, 1e12),
							base = num(slot.base, 0, 0, 1e18),
							claimed = slot.claimed == true,
						})
						break
					end
				end
			end
		end
	end
	return out
end

export type Verdict = "empty" | "ok" | "newer" | "unreadable"

-- Is the stored value (SessionLock-unwrapped) safe to overwrite with this build's serialize? Pure.
--   "empty": nothing stored (new player); "ok": a save this build knows (v1 legacy .. SAVE_VERSION);
--   "newer": a version above Config.SAVE_VERSION; "unreadable": anything else (deserialize would give a fresh
--   profile, and saving that would wipe the record).
function SaveData.check(stored: any): Verdict
	if stored == nil then
		return "empty"
	end
	if type(stored) ~= "table" then
		return "unreadable"
	end
	if stored.version == nil then
		if stored.Cash ~= nil or stored.Slimes ~= nil or stored.Rebirths ~= nil then
			return "ok" -- v1 legacy
		end
		return "unreadable"
	end
	local version = tonumber(stored.version)
	if version == nil or version ~= version then
		return "unreadable"
	end
	if version > Config.SAVE_VERSION then
		return "newer"
	end
	return "ok"
end

function SaveData.migrate(raw: any): { [string]: any }?
	if type(raw) ~= "table" then
		return nil
	end
	local version = tonumber(raw.version)
	local migrated = raw
	if version == nil then
		if raw.Cash == nil and raw.Slimes == nil and raw.Rebirths == nil then
			return nil
		end
		migrated, version = SaveData.migrateV1(raw), 2
	end
	if version < 4 then
		migrated = SaveData.migrateV3(migrated)
	end
	if version < 5 then
		migrated = SaveData.migrateV4(migrated)
	end
	if version < 6 then
		migrated = SaveData.migrateV5(migrated)
	end
	if version < 7 then
		migrated = SaveData.migrateV6(migrated)
	end
	if version < 8 then
		migrated = SaveData.migrateV7(migrated)
	end
	return migrated
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
	if type(raw.found) == "table" then
		for _, id in raw.found do
			if SpeciesDex.isSpecies(id) then
				data.found[id] = true
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
		-- v2 never counted catches: every slime on the plot was caught or merged at least.
		data.stats.caught = #data.slimes
	end
	if type(raw.goals) == "table" then
		for _, goal in Config.GOALS do
			local stage = num(raw.goals[goal.id], 0, 0, #goal.targets)
			if stage > 0 then
				data.goals[goal.id] = stage
			end
		end
	end
	data.quests = SaveData.cleanQuests(raw.quests) -- daily quests (no version bump: missing -> nothing rolled)
	data.speciesRewards = num(raw.speciesRewards, 0, 0, #Config.DEX_MILESTONES.species)
	data.plotSkin = SaveData.migratePlotSkin(raw, data)
	data.stealLog = StealAlert.clean(raw.stealLog) -- FEATURES.StealAlerts (missing -> empty)
	data.settings = AudioSettings.clean(raw.settings) -- FEATURES.Audio (missing -> defaults)
	data.pvp = SaveData.cleanPvp(raw.pvp) -- FEATURES.PvP (missing -> nothing owned)
	data.trophies = SaveData.cleanTrophies(raw.trophies) -- boss trophies (no version bump: missing -> none)
	data.hotbar = HotbarOrder.clean(raw.hotbar) -- hotbar order (no version bump: missing / junk -> nil)
	for _, trophy in data.trophies do
		PlayerData.discover(data, trophy) -- an owned boss always counts in the SlimeDex
	end

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
	-- Restocking shop counts (added without a version bump: missing -> nothing bought this slot).
	-- `held` (the stack of bought, unused consumables) is newer still: a save without it holds nothing (those
	-- purchases were applied when bought), and it is read even if `bought` is damaged.
	if type(raw.consumables) == "table" then
		local bought: { [string]: number } = {}
		local held: { [string]: number } = {}
		local rawBought = if type(raw.consumables.bought) == "table" then raw.consumables.bought else {}
		local rawHeld = if type(raw.consumables.held) == "table" then raw.consumables.held else {}
		for _, def in Config.CONSUMABLES do
			local n = num(rawBought[def.id], 0, 0, def.maxStock)
			if n > 0 then
				bought[def.id] = n
			end
			local h = math.floor(num(rawHeld[def.id], 0, 0, Config.CONSUMABLE_HELD_MAX))
			if h > 0 then
				held[def.id] = h
			end
		end
		data.consumables = { slot = num(raw.consumables.slot, 0, 0, 1e9), bought = bought, held = held }
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
			pad = slime.pad,
			species = slime.species, -- optional (v28), dropped on load if unknown
			growth = slime.growth, -- optional (FEATURES.GrowingSlimes): missing = 0, no version bump
			keep = if slime.keep == true then true else nil, -- optional (CONTRACT.md §21.1): missing = not kept, no version bump
			egg = if slime.egg then { kind = slime.egg.kind, hatchAt = slime.egg.hatchAt } else nil, -- optional (contract/mystery-egg.md): missing = a slime, no version bump
		})
	end
	local found = {}
	for id in data.found do
		table.insert(found, id)
	end
	table.sort(found)
	local redeemed = {}
	for code in data.redeemed do
		table.insert(redeemed, code)
	end
	table.sort(redeemed)
	local pvp = SaveData.cleanPvp(data.pvp)
	local pvpFun = {}
	for id in pvp.fun do
		table.insert(pvpFun, id)
	end
	table.sort(pvpFun)
	return {
		version = Config.SAVE_VERSION,
		cash = math.floor(data.cash),
		rebirths = data.rebirths,
		padsUnlocked = data.padsUnlocked,
		slimes = slimes,
		favoriteId = data.favoriteId,
		lastOnline = math.floor(now or data.lastOnline),
		daily = { lastDay = data.daily.lastDay, streak = data.daily.streak },
		found = found,
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
		speciesRewards = data.speciesRewards,
		quests = SaveData.cleanQuests(data.quests),
		plotSkin = data.plotSkin,
		stealLog = StealAlert.clean(data.stealLog),
		settings = AudioSettings.clean(data.settings),
		redeemed = redeemed,
		boost = { mult = data.boostMult, untilAt = math.floor(data.boostUntil) },
		consumables = {
			slot = data.consumables.slot,
			bought = table.clone(data.consumables.bought),
			held = table.clone(data.consumables.held),
		},
		pvp = { tiers = pvp.tiers, traps = pvp.traps, fun = pvpFun },
		trophies = SaveData.cleanTrophies(data.trophies),
		hotbar = HotbarOrder.clean(data.hotbar), -- nil until set: the key is left out
	}
end

return SaveData
