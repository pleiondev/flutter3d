/// What a simulation promises about its numbers: [SimulationProfile].
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show DocumentFormatException;

/// What a simulation promises about its numbers, and so what may be done
/// with a run of it.
///
/// **Two profiles in 1.0, and the set is open.**
/// * [deterministic]: the engine's `Portable` maths, float-compatible, so
///   the same tape gives the same bits on every platform. Rollback across
///   machines, a server that verifies a run by replaying it, and one
///   `SimulationVersion` per release rest on it. A game is played on it, and
///   so is a laboratory a server checks by replay.
/// * [accurate]: double precision and adaptive integrators inside the
///   fixed step, held to analytic tests rather than to bits. A laboratory or
///   a twin that demonstrates is run on it, and ships poses instead of a
///   tape to replay.
///
/// **Ask a capability, never which profile it is.** A later release, or an
/// outside package, may add a profile (`SimulationProfile('reference', …)`
/// is a value like these two), so code that decides something checks
/// [isBitExact], [usesDoublePrecision] or [allowsAdaptiveSteps]. The
/// determinism rule in this repository asks [isBitExact], not
/// `== deterministic`.
///
/// **Written by its [name]**, which is set here and never taken from a Dart
/// identifier: a file or a hello that carries the profile carries that word.
final class SimulationProfile {
  /// A profile called [name] with these capabilities. Two profiles are equal
  /// when their names and capabilities are.
  const SimulationProfile(
    this.name, {
    required this.isBitExact,
    required this.usesDoublePrecision,
    required this.allowsAdaptiveSteps,
  });

  /// Portable maths, the same bits on every platform: rollback, replay and
  /// verification by replay.
  static const SimulationProfile deterministic = SimulationProfile(
    'deterministic',
    isBitExact: true,
    usesDoublePrecision: false,
    allowsAdaptiveSteps: false,
  );

  /// Double precision and adaptive integrators, held to analytic tests: no
  /// promise about bits across platforms.
  static const SimulationProfile accurate = SimulationProfile(
    'accurate',
    isBitExact: false,
    usesDoublePrecision: true,
    allowsAdaptiveSteps: true,
  );

  /// The profiles this release defines, in the order they were added.
  static const List<SimulationProfile> values = <SimulationProfile>[
    deterministic,
    accurate,
  ];

  /// The profile [name] writes. [known] is where it is looked for: this
  /// release's [values] unless a caller adds its own. Throws a
  /// [DocumentFormatException] naming the known ones for any other word,
  /// rather than guessing a default: a run read under the wrong promise is
  /// verified, or not, for the wrong reason.
  static SimulationProfile parse(
    String name, {
    Iterable<SimulationProfile> known = values,
  }) =>
      known.where((SimulationProfile p) => p.name == name).firstOrNull ??
      (throw DocumentFormatException(
        'simulation profile "$name" is not one this build knows '
        '(${known.map((SimulationProfile p) => p.name).join(', ')})',
      ));

  /// The wire name: what a file, a tape or a hello writes for it.
  final String name;

  /// Whether the same inputs give the same bits on every platform and
  /// build of one `SimulationVersion`: what rollback between machines, a
  /// replay and a server's verification by replay rest on.
  final bool isBitExact;

  /// Whether the state is kept and stepped in double precision rather than
  /// the float-compatible `Portable` maths.
  final bool usesDoublePrecision;

  /// Whether an integrator may take steps of its own inside the loop's fixed
  /// step, as many as the error it is held to asks for.
  final bool allowsAdaptiveSteps;

  /// [name], as a document writes the profile.
  String toJson() => name;

  @override
  bool operator ==(Object other) =>
      other is SimulationProfile &&
      other.name == name &&
      other.isBitExact == isBitExact &&
      other.usesDoublePrecision == usesDoublePrecision &&
      other.allowsAdaptiveSteps == allowsAdaptiveSteps;

  @override
  int get hashCode =>
      Object.hash(name, isBitExact, usesDoublePrecision, allowsAdaptiveSteps);

  @override
  String toString() => name;
}
