/// A `.f3drun` an older build wrote, opened by this one.
///
///     dart test test/demo_fixture_test.dart
///
/// **Bytes minted once and never re-minted** (`doc-28`), one file per format
/// version this build reads: `test/fixtures/v<N>/run.f3drun`. A run is a bug
/// report somebody attached last year; when this goes red that attachment has
/// stopped opening. Re-minting makes it green and throws the guarantee away —
/// either the change was a mistake, or `Demo.formatVersion` moves, these stay,
/// and a migrator in `Demo._upgrades` carries them to the new meaning.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

/// The component the v5 fixture's world holds.
final class _Count {
  _Count(this.value);

  final int value;

  static final ComponentCodec<_Count> codec = ComponentCodec<_Count>.of(
    id: 'test.count',
    encode: (count) => count.value,
    decode: (data, _) => data is int ? _Count(data) : null,
  );
}

Demo fixture(int version) => Demo.fromJson(
  jsonDecode(File('test/fixtures/v$version/run.f3drun').readAsStringSync())
      as Map<String, Object?>,
);

void main() {
  test('the v1 run opens, and reads as the first simulation', () {
    final run = fixture(1);

    expect(run.level, 'assets/levels/crypt.json');
    expect(run.steps, 4);
    expect(run.tape.frames.first.pressed, <String>['fire']);
    expect(run.checkpoints.steps, <int>[2, 4]);
    expect(run.simulation, isNull);
    expect(run.poses, isNull);
    // Written before simulations had numbers, so it is version 1 of whatever
    // is running at version 1. Mutation: read a missing simulation as "other"
    // and every tape on every disk stops replaying the day 1.0.0 ships.
    expect(run.refusalOn(const SimulationVersion(genre: 'shooter')), isNull);
    expect(
      run.refusalOn(const SimulationVersion(genre: 'shooter', genreVersion: 2)),
      contains('shooter 1'),
    );
  });

  test('the v2 run opens with its level swap', () {
    final run = fixture(2);

    // Mutation: drop the identity step 1 → 2 from the chain and the reader
    // indexes past the end of it on every v2 file. Mutation: check the
    // swap's hash against the level as this build writes it back, and the
    // level's own version bump refuses this run as edited.
    expect(run.levelSwaps.single.step, 2);
    expect(run.levelSwaps.single.level.name, 'crypt');
  });

  test('the v3 run opens with its loop change, simulation and poses', () {
    final run = fixture(3);

    expect(run.loopChanges.single, const LoopStepRate(step: 2, rate: 30));
    expect(run.simulation, const SimulationVersion(genre: 'shooter'));
    final poses = run.poses!;
    expect(poses.bodies, <String>['runner', 'crate#1']);
    expect(poses.frames.map((f) => f.step), <int>[0, 2, 4]);
    // The crate arrived at step 2: absent before, there after. Mutation: read
    // the frame as a fixed stride and the crate's numbers land on the runner.
    expect(poses.frames.first.bodies, hasLength(1));
    expect(poses.frames[1].bodies[1]!.sublist(0, 3), <double>[1, 2, 3]);
  });

  test('the v5 run starts with its change stamps and keeps what is '
      'reserved', () {
    final run = fixture(5);

    // Restored through a loop, the stamps say which count changed when.
    // Mutation: drop `changedAt` from `EcsWorld.restore` — both are new.
    final loop = EngineLoop(input: InputState());
    loop.world.components.register<_Count>(_Count.codec);
    loop.restore(run.start);
    loop.world.beginStep(6);
    expect(
      loop.world.query().changed<_Count>(since: 3).entities.map((e) => e.index),
      <int>[1],
    );
    expect(run.unknown['probes'], hasLength(1));
    expect(run.unknown['externalInputs'], hasLength(1));
    expect(run.unknown['parent'], <String, Object?>{
      'digest': '9a8b7c6d',
      'step': 120,
    });
    final external =
        (run.unknown['externalInputs']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(external, <String, Object?>{
      'step': 3,
      'at': 0.05,
      'kind': 'sensor.pressure',
      'sourceTime': 12.5,
      'receivedTime': 12.75,
      'quality': 'uncertain',
      'tag': 'pump.3',
      'unit': 'kPa',
    });
    expect(run.toJson()['version'], 5);
  });

  test('every fixture directory is a version this build reads, and every '
      'version has one', () {
    final versions = <int>[
      for (final each in Directory('test/fixtures').listSync())
        if (each is Directory && File('${each.path}/run.f3drun').existsSync())
          int.parse(each.path.split(Platform.pathSeparator).last.substring(1)),
    ]..sort();

    // Mutation: bump `Demo.formatVersion` with no `v4/run.f3drun` beside it
    // and this is the only test that notices.
    expect(versions, <int>[for (var v = 1; v <= Demo.formatVersion; v++) v]);
    for (final version in versions) {
      expect(fixture(version).steps, 4);
    }
  });
}
