import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:vector_math/vector_math.dart';

/// The shooter's world: the standard one, falling at 24 m/s².
///
/// **The genre's tuning, said once.** Its player and its monsters fell at 24
/// m/s² — `MovementSettings`' old default — while its loose bodies fell at the
/// dynamics' own 22 and its sparks at 9.81; one gravity per game now
/// (decision 1 of `tasks/1.0-physics-audit.md`), and it is the one the
/// characters always had, so a run feels as it did. The game stages every
/// level in it, with the level's own world laid over it (`Level.worldOver`).
final WorldProperties shooterWorld = WorldProperties(
  gravity: Vector3(0.0, -shooterGravity, 0.0),
);

/// How hard the shooter's world pulls, m/s²: 2.4 g, snappy as the genre's
/// jumps are meant to be.
const double shooterGravity = 24.0;
