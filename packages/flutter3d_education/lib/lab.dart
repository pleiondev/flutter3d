/// Virtual laboratory simulations — `edu-04`'s own worked example
/// ([PendulumSimulation]) is the first, not the only one this package is
/// named for.
///
/// **Not `flutter3d_sim`.** A lab experiment is domain content built on top
/// of `flutter3d_sim`'s stepping and recording primitives
/// ([DigestTrace], [DataSourceTrace], [Demo]), the same relationship a genre
/// package (`flutter3d_game_shooter` and its siblings) already has with the
/// engine underneath it — one more phenomenon to simulate is not one more
/// thing `flutter3d_sim` itself needs to know how to do. Plain Dart, same
/// reason `flutter3d_sim` is: a server replays a lab run through it, in a
/// container with no Flutter SDK in it.
library;

// The recording primitives a lab run is read through, so a lab's code
// names them with this import and not `flutter3d_sim`'s.
export 'package:flutter3d_sim/flutter3d_sim.dart'
    show DataSourceTrace, Demo, DigestTrace, Divergence;
export 'src/lab/lab_review.dart';
export 'src/lab/pendulum.dart';
export 'src/lab/pendulum_lab_run.dart';
