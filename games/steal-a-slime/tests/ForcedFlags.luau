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
	["tower theme switch"] = "PlotSkins",
	["AdminEvents gate"] = "AdminEvents",
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
	["ground rays of returning slimes"] = "Parade",
	["ParadeLane: the despawn telegraph stays readable"] = "Parade",
	["ParadeLane in the live server"] = "Parade",
	["Carry.release + Spawner: a dropped wild slime walks back and rejoins the lane"] = "Parade",
	["Carry.replan: a new path swapped into a dropped slime's walk"] = "Parade",
	["Carry.pop: a slime with no way back is on the lane at once"] = "Parade",
	["ParadeLane.walkedRoute: a new route carries on from where it is"] = "Parade",
	["runtime part budget > boots with no server errors and spawns the parade lane and slide colliders"] = "Parade / SlideCollision",
	["FriendBonus math"] = "FriendBonus",
	["Friends.refresh"] = "FriendBonus",
	["a guest in a locked base"] = "FriendsInBase",
	["the lock button's friends prompt > says what pressing it does, and the plot shows the switch"] = "FriendsInBase",
	["friend bonus in income and State"] = "FriendBonus",
	["Weather flag"] = "Weather",
	["Growth curve"] = "GrowingSlimes",
	["Server boosts and small comforts > a Growth snack feeds the aimed slime, else the least grown one; nothing to feed is a credit"] = "GrowingSlimes",
	["Exclusive shop perks and boosts (ExclusiveShopView) > a Growth snack is offered on a growing slime, never on an egg or a grown one"] = "GrowingSlimes",
	["Growth income"] = "GrowingSlimes",
	["Growth offline"] = "GrowingSlimes",
	["Growth percent"] = "GrowingSlimes",
	["welcome-back on join > carries the offline cash and the slimes that grew"] = "GrowingSlimes",
	["Habitats table"] = "Habitats",
	["LiveBoot (server Script in the fake runtime) > with FEATURES.Habitats on, every pad carries a known habitat id and the server builds no looks"] = "Habitats",
	["Ritual.step"] = "CoopRitual",
	["RitualService.step"] = "CoopRitual",
	["SlideColliders specs"] = "SlideCollision",
	["SlideColliders in the live server"] = "SlideCollision",
}

-- Spec modules that assert a flag at load time.
ForcedFlags.offModules = {
	["HabitatsLive.spec"] = "Habitats",
}

-- All flags on: these pin a flag that ships off (ServerProfiler) or the shipped defaults.
ForcedFlags.on = {
	["FeatureOverride > leaves the shipped defaults unchanged under Lune (install is a no-op)"] = "every FeatureOverride flag",
	["Profiler > is off by default and the flag is declared"] = "ServerProfiler",
	["MoveWatch wiring > is off by default and records no allow-window while off"] = "MoveGuardLog",
}

-- Tests that exercise the off path (or pin "default off") of a flag that now ships ON (2026-10-18:
-- switch on every built feature). They only make sense with that flag off, so they run in the
-- all-flags-off mode alone and are skipped in the default and the all-on runs (and in the cloud tests).
ForcedFlags.needOff = {
	["Income.step"] = "CashPads (income goes straight to cash only with the cash pads off)",
	["Income.applyOffline"] = "CashPads (income goes straight to cash only with the cash pads off)",
	["friend bonus in income and State > Income.step pays the bonus"] = "CashPads (income goes straight to cash only with the cash pads off)",
	["GameLoop end to end > income resumes after the clock steps back"] = "CashPads (income goes straight to cash only with the cash pads off)",
	["MergeVat: a brewing vat locks its slimes > while brewing they earn nothing, live or offline"] = "CashPads (income goes straight to cash only with the cash pads off)",
	["Upgrades (BuyUpgrade) > Strong Arms shrinks the carry slowdown, Night Shift extends the offline cap"] = "CashPads (income goes straight to cash only with the cash pads off)",
	["RitualService.step > pays Blessed income through Income.step"] = "CashPads (income goes straight to cash only with the cash pads off)",
	["TestHooks > grants cash (not counted as earned) and skips time with income"] = "CashPads (income goes straight to cash only with the cash pads off)",
	["Weekend income > Income.step doubles pay on a weekend and not otherwise or without a clock"] = "CashPads (income goes straight to cash only with the cash pads off)",
	["FountainTiers: server > the world starts at tier 1 and the tier step is a no-op with the feature off"] = "FountainTiers",
	["FountainTiers: server > a spawned drop is Classic with the feature off even at tier 4"] = "FountainTiers",
	["plot skins: equip > the Request refuses a locked skin, and equips an unlocked one"] = "PlotSkins",
	["plot skins: equip > with the flag off the Request is refused, even for an unlocked skin"] = "PlotSkins",
	["plot skins: equip > flag off: State carries no plot skin fields"] = "PlotSkins",
	["plot bases: unlock and equip > with the flag off the Request is refused and State carries no base fields"] = "BaseShapes",
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
	["MeshSwap uniform scale (live boot, every upload answered) > swaps every uploaded MeshAsset slot"] = "FountainSplit",
}

return ForcedFlags
