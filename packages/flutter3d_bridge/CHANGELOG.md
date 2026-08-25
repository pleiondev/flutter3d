## 0.3.0

* `ActorVisuals` decides an animation's wrap and a model's yaw, so a death
  animation stops looping and a monster faces the way it moves.

## 0.2.0

* View models for a weapon held in the hands, and particle effects driven by
  what the simulation reported rather than by what it looks like.
* An actor is placed by its feet, which is how the level document means it.

## 0.1.0

* The binding between the two halves: level geometry to mesh nodes, actors to
  visuals, fixtures to the lights they drive.
* The one package allowed to know both `flutter3d` and `flutter3d_game`.
