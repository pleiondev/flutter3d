import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// Something about the loop that changed during a run, at a step boundary,
/// and was written down so a replay changes it at the same step.
///
/// Three kinds: the time scale, the world's step rate, and the plugins.
/// [affectsSimulation] separates what a replay must make to arrive where the
/// run did — a step rate, a simulation plugin switched — from what only
/// paces or decorates it — the time scale, a view plugin.
///
/// **Not sealed**: a later minor may journal a new kind of change, so a
/// `switch` over these needs a default. The constructor is private, so the
/// kinds are this library's.
abstract base class LoopChange {
  const LoopChange._();

  /// The boundary it was made at: after [step] steps had run.
  int get step;

  bool get affectsSimulation;

  /// The same change at another step.
  LoopChange at(int step);

  Map<String, Object?> toJson();

  /// Reads a change back, or throws a [LoopChangeFormatException] saying why not.
  static LoopChange fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw LoopChangeFormatException('a loop change is not a document');
    }
    final step = json['step'];
    if (step is! int || step < 0) {
      throw LoopChangeFormatException('a loop change names no step');
    }
    return switch (json['kind']) {
      'timeScale' => switch (json['scale']) {
        final num scale when scale >= 0 => LoopTimeScale(
          step: step,
          scale: scale.toDouble(),
        ),
        _ => throw LoopChangeFormatException(
          'a time scale is a number, nought or more',
        ),
      },
      'stepRate' => switch (json['rate']) {
        final num rate when rate > 0 => LoopStepRate(
          step: step,
          rate: rate.toDouble(),
        ),
        _ => throw LoopChangeFormatException(
          'a step rate is a positive number',
        ),
      },
      'plugin' => switch (json['change']) {
        final Map<String, Object?> change => LoopPluginChange(
          PluginChange.fromJson(change),
        ),
        _ => throw LoopChangeFormatException(
          'a plugin change has no change in it',
        ),
      },
      final kind => throw LoopChangeFormatException(
        'a loop change of kind "$kind" is not one this build knows',
      ),
    };
  }
}

/// The time scale became [scale] at [step].
///
/// **Paces the run and nothing else.** `dt` is the same at any scale — the
/// loop runs more or fewer steps a second — so a replay arrives at the same
/// state whatever it does with this, and a replay that wants to look the
/// same slows down where the run did.
final class LoopTimeScale extends LoopChange {
  const LoopTimeScale({required this.step, required this.scale}) : super._();

  @override
  final int step;

  /// Simulated seconds per wall-clock second: a unitless multiplier.
  final double scale;

  @override
  bool get affectsSimulation => false;

  @override
  LoopTimeScale at(int step) => LoopTimeScale(step: step, scale: scale);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'timeScale',
    'step': step,
    'scale': scale,
  };

  @override
  bool operator ==(Object other) =>
      other is LoopTimeScale && other.step == step && other.scale == scale;

  @override
  int get hashCode => Object.hash(step, scale);

  @override
  String toString() => 'time scale $scale at step $step';
}

/// The world's step rate became [rate] at [step].
final class LoopStepRate extends LoopChange {
  const LoopStepRate({required this.step, required this.rate}) : super._();

  @override
  final int step;

  /// Steps per second of simulated time, in hertz, as
  /// `WorldTiming.stepRate`.
  final double rate;

  @override
  bool get affectsSimulation => true;

  @override
  LoopStepRate at(int step) => LoopStepRate(step: step, rate: rate);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'stepRate',
    'step': step,
    'rate': rate,
  };

  @override
  bool operator ==(Object other) =>
      other is LoopStepRate && other.step == step && other.rate == rate;

  @override
  int get hashCode => Object.hash(step, rate);

  @override
  String toString() => 'step rate ${rate}Hz at step $step';
}

/// A plugin was switched or the plugins reordered: [change].
final class LoopPluginChange extends LoopChange {
  const LoopPluginChange(this.change) : super._();

  final PluginChange change;

  @override
  int get step => change.step;

  @override
  bool get affectsSimulation => change.affectsSimulation;

  @override
  LoopPluginChange at(int step) => LoopPluginChange(change.at(step));

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'kind': 'plugin',
    'step': step,
    'change': change.toJson(),
  };

  @override
  String toString() => change.toString();
}

/// Thrown when a recorded loop change cannot be read.
final class LoopChangeFormatException extends Flutter3dFormatException {
  const LoopChangeFormatException(this.message);

  @override
  final String message;

  @override
  String toString() => 'LoopChangeFormatException: $message';
}
