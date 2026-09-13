/// The dungeon's own assembly of a level into a run.
///
/// **It lives in `package:flutter3d_game_shooter/staging.dart` now**, so a
/// package can reach it — the agent's sim server kept a copy of its own while
/// it could not. Exported here so everything in this application that already
/// imports this file keeps doing so.
library;

export 'package:flutter3d_game_shooter/staging.dart'
    show Staged, stage, startingInventory;
