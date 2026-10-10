/// The strategy played blind: what a tool that drives a game with nobody at
/// a window needs from this one.
library;

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:vector_math/vector_math.dart';

import 'level_reader.dart';
import 'match.dart';
import 'simulation.dart';
import 'simulation_version.dart';
import 'unit.dart';

/// A strategy map, as the simulation's MCP server and a playtest farm play
/// it: side nought by orders, every other side by its [Bot].
///
/// **Played by orders, not by the stick.** A strategy has no body the input
/// walks; it has a selection sent somewhere. So this is an [OrderedGame],
/// and its four verbs — [orders] — reach the run through the input as
/// [OrderTunes] write them, on the tape with the step that takes them. A
/// run played this way replays, verifies and bisects as the other genres'
/// do. The stick and the look are not read, and there are no [buttons].
///
/// **The selection is part of the run's state**: it is in [HeadlessRun.save]
/// beside the match, since which units the next `move` sends depends on the
/// last `select`, and a run put back to a saved state must send the same
/// ones.
///
/// The map is read by [openStrategyLevel], so a level is a strategy map
/// document with its heightfield; [workers] and [seed] are passed on.
final class StrategyHeadlessGame extends OrderedGame {
  const StrategyHeadlessGame({this.workers, this.seed = 1});

  /// How many stand in each block of workers, or null for the map's own.
  final int? workers;

  /// The dice the match starts on.
  final int seed;

  /// The side the orders command.
  static const int side = 0;

  /// The kinds a `train` order's `kind` names, by number.
  static const List<UnitType> trainable = <UnitType>[
    UnitType.worker,
    UnitType.soldier,
    UnitType.tank,
  ];

  @override
  SimulationVersion get simulation => strategySimulationVersion;

  @override
  String get name => 'strategy';

  @override
  Map<String, GameAction> get buttons => const <String, GameAction>{};

  @override
  Map<String, GameOrder> get orders => const <String, GameOrder>{
    'select': GameOrder(
      description:
          'Pick out your units within `radius` metres of x, z; a radius of 0, '
          'or none, picks every unit you have. Replaces the selection.',
      arguments: <String, String>{
        'x': 'metres east, default 0',
        'z': 'metres south, default 0',
        'radius': 'metres, default 0: everybody',
      },
    ),
    'move': GameOrder(
      description:
          'Send the selection to x, z, in a block. Takes them off their jobs.',
      arguments: <String, String>{
        'x': 'metres east, default 0',
        'z': 'metres south, default 0',
      },
    ),
    'attack': GameOrder(
      description:
          'Send the selection after the enemy unit standing nearest x, z.',
      arguments: <String, String>{
        'x': 'metres east, default 0',
        'z': 'metres south, default 0',
      },
    ),
    'train': GameOrder(
      description:
          'Ask each of your halls for `count` units of `kind`, paid from your '
          'stockpile as they are made.',
      arguments: <String, String>{
        'kind': '0 a worker (the default), 1 a soldier, 2 a tank',
        'count': 'how many from each hall, default 1',
      },
    ),
  };

  @override
  EntityRegistry registry() => EntityRegistry(strategyLevelKinds);

  @override
  HeadlessRun start(Level level, CollisionWorld world, InputState input) =>
      _StrategyRun(
        openStrategyLevel(level, workers: workers, seed: seed).match,
        input,
      );
}

final class _StrategyRun extends RestorableRun {
  _StrategyRun(this.match, this.input);

  final Match match;
  final InputState input;

  /// The selected units' entity indices, in the order they were picked.
  List<int> _selected = const <int>[];

  StrategySimulation get _sim => match.simulation;

  static const int _side = StrategyHeadlessGame.side;

  @override
  void step(double dt) {
    // Queued before the match steps, so the step carries them out at its
    // top, as it does a mouse's.
    for (final order in OrderTunes.read(input)) {
      _obey(order);
    }
    match.step(dt);
  }

  void _obey(GivenOrder order) {
    final x = order.number('x');
    final z = order.number('z');
    switch (order.verb) {
      case 'select':
        final radius = order.number('radius');
        _selected = <int>[
          for (final unit in _sim.units)
            if (unit.side == _side &&
                unit.isAlive &&
                (radius <= 0.0 || _within(unit, x, z, radius)))
              unit.entity.index,
        ];
      case 'move':
        final chosen = _chosen();
        if (chosen.isEmpty) return;
        _sim.orders.moveTo(chosen, Vector3(x, _sim.ground.heightAt(x, z), z));
      case 'attack':
        final chosen = _chosen();
        final mark = _nearestEnemy(x, z);
        if (chosen.isEmpty || mark == null) return;
        _sim.orders.attackWith(chosen, mark);
      case 'train':
        final kind = order.number('kind').round();
        if (kind < 0 || kind >= StrategyHeadlessGame.trainable.length) return;
        final count = order.number('count', 1.0).round();
        if (count < 1) return;
        for (final maker in _sim.producers) {
          if (maker.building.side != _side) continue;
          _sim.orders.train(
            maker,
            StrategyHeadlessGame.trainable[kind],
            count: count,
          );
        }
    }
  }

