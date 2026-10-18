## 1.0.0-rc.1

- **Levels made from a seed when they are reached.** `SeededLevels` names a
  level `generated:<seed>` where a level would name its asset, reads the seed
  back with `seedOf`, and makes the document with `level`, off the drawing
  thread. The same seed makes the same level, so a save opens it again and a
  run through them replays.

- **Each level names the next.** The level made from a seed carries `next`
  as the following seed, so a game makes only the levels a player reaches.
  The rules are asked for by depth from the run's first seed, which is how
  they get harder on the way down.

- **From the dungeon demo's depths.** The rules stay the game's: what a room
  holds is its own business, and the dungeon's `Depths` is now its rules
  over this.
