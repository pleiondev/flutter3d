/// A `.fmat` written at version 1, read by this build.
///
///     dart test test/formats/fmat_fixture_test.dart
///
/// The fixture under `test/fixtures/v1/` is never rewritten: it is the file an
/// artist saved, and decision 8 of `tasks/1.0-stability.md` promises every 1.x
/// engine opens it. A version that changes what a key means moves
/// `fmatVersion`, teaches `readFmat` to lift the older file, and mints a
/// fixture of its own beside this one. `v1/brass.enveloped.fmat` is the same
/// material as this build writes it, in the envelope, still version 1.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

Uint8List _fixture(int version) =>
    File('test/fixtures/v$version/brass.fmat').readAsBytesSync();

void main() {
  test('the version 1 fixture reads back as the material it describes', () {
    final document = readFmat(_fixture(1), name: 'brass.fmat');

    // Mutation: refuse anything but the current version and a bumped
    // `fmatVersion` turns this file into an exception.
    expect(document.warnings, isEmpty);
    expect(document.surface.name, 'brass');
    expect(document.surface.metallic, 1.0);
    expect(document.surface.roughness, 0.375);
    expect(document.surface.doubleSided, isTrue);
    expect(document.images, <String>['brass_albedo.png']);
    expect(document.parameters['tarnish'], <double>[0.25]);
  });

  test('every version up to this build has a fixture', () {
    // Mutation: bump `fmatVersion` without minting `v2/brass.fmat`.
    for (var version = 1; version <= fmatVersion; version++) {
      expect(
        File('test/fixtures/v$version/brass.fmat').existsSync(),
        isTrue,
        reason: 'no fixture for .fmat version $version',
      );
      expect(readFmat(_fixture(version)).surface.name, 'brass');
    }
  });

  test('the enveloped version 1 reads as the same material', () {
    final document = readFmat(
      File('test/fixtures/v1/brass.enveloped.fmat').readAsBytesSync(),
      name: 'brass.fmat',
    );

    // Mutation: warn on the envelope's keys, or refuse a file whose head
    // names `f3d.fmat` rather than starting with `fmat`.
    expect(document.warnings, isEmpty);
    expect(document.surface.roughness, 0.375);
    expect(document.parameters['tarnish'], <double>[0.25]);
  });

  test('a material is written in the envelope, with `fmat` beside it', () {
    final written =
        jsonDecode(writeFmat(readFmat(_fixture(1)))) as Map<String, Object?>;

    // Mutation: drop the envelope, or drop `fmat` and a 0.8 reader refuses
    // the material inside a bundle it otherwise opens.
    expect(
      written.keys.take(4),
      orderedEquals(<String>['format', 'version', 'requires', 'generator']),
    );
    expect(written['format'], 'f3d.fmat');
    expect(written['version'], fmatVersion);
    expect(written['fmat'], fmatVersion);
    expect(isFmat(utf8.encode(writeFmat(readFmat(_fixture(1))))), isTrue);
  });

  test('a material from the future is refused rather than half drawn', () {
    final newer = utf8.encode(
      utf8
          .decode(_fixture(1))
          .replaceFirst('"fmat": 1', '"fmat": ${fmatVersion + 1}'),
    );

    // Mutation: drop the upper bound and a newer key's meaning is guessed.
    expect(() => readFmat(newer), throwsA(isA<FmatFormatException>()));
  });

  test('a key a later build added is kept when the material is saved', () {
    final document =
        jsonDecode(utf8.decode(_fixture(1))) as Map<String, Object?>;
    final later = utf8.encode(
      jsonEncode(<String, Object?>{
        ...document,
        'subsurface': <String, Object?>{'radius': 0.2},
      }),
    );

    // Mutation: drop `unknown` from `writeFmat` and the key is lost the
    // first time an earlier build opens and saves the file.
    final read = readFmat(later);
    expect(read.unknown.keys, <String>['subsurface']);
    final again = jsonDecode(writeFmat(read)) as Map<String, Object?>;
    expect(again['subsurface'], <String, Object?>{'radius': 0.2});
    expect(readFmat(utf8.encode(writeFmat(read))).unknown, read.unknown);
  });
}
