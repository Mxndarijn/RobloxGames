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

	SLIME_TAG = "Slime",
	DATASTORE_NAME = "StealASlime_v1",
	LEADERBOARD_STORE = "StealASlime_TotalEarned", -- OrderedDataStore, key "u_<UserId>"
	DATASTORE_MODE_ATTRIBUTE = "DataStoreMode", -- workspace attribute: "Memory" = no real DataStore
	-- workspace attribute set by the server: "Ok" | "Memory" | "Unavailable" | "Error" (CONTRACT.md §2)
	DATASTORE_STATUS_ATTRIBUTE = "DataStoreStatus",
	SLIME_LOOK_ATTRIBUTE = "SlimeLook", -- workspace attribute set by the server: "Mesh" | "Procedural"
	-- World folders. "Map" and "Slimes" are hardcoded in src/visuals (WorldLayout); keep them in sync.
	MAP_FOLDER = "Map",
	PLOTS_FOLDER = "Plots",
	PLOT_SLIMES_FOLDER = "Slimes", -- per-plot folder for pad slimes
	WILD_FOLDER = "WildSlimes",
	PLOT_INDEX_ATTRIBUTE = "PlotIndex", -- Plot_<i> model: i
	PAD_INDEX_ATTRIBUTE = "PadIndex", -- Pad_<j> part: j
	HOME_ZONE = "HomeZone",
	-- Instance attributes (CONTRACT.md §5.2)
	CARRYING_ATTRIBUTE = "Carrying", -- Player: carried slime id, nil when empty-handed
	RAIN_ATTRIBUTE = "SlimeRain", -- workspace: true during Slime Rain
	RAIN_ACTIVE_ATTRIBUTE = "RainActive", -- workspace: same as SlimeRain
	RAIN_ENDS_AT_ATTRIBUTE = "RainEndsAt", -- workspace: server time, while raining
	RAIN_NEXT_AT_ATTRIBUTE = "RainNextAt", -- workspace: server time, while not raining
	TUTORIAL_STEP_ATTRIBUTE = "TutorialStep", -- Player: 1..6, nil = done / not loaded
	SPEED_COIL_ATTRIBUTE = "SpeedCoil", -- Player: true once the Speed Coil is owned
	PET_ATTRIBUTE = "PetSlimeId", -- Player: slime id that follows them (FEATURES.FollowPets), nil = none
	BOSS_ATTRIBUTE = "Boss", -- slime model: true on the wild Boss Slime
	-- World props (CONTRACT.md §5.3), placed by the server under workspace.Map
	SHOP_STAND = "ShopStand",
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
	REBIRTH_TITLE_ATTRIBUTE = "RebirthTitle", -- Player: rank title (Config.REBIRTH_TIERS)
	PLOT_LOCKED_ATTRIBUTE = "Locked", -- Plot_<i>: true while LockUntil > now
	PLOT_LOCK_COST_ATTRIBUTE = "LockCost", -- Plot_<i>: owner's lock price, 0 = free plot
	PLOT_PADS_UNLOCKED_ATTRIBUTE = "PadsUnlocked", -- Plot_<i>: owner's unlocked pads, 0 = free plot
	PLOT_NEXT_PAD_COST_ATTRIBUTE = "NextPadCost", -- Plot_<i>: nil when maxed / free
	PAD_UNLOCKED_ATTRIBUTE = "Unlocked", -- Pad_<j>: j <= PadsUnlocked
	PLOT_DEX_COUNT_ATTRIBUTE = "DexCount", -- Plot_<i>: owner's discovered dex entries, 0 = free plot
	PLOT_DEX_TOTAL_ATTRIBUTE = "DexTotal", -- Plot_<i>: 720 (State.dexTotal)
	PLOT_DEX_TIER_MASK_ATTRIBUTE = "DexTierMask", -- Plot_<i>: bit k-1 set = owner discovered a tier-k slime
	PLOT_PRICE_ATTRIBUTE = "PlotPrice", -- Plot_<i>: reserved; nil while plots are free (v13)
	RARE_ATTRIBUTE = "RareSpawn", -- wild slime model: tier, only on Legendary+ drops
	-- wild slime model: server time it despawns; nil outside the telegraph window / FEATURES.DespawnTelegraph off
	DESPAWN_AT_ATTRIBUTE = "DespawnAt",
	RARE_SPAWN_ID_ATTRIBUTE = "RareSpawnId", -- workspace: latest rare drop
	RARE_SPAWN_TIER_ATTRIBUTE = "RareSpawnTier",
	RARE_SPAWN_AT_ATTRIBUTE = "RareSpawnAt", -- workspace: server time of the latest rare drop
	-- Owner-only prompts: only this UserId may see it (clients hide it locally); nil = free plot.
	PROMPT_OWNER_ATTRIBUTE = "ShowOnlyToUserId",
	LOCK_PROMPT_NAME = "LockPrompt", -- on LockButton
	BUY_PAD_PROMPT_NAME = "BuyPadPrompt", -- on the lowest locked Pad_<j>
	MERGE_PROMPT_NAME = "MergePrompt", -- on MergeVat
	-- v16 (CONTRACT.md §9.1): "Claim plot" on a free plot's BuyStand.Counter, everyone sees it.
	CLAIM_PROMPT_NAME = "ClaimPrompt",
})
