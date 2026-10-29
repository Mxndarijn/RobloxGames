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
	-- Server -> client: one global board per call (Types.Leaderboard; `stat` says which, Leaderboards.BOARDS)
	LEADERBOARD = "Leaderboard",
	PVP_EVENT = "PvpEvent", -- ServerToClient RemoteEvent: PvP cooldown / effect / trap events (FEATURES.PvP, CONTRACT.md §26.1)

	SLIME_TAG = "Slime",
	-- All stores moved to "_v2" on 2026-10-26 for a fresh start; the v1 data is still there, unread.
	DATASTORE_NAME = "StealASlime_v2",
	LEADERBOARD_STORE = "StealASlime_TotalEarned_v2", -- OrderedDataStore, key "u_<UserId>"
	WEEKLY_EARNED_STORE = "StealASlime_WeeklyEarned_v2", -- OrderedDataStore per week: "<name>_<WeeklyEvents.weekIndex>", key "u_<UserId>"
	STEALS_STORE = "StealASlime_TotalStolen_v2", -- OrderedDataStore, key "u_<UserId>"
	DEX_STORE = "StealASlime_SlimeDex_v2", -- OrderedDataStore, key "u_<UserId>"
	MERGES_STORE = "StealASlime_Merges_v2", -- OrderedDataStore, key "u_<UserId>"
	DATASTORE_MODE_ATTRIBUTE = "DataStoreMode", -- workspace attribute: "Memory" = no real DataStore
	-- workspace attribute set by the server: "Ok" | "Memory" | "Unavailable" | "Error" (CONTRACT.md §2)
	DATASTORE_STATUS_ATTRIBUTE = "DataStoreStatus",
	WORLD_MESHES_READY_ATTRIBUTE = "WorldMeshesReady", -- workspace attribute set by the server: true once MeshSwap dressed Map / Plots (CONTRACT.md §5.2)
	SLIME_LOOK_ATTRIBUTE = "SlimeLook", -- workspace attribute set by the server: "Mesh" | "Procedural"
	SPECIES_ATTRIBUTE = "Species", -- slime model: SlimeRoster id (v28 typed slimes only; SlimeLooks)
	-- On a part of a pad slime faded by the merge vat (server/VatView): its own transparency before the fade. A copy of
	-- the model (steal ghost, vat spot, Move ghost) starts from this, so it never inherits the fade.
	OWN_TRANSPARENCY_ATTRIBUTE = "VatFaded",
	-- World folders. "Map" and "Slimes" are hardcoded in src/visuals (WorldLayout); keep them in sync.
	MAP_FOLDER = "Map",
	PLOTS_FOLDER = "Plots",
	PLOT_SLIMES_FOLDER = "Slimes", -- per-plot folder for pad slimes
	WILD_FOLDER = "WildSlimes",
	SLIME_KITS_FOLDER = "SlimeKits", -- PlayerGui: the species MeshParts this player asked for (RequestKits), named "slime_<id>" (SlimeDex previews)
	PLOT_INDEX_ATTRIBUTE = "PlotIndex", -- Plot_<i> model: i
	PAD_INDEX_ATTRIBUTE = "PadIndex", -- Pad_<j> part: j
	HOME_ZONE = "HomeZone",
	-- Instance attributes (CONTRACT.md §5.2)
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
	PET_SEAT_ATTRIBUTE = "PetSeat", -- Player: Config.PET_SEATS id their follow pet rides (PetSeats.current)
	BOSS_ATTRIBUTE = "Boss", -- slime model: true on the wild Boss Slime
	BOSS_MOVE_ATTRIBUTE = "BossMove", -- boss model: its current move (BossChoreo.encode); clients draw it every frame
	BOSS_TARGETS_ATTRIBUTE = "BossTargets", -- boss model: "x,z;x,z" world spots its windup's spits will land on
	BOSS_SPITS_ATTRIBUTE = "BossSpits", -- boss model: "x,z,landAt;..." spits in the air (server time they land)
	BOSS_RUNES_ATTRIBUTE = "BossRunes", -- boss model: "x,z,burstAt,radius,speed;..." rune puddles that burst into a ring
	BOSS_HIT_AT_ATTRIBUTE = "BossHitAt", -- boss model: server time of the latest counted bat hit (it squashes)
	BOSS_HIT_BY_ATTRIBUTE = "BossHitBy", -- boss model: the UserId of that hit
	BOSS_HIT_POINTS_ATTRIBUTE = "BossHitPoints", -- boss model: meter points that hit counted
	BOSS_GUARD_ATTRIBUTE = "BossGuard", -- workspace.BossFx guard models: true
	-- World props (CONTRACT.md §5.3), placed by the server under workspace.Map
	SHOP_STAND_ITEM = "ItemShopStand", -- CONTRACT.md §27.2
	SHOP_STAND_UPGRADE = "UpgradeShopStand",
	SHOP_STAND_EXCLUSIVE = "ExclusiveShopStand", -- the Golden Jar Boutique (Model with the Counter) on the plaza
	EXCLUSIVE_SHOP_ID = "ExclusiveShop", -- ShopId of the jar stand; the client opens the ExclusiveShop panel for it
	LEADERBOARD_BOARD = "LeaderboardBoard", -- the Top Earners board (with the podium)
	WEEKLY_EARNERS_BOARD = "WeeklyEarnersBoard",
	TOP_STEALS_BOARD = "TopStealsBoard",
	TOP_DEX_BOARD = "TopDexBoard",
	TOP_MERGES_BOARD = "TopMergesBoard",
	LEADERBOARD_STAT_ATTRIBUTE = "LeaderboardStat", -- on each board Model: the Types.Leaderboard `stat` it shows
	PROFESSOR_GOO = "ProfessorGoo", -- the Hall of Fame greeter NPC under workspace.Map
	HALL_ARCH = "HallOfFameArch", -- the Hall of Fame entrance arch under workspace.Map
	TUTORIAL_NPC = "TutorialNpc",
	SPEED_COIL_TOOL = "SpeedCoil", -- Tool in the Backpack while owned
	-- ProximityPrompt on every slime's Body (grab / steal); Jolt's PromptHide matches this name.
	GRAB_PROMPT_NAME = "GrabPrompt",
	-- GrabPrompt: UserId that must not see this prompt (the owner on "Steal"); nil = everyone.
	-- Roblox has no per-player prompt visibility on the server, so clients hide it locally.
	PROMPT_HIDE_ATTRIBUTE = "HideFromUserId",
	PROMPT_GUESTS_ATTRIBUTE = "GuestsOnly", -- GrabPrompt on a locked base with guests: ",<id>,<id>," (PlotGuests); other clients hide it
	-- v13 (CONTRACT.md §8)
	TUTORIAL_STEP_ID_ATTRIBUTE = "TutorialStepId", -- Player: TutorialProgress.STEPS name, nil = done
	WALK_SPEED_ATTRIBUTE = "TargetWalkSpeed", -- Player: WalkSpeed the server enforces right now
	PVP_EQUIPPED_ATTRIBUTE = "PvpEquipped", -- Player: equipped PvP item id (FEATURES.PvP only; nil = none, CONTRACT.md §26.1)
	BAT_SWING_ATTRIBUTE = "BatSwingAt", -- Player: server time of the last Bat swing (every client plays the swing, CONTRACT.md §26.2)
	REBIRTH_TITLE_ATTRIBUTE = "RebirthTitle", -- Player: rank title (Config.REBIRTH_TIERS)
	PLOT_LOCKED_ATTRIBUTE = "Locked", -- Plot_<i>: true while LockUntil > now
	PLOT_LOCK_STARTED_AT_ATTRIBUTE = "LockStartedAt", -- Plot_<i>: server time the current lock began (0 = none)
	PLOT_LOCK_PAD_SINCE_ATTRIBUTE = "LockPadSince", -- Plot_<i>: server time the owner stepped onto the lock pad, nil = off it
	PLOT_FRIENDS_ALLOWED_ATTRIBUTE = "FriendsAllowed", -- Plot_<i>: true while the owner lets friends in (FEATURES.FriendsInBase)
	PLOT_GUESTS_ATTRIBUTE = "Guests", -- Plot_<i>: ",<id>,<id>," of the players its locked stopper lets through besides the owner
	PLOT_PADS_UNLOCKED_ATTRIBUTE = "PadsUnlocked", -- Plot_<i>: owner's unlocked pads, 0 = free plot
	PLOT_NEXT_PAD_COST_ATTRIBUTE = "NextPadCost", -- Plot_<i>: nil when maxed / free
	PAD_UNLOCKED_ATTRIBUTE = "Unlocked", -- Pad_<j>: j <= PadsUnlocked
	PLOT_SKIN_ATTRIBUTE = "PlotSkin", -- Plot_<i>: owner's equipped Config.PLOT_SKINS id (FEATURES.PlotSkins only)
	PLOT_BASE_ATTRIBUTE = "PlotBase", -- Plot_<i>: owner's equipped Config.PLOT_BASES id (FEATURES.BaseShapes only)
	SHINE_ATTRIBUTE = "Shine", -- slime model: its Config.SHINES id (weather mutation); nil = none
	GRAB_REBIRTHS_ATTRIBUTE = "GrabRebirths", -- wild slime model: rebirths needed to grab it (GrabBlock.rebirthsFor); nil = open
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
	-- Keys of the prompts on your own pad slime, as Enum.KeyCode names: the server's HatchPrompt and SlimeKeys'
	-- Move / Favorite / Sell prompts. No two share a key or a button, so a ready egg's prompts never collide.
	-- Gamepad A jumps, B closes menus and Y opens the bag (ui/Inventory), so the one free face button, X, is Hatch's.
	SLIME_PROMPT_KEYS = table.freeze({
		hatch = table.freeze({ keyboard = "F", gamepad = "ButtonX" }),
		move = table.freeze({ keyboard = "E", gamepad = "DPadRight" }),
		favorite = table.freeze({ keyboard = "R", gamepad = "DPadUp" }),
		sell = table.freeze({ keyboard = "X", gamepad = "DPadDown" }),
	}),
	HATCHED_AT_ATTRIBUTE = "HatchedAt", -- egg, then slime model, for MYSTERY_EGG.HATCH_FX_SECONDS after a hatch: server time of it
	HATCHED_FROM_ATTRIBUTE = "HatchedFrom", -- slime model, with HatchedAt: the egg kind id it hatched from
	EGG_SMASHED_AT_ATTRIBUTE = "EggSmashedAt", -- wild egg model: server time a carrier dropped it and it smashed
	HATCH_LUCKY_ATTRIBUTE = "HatchLucky", -- slime model, with HatchedAt: true for a lucky egg or a full lucky meter
	HATCH_TIER_ATTRIBUTE = "HatchTier", -- the egg model during a hatch show (HATCH_BURST_SECONDS): the tier inside, for the glow
	LUCKY_AT_ATTRIBUTE = "LuckyAt", -- pad slime model, for LUCKY_SHOW.FX_SECONDS after a Lucky Charm upgrade: server time of it
	LUCKY_FROM_TIER_ATTRIBUTE = "LuckyFromTier", -- pad slime model, with LuckyAt: the rarity it was caught at
	HATCH_POPPING_ATTRIBUTE = "HatchPopping", -- client-local, on a hatched slime model while its pop plays: the label waits
	LABEL_PAD_ATTRIBUTE = "LabelPad", -- slime model: pad index while it rests on a pad (the label is the pad sign), else nil
	LABEL_HEIGHT_ATTRIBUTE = "LabelHeight", -- slime model: studs from the Body centre to the card's bottom edge
	TAG_ANCHOR = "TagAnchor", -- client-only Attachment on a slime's Body: the name tag and the Buy card hang on it;
	-- SlimeLifeRunner moves it after the drawn slime (contract/slime-life.md "Clean lane")
	GROWTH_OVERRIDE_ATTRIBUTE = "PcwGrowth", -- slime model: Studio-only whole percent shown instead of the real growth (pc-watcher shot)
	FOUNTAIN_TIER_ATTRIBUTE = "FountainTier", -- workspace: fountain tier 1..4 (FEATURES.FountainTiers, FountainTiers); clients draw the ring / crest / glow from it
	RARE_SPAWN_ID_ATTRIBUTE = "RareSpawnId", -- workspace: latest rare drop
	RARE_SPAWN_TIER_ATTRIBUTE = "RareSpawnTier",
	RARE_SPAWN_AT_ATTRIBUTE = "RareSpawnAt", -- workspace: server time of the latest rare drop
	-- Owner-only prompts: only this UserId may see it (clients hide it locally); nil = free plot.
	PROMPT_OWNER_ATTRIBUTE = "ShowOnlyToUserId",
	LOCK_PROMPT_NAME = "LockPrompt", -- on LockButton
	LOCK_PAD_NAME = "LockPad", -- Plot_<i> Model: the lock pad (a shared RingPad): Models Seg_1..Seg_n round the LockButton (server-built)
	FRIENDS_PROMPT_NAME = "FriendsPrompt", -- on LockButton, next to LockPrompt: the owner's friends switch (FEATURES.FriendsInBase)
	FRIENDS_PROMPT_KEYS = table.freeze({ keyboard = "G", gamepad = "ButtonY" }), -- FriendsPrompt's keys (F is the pad hatch key)
	BUY_PAD_PROMPT_NAME = "BuyPadPrompt", -- on the lowest locked Pad_<j>
	MERGE_PROMPT_NAME = "MergePrompt", -- on MergeVat
	DROP_PROMPT_NAME = "DropPrompt", -- in every upper jar's DropHatch (CONTRACT.md §5.3): the owner, inside the top jar
	-- One ShopPrompt (E) on each shop stand's Counter (CONTRACT.md §27.3; the server opens that shop) and "Talk" (E)
	-- on the TutorialNpc (CONTRACT.md §5.3; the UI opens the Guide menu on PromptTriggered).
	SHOP_PROMPT_NAME = "ShopPrompt",
	SHOP_EVENT = "ShopEvent", -- RemoteEvent, ServerToClient (CONTRACT.md §27.4)
	OPEN_SHOP_ATTRIBUTE = "OpenShop", -- Player: shopId the server has open for them, nil = closed
	MENU_OPEN_ATTRIBUTE = "MenuOpen", -- PlayerGui.SlimeUI (client only): a menu or popup is open; edge arrows hide
	UI_GUI_NAME = "SlimeUI", -- the client's main ScreenGui in PlayerGui
	SHOP_ID_ATTRIBUTE = "ShopId", -- ItemShopStand / UpgradeShopStand: "ItemShop" | "UpgradeShop"
	GUIDE_PROMPT_NAME = "GuidePrompt",
	LEADERBOARD_PROMPT_NAME = "LeaderboardPrompt", -- ProfessorGoo: opens the client's Leaderboards panel
	LEADERBOARD_CLICK_NAME = "LeaderboardClick", -- ProfessorGoo's ClickDetector: a click or right-click opens the same panel
	-- Slime habitats (FEATURES.Habitats, HABITATS.md): Pad_<j> attributes, only set with the flag on.
	HABITAT_ATTRIBUTE = "Habitat", -- Pad_<j>: Shared.Habitats id, "base" = empty pad
	HABITAT_FROM_ATTRIBUTE = "HabitatFrom", -- Pad_<j>: the id before the latest change
	HABITAT_AT_ATTRIBUTE = "HabitatAt", -- Pad_<j>: server time of the latest change
	-- Full steal alerts (FEATURES.StealAlerts, CONTRACT.md §17): Player attributes.
	STEALING_ATTRIBUTE = "Stealing", -- Player: true while carrying a stolen slime (the client draws the thief trail), nil otherwise
	SLAP_HIT_ATTRIBUTE = "SlapHitAt", -- Player: server time the player was last slapped off a stolen slime (the client draws the hit effect)
	-- Exclusive Shop cosmetics (contract/exclusive-shop.md §9-§10): Player attributes.
	CARRY_TRAIL_ATTRIBUTE = "CarryTrail", -- Player: equipped Config.EXCLUSIVE_SHOP.trails id (the client draws it while they carry a slime), nil = none
	BAT_SKIN_ATTRIBUTE = "BatSkin", -- Player: equipped Config.EXCLUSIVE_SHOP.batSkins id (the server re-gives the Bat with that look), nil = the default Bat
	PLOT_LOCK_STYLE_ATTRIBUTE = "LockStyle", -- Plot_<i>: the owner's worn Exclusive lock style id (MeshSwap shows its stopper), nil = default
	PLOT_SLIME_HAT_ATTRIBUTE = "SlimeHat", -- Plot_<i>: the owner's worn Exclusive slime hat id (the client puts it on their pad slimes), nil = none
	MEMBER_ATTRIBUTE = "Member", -- Player: "vip" (VIP pass) or "club" (Slime Club subscriber; VIP wins when both): the name tag and chat tag, nil = none
	HABITAT_FOLDER = "ClientHabitats", -- client-only workspace folder for habitat looks
	HABITAT_MESHES = "HabitatMeshes", -- ReplicatedStorage folder: server-made overlay MeshPart templates (MeshSwap)
	PVP_MARKER_MESHES = "PvpMarkerMeshes", -- ReplicatedStorage folder: placed trap / pad MeshPart templates (FEATURES.PvP, MeshSwap)
})
