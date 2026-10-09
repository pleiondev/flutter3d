/// A `.f3d` an older converter wrote, opened by this build.
///
///     dart test test/formats/f3d_fixture_test.dart
///
/// **The bytes under `test/fixtures/v<N>/` are minted once and never
/// re-minted.** The round-trip tests say the writer and the reader agree with
/// each other today; this says a file converted at version N still opens at
/// every later 1.x version (decision 8 of `tasks/1.0-stability.md`). When it
/// goes red, re-minting the fixture is the wrong repair: either the change was
/// a mistake, or it changes what a record means, in which case `f3dVersion`
/// moves, the reader branches on the file's version for that record, and a
/// fixture for the new version joins this one.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:test/test.dart';

Uint8List _fixture(int version) =>
    File('test/fixtures/v$version/box.f3d').readAsBytesSync();

void main() {
  test('the version 1 fixture opens with what it was written with', () {
    final bytes = _fixture(1);
    expect(ByteData.sublistView(bytes).getUint32(4, Endian.little), 1);

    // The textured box, converted on 2026-08-31. Mutation: read the version
    // with `!=` against a bumped `f3dVersion` and this throws instead.
    final document = F3dDocument.parse(bytes);
    expect(document.surfaces, hasLength(1));
    expect(document.triangleCount, 12);
    expect(document.materials, hasLength(1));
    expect(document.images, hasLength(1));
    expect(document.nodes, hasLength(2));
  });

  test('every fixture version is one this build reads', () {
    final versions = <int>[
      for (final each in Directory('test/fixtures').listSync())
        if (each is Directory && File('${each.path}/box.f3d').existsSync())
          int.parse(each.path.split(Platform.pathSeparator).last.substring(1)),
    ]..sort();

    // Mutation: bump `f3dVersion` with no `v2/box.f3d` minted, and the
    // second expectation names the gap.
    for (final version in versions) {
      expect(F3dDocument.parse(_fixture(version)).surfaces, isNotEmpty);
    }
    expect(versions, contains(f3dVersion));
  });

  test('a file from a newer converter is refused, and says to update', () {
    final bytes = Uint8List.fromList(_fixture(1));
    ByteData.sublistView(bytes).setUint32(4, f3dVersion + 1, Endian.little);

    // Mutation: drop the upper bound and the newer file is read as if its
    // records meant what this build thinks they mean.
    expect(
      () => F3dDocument.parse(bytes),
      throwsA(
        isA<F3dFormatException>().having(
          (F3dFormatException e) => e.toString(),
          'message',
          contains('Update flutter3d'),
        ),
      ),
    );
  });

  test('the version 2 fixture carries a flags word and a tool\'s section', () {
    final bytes = _fixture(2);
    final header = ByteData.sublistView(bytes);
    expect(header.getUint32(4, Endian.little), 2);
    expect(header.getUint32(12, Endian.little), f3dSectionEntryBytesV2);

    // The same box as version 1, plus a section of kind
    // `f3dVendorKindStart + 1` holding "fixture\0", not must-understand.
    final document = F3dDocument.parse(bytes);
    expect(document.version, 2);
    expect(document.triangleCount, 12);
    final vendor = document.section(f3dVendorKindStart + 1);
    expect(vendor, isNotNull);
    expect(String.fromCharCodes(vendor!.bytes.take(7)), 'fixture');
    expect(vendor.flags, 0);
  });

  test('a must-understand section nobody knows refuses the file', () {
    final document = F3dDocument.parse(_fixture(1));
    final bytes = F3dWriter(
      document,
      extraSections: <F3dExtraSection>[
        F3dExtraSection(
          kind: f3dVendorKindStart + 7,
          bytes: Uint8List(4),
          flags: F3dSectionFlags.mustUnderstand,
        ),
      ],
    ).write();

    // Mutation: skip a flagged section like any other and this opens.
    expect(() => F3dDocument.parse(bytes), throwsA(isA<F3dFormatException>()));
    expect(
      F3dDocument.parse(
        bytes,
        understands: <int>{f3dVendorKindStart + 7},
      ).surfaces,
      hasLength(1),
    );
  });

  test('a bundle and an unflagged tool section still open in a 0.8 reader', () {
    final box = F3dDocument.parse(_fixture(1));
    final bundle = F3dDocument.parse(
      File('test/fixtures/v2/bundle.f3d').readAsBytesSync(),
    );
    final bytes = F3dWriter(
      bundle,
      programs: bundle.programs,
      prefabs: bundle.prefabs,
      files: bundle.files,
      extraSections: <F3dExtraSection>[
        F3dExtraSection(kind: f3dVendorKindStart + 3, bytes: Uint8List(4)),
      ],
    ).write();

    // The walk the 0.8.5 loader does: version exactly 1, 16-byte entries,
    // every section inside the file, unknown kinds kept and ignored.
    // Mutation: write version 2 whenever an extra section is present, and
    // the first expectation fails, which is the file a 0.8 game refuses.
    final view = ByteData.sublistView(bytes);
    expect(view.getUint32(4, Endian.little), 1);
    final sections = <int, int>{};
    for (var i = 0; i < view.getUint32(8, Endian.little); i++) {
      final entry = f3dHeaderBytes + i * f3dSectionEntryBytes;
      final offset = view.getUint32(entry + 4, Endian.little);
      final length = view.getUint32(entry + 8, Endian.little);
      expect(offset + length, lessThanOrEqualTo(bytes.lengthInBytes));
      sections[view.getUint32(entry, Endian.little)] = view.getUint32(
        entry + 12,
        Endian.little,
      );
    }
    expect(sections[F3dSection.surfaces], bundle.surfaces.length);
    expect(sections[F3dSection.materials], bundle.materials.length);
    expect(F3dDocument.parse(bytes).triangleCount, box.triangleCount);
  });

  test('a wide file is refused by name', () {
    final bytes = Uint8List.fromList(_fixture(1));
    ByteData.sublistView(bytes).setUint32(0, f3dWideMagic, Endian.little);
    expect(
      () => F3dDocument.parse(bytes),
      throwsA(
        isA<F3dFormatException>().having(
          (F3dFormatException e) => e.message,
          'message',
          contains('wide'),
        ),
      ),
    );
  });

  test('the version 1 bundle fixture opens with every bundle section', () {
    final bytes = File('test/fixtures/v1/bundle.f3d').readAsBytesSync();
    expect(ByteData.sublistView(bytes).getUint32(4, Endian.little), 1);

    // Minted on 2026-10-09 by re-exporting `v2/bundle.f3d` through
    // `F3dModelWriter`, which writes a bundle with no flagged section at
    // version 1. Mutation: drop the bundle from `F3dWriter.carrying` and the
    // file this was minted from would have had none of it.
    final bundle = F3dDocument.parse(bytes);
    expect(bundle.version, 1);
    expect(bundle.programs['RimGlow'], contains('material RimGlow'));
    expect(bundle.prefabs['box']?['format'], 'f3d.level');
    expect(bundle.files.keys, <String>['notes/readme.txt']);
    expect(bundle.lights, hasLength(1));
    expect(bundle.cameras, hasLength(1));
    expect(bundle.extraSections.single.kind, f3dVendorKindStart + 2);
    expect(bundle.triangleCount, 12);
  });

  test('re-exporting a bundle keeps its programs, prefabs, files and a '
      'tool\'s sections', () {
    final bundle = F3dDocument.parse(
      File('test/fixtures/v2/bundle.f3d').readAsBytesSync(),
    );
    final written = const F3dModelWriter().write(bundle);

    // The cloud's "download .f3d" goes through this writer. Mutation: write
    // `F3dWriter(document)` in `F3dModelWriter.write` and every map is empty.
    final back = F3dDocument.parse(written.files.single.bytes);
    expect(back.programs, bundle.programs);
    expect(back.prefabs.keys, bundle.prefabs.keys);
    expect(back.files.keys, bundle.files.keys);
    expect(
      back.extraSections.map((F3dExtraSection s) => (s.kind, s.flags)),
      bundle.extraSections.map((F3dExtraSection s) => (s.kind, s.flags)),
    );
    expect(
      back.section(f3dVendorKindStart + 2)?.bytes,
      bundle.section(f3dVendorKindStart + 2)?.bytes,
    );
  });

  test('a pointer track this build does not animate is skipped out loud', () {
    final box = F3dDocument.parse(_fixture(1));
    AnimationTrack track(String pointer) => AnimationTrack(
      nodeIndex: -1,
      path: AnimationPath.pointer,
      interpolation: AnimationInterpolation.linear,
      componentCount: 1,
      times: Float32List.fromList(<double>[0, 1]),
      values: Float32List.fromList(<double>[0, 1]),
      pointer: AnimationPointer(
        property: AnimationPointerProperty.roughness,
        index: 0,
        pointer: pointer,
      ),
    );
    final document = PlainModelDocument(
      surfaces: box.surfaces,
      materials: box.materials,
      nodes: box.nodes,
      animations: <AnimationClip>[
        AnimationClip(
          tracks: <AnimationTrack>[
            track('/materials/0/pbrMetallicRoughness/roughnessFactor'),
            // A property a later build animates and this one does not.
            track('/materials/0/extensions/KHR_future/amount'),
          ],
        ),
      ],
    );
    final read = F3dDocument.parse(F3dWriter(document).write());

    // Mutation: `continue` without a word and the warning is gone, though
    // the track is gone from every file written from this document.
    expect(read.animations.single.tracks, hasLength(1));
    expect(read.warnings, contains(contains('KHR_future')));
  });

  test('a writer refuses an extra section of the engine\'s own kind', () {
    final box = F3dDocument.parse(_fixture(1));
    expect(
      () => F3dWriter(
        box,
        extraSections: <F3dExtraSection>[
          F3dExtraSection(kind: F3dSection.materials, bytes: Uint8List(4)),
        ],
      ),
      throwsArgumentError,
    );
  });

  test('the bundle fixture carries lights, a camera, a program, a prefab '
      'and a file', () {
    final bundle = F3dDocument.parse(
      File('test/fixtures/v2/bundle.f3d').readAsBytesSync(),
    );

    // Minted once with every bundle section; a reader that drops one, or
    // reads one at the wrong offset, fails here.
    final lamp = bundle.lights.single;
    expect(lamp.type, ModelLightType.spot);
    expect(lamp.intensity, 100.0);
    expect(lamp.range, 12.0);
    expect(bundle.cameras.single.projection, isA<ModelPerspectiveCamera>());
    expect(bundle.nodes.first.lightIndex, 0);
    expect(bundle.nodes.first.cameraIndex, 0);
    expect(bundle.materials.single.lightingModel?.shaderName, 'RimGlow');
    expect(bundle.programs['RimGlow'], contains('material RimGlow'));
    expect(bundle.prefabs['box']?['format'], 'f3d.level');
    expect(bundle.files.keys, <String>['notes/readme.txt']);
    expect(bundle.triangleCount, 12);
  });
}
