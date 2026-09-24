/// A2: a claim about a run, answered with the step it held at, the digest
/// there and a `.f3drun` — and a replay of that file that either retraces it
/// or names the checkpoint where it stopped.
///
/// Played in-process against the shooter's own staging of the crypt, rather
/// than over the socket `sim_mcp_test.dart` already proves: what is under
/// test here is what the answers say, not how they travel.
///
///     flutter test test/claims_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart' show WidgetSurfaceKind;
import 'package:flutter3d_game_shooter/staging.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_sim_mcp/flutter3d_sim_mcp.dart';
import 'package:flutter_test/flutter_test.dart';

const String _crypt =
    '../../apps/flutter3d_demo_dungeon/assets/levels/crypt.json';

SimSession _session() => SimSession(
  game: const ShooterHeadlessGame(extra: <EntityKind>[WidgetSurfaceKind()]),
);

Map<String, Object?> _reading(SimSession session) =>
    jsonDecode(session.snapshot().says) as Map<String, Object?>;

List<double> _playerAt(SimSession session) => <double>[
  for (final v
      in ((_reading(session)['player']! as Map)['position']! as List<Object?>))
    (v! as num).toDouble(),
];

String _digestIn(String says) =>
    RegExp(r'digest ([0-9a-f]{8})').firstMatch(says)!.group(1)!;

int _stepIn(String says) =>
    int.parse(RegExp(r'at step (\d+)').firstMatch(says)!.group(1)!);

