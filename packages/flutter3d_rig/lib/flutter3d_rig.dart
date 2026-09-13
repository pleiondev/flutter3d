/// Bone-name mapping and rest-relative clip retargeting between two
/// skeletons, with a two-bone-IK foot lock — `anim-17`'s own row, the first
/// piece of `flutter3d_rig` — and automatic skin weights.
///
/// **The algorithms, reading a rig as nodes and tracks.** Nothing here knows
/// what a modeller's project is: `flutter3d_model_core` adapts its own
/// skeletons and clips to [RetargetRig] and [RigTrack], and runs these
/// through its rig jobs. A dependency the other way would put a modeller's
/// whole document — cloth, physics and particles with it — under anything
/// that only wanted to retarget a clip.
library;

export 'src/bind_weights.dart';
export 'src/bone_map.dart';
export 'src/retarget.dart';
export 'src/two_bone_ik.dart';
