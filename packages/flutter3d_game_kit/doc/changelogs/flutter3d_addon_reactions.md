## 1.0.0-rc.1

- **Breaking: `ReactionsPlugin.take` is `drain`**, the verb for a read that
  empties what it reads.
- **A reaction a game can grow.** `ReactionEffect` is an open base for what
  `Reaction` has no field for — slow motion, a rumble, a flare — added by a
  rule with `ReactionBuilder.add`, read from `Reaction.effects` and done by
  `Reaction.perform`. A sixth kind of effect no longer needs this package.

- **What an event looks and feels like, as a decision.** `Reaction` holds
  bursts, lingering plumes, camera jolts, sounds, haptic pulses and whether
  the screen flashes, so a test can assert what a step showed without a
  device. `showIn` and `feel` perform it on a particle system and a camera
  rig.

- **Keyed by event type.** `ReactionTable` runs a game's rules over its
  events in the order they happened, and `ReactionsPlugin` hears it from the
  engine's bus on the frame channel, as a view plugin on plugin API 1.0. A
  step a rollback ran again is not shown twice.

- **The camera's three verbs and the flash.** `Felt` describes a kick, a
  shake or a widening, applied to a `CameraRig`, whose motion setting
  still decides how much. `ScreenFlash` fades by the step and is fired at
  the player's own brightness, so a flash on every hit stays the player's
  choice.

- **Out of three games.** The dungeon, the platformer and racing each had a
  `Reaction` of their own. They use this one now, and keep only the part
  that says which of their events shows what.
