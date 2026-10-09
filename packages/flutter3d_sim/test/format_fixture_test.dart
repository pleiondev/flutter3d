/// The simulation's files as an older build wrote them, read by this one:
/// a level, its visibility table and lightmap, a save, a share bundle and a
/// telemetry upload.
///
///     dart test test/format_fixture_test.dart
///
/// **Bytes minted once and never re-minted** (decision 8 of
/// `tasks/1.0-stability.md`, and `doc-28` before it), one per format version
/// this build reads, under `test/fixtures/v<N>/`. The `.f3drun` beside them
/// has its own file, `demo_fixture_test.dart`. When one of these goes red a
/// file on somebody's disk has stopped opening: either the change was a
/// mistake, or the format's version moves, its migration list gains the step,
/// and a fixture for the new version joins these.
@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_matter/flutter3d_matter.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart';
import 'package:test/test.dart';

String _path(String name, int version) => 'test/fixtures/v$version/$name';

Map<String, Object?> _json(String name, int version) =>
    jsonDecode(File(_path(name, version)).readAsStringSync())
        as Map<String, Object?>;

/// [json] claiming to be one version past [current].
Map<String, Object?> _fromTheFuture(Map<String, Object?> json, int current) =>
    <String, Object?>{...json, 'version': current + 1};

