--!strict
-- About how many seconds each slow spec takes (loading it plus running its tests), so tests/Shard can
-- spread them over the parallel shards. Only specs over a second are listed; the rest count as
-- `default`. Measured 2026-11-01 on a dev PC (16 shards); CI runners are 1.2-1.5x slower. Refresh after adding a slow spec:
--   SPEC_TIMINGS=1 lune run scripts/test-parallel        (prints TIME <seconds> <spec> per spec)
-- Stale numbers only make the shards less even; they never skip a spec.
local SpecWeights = {}

SpecWeights.default = 0.10

SpecWeights.seconds = {
	["GroundParamsLive.spec"] = 78.1,
	["MeshPrefetch.spec"] = 49.8,
	["SlideColliders.spec"] = 37.2,
	["ParadeLane.spec"] = 34.0,
	["RuntimeParts.spec"] = 25.0,
	["FountainSplit.spec"] = 18.7,
	["FountainRide.spec"] = 16.9,
	["PlotPadPurchaseWorld.spec"] = 14.8,
	["PropCollision.spec"] = 11.8,
	["LiveBoot.spec"] = 11.0,
	["Pacing.spec"] = 9.4,
	["ThemeSwitchLive.spec"] = 8.8,
	["FountainCollider.spec"] = 7.7,
	["WorldShopsWorld.spec"] = 7.1,
	["ExclusiveClawWorld.spec"] = 4.8,
	["HabitatsLive.spec"] = 4.8,
	["PadSlimeJoin.spec"] = 4.6,
	["MeshCollision.spec"] = 4.5,
	["WorldBorder.spec"] = 4.5,
	["DropHatchLive.spec"] = 4.5,
	["RequestRefresh.spec"] = 4.2,
	["SecretTier.spec"] = 3.3,
	["SlideWalk.spec"] = 3.3,
	["HatchPromptLive.spec"] = 3.3,
	["VatMesh.spec"] = 3.1,
	["MeshFit.spec"] = 2.8,
	["LeaveSave.spec"] = 2.7,
	["PropMesh.spec"] = 2.6,
	["ParadeChoreo.spec"] = 2.4,
	["ui/ExclusiveShop.spec"] = 2.3,
	["FeatureFlags.spec"] = 2.3,
	["ConsumableStacks.spec"] = 1.8,
	["BaseShapes.spec"] = 1.8,
	["Consumables.spec"] = 1.8,
	["AdminService.spec"] = 1.8,
	["Actions.spec"] = 1.7,
	["DropTube.spec"] = 1.6,
	["ShotTargets.spec"] = 1.5,
	["BossEvent.spec"] = 1.5,
	["ConsumablesHardening.spec"] = 1.5,
	["Codes.spec"] = 1.5,
	["AdminEvents.spec"] = 1.5,
	["EventSecrets.spec"] = 1.3,
	["BatTool.spec"] = 1.3,
	["Badges.spec"] = 1.3,
	["BossEventAttacks.spec"] = 1.2,
	["DespawnTelegraph.spec"] = 1.1,
	["BorderTerrain.spec"] = 1.1,
	["JarTower.spec"] = 1.1,
} :: { [string]: number }

return SpecWeights