void main() {
  late Directory workspace;

  setUp(() {
    workspace = Directory.systemTemp.createTempSync('flutter3d_claims');
  });

  tearDown(() => workspace.deleteSync(recursive: true));

  group('a claim over a reading', () {
    const reading = <String, Object?>{
      'player': <String, Object?>{
        'position': <double>[1.0, 0.0, 2.0],
        'health': 40.0,
        'alive': true,
      },
      'actors': <Map<String, Object?>>[
        <String, Object?>{
          'name': 'imp',
          'position': <double>[5.0, 0.0, 5.0],
          'health': 0.0,
          'alive': false,
        },
        <String, Object?>{
          'name': 'door',
          'position': null,
          'health': null,
          'alive': true,
        },
      ],
    };

    bool holds(Map<String, Object?> json) =>
        ReadingPredicate.fromJson(json).holds(reading);

    test('near and inside measure where the row stands', () {
      expect(
        holds(<String, Object?>{
          'kind': 'near',
          'point': <num>[1, 0, 2.5],
          'within': 0.6,
        }),
        isTrue,
      );
      expect(
        holds(<String, Object?>{
          'kind': 'near',
          'point': <num>[1, 0, 2.5],
          'within': 0.4,
        }),
        isFalse,
      );
      expect(
        holds(<String, Object?>{
          'kind': 'inside',
          'who': 'imp',
          'min': <num>[4, -1, 4],
          'max': <num>[6, 1, 6],
        }),
        isTrue,
      );
      expect(
        holds(<String, Object?>{
          'kind': 'inside',
          'min': <num>[4, -1, 4],
          'max': <num>[6, 1, 6],
        }),
        isFalse,
      );
    });

    test('something with no body is near nothing and has no health', () {
      expect(
        holds(<String, Object?>{
          'kind': 'near',
          'who': 'door',
          'point': <num>[0, 0, 0],
          'within': 1000,
        }),
        isFalse,
      );
      expect(
        holds(<String, Object?>{
          'kind': 'health',
          'who': 'door',
          'below': 1000,
        }),
        isFalse,
      );
    });

    test('alive and health read the row', () {
      expect(holds(<String, Object?>{'kind': 'alive'}), isTrue);
      expect(
        holds(<String, Object?>{'kind': 'alive', 'who': 'imp', 'is': false}),
        isTrue,
      );
      expect(holds(<String, Object?>{'kind': 'health', 'below': 50}), isTrue);
      expect(
        holds(<String, Object?>{'kind': 'health', 'below': 50, 'atLeast': 45}),
        isFalse,
      );
    });

    test('a claim about nobody, or of no known kind, is refused', () {
      expect(
        () => holds(<String, Object?>{'kind': 'alive', 'who': 'ghost'}),
        throwsA(isA<ReadingPredicateException>()),
      );
      expect(
        () => holds(<String, Object?>{'kind': 'touching'}),
        throwsA(isA<ReadingPredicateException>()),
      );
      expect(
        () => holds(<String, Object?>{'kind': 'health'}),
        throwsA(isA<ReadingPredicateException>()),
      );
    });
  });

  group('expect and verify on the crypt', () {
    test('a claim that holds is answered with its step and digest, and the '
        'replay of the file it wrote ends at both', () {
      // Where forty steps forward take the player, found by walking there.
      final probe = _session()..open(_crypt);
      probe.step(steps: 40, moveY: 1.0);
      final there = _playerAt(probe);

      final session = _session();
      expect(session.open(_crypt).did, isTrue);
      final path = '${workspace.path}/claim.f3drun';
      final claimed = session.expect(
        predicate: <String, Object?>{
          'kind': 'near',
          'point': there,
          'within': 0.001,
        },
        limit: 200,
        path: path,
        moveY: 1.0,
      );
      expect(claimed.did, isTrue, reason: claimed.says);
      expect(_stepIn(claimed.says), 40, reason: claimed.says);

      final demo = Demo.fromJson(
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>,
      );
      expect(demo.steps, 40);

      final replayed = session.verify(
        path,
        predicate: <String, Object?>{
          'kind': 'near',
          'point': there,
          'within': 0.001,
        },
      );
      expect(replayed.did, isTrue, reason: replayed.says);
      expect(replayed.says, contains('agrees at all 1 checkpoints'));
      expect(replayed.says, contains('ends at step 40'));
      expect(_digestIn(replayed.says), _digestIn(claimed.says));
      expect(replayed.says, contains('holds there'));
    });

    test('a claim that never holds stops at the limit and still writes the '
        'run that failed', () {
      final session = _session()..open(_crypt);
      final path = '${workspace.path}/failed.f3drun';
      final claimed = session.expect(
        predicate: <String, Object?>{'kind': 'health', 'below': 0},
        limit: 30,
        path: path,
        moveY: 1.0,
      );
      expect(claimed.did, isFalse);
      expect(claimed.says, contains('did not hold within 30 steps'));
      expect(_stepIn(claimed.says), 30);
      expect(session.verify(path).did, isTrue);
    });

    test('a claim about nobody is refused before anything moves', () {
      final session = _session()..open(_crypt);
      final claimed = session.expect(
        predicate: <String, Object?>{'kind': 'alive', 'who': 'nobody'},
        limit: 10,
        path: '${workspace.path}/nobody.f3drun',
      );
      expect(claimed.did, isFalse);
      expect(claimed.says, contains('nobody called "nobody"'));
      expect(_reading(session)['step'], 0);
    });

    test('a run whose tape was changed is caught at the first checkpoint '
        'after the change', () {
      final session = _session()..open(_crypt);
      final path = '${workspace.path}/walk.f3drun';
      session
        ..step(steps: 60, moveY: 1.0)
        ..writeRun(path);
      expect(session.verify(path).did, isTrue);

      // Step 30 (index 29) turns the stick sideways: nothing before the
      // checkpoint at 25 changes, and the one at 50 cannot survive it.
      final json =
          jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      final frames = (json['tape']! as Map)['frames']! as List<Object?>;
      frames[29] = <String, Object?>{'sx': 1.0, 'sy': 1.0};
      File(path).writeAsStringSync(jsonEncode(json));

      final replayed = session.verify(path);
      expect(replayed.did, isFalse, reason: replayed.says);
      expect(replayed.says, contains('diverges'));
      expect(replayed.says, contains('step 50:'));
      expect(replayed.says, contains('arose after step 25'));
    });

    test('a replay into a level that has changed is refused', () {
      final session = _session()..open(_crypt);
      final path = '${workspace.path}/moved.f3drun';
      session
        ..step(steps: 5, moveY: 1.0)
        ..writeRun(path);
      final json =
          jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      json['levelHash'] = '00000000';
      File(path).writeAsStringSync(jsonEncode(json));

      final replayed = session.verify(path);
      expect(replayed.did, isFalse);
      expect(replayed.says, contains('has changed since the run was recorded'));
    });

    test('verify leaves the session\'s own run where it was', () {
      final session = _session()..open(_crypt);
      final path = '${workspace.path}/aside.f3drun';
      session
        ..step(steps: 30, moveY: 1.0)
        ..writeRun(path);
      final before = session.snapshot().says;
      session.verify(path);
      expect(session.snapshot().says, before);
    });
  });
}
