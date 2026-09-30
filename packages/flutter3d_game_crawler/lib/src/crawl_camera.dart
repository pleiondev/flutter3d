/// The camera over a crawl: it eases towards the framing the heroes need.
///
/// **It decides nothing.** Where the view has to be is [CrawlFraming]'s, which
/// the simulation keeps because the edge of the view is a rule about where a
/// hero may walk. This is only the drawing half: it turns a [CameraRig] towards
/// that framing, so the view glides rather than jumps when somebody runs
/// ahead, and a blast can still shake it.
///
/// The rig is handed an empty world, as the strategy's map camera does: from
/// straight above a maze there is no wall to be pulled out of, and a camera
/// that dived towards the heroes whenever a wall stood between it and them
/// would be doing it all the time.
library;

import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'framing.dart';

final class CrawlCamera {
  CrawlCamera({this.lag = 4.0}) : rig = CameraRig(world: CollisionWorld());

  /// How much of the gap the rig closes in a second.
  final double lag;

  /// The smoothing, the impulses and the first-frame cut.
  final CameraRig rig;

  final Vector3 _eye = Vector3.zero();
  final Vector3 _target = Vector3.zero();

  /// Where the camera is this frame.
  Vector3 get eye => rig.eye;

  /// What it looks at.
  Vector3 get target => rig.target;

  /// Moves towards what [framing] asks for. Call once a frame, after the step.
  void follow(CrawlFraming framing, double dt) {
    if (!framing.isFramed) return;
    framing.view(_eye, _target);
    rig.place(desiredEye: _eye, desiredTarget: _target, lag: lag, dt: dt);
  }
}
