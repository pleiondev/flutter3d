## 1.0.0-rc.1

- **Actors that fall as bodies when they die.** `RagdollCorpses` is an
  `ActorCorpses`: handed to `ActorVisuals`, it takes a dead actor's skeleton
  over and lets it fall in the physics core against the level and the
  actors still standing. A rig the ragdoll profile does not name keeps its
  death clip.

- **Pushed away from the blow.** `pushedFrom` says where the killing blow
  came from, and the chest is thrown away from there, level and a little up.
  The push, the body it lands on and the body's mass are a game's to set.

- **Display, not simulation.** The bodies step on the frame, in fixed
  sixtieths of their own and at most four a frame, and are in no save or
  replay: nothing in a step asks where a body lies.

- **From the dungeon demo**, which now hands it the player's position as
  where each blow came from.
