# flutter3d_demo_content

What this repository's demo games are made of, kept out of the engine's
published API. Not on pub.dev (`publish_to: none`).

| Library | What it holds | Used by |
|---|---|---|
| `shooter_sample.dart` | The shooter's roster: `Monsters`, `Weapons`, `sampleGifts`, `sampleRegistry`, `sampleRules`, `sampleArsenal`, `stageRoutes`, `followBreaches` | the dungeon, the shooter's tests, the editor's tests |
| `shooter_staging.dart` | `stage()` and `Staged`, the one assembly of a shooter run; `startingInventory`, `shooterDynamics`, `ShooterHeadlessGame` | the dungeon, `flutter3d_sim_mcp`'s tests |
| `crypt.dart` | The crypt's fire, water and loose wood on the physics core: `CryptWorld`, `CryptTorch`, `FloodPlan`, `WoodKind` and the rest | the dungeon, `shooter_staging.dart` |
| `map_world.dart` | The strategy map's pond, river, fires and siege stones: `MapWorld` | the strategy demo |

Until 1.0 these lived inside `flutter3d_game_shooter` and
`flutter3d_game_strategy`, which made one game's monsters part of the genre's
public API and gave both genres a hard dependency on the native physics core.

A published package may take this only as a `dev_dependency`. A game of your
own copies what it wants from here rather than depending on it.
