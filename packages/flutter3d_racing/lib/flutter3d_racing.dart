/// A third genre: driving, and the lap that comes of it.
///
/// The shape of this package is the one the other two genres settled into. It
/// holds a simulation and nothing that draws — no `flutter3d`, no `flutter_gpu`
/// — because the things that go wrong in a racing game go wrong invisibly. A
/// car that understeers differently at a lower frame rate, a lap that counts
/// twice because the finish line was crossed twice in one step, a driving line
/// an AI cuts through a barrier, a position table that disagrees with itself on
/// a track that crosses over itself: none of those appear in a screenshot, and
/// all of them are reachable from a plain test.
///
/// What is genuinely new here, and the reason this is not a platformer with a
/// faster runner, is that the ground stops being geometry. A track is a
/// measured curve with a width and a camber, and the surface under a car is
/// worked out from it rather than swept against — see [TrackSpline]. Everything
/// that is really an object stays in the collision world as before.
library;

export 'src/ai/ai_driver.dart';
export 'src/chase_camera.dart';
export 'src/ghost.dart';
export 'src/layers.dart';
export 'src/race_state.dart';
export 'src/simulation.dart';
export 'src/sky.dart';
export 'src/track.dart';
export 'src/track_field.dart';
export 'src/track_reader.dart';
export 'src/vehicle/sphere_vehicle.dart';
export 'src/vehicle/tire_model.dart';
export 'src/vehicle/vehicle_controller.dart';
