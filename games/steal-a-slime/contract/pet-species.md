# 53. Pet species: the slime on the follow pet's cloud (2026-11-01)

**Status:** live, no feature flag. Proposal `docs/pet-from-dex-proposal.html` (Merijn, 2026-11-01: "build the rest").

The follow pet (§2 Extras, `FollowPets`) is Auto by default: the favourite slime, else the best owned slime
(`World.pet`). A player can instead pick any slime they have found in the SlimeDex. The pick is looks only.

- **Rule (`src/shared/PetSpecies`):** a species can be picked when it is a `SlimeRoster` species with its own kit mesh
  (`KitRequest.kitOf(id) ~= nil`) and `data.found[id]` is true (Dex entries and bonus entries alike). Refusals:
  `"unknown slime"` (not a string, longer than 32, not in the roster, or no kit) and `"slime not found yet"`.
  `PetSpecies.current(data)` returns the pick only while it is still allowed, else nil (Auto).
- **Cosmetic:** the pet perk (`Perks.petPassive`, [follow-pet-passives.md](follow-pet-passives.md)) stays on the
  favourite owned slime. A thief carrying the favourite does not hide a picked pet (it is not a slime on the plot).
- **Save (no version bump):** `petSpecies: string?`, written only while allowed (`PetSpecies.current`). On load it is
  read after `found`; missing, junk, unknown, kit-less or not found loads as nil (`PetSpecies.clean`).
- **Remote:** `Request("SetPetSpecies", id)`, argument kind `"cosmetic"` (`""` = Auto, else an id); rate limit 0.5 s.
  Refused with the rule's reasons. On success the player gets a toast `Pet: <species name>` or `Pet: Auto`.
- **State:** `petSpecies: string?` (`PetSpecies.current`); nil = Auto. The menu reads `State.dex` for what is found.
- **Player attribute:** `PetSpecies` (`Constants.PET_SPECIES_ATTRIBUTE`) = `PetSpecies.current(data)`, set by
  `WorldView.updatePlayer` next to `PetSlimeId` and `PetSeat`. `PetSlimeId` keeps its meaning (Auto's slime, may be
  nil); the client shows the picked species whenever `PetSpecies` is set, even when `PetSlimeId` is nil.
- **Kit delivery:** every client draws every player's pet, so while a player has a pick, `WorldView.updatePlayer`
  asks `KitDelivery.request` for that species' kit for every player in the server each tick. KitDelivery sends a
  kit to a player once (a kit still loading goes out when it arrives; a failed kit never does), so a player who
  joins later gets it on the next tick. Kits land in the receiving player's `PlayerGui[Constants.SLIME_KITS_FOLDER]`
  as `slime_<id>`, like the SlimeDex previews.
