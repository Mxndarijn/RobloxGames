--!strict
-- Names shared by server and client: remotes, attributes, tags.

return table.freeze({
	REMOTES_FOLDER = "Remotes",
	-- Client -> server requests (RemoteFunction returns { ok: boolean, message: string? })
	REQUEST = "Request",
	-- Server -> client: full HUD snapshot (Types.State, server Snapshot.build)
	STATE = "State",
	-- Server -> client: toast message (text, kind: "info" | "good" | "bad", sound: string?)
	NOTIFY = "Notify",
	-- Server -> client: global TotalEarned board (Types.Leaderboard)
	LEADERBOARD = "Leaderboard",
	PVP_EVENT = "PvpEvent", -- ServerToClient RemoteEvent: PvP cooldown / effect / trap events (FEATURES.PvP, CONTRACT.md §26.1)

	SLIME_TAG = "Slime",
	DATASTORE_NAME = "StealASlime_v1",
	LEADERBOARD_STORE = "StealASlime_TotalEarned", -- OrderedDataStore, key "u_<UserId>"
	DATASTORE_MODE_ATTRIBUTE = "DataStoreMode", -- workspace attribute: "Memory" = no real DataStore
	-- workspace attribute set by the server: "Ok" | "Memory" | "Unavailable" | "Error" (CONTRACT.md §2)
	DATASTORE_STATUS_ATTRIBUTE = "DataStoreStatus",
	WORLD_MESHES_READY_ATTRIBUTE = "WorldMeshesReady", -- workspace attribute set by the server: true once MeshSwap dressed Map / Plots (CONTRACT.md §5.2)
	SLIME_LOOK_ATTRIBUTE = "SlimeLook", -- workspace attribute set by the server: "Mesh" | "Procedural"
	SPECIES_ATTRIBUTE = "Species", -- slime model: SlimeRoster id (v28 typed slimes only; SlimeLooks)
	-- World folders. "Map" and "Slimes" are hardcoded in src/visuals (WorldLayout); keep them in sync.
	MAP_FOLDER = "Map",
	PLOTS_FOLDER = "Plots",
	PLOT_SLIMES_FOLDER = "Slimes", -- per-plot folder for pad slimes
	WILD_FOLDER = "WildSlimes",
	SLIME_KITS_FOLDER = "SlimeKits", -- ReplicatedStorage: one loaded species MeshPart per kit, named "slime_<id>" (SlimeDex previews)
	PLOT_INDEX_ATTRIBUTE = "PlotIndex", -- Plot_<i> model: i
	PAD_INDEX_ATTRIBUTE = "PadIndex", -- Pad_<j> part: j
	HOME_ZONE = "HomeZone",
	-- Instance attributes (CONTRACT.md §5.2)
	REVENGE_PLOTS_ATTRIBUTE = "RevengePlots", -- Player (victim only): "3,5" = plot indexes of thieves inside the revenge window (FEATURES.Revenge), nil = none
	RITUAL_PHASE_ATTRIBUTE = "Phase", -- Map.RitualCircle: Ritual phase, "Idle" | "Charging" | "Cooldown"
	RITUAL_CHARGE_ENDS_ATTRIBUTE = "ChargeEndsAt", -- Map.RitualCircle: server time the hold completes (Charging only, else nil)
	RITUAL_READY_AT_ATTRIBUTE = "ReadyAt", -- Map.RitualCircle: server time the rest ends (Cooldown only, else nil)
	RITUAL_TAKEN_ATTRIBUTE = "Taken", -- Map.RitualCircle.Spot_<i>: true while a counted player stands on it
	CARRYING_ATTRIBUTE = "Carrying", -- Player: carried slime id, nil when empty-handed
	WEATHER_ATTRIBUTE = "Weather", -- workspace, set by the server (WeatherService): "Clear" | "Rain" | "Snow" | "Starfall"
	WEATHER_STARTED_ATTRIBUTE = "WeatherStartedAt", -- workspace, server time (GetServerTimeNow) the current weather began; set before WEATHER_ATTRIBUTE
	SNOW_ENDED_ATTRIBUTE = "SnowEndedAt", -- workspace, server time Snow last ended; cleared (nil) while Snow shows. Late joiners derive ground snow from both
	WEATHER_DEBUG_ATTRIBUTE = "WeatherDebug", -- workspace, set on ONE client only (pc-watcher shots): forces that weather's visuals
	SNOW_COVER_DEBUG_ATTRIBUTE = "SnowCoverDebug", -- workspace, client-local number 0..1 (pc-watcher snow shots): pins the ground snow cover level
	WEEKLY_EVENT_ATTRIBUTE = "WeeklyEvent", -- workspace string, set by the server (WeeklyEventService): WeeklyEvents.encode; absent while FEATURES.WeeklyEvents is off
	RAIN_ATTRIBUTE = "SlimeRain", -- workspace: true during Slime Rain
	RAIN_ACTIVE_ATTRIBUTE = "RainActive", -- workspace: same as SlimeRain
	RAIN_ENDS_AT_ATTRIBUTE = "RainEndsAt", -- workspace: server time, while raining
	RAIN_NEXT_AT_ATTRIBUTE = "RainNextAt", -- workspace: server time, while not raining
	BOSS_NEXT_AT_ATTRIBUTE = "BossNextAt", -- workspace: server time of the next Boss Slime
	TUTORIAL_STEP_ATTRIBUTE = "TutorialStep", -- Player: 1..6, nil = done / not loaded
	SPEED_COIL_ATTRIBUTE = "SpeedCoil", -- Player: true once the Speed Coil is owned
	PET_ATTRIBUTE = "PetSlimeId", -- Player: slime id that follows them (FollowPets), nil = none
	BOSS_ATTRIBUTE = "Boss", -- slime model: true on the wild Boss Slime
	BOSS_WALK_SEED_ATTRIBUTE = "BossWalkSeed", -- boss model: BossWander seed of its walk (the client draws the walk)
	BOSS_WALK_AT_ATTRIBUTE = "BossWalkAt", -- boss model: server time the walk starts (its arrival)
	BOSS_WALK_UNTIL_ATTRIBUTE = "BossWalkUntil", -- boss model: server time the walk stopped (the haul); nil while it walks
	-- World props (CONTRACT.md §5.3), placed by the server under workspace.Map
	SHOP_STAND = "ShopStand", -- alias of the Item Shop while FEATURES.WorldShops is off (the single HUD-shop stand)
	SHOP_STAND_ITEM = "ItemShopStand", -- CONTRACT.md §27.2
	SHOP_STAND_UPGRADE = "UpgradeShopStand",
	LEADERBOARD_BOARD = "LeaderboardBoard",
	TUTORIAL_NPC = "TutorialNpc",
	SPEED_COIL_TOOL = "SpeedCoil", -- Tool in the Backpack while owned
	-- ProximityPrompt on every slime's Body (grab / steal); Jolt's PromptHide matches this name.
	GRAB_PROMPT_NAME = "GrabPrompt",
	-- GrabPrompt: UserId that must not see this prompt (the owner on "Steal"); nil = everyone.
	-- Roblox has no per-player prompt visibility on the server, so clients hide it locally.
	PROMPT_HIDE_ATTRIBUTE = "HideFromUserId",
	-- v13 (CONTRACT.md §8)
	TUTORIAL_STEP_ID_ATTRIBUTE = "TutorialStepId", -- Player: TutorialProgress.STEPS name, nil = done
	WALK_SPEED_ATTRIBUTE = "TargetWalkSpeed", -- Player: WalkSpeed the server enforces right now
	PVP_EQUIPPED_ATTRIBUTE = "PvpEquipped", -- Player: equipped PvP item id (FEATURES.PvP only; nil = none, CONTRACT.md §26.1)
	BAT_SWING_ATTRIBUTE = "BatSwingAt", -- Player: server time of the last Bat swing (every client plays the swing, CONTRACT.md §26.2)
	REBIRTH_TITLE_ATTRIBUTE = "RebirthTitle", -- Player: rank title (Config.REBIRTH_TIERS)
	PLOT_LOCKED_ATTRIBUTE = "Locked", -- Plot_<i>: true while LockUntil > now
	PLOT_LOCK_COST_ATTRIBUTE = "LockCost", -- Plot_<i>: owner's lock price, 0 = free plot
	PLOT_PADS_UNLOCKED_ATTRIBUTE = "PadsUnlocked", -- Plot_<i>: owner's unlocked pads, 0 = free plot
	PLOT_NEXT_PAD_COST_ATTRIBUTE = "NextPadCost", -- Plot_<i>: nil when maxed / free
	PAD_UNLOCKED_ATTRIBUTE = "Unlocked", -- Pad_<j>: j <= PadsUnlocked
	PLOT_DEX_COUNT_ATTRIBUTE = "DexCount", -- Plot_<i>: owner's discovered dex entries, 0 = free plot
	PLOT_DEX_TOTAL_ATTRIBUTE = "DexTotal", -- Plot_<i>: SlimeDex entries (SpeciesDex.TOTAL, State.dex.total)
	PLOT_DEX_TIER_MASK_ATTRIBUTE = "DexTierMask", -- Plot_<i>: bit k-1 set = owner discovered a tier-k slime
	PLOT_SKIN_ATTRIBUTE = "PlotSkin", -- Plot_<i>: owner's equipped Config.PLOT_SKINS id (FEATURES.PlotSkins only)
	PLOT_PRICE_ATTRIBUTE = "PlotPrice", -- Plot_<i>: reserved; nil while plots are free (v13)
	RARE_ATTRIBUTE = "RareSpawn", -- wild slime model: tier, only on Legendary+ drops
	RIDING_ATTRIBUTE = "Riding", -- wild slime model: true while it rides the fountain slide (emerge to landing / lane entry), else nil
	CHOREO_SEED_ATTRIBUTE = "ChoreoSeed", -- lane wild model: ParadeChoreo seed of its lane beats (FEATURES.SlimeChoreo); nil off the lane
	LANE_AT_ATTRIBUTE = "LaneAt", -- lane wild model: server time it spawned (wild.spawnedAt), with ChoreoSeed
	LANE_UNTIL_ATTRIBUTE = "LaneUntil", -- lane wild model: server time it drains (wild.expiresAt), with ChoreoSeed
	-- wild slime model: server time it despawns; nil outside the telegraph window / FEATURES.DespawnTelegraph off
	DESPAWN_AT_ATTRIBUTE = "DespawnAt",
	GROWTH_ATTRIBUTE = "Growth", -- slime model: whole percent 0..100 (FEATURES.GrowingSlimes)
	LABEL_NAME_ATTRIBUTE = "LabelName", -- slime model: species name for its label (contract/slime-labels.md)
	LABEL_TIER_ATTRIBUTE = "LabelTier", -- slime model: Config.RARITIES tier
	LABEL_INCOME_ATTRIBUTE = "LabelIncome", -- slime model: cash per second of this slime
	LABEL_STATUS_ATTRIBUTE = "LabelStatus", -- slime model: text that replaces the income row (a Mystery Egg's hatch countdown), else nil
	EGG_KIND_ATTRIBUTE = "EggKind", -- Mystery Egg model: Config.MYSTERY_EGG.KINDS id (contract/mystery-egg.md)
	EGG_HATCH_AT_ATTRIBUTE = "EggHatchAt", -- Mystery Egg model: server time it is ready; nil while not incubating
	EGG_HATCH_SECONDS_ATTRIBUTE = "EggHatchSeconds", -- Mystery Egg model: its kind's full incubation time
	HATCH_PROMPT_NAME = "HatchPrompt", -- owner-only ProximityPrompt on a ready Mystery Egg
	LABEL_PAD_ATTRIBUTE = "LabelPad", -- slime model: pad index while it rests on a pad (the label is the pad sign), else nil
	LABEL_HEIGHT_ATTRIBUTE = "LabelHeight", -- slime model: studs from the Body centre to the card's bottom edge
	GROWTH_OVERRIDE_ATTRIBUTE = "PcwGrowth", -- slime model: Studio-only whole percent shown instead of the real growth (pc-watcher shot)
	FOUNTAIN_TIER_ATTRIBUTE = "FountainTier", -- workspace: fountain tier 1..4 (FEATURES.FountainTiers, FountainTiers); clients draw the ring / crest / glow from it
	RARE_SPAWN_ID_ATTRIBUTE = "RareSpawnId", -- workspace: latest rare drop
	RARE_SPAWN_TIER_ATTRIBUTE = "RareSpawnTier",
	RARE_SPAWN_AT_ATTRIBUTE = "RareSpawnAt", -- workspace: server time of the latest rare drop
	-- Owner-only prompts: only this UserId may see it (clients hide it locally); nil = free plot.
	PROMPT_OWNER_ATTRIBUTE = "ShowOnlyToUserId",
	LOCK_PROMPT_NAME = "LockPrompt", -- on LockButton
	BUY_PAD_PROMPT_NAME = "BuyPadPrompt", -- on the lowest locked Pad_<j>
	MERGE_PROMPT_NAME = "MergePrompt", -- on MergeVat
	-- v28 (CONTRACT.md §5.3): "Open Shop" (E) on ShopStand.Counter and "Talk" (E) on the
	-- TutorialNpc. Client-only effect: the UI opens the Shop / Guide menu on PromptTriggered.
	SHOP_PROMPT_NAME = "ShopPrompt",
	SHOP_EVENT = "ShopEvent", -- RemoteEvent, ServerToClient (CONTRACT.md §27.4)
	OPEN_SHOP_ATTRIBUTE = "OpenShop", -- Player: shopId the server has open for them, nil = closed (FEATURES.WorldShops)
	SHOP_ID_ATTRIBUTE = "ShopId", -- ItemShopStand / UpgradeShopStand: "ItemShop" | "UpgradeShop" (FEATURES.WorldShops)
	GUIDE_PROMPT_NAME = "GuidePrompt",
	-- Slime habitats (FEATURES.Habitats, HABITATS.md): Pad_<j> attributes, only set with the flag on.
	HABITAT_ATTRIBUTE = "Habitat", -- Pad_<j>: Shared.Habitats id, "base" = empty pad
	HABITAT_FROM_ATTRIBUTE = "HabitatFrom", -- Pad_<j>: the id before the latest change
	HABITAT_AT_ATTRIBUTE = "HabitatAt", -- Pad_<j>: server time of the latest change
	-- Full steal alerts (FEATURES.StealAlerts, CONTRACT.md §17): Player attributes, set only with the flag on.
	STEALING_ATTRIBUTE = "Stealing", -- Player: true while carrying a stolen slime (the client draws the thief trail), nil otherwise
	SLAP_HIT_ATTRIBUTE = "SlapHitAt", -- Player: server time the player was last slapped off a stolen slime (the client draws the hit effect)
	HABITAT_FOLDER = "ClientHabitats", -- client-only workspace folder for habitat looks
	HABITAT_MESHES = "HabitatMeshes", -- ReplicatedStorage folder: server-made overlay MeshPart templates (MeshSwap)
	PVP_MARKER_MESHES = "PvpMarkerMeshes", -- ReplicatedStorage folder: placed trap / pad MeshPart templates (FEATURES.PvP, MeshSwap)
})
