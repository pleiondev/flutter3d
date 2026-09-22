/// The turntable a drag, a pinch or a wheel notch drives — a [Cubit] rather
/// than a `setState` field on [LessonView] itself, so the camera pose is
/// owned the same way `LessonCubit` already owns everything else this
/// screen shows, instead of being the one piece of state left in a bare
/// `StatefulWidget`.
///
/// **Emits a value, not the controller itself.** `Cubit.emit` skips a state
/// that equals the one already held, and a live [OrbitController] mutated in
/// place is always `==` to itself (identity), so emitting it a second time
/// after mutating it would notify nobody. Each call therefore reads the
/// controller's own numbers into a fresh, comparable [OrbitPose] — the
/// [OrbitController] stays the single source of truth for where the camera
/// actually is; [OrbitPose] exists only so `Cubit` has something to compare.
library;

import 'dart:math' as math;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_sim/flutter3d_sim.dart' show EntityDef;
import 'package:flutter_bloc/flutter_bloc.dart';

import 'lesson_player.dart';

/// A snapshot of [OrbitController]'s own numbers.
final class OrbitPose {
  const OrbitPose({
    required this.distance,
    required this.yaw,
    required this.pitch,
  });

  final double distance;
  final double yaw;
  final double pitch;

  @override
  bool operator ==(Object other) =>
      other is OrbitPose &&
      other.distance == distance &&
      other.yaw == yaw &&
      other.pitch == pitch;

  @override
  int get hashCode => Object.hash(distance, yaw, pitch);
}

/// Owns one [OrbitController] for a [LessonView]'s whole lifetime and emits
/// after every mutation, so a `BlocBuilder` around the scene surface knows
/// to ask `SceneSurface` for a fresh frame.
class OrbitCubit extends Cubit<OrbitPose> {
  OrbitCubit(this.orbit) : super(_poseOf(orbit));

  /// The live turntable. Held rather than rebuilt each time so [rotate]/
  /// [pan]/[zoom] keep acting on the same node they were constructed for.
  final OrbitController orbit;

  static OrbitPose _poseOf(OrbitController o) =>
      OrbitPose(distance: o.distance, yaw: o.yaw, pitch: o.pitch);

  void _sync() => emit(_poseOf(orbit));

  void rotate(double dx, double dy) {
    orbit.rotate(dx, dy);
    _sync();
  }

  void pan(double dx, double dy, {required double viewportHeight}) {
    orbit.pan(dx, dy, viewportHeight: viewportHeight);
    _sync();
  }

  void zoom(double factor) {
    orbit.zoom(factor);
    _sync();
  }

  /// Places [step] exactly where `edu-00` says it stands
  /// (`applyLessonStepToCamera`, unchanged), then rebuilds the turntable
  /// around the resulting position — the origin is the assumed subject, the
  /// same convention the shipped tour's own pedestal already stands on —
  /// so a drag afterward orbits from where the step actually landed rather
  /// than from stale numbers.
  void resetFromStep(
    EntityDef? step, {
    Map<String, SceneNode> nodes = const <String, SceneNode>{},
  }) {
    if (step != null) {
      applyLessonStepToCamera(orbit.node, step, nodes: nodes);
    }
    final at = orbit.node.readPosition();
    final distance = math.max(at.length, 0.05);
    orbit
      ..distance = distance
      ..yaw = math.atan2(at.x, at.z)
      ..pitch = math.asin((at.y / distance).clamp(-1.0, 1.0))
      ..apply();
    _sync();
  }
}
