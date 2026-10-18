--!strict
-- Tests that cannot run when scripts/test-flags forces every Config.FEATURES flag (SLIME_FORCE_FEATURES).
-- Config.FEATURES is frozen, so a check that needs a flag on cannot run in the all-off mode, and a
-- check that pins the shipped default (or the off path of a default-off flag) cannot run in the
-- all-on mode. The single-flag off paths of the default-on flags stay covered by FeatureFlags.spec
-- and by the specs that pass the flag as an argument. Keys are a describe group (the part of the
-- test name before " > ") or a full test name; the value says why.
local ForcedFlags = {}

-- All flags off: these need the named flag(s) on.
ForcedFlags.off = {
	["world shops config > WorldShops is on by default"] = "WorldShops",
	["world shops config > WorldShopsStrict is on by default"] = "WorldShopsStrict",
	["world shop stands in the booted server"] = "WorldShops",
	["AdminEvents gate"] = "AdminEvents",
	["PvpRules config > is on by default (Merijn 2026-10-17: PvP ships on)"] = "PvP",
	["AdminEvents parse + validate"] = "AdminEvents",
	["AdminEvents effects"] = "AdminEvents",
	["WeeklyEvents vs live admin events (#130)"] = "AdminEvents",
	["Appraise"] = "Appraise",
	["FeatureOverride > leaves the shipped defaults unchanged under Lune (install is a no-op)"] = "the shipped defaults (all-off mode forces every flag false)",
	["Merge and Appraise stacking"] = "MutationStacking",
	["Boss Slime (FEATURES.BossSlime)"] = "BossSlime",
	["Player-facing copy"] = "BossSlime",
	["BuyEgg"] = "MysteryEgg",
	["MysteryEgg.spawnForEvent"] = "MysteryEgg",
	["MysteryEgg save format"] = "MutationStacking",
	["Consumables schedule"] = "Consumables",
	["Consumables purchase rules"] = "Consumables",
	["Consumables effects"] = "Consumables",
	["Consumables state and saves"] = "Consumables",
	["CycleModifier odds"] = "CycleModifier",
	["Spawner.stepModifier"] = "CycleModifier",
	["FountainRide: the live server rides every spawned slime"] = "Parade",
	["ParadeLane: handoff to the goo drain"] = "Parade",
	["ParadeLane: the despawn telegraph stays readable"] = "Parade",
	["ParadeLane in the live server"] = "Parade",
	["runtime part budget > boots with no server errors and spawns the parade lane and slide colliders"] = "Parade / SlideCollision",
	["FriendBonus math"] = "FriendBonus",
	["Friends.refresh"] = "FriendBonus",
	["friend bonus in income and State"] = "FriendBonus",
	["Genome stacking"] = "MutationStacking",
	["MutationStacking config"] = "MutationStacking",
	["plot skins: unlock thresholds"] = "MutationStacking (the Dex total)",
	["plot skin cards (SlimeDex.skinRows)"] = "MutationStacking (the Dex total)",
	["Snapshot.build > has every Types.State field with the right values"] = "MutationStacking (the Dex total)",
	["Genome.rollMutation with weather"] = "Weather",
	["Weather flag"] = "Weather",
	["SnowGround flag > is on and WeatherFx checks it before SnowGround.start"] = "SnowGround",
	["Weather mutation config"] = "Weather",
	["RainMagnet: target and roll"] = "MutationStacking",
	["RainMagnet: deposit hook > a full mutation stack is left alone, a fusing combo still fits"] = "MutationStacking",
	["Growth curve"] = "GrowingSlimes",
	["Growth income"] = "GrowingSlimes",
	["Growth offline"] = "GrowingSlimes",
	["Growth label"] = "GrowingSlimes",
	["Habitats table"] = "Habitats",
	["LiveBoot (server Script in the fake runtime) > with FEATURES.Habitats on, every pad carries a known habitat id and the server builds no looks"] = "Habitats",
	["LOD tiers (FEATURES.SlimeLod)"] = "SlimeLod",
	["MinimapData (FEATURES.Minimap)"] = "Minimap",
	["Perks.petPassive"] = "PetPassives",
	["applied server-side"] = "PetPassives",
	["Revenge config"] = "Revenge",
	["Revenge window"] = "Revenge",
	["Revenge lock cost"] = "Revenge",
	["Revenge several thieves and victims"] = "Revenge",
	["Revenge thief or victim leaving"] = "Revenge",
	["Ritual.step"] = "CoopRitual",
	["RitualService.step"] = "CoopRitual",
	["SlideColliders specs"] = "SlideCollision",
	["SlideColliders in the live server"] = "SlideCollision",
	["WelcomeBack.report"] = "WelcomeBack",
	["welcome-back on join"] = "WelcomeBack",
}

