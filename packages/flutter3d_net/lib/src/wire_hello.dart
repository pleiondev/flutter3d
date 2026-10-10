/// What two machines check before they play together: the protocol their
/// messages are in, and the simulation their steps run.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationVersion;

/// The versions a machine names in its hello, and the rule two hellos are
/// held to.
///
/// **The protocol, major and minor.** Within a major the protocol only
/// grows: a minor adds messages and optional fields, and never changes or
/// takes away one a lower minor sends. So two machines whose majors agree
/// play together whatever their minors, each reading what it knows and
/// passing over what it does not, and [sharedMinor] is the minor both
/// speak. A different major is refused.
///
/// **The simulation, exactly.** [simulation] is the game's
/// [SimulationVersion]: the engine's number, the genre's, and every
/// simulation plugin's. Rollback and lockstep only work when both machines
/// compute the same step from the same frames, so two machines on different
/// simulations are refused, whichever is newer — a match that would drift
/// apart a few seconds in is worse than no match.
///
/// **Protocol 3** marks the engine's own messages with the wire's reserved
/// key (`PeerWire.engineKey`): a rollback's frames are `{"f3d": "rollback",
/// "frames": …}` where protocol 2 sent the frames bare, which a game's
/// message with a `frames` field could be taken for; bytes on a wire that
/// carries only JSON are `{"f3d": "bytes", "b": …}`, base64 under the same
/// key (`PeerWire.sendBytes`), part of 3.0 as it first shipped, so no minor
/// counts them. Protocol 2 carried the
/// whole simulation where protocol 1 carried one number. A hello from an
/// earlier major, or from before versions, is refused as another major, with
/// the version to update to.
final class WireHello {
  const WireHello({
    required this.simulation,
    this.protocolMajor = currentProtocolMajor,
    this.protocolMinor = currentProtocolMinor,
  });

  /// The protocol's major in this build. It changes only with a major
  /// release of the packages that speak it. 3: the engine's messages carry
  /// the reserved key; 2: the hello carries a whole [SimulationVersion].
  static const int currentProtocolMajor = 3;

  /// The protocol's minor in this build: the count of additions since the
  /// major began.
  static const int currentProtocolMinor = 0;

  final int protocolMajor;
  final int protocolMinor;

  /// The game's simulation — see the class doc.
  final SimulationVersion simulation;

  /// The protocol as it is written: `3.0`.
  String get protocol => '$protocolMajor.$protocolMinor';

  /// The fields a hello carries, beside whatever else the message holds.
  Map<String, Object?> toJson() => <String, Object?>{
    'protocol': <int>[protocolMajor, protocolMinor],
    'simulation': simulation.toJson(),
  };

  /// The versions in [said], a hello as [toJson] wrote it. A hello that
  /// names no protocol is from before versions — protocol 0.0. A simulation
  /// that cannot be read is the engine's alone, which a different major is
  /// refused before it matters.
  static WireHello read(Map<String, Object?> said) {
    final (major, minor) = switch (said['protocol']) {
      [final int major, final int minor] when major >= 0 && minor >= 0 => (
        major,
        minor,
      ),
      _ => (0, 0),
    };
    SimulationVersion simulation = SimulationVersion.engineOnly;
    if (said['simulation'] case final Map<Object?, Object?> named) {
      try {
        simulation = SimulationVersion.fromJson(named.cast<String, Object?>());
      } on Exception {
        // A simulation named wrongly is no simulation this build plays.
        return WireHello(
          simulation: SimulationVersion.engineOnly,
          protocolMajor: major,
          protocolMinor: minor,
        );
      }
    }
    return WireHello(
      simulation: simulation,
      protocolMajor: major,
      protocolMinor: minor,
    );
  }

  /// Why this machine cannot play with the one that said [other]: a
  /// sentence to show the player, naming what has to be updated. Null when
  /// the two can play.
  String? refusal(WireHello other) {
    if (other.protocolMajor != protocolMajor) {
      final behind = other.protocolMajor > protocolMajor ? 'this' : 'the other';
      final major = other.protocolMajor > protocolMajor
          ? other.protocolMajor
          : protocolMajor;
      return 'the other machine speaks protocol ${other.protocol} and this '
          'one $protocol: update $behind game to protocol $major';
    }
    if (other.simulation == simulation) return null;
    final theirs = other.simulation.describe();
    final ours = simulation.describe();
    final update = switch (_newer(other.simulation, simulation)) {
      true => 'update this game',
      false => 'update the other game',
      null => 'both games have to run the same simulation',
    };
    return 'the other machine runs simulation $theirs and this one $ours: '
        '$update';
  }

  /// Whether [a] is the newer of two simulations: true, false, or null when
  /// they are not the same game (another genre, other plugins).
  static bool? _newer(SimulationVersion a, SimulationVersion b) {
    if (a.genre != b.genre) return null;
    if (a.engine != b.engine) return a.engine > b.engine;
    if (a.genre != null && a.genreVersion != b.genreVersion) {
      return a.genreVersion > b.genreVersion;
    }
    final ids = <String>{...a.plugins.keys, ...b.plugins.keys};
    if (ids.length != a.plugins.length || ids.length != b.plugins.length) {
      return null;
    }
    for (final id in ids.toList()..sort()) {
      final x = a.plugins[id]!, y = b.plugins[id]!;
      if (x != y) return x > y;
    }
    return null;
  }

  /// The protocol minor both machines speak, when [refusal] lets them play:
  /// the lower of the two.
  int sharedMinor(WireHello other) =>
      other.protocolMinor < protocolMinor ? other.protocolMinor : protocolMinor;

  @override
  bool operator ==(Object other) =>
      other is WireHello &&
      other.protocolMajor == protocolMajor &&
      other.protocolMinor == protocolMinor &&
      other.simulation == simulation;

  @override
  int get hashCode => Object.hash(protocolMajor, protocolMinor, simulation);

  @override
  String toString() =>
      'WireHello(protocol $protocol, simulation ${simulation.describe()})';
}
