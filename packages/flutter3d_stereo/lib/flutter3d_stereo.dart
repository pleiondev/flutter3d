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
/// **Rebased on the XR session since 1.0.** What this package once left out
/// until a headset said otherwise — the swapchain, the frame's timing, the
/// pose a compositor predicts rather than a sensor reports — is now
/// `XrSession`'s, in `flutter3d_app`, and a phone in a holder is one more
/// runtime behind it: [HolderXrSession] makes inline frames from a
/// [HeadTracker] and a holder's lenses, and `StereoRig.applyFrame` takes a
/// rig's eyes from any runtime's frame, a headset's or a holder's.
library;

export 'src/head_pose.dart';
export 'src/head_tracker.dart';
export 'src/lesson_player.dart';
export 'src/lesson_stereo_view.dart';
export 'src/stereo_rig.dart';
export 'src/stereo_session.dart';
export 'src/stereo_surface.dart';
export 'src/stereo_viewer.dart';
