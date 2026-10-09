/// Virtual cameras for flutter3d games: many cameras a game could look
/// through, one shown at a time, and the view moving between them.
///
/// A [VirtualCamera] is a [CameraFraming] — where it wants to be — carried out
/// by the engine's `CameraRig`, which eases, knocks and keeps it out of the
/// walls. A [CameraDirector] picks the live camera by priority, blends to the
/// next by a [CameraBlend] (a cut, an ease, a curve of the game's own), keeps
/// the blend out of the walls and shakes the result with [ImpulseShake]'s
/// decaying noise, seeded by the step. [CameraPlugin] runs it in the loop's
/// frame phase `camera` and shakes it from events on the bus.
///
/// The framings: [FollowFraming] and [LookAtFraming] with dead zones and
/// damping, [GroupFraming] for several subjects at once, and the presets the
/// engine's games were built from — [ChaseFraming], [OrbitFraming],
/// [OverheadFraming] and [FirstPersonFraming].
library;

export 'src/blend.dart';
export 'src/camera_rig.dart';
export 'src/director.dart';
export 'src/framing.dart';
export 'src/photo_camera.dart';
export 'src/plugin.dart';
export 'src/presets.dart';
export 'src/rig_tuning.dart';
export 'src/shake.dart';
export 'src/shot.dart';
export 'src/virtual_camera.dart';
