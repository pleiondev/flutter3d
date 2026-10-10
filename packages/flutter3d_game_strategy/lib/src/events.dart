/// What a step of a match did, on the engine's bus.
///
/// **Published by the [Match], read off its step.** The strategy's step has
/// no event buffer of its own: what a step did is read off it —
/// [StrategySimulation.shots], [Match.standing] — and the drawing half reads
/// exactly that. The match turns the same two readings into events at the
/// end of its step, onto the bus [Match.publishTo] named (the
/// [StrategyPlugin] points it at the engine's), so a subscriber hears them
/// without the simulation growing a buffer it would also have to save, and
/// two runs of one tape publish the same events because they read the same
/// state.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';

import 'match.dart';
import 'plugin.dart';
import 'simulation.dart';

/// A unit fired at another: one per [UnitShot] of the step, in the order
/// they were fired.
///
/// The units are named by their entities, which is what a digest can carry
/// and what a save already names them by.
final class UnitFired extends GameEvent {
  const UnitFired({
    required this.side,
    required this.shooter,
    required this.mark,
  });

  /// The [UnitShot] as an event.
  factory UnitFired.of(UnitShot shot) => UnitFired(
    side: shot.shooter.side,
    shooter: shot.shooter.entity,
    mark: shot.mark.entity,
  );

  /// The name it is published and declared under.
  static const String eventName = 'strategy.unitFired';

  /// Its codec: the side and the two entities, packed. Reads back whole.
  static final EventCodec<UnitFired> codec = EventCodec<UnitFired>.of(
    encode: (UnitFired e) => <Object?>[e.side, e.shooter.packed, e.mark.packed],
    decode: (Object? data, int version) => switch (data) {
      [final int side, final int shooter, final int mark] => UnitFired(
        side: side,
        shooter: Entity.fromPacked(shooter),
        mark: Entity.fromPacked(mark),
      ),
      _ => null,
    },
  );

  /// Whose unit fired.
  final int side;

  /// The unit that fired, and the one it fired at.
  final Entity shooter;
  final Entity mark;

  @override
  String get name => eventName;

  @override
  void digestInto(EventDigestSink sink) {
    sink
      ..add(side)
      ..add(shooter.packed)
      ..add(mark.packed);
  }
}

/// The match was decided, on the step it was: won by [winner], or drawn
/// when that is null. Once a match; see [Standing].
final class MatchDecided extends GameEvent {
  const MatchDecided(this.winner);

  /// The name it is published and declared under.
  static const String eventName = 'strategy.matchDecided';

  /// Its codec: the winning side, or null for a draw.
  static final EventCodec<MatchDecided> codec = EventCodec<MatchDecided>.of(
    encode: (MatchDecided e) => e.winner,
    decode: (Object? data, int version) =>
        data == null || data is int ? MatchDecided(data as int?) : null,
  );

  /// The side that won, or null for a draw.
  final int? winner;

  @override
  String get name => eventName;

  @override
  void digestInto(EventDigestSink sink) => sink.add(winner);
}
