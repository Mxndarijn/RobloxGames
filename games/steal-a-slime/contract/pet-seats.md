# 43. Pet seats: what the follow pet rides on (2026-10-26)

**Status:** live, no feature flag. Approved by Merijn from a mockup (v3, 2026-10-26).

The follow pet (§2 Extras, `FollowPets`) rides a seat the player picks in the Skins menu's **Cloud** tab. The seats are
the 19 models in `shared/modeling-kit` (`models/pet_cloud.py` and `models/pet_mount_<name>.py`, see
`models/PET_MOUNTS.md`).

- **Rule (`src/shared/PetSeats`):** `Config.PET_SEATS` lists the seats (`id`, `name`, `mesh` = MeshAssets name, `seat` =
  seat surface height over the mesh bottom in native studs, `color`, `unlock`). Unlock kinds:
  - `free`: `cloud` ("Fluffy", the plain `pet_cloud`), every player, the default (`Config.PET_SEAT_DEFAULT`).
  - `merges`: `jelly`, once `stats.merges >= 200`.
  - `dex`: `rainbow_cloud`, once 80 % of the SlimeDex is found (`SpeciesDex.count * 100 >= 80 * SpeciesDex.TOTAL`:
    40 of 50; event Secrets don't count).
  - `exclusive`: the other 16 (storm, sunset, ice and flame clouds, leaf, bubble, lily pad, mushroom, pancakes, star
    cushion, crescent moon, magic carpet, UFO, royal cushion, hoverboard, clam shell). Sold in the Exclusive shop,
    which does not exist yet: nobody can unlock one, and the UI never says "Coming soon".
  Ids are permanent save ids.
- **Save (no version bump):** `petSeat: string`. Missing, unknown or not unlocked loads as `"cloud"`
  (`SaveData.cleanPetSeat`, after `found`, `stats` and won bosses are loaded). The unlock is recomputed from the save
  on every load, like plot skins.
- **Remote:** `Request("EquipPetSeat", seatId)` (`string`; rate limit 0.5 s). Refused unless the seat exists and is
  unlocked ("unknown pet seat" / "pet seat is locked").
- **State:** `petSeat: string` (`PetSeats.current`), `petSeats: { { id, name, kind, have, need, unlocked, equipped } }`
  in Config order. `have` / `need` are merges for `merges`, whole SlimeDex percent for `dex`, 0 / 0 otherwise.
- **Player attribute:** `PetSeat` (`Constants.PET_SEAT_ATTRIBUTE`) = `PetSeats.current(data)`, set by `WorldView` next
  to `PetSlimeId`.
- **Templates (server, `MeshSwap.publishPetSeatTemplates`):** one MeshPart per seat whose mesh is in `MeshAssets`,
  in `ReplicatedStorage.PetCloudMeshes`, named by mesh, native size, decor, attribute `SeatHeight` = the seat's
  `seat`. A seat whose mesh is not uploaded has no template.
- **Client (`FollowPets`, `PetCloud`):** the pet rides its owner's seat template; while that is missing, the plain
  cloud; without any template, the invisible Mount. The slime's foot sinks `CLOUD_SINK` into the seat surface
  (`SeatHeight`), so decoration above it (Jelly's cherry, the rainbow arch) does not lift the pet. When the seat or
  the available template changes, the pet is built again where it glides.
- **Menu (`Panels/Skins`, `PetSeatsView`):** the menu is titled "Skins" with two tabs, Base (plot skins, §15) and
  Cloud; every open starts on Base. Cloud: one row per seat with its icon (`PetSeat_<id>`, pictures from
  `shared/modeling-kit/tools/icons/recipes_seat.py`), its name and Equipped / Unlocked; a free unlock shows its line
  ("Merge 200 slimes.", "Complete 80% of the SlimeDex.") with a bar and count; an Exclusive a gold "Exclusive" tag
  and "Only in the Exclusive shop.". The pane repeats it under "How to unlock" / "How to get it" and ends in Equip
  (`EquipPetSeat`), Equipped, what is still missing ("Merge 64 more slimes"), or a gold "Exclusive shop" well.
