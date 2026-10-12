## 1.0.0-rc.1

- **The crypt is furnished the same on the web.** `CryptWorld.seedOf`
  multiplies in 16-bit halves, so a JavaScript build no longer rounds the
  hash and seeds other crates and barrels than the VM.
- **The strategy map's halls are lit and broken by what strikes them.** A
  fire arrow is a body loosed at the timber nearest the shooter, and its
  flame is held where the core says it struck timber; a ram's stone breaks
  pieces off a wall where it strikes the wall's stone, not when it comes
  within a distance of the footprint. A shooter looses at a hall within its
  range, with no slack added. Stones and arrows are thrown by the core's
  own flight of them (`Ballistics.aim`) on the arc of the lob they had,
  and a stone weighs the catalogue's granite.
- **Brands are lofted by what a fire burns.** The map's fires loft brands
  through `Firebrands`, a share of the fuel burnt, from the top of the
  flame up the plume and with the wind, as hot as the flame — twigs of the
  catalogue's pine rather than balls of thatch, which burnt out in a step
  — where a die per step threw them before.
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
