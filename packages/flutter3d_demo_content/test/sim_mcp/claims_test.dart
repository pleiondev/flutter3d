/// A2: a claim about a run, answered with the step it held at, the digest
/// there and a `.f3drun` — and a replay of that file that either retraces it
/// or names the checkpoint where it stopped.
///
/// Played in-process against the shooter's own staging of the crypt, rather
/// than over the socket `sim_mcp_test.dart` already proves: what is under
/// test here is what the answers say, not how they travel.
///
///     flutter test test/sim_mcp/claims_test.dart
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_app/flutter3d_app.dart' show WidgetSurfaceKind;
import 'package:flutter3d_demo_content/shooter_staging.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show NativePhysics, usePhysics;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
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

    test('two runs that part are bisected to the step and the field', () {
      // The same forty steps forward, except that one of them turns aside
      // for the last twenty: they agree for twenty and part on the next.
      final straight = _session()..open(_crypt);
      straight.step(steps: 40, moveY: 1.0);
      final a = '${workspace.path}/straight.f3drun';
      expect(straight.writeRun(a).did, isTrue);

      final aside = _session()..open(_crypt);
      aside
        ..step(steps: 20, moveY: 1.0)
        ..step(steps: 20, moveX: 1.0);
      final b = '${workspace.path}/aside.f3drun';
      expect(aside.writeRun(b).did, isTrue);

      // Mutation: comparing at the checkpoints only, which names a later
      // step; or stepping one run ahead of the other, which parts at once.
      final found = _session().bisect(a, b);
      expect(found.did, isTrue, reason: found.says);
      expect(found.says, contains('agree for 20 steps and part at step 21'));
      // The input is what differed, and the answer says so, with where.
      expect(found.says, contains('step 20 had different input'));
      expect(found.says, contains('first at `'));
      expect(
        _session().bisect(a, a).says,
        contains('the runs agree for all 40 steps'),
      );
    });

    test('read through the save\'s entities, a bisection names the component '
        'the runs part on', () {
      // Forty steps forward, and the same with the trigger held for the last
      // twenty: the shot lands in the monster ahead on the step it is fired,
      // so the runs part there, and in that monster's components.
      String run(String name, {required bool fire}) {
        final session = _session()..open(_crypt);
        session
          ..step(steps: 20, moveY: 1.0)
          ..step(steps: 20, moveY: 1.0, held: <String, bool>{'fire': fire});
        final path = '${workspace.path}/$name.f3drun';
        expect(session.writeRun(path).did, isTrue);
        return path;
      }

      final walked = run('walked', fire: false);
      final fired = run('fired', fire: true);
      final entities = EntityLayout.ecs(<String>['entities']);

      // Mutation: the layout not handed to `bisectTapes`, which leaves the
      // answer a path into the raw save with no component in it.
      final found = SimSession(
        game: const ShooterHeadlessGame(
          extra: <EntityKind>[WidgetSurfaceKind()],
        ),
        entities: entities,
      ).bisect(walked, fired);
      expect(found.did, isTrue, reason: found.says);
      expect(found.says, contains('part at step 21'));
      expect(found.says, contains('first at `0.facing.yaw`'));
      expect(
        found.says,
        contains('The first component that differs is 0.facing; also '),
      );
      // The shot landed: the monster's health is one of them.
      expect(found.says, contains('0.vitality'));

      // Given to the call, the layout is the call's; without one anywhere,
      // the answer is the raw path and nothing about components.
      expect(
        _session().bisect(walked, fired, layout: entities).says,
        contains('The first component that differs is 0.facing'),
      );
      final raw = _session().bisect(walked, fired).says;
      expect(raw, contains('first at `entities.components.facing.0.yaw`'));
      expect(raw, isNot(contains('component that differs')));

      // Turning aside parts the runs in the player, which is not one of the
      // save's entities. On the reference that is all, and the answer says
      // no component differs rather than naming one that does not; on the
      // core the crypt's elements follow the player with a walker of their
      // own, and theirs is the one component named.
      final aside = _session()..open(_crypt);
      aside
        ..step(steps: 20, moveY: 1.0)
        ..step(steps: 20, moveX: 1.0);
      final turned = '${workspace.path}/turned.f3drun';
      expect(aside.writeRun(turned).did, isTrue);
      final parted = _session().bisect(walked, turned, layout: entities).says;
      expect(
        parted,
        usePhysics() is NativePhysics
            ? matches(RegExp(r'The component that differs is \d+\.crypt\b'))
            : contains('No entity component differs at that step'),
      );
    });

    test('a run is verified on the physics it was recorded on', () {
      final session = _session()..open(_crypt);
      final path = '${workspace.path}/walked.f3drun';
      session.expect(
        predicate: <String, Object?>{'kind': 'health', 'below': 0},
        limit: 120,
        path: path,
        moveY: 1.0,
      );
      final json =
          jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      expect(json['physics'], usePhysics().name);
      expect(session.verify(path).did, isTrue);
      // Said to be from the other backend, the same steps are played on that
      // one, which walks the crypt by other numbers — and the session is on
      // its own again after. Mutation: verifying on the session's physics
      // whatever the file says, which retraces it.
      final other = usePhysics().name == 'native' ? 'dart' : 'native';
      File(path).writeAsStringSync(jsonEncode(json..['physics'] = other));
      final replayed = session.verify(path);
      expect(replayed.did, isFalse, reason: replayed.says);
      expect(replayed.says, contains('diverges'));
      expect(usePhysics().name, isNot(other));
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

    test('a claim that holds but could not write its run is refused', () {
      final session = _session()..open(_crypt);
      final claimed = session.expect(
        predicate: <String, Object?>{'kind': 'alive'},
        limit: 10,
        path: '${workspace.path}/no/such/dir/held.f3drun',
      );
      expect(claimed.did, isFalse, reason: claimed.says);
      expect(claimed.says, contains('held at step 0'));
      expect(claimed.says, contains('could not write'));
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

    test('a run recorded on another simulation is refused before it is '
        'played', () {
      final session = _session()..open(_crypt);
      final path = '${workspace.path}/rules.f3drun';
      session
        ..step(steps: 5, moveY: 1.0)
        ..writeRun(path);
      final json =
          jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
      // The session writes the shooter's simulation into the run it records.
      // Mutation: leave it out, and a run from 1.0 cannot be told from one
      // recorded after the rules changed.
      expect(
        json['simulation'],
        const ShooterHeadlessGame().simulation.toJson(),
      );
      expect(session.verify(path).did, isTrue);

      json['simulation'] = const SimulationVersion(
        genre: 'shooter',
        genreVersion: 99,
      ).toJson();
      File(path).writeAsStringSync(jsonEncode(json));
      final replayed = session.verify(path);
      // Mutation: drop the check in `verify` and this plays the tape and
      // passes — the session's rules are the ones it was written on — which
      // is exactly the run a newer build would misreport as diverging.
      expect(replayed.did, isFalse);
      expect(replayed.says, contains('is not replayed'));
      expect(replayed.says, contains('shooter 99'));
    });

    test('a run with the level edited under it is refused, naming the '
        'step', () {
      final session = _session()..open(_crypt);
      final path = '${workspace.path}/edited.f3drun';
      session
        ..step(steps: 10, moveY: 1.0)
        ..writeRun(path);
      final demo = Demo.fromJson(
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>,
      );
      File(path).writeAsStringSync(
        jsonEncode(
          Demo(
            level: demo.level,
            levelHash: demo.levelHash,
            start: demo.start,
            tape: demo.tape,
            buildStamp: demo.buildStamp,
            checkpoints: demo.checkpoints,
            levelSwaps: <DemoLevelSwap>[
              DemoLevelSwap(step: 4, level: Level(name: 'crypt')),
            ],
          ).toJson(),
        ),
      );

      // Mutation: drop the refusal — the session plays through the edit in
      // the shipped crypt and reports the run as diverging.
      final replayed = session.verify(path);
      expect(replayed.did, isFalse);
      expect(replayed.says, contains('edited under it at step 4'));
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
