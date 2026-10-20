# 15. Gaps #15: plot skins unlocked by collection (2026-10-16, Archer)

**Status:** contract first. `Config.FEATURES.PlotSkins` (default **on** since 2026-10-18); `false` = no remote, no State fields, no plot attribute, no visuals. The save field is still read and written.

- **Rule:** `Config.PLOT_SKINS` lists the skins; each is tied to a SlimeDex set (`set` = rarity tier: that tier's species Dex entries, `PlotSkins.setSize(tier)`, §36.3) and unlocks at `owned / setSize >= threshold` (0.75, integer test `owned >= ceil(setSize * threshold)`). `classic` is the default and always unlocked. `src/shared/PlotSkins`.
- **Save (versioned since v6, §8.9c):** `plotSkin: string`. Missing, unknown or not unlocked loads as `"classic"` (`SaveData.deserialize`; `SaveData.migratePlotSkin` is the pure step; `migrateV5` normalises unknown ids).
- **Remote:** `Request("EquipPlotSkin", skinId)` (`string`; rate limit 0.5 s). Refused unless the skin exists and is unlocked, or when the flag is off. Equipping `classic` always works.
- **State (flag on only):** `plotSkin: string`, `plotSkins: { { id, name, setName, tier, owned, total, needed, fraction, unlocked, equipped } }` (classic first).
- **Plot attribute (flag on only):** `Plot_<i>.PlotSkin = <id>` ("classic" for a free plot). Clients paint from it.
- **Visuals (client, `PlotDecor.applySkin`):** floor `Base` colour + material, the jar's cork and trim tint (`trim`: the bridge, jar floor, parked stopper and lids), and the skin's decor mesh stands in for the plot's `Mailbox_<i>` slot. **No new mesh slots:** the decor meshes are templates in `ReplicatedStorage.PlotSkinMeshes` (server-published), not world slots. `WorldLayout.build` is unchanged.
- **Studio-only debug:** SlimeUI attribute `PcwPlotSkin` (skin id) forces Plot_1's skin and the picker view for shots.
