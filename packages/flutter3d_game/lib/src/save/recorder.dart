import 'package:vector_math/vector_math.dart';

import 'pose.dart';
import 'tape.dart';

/// Writes down where something was, a few times a second.
///
/// Fifteen a second rather than every step, and the reason is the file: what a
/// replay is looked at is a shape moving in the distance, and the difference
/// between a sample every sixtieth of a second and every fifteenth is invisible
/// once the gaps are interpolated — while the file is a quarter of the size.
final class Recorder {
  Recorder({this.hz = 15.0});

  final double hz;

  final List<Pose> _poses = <Pose>[];
  double _nextAt = 0.0;

  int get length => _poses.length;

  /// Records a place at [time], if enough time has passed since the last one.
  ///
  /// Called every step and mostly does nothing, which is the point: the caller
  /// does not have to know the rate, so changing it changes one number here
  /// rather than a condition at every call site.
  void tick(
    double time, {
    required Vector3 position,
    required double yaw,
    Vector3? up,
  }) {
    if (_poses.isNotEmpty && time < _nextAt) return;

    final pose = Pose(time: time, yaw: yaw)..position.setFrom(position);
    if (up != null) pose.up.setFrom(up);

    _poses.add(pose);
    _nextAt = time + 1.0 / hz;
  }

  /// Ends the recording and hands over what was recorded.
  Tape finish(double seconds) =>
      Tape(poses: List<Pose>.of(_poses), seconds: seconds);

  /// Throws the recording away and starts again.
  void reset() {
    _poses.clear();
    _nextAt = 0.0;
  }
}
