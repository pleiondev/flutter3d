/// `rp-00`'s determinism probe, on the one platform `flutter test` cannot
/// reach: an actual device.
///
///     flutter test integration_test/parity_test.dart -d <device-id>
///
/// **Mirrors `packages/flutter3d_game_strategy/test/parity_test.dart` (and its
/// `mirror` helper from `test/match_test.dart`) on purpose, rather than
/// importing them** — see
/// `apps/flutter3d_demo_platformer/integration_test/parity_test.dart` for why.
/// See `doc/tooling-plan.md` rp-00 for what this answers.
library;

import 'dart:typed_data';

import 'package:flutter3d_game/flutter3d_game.dart';
import 'package:flutter3d_game_strategy/flutter3d_game_strategy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vector_math/vector_math.dart';

const double _step = 1.0 / 30.0;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a thousand steps of a match match the recorded match', (
    WidgetTester tester,
  ) async {
    final trace = _play();
    final divergence = trace.divergenceFromHex(_recorded);
    expect(
      divergence,
      isNull,
      reason:
          'this device played a different match: $divergence. See '
          'packages/flutter3d_game_strategy/test/parity_test.dart, which '
          'recorded the trace this compares against.',
    );
  });
}

Heightfield _flat() => Heightfield(
  columns: 41,
  rows: 41,
  cellSize: 2.0,
  heights: Float32List(41 * 41),
);

Match _mirror({
  double seamOne = 20.0,
  double seamTwo = 20.0,
  double amountOne = 500.0,
  double amountTwo = 500.0,
  double target = 300.0,
  int workers = 3,
  bool produce = true,
  bool policies = true,
}) {
  final sim = StrategySimulation(random: GameRandom(1), ground: _flat());
  final bots = <Bot>[];
  for (var side = 0; side < 2; side++) {
    final double z = 16.0 + side * 40.0;
    final base = sim.build(
      Building(
        centre: Vector3(16.0, 0.0, z),
        width: 6.0,
        depth: 6.0,
        name: 'base',
        side: side,
      ),
    );
    sim.addResource(
      ResourceNode(
        at: Vector3(16.0 + (side == 0 ? seamOne : seamTwo), 0.0, z),
        amount: side == 0 ? amountOne : amountTwo,
      ),
    );
    for (var i = 0; i < workers; i++) {
      sim.add(Unit(position: Vector3(22.0, 0.0, z - 1.0 + i), side: side));
    }
    if (produce) {
      sim.addProducer(Producer(building: base));
    }
    if (policies) bots.add(Bot(side: side, base: base));
  }
  return Match(
    simulation: sim,
    bots: bots,
    goal: MatchGoal(delivered: target),
  );
}

DigestTrace _play({double seamTwo = 20.0, int steps = 1200, int every = 30}) {
  final Match match = _mirror(seamTwo: seamTwo, target: 10000.0);
  final trace = DigestTrace(every: every);
  for (var step = 1; step <= steps; step++) {
    match.step(_step);
    if (step % every == 0) trace.observe(step, match.save().data);
  }
  return trace;
}

/// The same trace `packages/flutter3d_game_strategy/test/parity_test.dart`
/// recorded on macOS-arm64 under the VM, 2026-09-08.
const List<String> _recorded = <String>[
  '4bf7e8cb',
  '270ca193',
  '3b5d7d0d',
  '41bf1a68',
  'd266d559',
  '9c4e1e2e',
  '8a7fe96e',
  '91377bbd',
  'ee182ff4',
  '4879ba73',
  '78d59d38',
  '226f06e9',
  '51349317',
  'f7c6be40',
  '8131043e',
  '0297b501',
  '9e40236b',
  '83f15782',
  '1df8c05e',
  '8d03801e',
  'cf36f147',
  'c8ac928f',
  '7c369fc5',
  '1d8cd2e4',
  '6d6f95ab',
  'a8e3845e',
  '34a8310f',
  '97db9317',
  'c79f8391',
  '2fd41325',
  '18203ac1',
  'e3ab4456',
  'd24e9a9c',
  '481c10c3',
  'f9148c66',
  '6e18599d',
  '6a66fff7',
  '67f5e079',
  '5d241ffe',
  '5be26087',
];
