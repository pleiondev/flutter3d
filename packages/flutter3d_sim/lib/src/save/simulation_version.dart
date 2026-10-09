import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show Flutter3dFormatException;

import 'pose_record.dart';

/// Thrown when a run's tape of intents will not be replayed here, with the
/// sentence that says why and what can be shown instead.
///
/// **An honest refusal, not a failure.** A tape from another simulation
/// replayed anyway would reach the first checkpoint, part from it, and be
/// reported as a bug in the simulation that played it. [poses] is the record
/// written beside the tape, which plays on any build: a viewer draws that.
final class ReplayException extends Flutter3dFormatException {
  const ReplayException(this.reason, {this.poses});

  final String reason;

  /// The run's pose record, or null for a run written without one.
  final PoseRecord? poses;

  /// The reason, and what is left to show.
  @override
  String get message => poses == null
      ? '$reason; the run has no pose record to show instead'
      : '$reason; its pose record plays instead';

  @override
  String toString() => 'ReplayException: $message';
}

/// Thrown when a run names a simulation that is not one.
final class SimulationVersionFormatException extends Flutter3dFormatException {
  const SimulationVersionFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'SimulationVersionFormatException: $message';
}