  static bool _within(StrategyUnit unit, double x, double z, double radius) {
    final dx = unit.position.x - x;
    final dz = unit.position.z - z;
    return dx * dx + dz * dz <= radius * radius;
  }

  /// The selection as it stands: those picked out who are still on the map.
  List<StrategyUnit> _chosen() {
    if (_selected.isEmpty) return const <StrategyUnit>[];
    final picked = _selected.toSet();
    return <StrategyUnit>[
      for (final unit in _sim.units)
        if (unit.side == _side &&
            unit.isAlive &&
            picked.contains(unit.entity.index))
          unit,
    ];
  }

  /// The enemy unit nearest x, z; the first in the crowd's order on a tie.
  StrategyUnit? _nearestEnemy(double x, double z) {
    StrategyUnit? nearest;
    var best = double.infinity;
    for (final unit in _sim.units) {
      if (unit.side == _side || !unit.isAlive) continue;
      final dx = unit.position.x - x;
      final dz = unit.position.z - z;
      final distance = dx * dx + dz * dz;
      if (distance < best) {
        best = distance;
        nearest = unit;
      }
    }
    return nearest;
  }

  @override
  Snapshot save() => Snapshot(<String, Object?>{
    ...match.save().data,
    'selected': List<int>.of(_selected),
  });

  @override
  void restore(Snapshot snapshot) {
    match.restore(snapshot);
    _selected = <int>[
      if (snapshot.data['selected'] case final List<Object?> picked)
        for (final index in picked)
          if (index is num) index.toInt(),
    ];
  }

  /// Won when side nought wins; a draw is not a win, so it is lost.
  @override
  RunOutcome get outcome => switch (match.standing) {
    Standing(isOver: false) => RunOutcome.playing,
    Standing(winner: _side) => RunOutcome.won,
    _ => RunOutcome.lost,
  };

  /// The middle of the selection, or of every unit of side nought when
  /// nobody is selected.
  ///
  /// **Against the world's origin, said outright.** A match keeps its units
  /// in a frame of its own, on no `CollisionWorld`, and no origin shift moves
  /// it: the world a tool hands [StrategyHeadlessGame.start] may be rebased
  /// and the units stay where they were. So their float32 positions are
  /// offsets from the world's origin, not from the loop's.
  @override
  WorldPosition get position {
    final chosen = _chosen();
    return _middle(
      chosen.isEmpty ? _units(_side) : chosen,
    ).toWorldPosition(origin: WorldPosition.origin);
  }

  List<StrategyUnit> _units(int side) => <StrategyUnit>[
    for (final unit in _sim.units)
      if (unit.side == side && unit.isAlive) unit,
  ];

  static Vector3 _middle(List<StrategyUnit> units) {
    final sum = Vector3.zero();
    if (units.isEmpty) return sum;
    for (final unit in units) {
      sum.add(unit.position);
    }
    return sum..scale(1.0 / units.length);
  }

  /// Above and behind [position], as the map's camera looks down on a crowd.
  @override
  WorldPosition get eye => position.translated(0.0, 40.0, -30.0);

  @override
  void aim(Vector3 out) => out
    ..setValues(0.0, -0.8, 0.6)
    ..normalize();

  String get _standing => switch (match.standing) {
    Standing(isOver: false) => 'playing',
    Standing(winner: final int side) => 'won by side $side',
    _ => 'drawn',
  };

  @override
  String get summary {
    final delivered = _sim.delivered;
    return 'Side $_side has ${_units(_side).length} units, '
        '${_chosen().length} selected, and has brought home '
        '${delivered[_side].toStringAsFixed(1)} of '
        '${match.goal.delivered}; the match is $_standing.';
  }

  /// `player` is side nought and each `actors` row another side, named
  /// `side N`: its middle, whether it can still act, and as `health` how
  /// many units it has — so the server's claims (near, alive, health) read
  /// a side as they read a body.
  @override
  Map<String, Object?> get reading => <String, Object?>{
    'standing': _standing,
    'player': <String, Object?>{
      ..._sideRow(_side),
      'selected': _chosen().length,
    },
    'actors': <Map<String, Object?>>[
      for (var side = 0; side < _sim.sides; side++)
        if (side != _side)
          <String, Object?>{'name': 'side $side', ..._sideRow(side)},
    ],
  };

  Map<String, Object?> _sideRow(int side) {
    final units = _units(side);
    final at = _middle(units);
    final alive =
        units.isNotEmpty ||
        _sim.producers.any((maker) => maker.building.side == side);
    return <String, Object?>{
      'position': <double>[at.x, at.y, at.z],
      'alive': alive,
      'health': units.length.toDouble(),
      'delivered': _sim.delivered[side],
      'stock': _sim.stock[side].amount,
    };
  }
}
