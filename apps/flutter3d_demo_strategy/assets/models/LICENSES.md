# Models

## `worker.glb` — "Blocky Characters", character A

| | |
|---|---|
| Author | Kenney — https://kenney.nl |
| Source | Blocky Characters — https://kenney.nl/assets/blocky-characters |
| Licence | **CC0 1.0** — http://creativecommons.org/publicdomain/zero/1.0/ |

CC0 asks for nothing, so this table is a note to ourselves rather than a
condition being met.

**Modified in three ways**, all by `tool/prepare_models.py`:

* the six rigid parts — head, torso, two arms, two legs, each a child of an
  armature bone — are joined into one mesh. A crowd unit is drawn through
  `InstancedMeshNode`, which shares one mesh across every instance and cannot
  share six;
* the twenty-seven clips that animated those bones are dropped with them —
  a crowd of a hundred does not carry a hundred independent clip players, and
  the six parts still read as recognisably a person standing in the rig's
  rest pose;
* the joined mesh is scaled and repositioned so it stands on its own feet at
  its local origin, 1.2 m tall — `UnitSize.height` in
  `packages/flutter3d_game_strategy/lib/bridge.dart`. Scaled by height alone,
  the same call the platformer's own script makes for its runner: a rest
  pose's width is however far it happens to hold its arms, and only the
  height is a measurement worth matching to anything.

## `hall.glb` — "Castle Kit", `tower-square`

| | |
|---|---|
| Author | Kenney — https://kenney.nl |
| Source | Castle Kit — https://kenney.nl/assets/castle-kit |
| Licence | **CC0 1.0** — http://creativecommons.org/publicdomain/zero/1.0/ |

One of the kit's own complete towers, already a single mesh at the identity
transform — nothing about its geometry needed changing.

**Modified in one way: the texture is now inside the file.** The kit ships
`Textures/colormap.png` as a sibling PNG, which a bundle resolves nothing
relative to, so every hall arrived untextured. The PNG is appended as a
buffer view and the image points at it instead, the same fix `car.glb` and
the racing game's own buildings needed.

A hall's footprint comes from the level document rather than from this file:
`packages/flutter3d_game_strategy/lib/bridge.dart` uploads this mesh once and
stretches a copy of it to each building's authored width and depth with
`SceneNode.setScale`, so the model on disk stays at whatever size Castle Kit
authored it.
