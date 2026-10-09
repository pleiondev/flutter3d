/// A lap written at each version the reader takes, read by this build.
///
///     flutter test test/ghost_fixture_test.dart
///
/// Version 1 is the bare `{"version": 1}` shape every lap before 1.0 was kept
/// in, and version 2 the same body in the shared envelope. Both were minted
/// once under `test/fixtures/v<N>/` and are never re-minted (decision 8 of
/// `tasks/1.0-stability.md`): a player's best lap is on their disk in one of
/// these shapes.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_foundation/flutter3d_foundation.dart';
import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _fixture(int version) =>
    jsonDecode(
          File('test/fixtures/v$version/lap.ghost.json').readAsStringSync(),
        )
        as Map<String, Object?>;

void main() {
  test('every version up to this build reads the same lap', () {
    // Mutation: bump `ghostFormatVersion` with no new fixture, or refuse the
    // bare `{"version": 1}` shape.
    for (var v = 1; v <= ghostFormatVersion; v++) {
      final lap = ghostTapeFromJson(_fixture(v));
      expect(lap.lapTime, 41.25, reason: 'v$v');
      expect(lap.poses, hasLength(3), reason: 'v$v');
      expect(lap.poses.first.up.y, 1.0, reason: 'v$v');
    }
  });

  test('a lap is written in the envelope', () {
    final written = ghostTapeFromJson(_fixture(1)).toJson();

    // Mutation: write `{'version': 1}` again.
    expect(written['format'], 'f3d.ghost');
    expect(written['version'], ghostFormatVersion);
    expect(ghostTapeFromJson(written).poses, hasLength(3));
  });

  test('a lap from a newer build is refused with both versions', () {
    final newer = <String, Object?>{
      ..._fixture(ghostFormatVersion),
      'version': ghostFormatVersion + 1,
    };

    expect(
      () => ghostTapeFromJson(newer),
      throwsA(
        isA<DocumentFormatException>().having(
          (DocumentFormatException e) => e.message,
          'message',
          allOf(
            contains('${ghostFormatVersion + 1}'),
            contains('$ghostFormatVersion'),
          ),
        ),
      ),
    );
  });
}
