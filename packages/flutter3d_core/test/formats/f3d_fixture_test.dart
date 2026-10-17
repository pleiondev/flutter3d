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
import 'package:flutter3d_foundation/flutter3d_foundation.dart' show LightType;
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
    final written = const F3dModelWriter().write(
      ModelWriteContext(document: bundle),
    );

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

  group('the fixture with every section', () {
    final bytes = File('test/fixtures/v2/everything.f3d').readAsBytesSync();

    test('lists every kind the engine writes in its directory', () {
      final view = ByteData.sublistView(bytes);
      final entryBytes = view.getUint32(12, Endian.little);
      final kinds = <int>{
        for (var i = 0; i < view.getUint32(8, Endian.little); i++)
          view.getUint32(f3dHeaderBytes + i * entryBytes, Endian.little),
      };
      // Minted on 2026-10-15 by `tool/make_everything_fixture.dart`.
      // A kind added to `F3dSection.known` after it has its own fixture.
      expect(kinds, containsAll(F3dSection.known));
    });

    test('reads back what each section carried', () {
      final document = F3dDocument.parse(bytes);
      expect(document.version, 2);
      // Variants (23) and the surface that changes in them.
      expect(document.variants, <String>['day', 'night']);
      final ball = document.surfaces.firstWhere(
        (ModelSurface s) => s.name == 'ball',
      );
      expect(ball.variantMaterials, hasLength(2));
      // Clusters (26).
      expect(ball.mesh.clusters, isNotNull);
      // A measured level (27) and an impostor (25).
      final node = document.nodes.firstWhere((ModelNode n) => n.name == 'ball');
      expect(node.lods.first.error, closeTo(0.0125, 1e-7));
      expect(node.lods.last.impostor?.grid, 4);
      // Extras (28) on the node, a material, a clip and the document.
      expect(node.extras?['tag'], 'ball');
      expect(document.asset?.extras?['minted'], '2026-10-15');
      // A pointer track (24).
      final glow = document.animations.firstWhere(
        (AnimationClip c) => c.name == 'glow',
      );
      expect(glow.tracks.single.pointer?.property, isNotNull);
      // Rights (38), a physical material (36) and its reference (37).
      expect(document.asset?.license, 'CC0-1.0');
      expect(document.physicalMaterials.keys, contains('acme.foam'));
      expect(
        document.materials.map((SurfaceMaterial m) => m.physicalMaterial),
        contains('acme.foam'),
      );
      // A tool's section a writer may carry over edited tables.
      expect(
        document.section(f3dVendorKindStart + 9)?.flags,
        F3dSectionFlags.safeToCopy,
      );
    });
  });

  group('the flag bits', () {
    Uint8List withFlags(int kind, int flags) {
      final bytes = Uint8List.fromList(
        File('test/fixtures/v2/box.f3d').readAsBytesSync(),
      );
      final view = ByteData.sublistView(bytes);
      for (var i = 0; i < view.getUint32(8, Endian.little); i++) {
        final entry = f3dHeaderBytes + i * f3dSectionEntryBytesV2;
        if (view.getUint32(entry, Endian.little) == kind) {
          view.setUint32(entry + 16, flags, Endian.little);
        }
      }
      return bytes;
    }

    test('are all spoken for', () {
      // Written into files for good. Mutation: move a bit and a 1.x
      // writer's flag reads as another in a 1.0 reader.
      expect(
        F3dSectionFlags.mustUnderstand |
            F3dSectionFlags.safeToCopy |
            F3dSectionFlags.ignorable |
            F3dSectionFlags.mustUnderstandIfSet,
        0xFFFFFFFF,
      );
      expect(F3dSectionFlags.mustUnderstand, 1 << 0);
      expect(F3dSectionFlags.safeToCopy, 1 << 1);
      expect(F3dSectionFlags.ignorable & F3dSectionFlags.safeToCopy, 0);
    });

    test('an ignorable bit on a known section reads on', () {
      final document = F3dDocument.parse(
        withFlags(F3dSection.materials, 1 << 9),
      );
      expect(document.materials, hasLength(1));
    });

    test('an unknown high bit on a known section refuses the file', () {
      // Mutation: drop the check and a 1.x section whose bytes are
      // compressed reads as garbage records.
      expect(
        () => F3dDocument.parse(withFlags(F3dSection.materials, 1 << 20)),
        throwsA(
          isA<F3dFormatException>().having(
            (F3dFormatException e) => e.message,
            'message',
            contains('Update flutter3d'),
          ),
        ),
      );
    });

    test('a high bit on a section nobody knows is its writer\'s', () {
      final document = F3dDocument.parse(
        withFlags(f3dVendorKindStart + 1, 1 << 20),
      );
      expect(document.section(f3dVendorKindStart + 1)?.flags, 1 << 20);
    });

    test('over edited tables, only a section safe to copy is carried', () {
      final source = F3dDocument.parse(
        File('test/fixtures/v2/everything.f3d').readAsBytesSync(),
      );
      final edited = PlainModelDocument(
        surfaces: source.surfaces.take(1).toList(),
        materials: source.materials,
        images: source.images,
        nodes: <ModelNode>[
          ModelNode(surfaces: <int>[0]),
        ],
      );
      final same = F3dDocument.parse(F3dWriter.carrying(source).write());
      final moved = F3dDocument.parse(
        F3dWriter.carrying(edited, from: source).write(),
      );
      // Mutation: carry every unknown section over edited tables, and a
      // tool's section names nodes that are not there any more.
      expect(
        same.extraSections.map((F3dExtraSection s) => s.kind),
        source.extraSections.map((F3dExtraSection s) => s.kind),
      );
      expect(moved.extraSections.map((F3dExtraSection s) => s.kind), <int>[
        f3dVendorKindStart + 9,
      ]);
      expect(moved.programs, source.programs);
    });
  });

  test('the bundle fixture carries lights, a camera, a program, a prefab '
      'and a file', () {
    final bundle = F3dDocument.parse(
      File('test/fixtures/v2/bundle.f3d').readAsBytesSync(),
    );

    // Minted once with every bundle section; a reader that drops one, or
    // reads one at the wrong offset, fails here.
    final lamp = bundle.lights.single;
    expect(lamp.type, LightType.spot);
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
