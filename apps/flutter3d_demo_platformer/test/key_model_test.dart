/// The key both games ship, and the fact that nobody had to be asked for it.
///
///     flutter test test/key_model_test.dart
///
/// **This was the release blocker.** `key.glb` came from an archive with no
/// licence file, no author and no trail back to one; both games placed it; and
/// the credits screen told the player "author unknown, licence untraced". No
/// amount of looking fixes that — an asset with no provenance does not acquire
/// one — so the key is generated instead, by `tool/make_key.py`, and its
/// provenance is a hundred lines of arithmetic in this repository.
///
/// What is checked here is what a generator can get wrong and a screenshot
/// cannot show: that the file the games ship parses, that it is the size the one
/// it replaced was, and that it is still centred on its own origin — because a
/// level document says *where* a key is, not how big, and a model whose origin
/// sat at its teeth would sink half of every key into the floor of both games.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d/src/engine/assets/gltf/glb_container.dart';
import 'package:flutter_test/flutter_test.dart';

/// The shipped file, read the way the game reads it: off disk, as bytes.
GlbContainer _key(String game) => GlbContainer.parse(
  Uint8List.fromList(
    File(
      '${game == 'platformer' ? '.' : '../flutter3d_demo_dungeon'}'
      '/assets/models/key.glb',
    ).readAsBytesSync(),
  ),
);

/// The extent of the mesh, from the accessor that carries bounds.
({List<double> low, List<double> high}) _bounds(GlbContainer glb) {
  final accessors = glb.json['accessors']! as List<Object?>;
  for (final entry in accessors) {
    final accessor = entry! as Map<String, Object?>;
    if (accessor['type'] != 'VEC3' || !accessor.containsKey('min')) continue;
    return (
      low: (accessor['min']! as List<Object?>)
          .map((Object? v) => (v! as num).toDouble())
          .toList(),
      high: (accessor['max']! as List<Object?>)
          .map((Object? v) => (v! as num).toDouble())
          .toList(),
    );
  }
  throw StateError('no bounded VEC3 accessor: the positions have no min/max');
}

void main() {
  for (final game in <String>['platformer', 'dungeon']) {
    group('the key $game ships', () {
      test('parses as the binary glTF it claims to be', () {
        final glb = _key(game);

        expect(glb.json['meshes'], isNotEmpty);
        expect(
          glb.binaryChunk,
          isNotNull,
          reason: 'no BIN chunk: the mesh has no data',
        );
      });

      test('and says where it came from, in the file itself', () {
        // The credits read `credits.dart`, but a model that travels should
        // carry its own provenance — which is exactly what the old one did not.
        final asset = _key(game).json['asset']! as Map<String, Object?>;

        expect(asset['generator'], contains('make_key.py'));
        expect(asset['copyright'], contains('CC0'));
      });

      test('and is the size the one it replaced was', () {
        // 0.25 by 0.72 metres once its node scale was applied. Both games place
        // it by that size, and a level document says where a key is rather than
        // how big — so a key that came back half as tall would be a change to
        // every level at once, made in a tool nobody was editing.
        final bounds = _bounds(_key(game));
        final extent = <double>[
          for (var i = 0; i < 3; i++) bounds.high[i] - bounds.low[i],
        ];

        expect(extent[0], closeTo(0.25, 0.06), reason: 'width');
        expect(extent[1], closeTo(0.72, 0.08), reason: 'height');
      });

      test('and is centred on its own origin', () {
        // A model whose origin sat at its teeth would sink half of every key
        // into the floor, in both games, in every level that places one.
        final bounds = _bounds(_key(game));

        for (var i = 0; i < 3; i++) {
          expect(
            (bounds.low[i] + bounds.high[i]) / 2,
            closeTo(0.0, 1e-6),
            reason: 'axis $i is off centre',
          );
        }
      });
    });
  }

  test('and both games ship the same one', () {
    // One generator, two copies, and a script that writes both — so the day the
    // key changes it cannot change in one game only.
    expect(
      File('assets/models/key.glb').readAsBytesSync(),
      File('../flutter3d_demo_dungeon/assets/models/key.glb').readAsBytesSync(),
    );
  });
}
