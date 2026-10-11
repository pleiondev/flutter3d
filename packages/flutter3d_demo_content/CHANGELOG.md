## 1.0.0-rc.1

- **The crypt burns its player by the heat on them in the field.**
  `CryptWorld.heatOnPlayer` reads the radiant heat on the body that stands
  in for the player in the crypt's world (`ElementFields.radiantFluxOn`),
  so the walls and the wood between shade them as the world has them;
  `CryptHarm.flux`, the crypt's own copy of the law, is gone.
- **The demo games' content, out of the published packages.** The shooter's
  roster, crypt and staging (from `flutter3d_game_shooter`'s `sample.dart`,
  `crypt.dart` and `staging.dart`), the strategy map's world (from
  `flutter3d_game_strategy`'s `map_world.dart`) and the repository's hygiene
  checks (`soundTableIn`, `creditGaps`) live here, unpublished.
