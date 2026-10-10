/// `SimSession`'s file verbs — `open`, `writeRun`, `verify`, `bisect` — read
/// and write inside its root, and so does the level a run names.
///
///     flutter test test/sim_session_root_test.dart
///
/// Each payload is an argument a prompt could put in an agent's call, or a
/// field of a run somebody handed it. Each test was written by breaking what
/// it covers; the mutation is named.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_mcp/kit.dart' show ProjectRoot;
import 'package:flutter3d_physics/flutter3d_physics.dart' show CollisionWorld;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show usePhysics;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show WorldPosition;
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:flutter3d_sim_mcp/flutter3d_sim_mcp.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

/// A run that stands still: enough for a session to open a level, step and
/// write what it recorded.
final class _StillRun extends HeadlessRun {
  @override
  void step(double dt) {}

  @override
  Snapshot save() => const Snapshot(<String, Object?>{});

  @override
  RunOutcome get outcome => RunOutcome.playing;

  @override
  WorldPosition get position => WorldPosition.origin;

  @override
  void aim(Vector3 out) => out.setValues(0, 0, -1);

  @override
  String get summary => 'standing still';
}

final class _StillGame extends HeadlessGame {
  @override
  String get name => 'still';

  @override
  Map<String, GameAction> get buttons => const <String, GameAction>{};

  @override
  EntityRegistry registry() => EntityRegistry(const <EntityKind>[]);

  @override
  HeadlessRun start(Level level, CollisionWorld world, InputState input) =>
      _StillRun();
}

const Map<String, Object?> _level = <String, Object?>{
  'version': 1,
  'name': 'a floor',
  'materials': <String, Object?>{
    'floor': <String, Object?>{
      'baseColor': <double>[0.5, 0.5, 0.5, 1.0],
    },
  },
  'brushes': <Map<String, Object?>>[
    <String, Object?>{
      'at': <double>[0.0, -0.5, 0.0],
      'size': <double>[8.0, 1.0, 8.0],
      'material': 'floor',
    },
  ],
  'lights': <Map<String, Object?>>[],
  'entities': <Map<String, Object?>>[],
};

void main() {
  late Directory sandbox;
  late Directory project;
  late SimSession session;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('sim_session_root');
    project = Directory('${sandbox.path}/game')..createSync();
    File('${project.path}/floor.json').writeAsStringSync(jsonEncode(_level));
    File('${sandbox.path}/outside.json').writeAsStringSync('root:x:0:0');
    File('${sandbox.path}/floor.json').writeAsStringSync(jsonEncode(_level));
    session = SimSession(game: _StillGame(), root: ProjectRoot(project.path));
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  test('a level outside the root is refused before it is read', () {
    // Mutation: read `path` unresolved, as before 1.0. The parse error
    // quotes the file: `root:x:0:0`.
    for (final where in <String>[
      '../outside.json',
      '${sandbox.path}/outside.json',
      '/etc/passwd',
    ]) {
      final opened = session.open(where);
      expect(opened.did, isFalse, reason: where);
      expect(opened.says, contains('outside the project'));
      expect(opened.says, isNot(contains('root:x')));
    }
    expect(session.isOpen, isFalse);
    expect(session.open('floor.json').did, isTrue);
  });

  test('a run is written only inside the root', () {
    expect(session.open('floor.json').did, isTrue);
    session.step(steps: 3);
    // Mutation: write `path` unresolved. The run lands beside the project,
    // or over any file this process may write.
    for (final where in <String>['../escaped.f3drun', '/tmp/../escaped']) {
      final written = session.writeRun(where);
      expect(written.did, isFalse, reason: where);
      expect(written.says, contains('outside the project'));
    }
    expect(File('${sandbox.path}/escaped.f3drun').existsSync(), isFalse);
    expect(session.writeRun('kept.f3drun').did, isTrue);
  });

  test('a run, and the level a run names, are read only inside the root', () {
    expect(session.open('floor.json').did, isTrue);
    session.step(steps: 3);
    expect(session.writeRun('kept.f3drun').did, isTrue);

    // Mutation: read the runs unresolved.
    final outsideRun = session.verify('../outside.json');
    expect(outsideRun.did, isFalse);
    expect(outsideRun.says, contains('outside the project'));
    final bisected = session.bisect('kept.f3drun', '../outside.json');
    expect(bisected.did, isFalse);
    expect(bisected.says, contains('outside the project'));

    // Mutation: read the run's own `level` unresolved. A run file is
    // somebody's data, and its `level` field points wherever they like.
    final run =
        jsonDecode(File('${project.path}/kept.f3drun').readAsStringSync())
            as Map<String, Object?>;
    File('${project.path}/reaching.f3drun').writeAsStringSync(
      jsonEncode(<String, Object?>{
        ...run,
        'level': '${sandbox.path}/floor.json',
      }),
    );
    final reaching = session.verify('reaching.f3drun');
    expect(reaching.did, isFalse);
    expect(reaching.says, contains('outside the project'));
  });

  test('a run is verified on the physics it was recorded on', () {
    if (usePhysics().name == 'dart') {
      markTestSkipped('the native core is not loaded, so every run is Dart');
      return;
    }
    expect(session.open('floor.json').did, isTrue);
    session.step(steps: 3);
    expect(session.writeRun('kept.f3drun').did, isTrue);
    // Mutation: leave `resimulate` on its default, the Dart physics, as
    // before. A run this session just recorded on native is refused as
    // "recorded on the native physics and this session runs dart".
    final verified = session.verify('kept.f3drun');
    expect(verified.did, isTrue, reason: verified.says);
  });
}
