/// A track the generator wrote at version 1, read by this build.
///
///     flutter test test/track_fixture_test.dart
///
/// The ring circuit as it shipped, minted once under `test/fixtures/v1/` and
/// never re-minted (decision 8 of `tasks/1.0-stability.md`). The generator
/// rewrites `assets/tracks/` whenever it runs; this copy stays, so a change to
/// the reader that would stop an old track loading shows up here rather than
/// on somebody's custom circuit.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter3d_game_racing/flutter3d_game_racing.dart';
import 'package:flutter_test/flutter_test.dart';

TrackDocument _fixture(int version) => TrackDocument.fromJson(
  jsonDecode(File('test/fixtures/v$version/ring.track.json').readAsStringSync())
      as Map<String, Object?>,
);

void main() {
  test('the v1 ring reads its circuit, its level and its sky', () {
    final document = _fixture(1);

    // Mutation: refuse anything but the current version, then bump it.
    expect(document.track.center.pointCount, 32);
    expect(document.track.checkpoints, hasLength(3));
    expect(document.level, isNotNull);
    expect(document.level!.brushes, hasLength(25));
  });

  test('every version up to this build has a fixture', () {
    // Mutation: bump `TrackDocument.formatVersion` with no new fixture.
    for (var v = 1; v <= TrackDocument.formatVersion; v++) {
      expect(_fixture(v).track.center.pointCount, greaterThan(0));
    }
  });
}