-- Spec modules that assert a flag at load time.
ForcedFlags.offModules = {
	["HabitatsLive.spec"] = "Habitats",
}

-- All flags on: these pin a flag that ships off (ServerProfiler) or the shipped defaults.
ForcedFlags.on = {
	["FeatureOverride > leaves the shipped defaults unchanged under Lune (install is a no-op)"] = "every FeatureOverride flag",
	["Profiler > is off by default and the flag is declared"] = "ServerProfiler",
}

-- Tests that exercise the off path (or pin "default off") of a flag that now ships ON (2026-10-18:
-- switch on every built feature). They only make sense with that flag off, so they run in the
-- all-flags-off mode alone and are skipped in the default and the all-on runs (and in the cloud tests).
ForcedFlags.needOff = {
	["Audio flag > is off by default"] = "Audio",
	["StealAlerts arrow and flash vs the banners and nav > the StealAlerts flag stays default off"] = "StealAlerts",
	["FountainTiers: the ladder > is behind FEATURES.FountainTiers, default off"] = "FountainTiers",
	["FountainTiers: the ladder > rank cards only mention a family with the feature on (off: tierText is unchanged)"] = "FountainTiers",
	["FountainTiers: server > the world starts at tier 1 and the tier step is a no-op with the feature off"] = "FountainTiers",
	["FountainTiers: server > a spawned drop is Classic with the feature off even at tier 4"] = "FountainTiers",
	["FountainTiers: server > the catch gate: a family slime needs the family's rank, Classic and stolen slimes never do"] = "FountainTiers",
	["FountainTiers: server > a refused family grab costs nothing and a rank-ready player grabs it"] = "FountainTiers",
	["plot skins: config > is behind FEATURES.PlotSkins, default off"] = "PlotSkins",
	["plot skins: equip > the Request refuses a locked skin, and equips an unlocked one"] = "PlotSkins",
	["plot skins: equip > with the flag off the Request is refused, even for an unlocked skin"] = "PlotSkins",
	["plot skins: equip > flag off: State carries no plot skin fields"] = "PlotSkins",
	["RainMagnet: the upgrade entry > is behind FEATURES.RainMagnet, default off, and the def is flag-tagged"] = "RainMagnet",
	["RainMagnet: the upgrade entry > is not listed, not buyable and has no effect while the flag is off"] = "RainMagnet",
	["RainMagnet: the upgrade entry > old upgrades are listed exactly as before"] = "RainMagnet",
	["RainMagnet: deposit hook > does nothing in Clear, at level 0, with the flag off, or for a full-stack slime"] = "RainMagnet",
	["RainMagnet: deposit hook > a full deposit with the flag off leaves the slime and the rng alone"] = "RainMagnet",
	["RainMagnet: deposit hook > deposit draws the same rng with and without weather while the flag is off"] = "RainMagnet",
	["RainMagnet: deposit hook > buying is refused with the flag off even for a rich rank-6 player"] = "RainMagnet",
	["StealAlert config > is behind FEATURES.StealAlerts, default off"] = "StealAlerts",
	["TripleMerge: rules > is behind FEATURES.MergeVat3, default off"] = "MergeVat3",
	["TripleMerge: server action > is refused with the flag off and merges with it on"] = "MergeVat3",
	["WeeklyEvents config > is off by default and every rotation entry is a real, plain mutation"] = "WeeklyEvents",
	["driver choice > ships with the uploaded animations off"] = "SlimeAnimations",
}

return ForcedFlags