void main() {
  group('Level', () {
    test('the v1 level reads, and keeps the keys it does not know', () {
      final level = Level.fromJson(_json('first.level.json', 1));

      // Mutation: put back an exact-version gate and bump the constant.
      expect(level.name, 'shooter start');
      expect(level.brushes, hasLength(6));
      expect(level.entities, hasLength(4));
      expect(level.lights, hasLength(1));
      // `generatedBy` and `editor` belong to the tools, not the format.
      // Mutation: build `toJson` from the fields alone and both are lost.
      final written = level.toJson();
      expect(written['generatedBy'], 'tool/make_templates.py');
      expect(written['editor'], <String, Object?>{'template': 'shooter'});
    });

    test('every version up to this build has a fixture', () {
      for (var v = 1; v <= Level.formatVersion; v++) {
        expect(
          Level.fromJson(_json('first.level.json', v)).brushes,
          isNotEmpty,
        );
      }
    });

    test('the v3 level reads its ids, props and id-path overrides', () {
      final level = Level.fromJson(_json('first.level.json', 3));

      expect(level.entities.first.id, 'u5m4q91i');
      expect(level.entities[2].properties['gives'], 'health');
      final gate = PrefabInstance.of(level.entities.last)!;
      expect(gate.overrides.keys, contains('k1o83ltm/oz6whrfj'));
      // Mutation: write `props` back at the top of the row, or drop the ids.
      final written = level.toJson();
      expect(written['format'], 'f3d.level');
      expect(written['version'], Level.formatVersion);
      final rows = written['entities']! as List<Object?>;
      expect((rows[2]! as Map<String, Object?>)['props'], <String, Object?>{
        'gives': 'health',
        'amount': 25,
      });
    });

    test(
      'the v4 level reads its world, and a v3 gravity is lifted into one',
      () {
        final level = Level.fromJson(_json('first.level.json', 4));
        final played = level.worldOver(WorldProperties.standard);
        expect(played.gravity.y, closeTo(-1.62, 1e-6));
        expect(played.airPressure, 300.0);
        expect(played.wind.x, 2.0);
        // Mutation: drop `_gravityIntoWorld` from the migrations — the v3
        // document's scalar is then an unknown key and the Moon is lost.
        final lifted = Level.fromJson(<String, Object?>{
          ..._json('first.level.json', 3),
          'gravity': 1.62,
        });
        expect(lifted.world, <String, Object?>{'gravity': 1.62});
        expect(lifted.toJson().containsKey('gravity'), isFalse);
        expect(
          lifted.worldOver(WorldProperties.standard).gravity.y,
          closeTo(-1.62, 1e-6),
        );
      },
    );

    test('a v2 level is given the same ids on every load, and its '
        'overrides become id paths', () {
      final first = Level.fromJson(_json('first.level.json', 2));
      final again = Level.fromJson(_json('first.level.json', 2));

      // Mutation: mint a random id for a row without one, and a digest a
      // recorded run is checked against moves on every load.
      expect(
        first.entities.map((EntityDef e) => e.id),
        again.entities.map((EntityDef e) => e.id),
      );
      expect(first.digestHex, again.digestHex);
      final post = first.prefabs['post']!.entities;
      final lamp = first.prefabs['lamp']!.entities;
      final gate = PrefabInstance.of(first.entities.last)!;
      // `top/bulb` and `base`, by name, are now the ids they named.
      expect(
        gate.overrides.keys,
        unorderedEquals(<String>['${post[1].id}/${lamp[0].id}', post[0].id]),
      );
      // And the expanded level is the one the v2 file described.
      final expanded = expandPrefabs(first);
      final bulb = expanded.entities.firstWhere(
        (EntityDef e) => e.name == 'gate/top/bulb',
      );
      expect(bulb.properties['glow'], <String, Object?>{
        'strength': 2.0,
        'tint': 'cold',
      });
    });

    test('a level from the future is refused, saying to update', () {
      expect(
        () => Level.fromJson(
          _fromTheFuture(_json('first.level.json', 1), Level.formatVersion),
        ),
        throwsA(
          isA<LevelFormatException>().having(
            (LevelFormatException e) => e.toString(),
            'message',
            contains('update flutter3d'),
          ),
        ),
      );
    });
  });

  group('LevelVisibility', () {
    test('the v1 table reads with its grid and its brush hash', () {
      final table = LevelVisibility.fromJson(_json('deep.visibility.json', 1));

      expect(table.cellSize, 3.0);
      expect(table.countX, 6);
      expect(table.brushHash, 1847967362);
    });

    test('every version up to this build has a fixture', () {
      for (var v = 1; v <= LevelVisibility.formatVersion; v++) {
        expect(
          LevelVisibility.fromJson(_json('deep.visibility.json', v)).countX,
          6,
        );
      }
    });
  });

  group('Lightmap', () {
    Uint8List bytes(int version) =>
        File(_path('room.lightmap.bin', version)).readAsBytesSync();

    test('the v1 sidecar reads its size, density, hash and texels', () {
      final map = Lightmap.fromBytes(bytes(1));

      // Mutation: put back `!=` against a bumped `formatVersion`.
      expect(map.width, 2);
      expect(map.height, 1);
      expect(map.texelsPerMeter, 4.0);
      expect(map.levelHash, 0x12345678);
      expect(map.pixels, <int>[255, 128, 0, 32, 0, 0, 0, 0]);
    });

    test('every version up to this build has a fixture', () {
      for (var v = 1; v <= Lightmap.formatVersion; v++) {
        expect(Lightmap.fromBytes(bytes(v)).texelCount, 2);
      }
    });

    test('a sidecar from the future is refused, naming the cure', () {
      final newer = Uint8List.fromList(bytes(1));
      ByteData.sublistView(
        newer,
      ).setUint32(4, Lightmap.formatVersion + 1, Endian.little);

      // Mutation: drop the upper bound and a newer layout's texels are read
      // as RGBM.
      expect(
        () => Lightmap.fromBytes(newer),
        throwsA(
          isA<LightmapFormatException>().having(
            (LightmapFormatException e) => e.message,
            'message',
            contains('update flutter3d'),
          ),
        ),
      );
    });
  });

  group('a save', () {
    test('the v1 save opens with every field the game wrote', () {
      final read = SaveRecord.read(_json('save.json', 1), const SaveSchema());

      // Mutation: start the envelope's migrations at 0 for every save, or
      // drop the fields `Snapshot` does not know, and this changes.
      expect(read, isA<SaveFound>());
      final record = (read as SaveFound).record;
      expect(record.level, 'assets/levels/crypt.json');
      expect(record.step, 120);
      final data = record.run.data;
      expect((data['player']! as Map<String, Object?>)['health'], 3);
      expect(data['keptForANewerBuild'], 'a field this build never wrote');
      expect(data.containsKey(Snapshot.versionKey), isFalse);
    });

    test('every envelope version up to this build has a fixture', () {
      for (var v = 1; v <= Snapshot.formatVersion; v++) {
        expect(
          SaveRecord.read(_json('save.json', v), const SaveSchema()),
          isA<SaveFound>(),
        );
      }
    });

    test('an envelope from the future is not read', () {
      final json = _json('save.json', 1);
      final run = json['run']! as Map<String, Object?>;
      final newer = <String, Object?>{
        ...json,
        'run': _fromTheFuture(run, Snapshot.formatVersion),
      };

      final read = SaveRecord.read(newer, const SaveSchema());
      expect(read, isA<SaveNotRead>());
      expect((read as SaveNotRead).newer, isTrue);
    });
  });

  group('ShareBundle', () {
    test('the v1 bundle opens, and its hash still names its level', () {
      final bundle = ShareBundle.fromJson(_json('first.share.json', 1));

      // The hash is checked on the way in, so this also says
      // `contentDigestHex` still hashes the level the way it did when the
      // fixture was minted. Mutation: change the digest and this throws.
      expect(bundle.game, 'shooter');
      expect(bundle.title, 'first room');
      expect(bundle.run, isNull);
      expect(Level.fromJson(bundle.level).name, 'shooter start');
    });

    test('every version up to this build has a fixture', () {
      for (var v = 1; v <= ShareBundle.formatVersion; v++) {
        expect(
          ShareBundle.fromJson(_json('first.share.json', v)).game,
          'shooter',
        );
      }
    });

    test('a bundle from the future is refused, saying to update', () {
      expect(
        () => ShareBundle.fromJson(
          _fromTheFuture(
            _json('first.share.json', 1),
            ShareBundle.formatVersion,
          ),
        ),
        throwsA(
          isA<ShareFormatException>().having(
            (ShareFormatException e) => e.message,
            'message',
            contains('update flutter3d'),
          ),
        ),
      );
    });
  });

  group('TelemetryUpload', () {
    test('the v1 upload opens with its consent and its run', () {
      final upload = TelemetryUpload.fromJson(_json('upload.json', 1));

      expect(upload.game, 'shooter');
      expect(upload.policy, 'runs-2026');
      expect(upload.consentedAt, DateTime.utc(2026, 10, 8, 12));
      expect(upload.demo.level, 'assets/levels/crypt.json');
      expect(upload.demo.steps, 4);
    });

    test('every version up to this build has a fixture', () {
      for (var v = 1; v <= TelemetryUpload.formatVersion; v++) {
        expect(
          TelemetryUpload.fromJson(_json('upload.json', v)).game,
          'shooter',
        );
      }
    });

    test('an upload from the future is refused', () {
      // Mutation: drop the upper bound and a newer client's run is replayed
      // with this server's idea of what its fields mean.
      expect(
        () => TelemetryUpload.fromJson(
          _fromTheFuture(
            _json('upload.json', 1),
            TelemetryUpload.formatVersion,
          ),
        ),
        throwsA(isA<TelemetryUploadFormatException>()),
      );
    });
  });
}
