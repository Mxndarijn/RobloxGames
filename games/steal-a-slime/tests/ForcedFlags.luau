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
	["plot pad prompts on the real world (WorldShopsStrict on)"] = "WorldShopsStrict",
	["AdminEvents gate"] = "AdminEvents",
	["PvpRules config > is on by default (Merijn 2026-10-17: PvP ships on)"] = "PvP",
	["AdminEvents parse + validate"] = "AdminEvents",
	["AdminEvents effects"] = "AdminEvents",
	["WeeklyEvents vs live admin events (#130)"] = "AdminEvents",
	["FeatureOverride > leaves the shipped defaults unchanged under Lune (install is a no-op)"] = "the shipped defaults (all-off mode forces every flag false)",
	["Consumables schedule"] = "Consumables",
	["Consumable stacks"] = "Consumables",
	["UseConsumable"] = "Consumables",
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
	["Weather flag"] = "Weather",
	["Growth curve"] = "GrowingSlimes",
	["Growth income"] = "GrowingSlimes",
	["Growth offline"] = "GrowingSlimes",
	["Growth label"] = "GrowingSlimes",
	["welcome-back on join > carries the offline cash and the slimes that grew"] = "GrowingSlimes",
	["Habitats table"] = "Habitats",
	["LiveBoot (server Script in the fake runtime) > with FEATURES.Habitats on, every pad carries a known habitat id and the server builds no looks"] = "Habitats",
	["Revenge config"] = "Revenge",
	["Revenge window"] = "Revenge",
	["Revenge lock cost"] = "Revenge",
	["Revenge several thieves and victims"] = "Revenge",
	["Revenge thief or victim leaving"] = "Revenge",
	["Ritual.step"] = "CoopRitual",
	["RitualService.step"] = "CoopRitual",
	["SlideColliders specs"] = "SlideCollision",
	["SlideColliders in the live server"] = "SlideCollision",
	["FountainSplit data > is behind FEATURES.FountainSplit, default on"] = "FountainSplit",
	["FountainSplit data > the slide is PCD behind FEATURES.SlidePCD, default on"] = "SlidePCD",
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
	["StealAlert config > is behind FEATURES.StealAlerts, default off"] = "StealAlerts",
	["TripleMerge: rules > is behind FEATURES.MergeVat3, default off"] = "MergeVat3",
	["TripleMerge: server action > is refused with the flag off and merges with it on"] = "MergeVat3",
	["driver choice > ships with the uploaded animations off"] = "SlimeAnimations",
	-- FEATURES.FountainSplit on: the fountain is 5 PCD pieces and the hand-placed colliders stay off (tests/FountainSplit.spec);
	-- these pin the single Mesh child and the colliders turned on by it
	["fountain collider, mesh loading > stays that way while the fountain's CreateMeshPartAsync is in flight"] = "FountainSplit",
	["fountain collider, mesh loaded > swaps the mesh in as visual-only"] = "FountainSplit",
	["fountain collider, mesh loaded > switches all three colliders on and the stand-ins off in the same step"] = "FountainSplit",
	["fountain collider, mesh loaded > keeps the plinth and silo colliders on the kit profile"] = "FountainSplit",
	["fountain collider, mesh loaded > leaves no invisible step around the base (only the base and top colliders collide unseen)"] = "FountainSplit",
	["fountain collider, mesh loaded > setMeshCollision is the one switch: off restores the stand-ins, on again matches MeshSwap"] = "FountainSplit",
	["fountain bevel collider, real numbers > loaded: plinth r13.1 h0-1.5, bevel r12.3 h1.5-2.4, wall r11.2 h1.5-31.3"] = "FountainSplit",
	["fountain bevel collider, real numbers > loaded: the collision silhouette follows the profile (no sink between h1.5 and h2.4)"] = "FountainSplit",
	["fountain top collider, profile > stacks invisible upright cylinders on the silo axis from the eave to the basin floor"] = "FountainSplit",
	["fountain top collider, no holes > loaded: the collision covers the dome, never under the profile, never far over it"] = "FountainSplit",
	["fountain top collider, no holes > loaded: every radius from the axis to the eave edge has a collider top above the wall"] = "FountainSplit",
	["fountain top collider, no holes > states: loaded and loading are never both off or both on"] = "FountainSplit",
	["MeshSwap uniform scale (live boot, every upload answered) > swaps every uploaded MeshAsset slot"] = "FountainSplit",
}

return ForcedFlags
