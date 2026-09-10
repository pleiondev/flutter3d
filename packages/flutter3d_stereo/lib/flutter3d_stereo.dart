/// Stereo for this engine, and the head that points it.
///
/// **What is here is what is true of both destinations.** A phone in a holder
/// and a headset differ in where the pose comes from, how precise it is, and
/// who owns the surface — and agree on everything else: two cameras a fixed
/// distance apart, two views into one frame, and a set of render settings that
/// a pair can actually have.
///
/// So the package starts at the agreement. [StereoRig] and [StereoSurface] are
/// the whole of it, and neither mentions OpenXR; [SensorHeadTracker] is the
/// phone's answer to [HeadTracker], and a runtime's answer replaces it without
/// either of the other two noticing.
///
/// What is deliberately missing until a headset says otherwise: the swapchain,
/// the frame's timing, and the pose that a compositor predicts rather than a
/// sensor reports. Those are not "the same thing but better" — they change who
/// drives the frame — and guessing their shape before the device has answered
/// is how an interface ends up describing the wrong machine.
library;

export 'src/head_pose.dart';
export 'src/head_tracker.dart';
export 'src/stereo_rig.dart';
export 'src/stereo_surface.dart';
