/// A file an older build wrote, opened by this one.
///
///     dart test test/fixture_migration_test.dart
///
/// **The only test in the suite that is not about what this build does.** Every
/// other format test writes a file and reads it back, which says the writer and
/// the reader agree with each other today and nothing at all about the file
/// somebody saved last year. This one reads bytes that were minted once and are
/// never re-minted, so when it goes red the file on somebody's disk has stopped
/// opening.
///
/// **What to do when it fails**, because the tempting repair is the wrong one.
/// Re-minting the fixture makes it green and throws away the guarantee. Either
/// the change was a mistake and belongs undone, or it genuinely changes what a
/// record means — in which case `kProjectVersion` moves, this fixture stays and
/// keeps being read by whatever migration the new reader carries, and a v2
/// fixture joins it. `doc-28`: the fixtures live for ever.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_formats/flutter3d_formats.dart';
import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

import 'fixture_project.dart';

Uint8List fixtureBytes(int version) =>
    File('test/fixtures/v$version/workshop.f3dproj').readAsBytesSync();

ModelProject fixtureOpened(int version) {
  final read = readProject(fixtureBytes(version));
  if (read case ProjectOpened(:final ModelProject project)) return project;
  fail(
    'the v$version fixture no longer opens: '
    '${(read as ProjectRefused).because}',
  );
}

void main() {
  group('the version 1 fixture', () {
    test('is still a project file this build recognises', () {
      final bytes = fixtureBytes(1);

      expect(isProjectFile(bytes), isTrue);
      expect(
        ByteData.sublistView(bytes).getUint32(4, Endian.little),
        1,
        reason: 'the file records the version it was written by',
      );
    });

    test('its checksums still agree with its sections', () {
      // The sums were computed by the build that minted it. They are checked
      // here by this one, so a change to `crc32` or to how a section is laid
      // out shows up as a damaged file rather than as nothing at all.
      expect(readProject(fixtureBytes(1)), isA<ProjectOpened>());
    });

    test('the objects come back with their names, places and parents', () {
      final project = fixtureOpened(1);

      expect(project.objects.map((ModelObject o) => o.name), <String>[
        'body',
        'lid',
        'arrived',
      ]);
      expect(project.objects[0].transform.getTranslation(), Vector3(1, 2, 3));
      expect(project.objects[1].parent, project.objects[0].id);
      // Ahead of the count, because an object was added and deleted before the
      // file was written. A reader that counted the objects instead of reading
      // the number would hand out an id that history already names.
      expect(project.nextId, 5);
      expect(project.objects[1].version, 2);
    });

    test('a cylinder still knows it is a cylinder', () {
      final geometry = fixtureOpened(1).objects[0].geometry;

      // The one thing a glTF cannot hold, and the whole reason this format
      // exists. A fixture that came back as triangles would mean the
      // parameters had quietly stopped surviving a save.
      expect(geometry, isA<ParametricGeometry>());
      final shape = (geometry as ParametricGeometry).shape;
      expect(shape, isA<ParametricCylinder>());
      final cylinder = shape as ParametricCylinder;
      expect(cylinder.segments, 12);
      expect(cylinder.radiusTop, 0.25);
      expect(cylinder.radiusBottom, 0.75);
      expect(cylinder.height, 2.5);
      expect(cylinder.capped, isFalse);
    });

    test('an edited mesh comes back with its topology', () {
      final geometry = fixtureOpened(1).objects[1].geometry;

      expect(geometry, isA<EditedGeometry>());
      final mesh = (geometry as EditedGeometry).mesh;
      expect(mesh.faceCount, 6);
      expect(geometry.triangleCount, 12);
    });

    test('imported buffers come back byte for byte', () {
      final geometry = fixtureOpened(1).objects[2].geometry;

      expect(geometry, isA<ImportedGeometry>());
      final mesh = (geometry as ImportedGeometry).data;
      // Against the source the fixture was minted from, so that changing the
      // fixture project cannot leave this passing about the wrong numbers.
      expect(mesh.vertices, fixtureImported().vertices);
      expect(mesh.indices, fixtureImported().indices);
      expect(
        mesh.layout.attributes.map((VertexAttribute a) => a.name),
        <String>['position', 'normal'],
      );
    });

    test('the paint and the image it samples both survive', () {
      final project = fixtureOpened(1);
      final material = project.materials.single;

      expect(material.version, 3);
      expect(material.surface.name, 'brass');
      expect(material.surface.metallic, 0.75);
      expect(material.surface.alphaMode, SurfaceAlphaMode.mask);
      expect(material.surface.alphaCutoff, 0.875);
      expect(material.surface.doubleSided, isTrue);

      final binding = material.surface.baseColorTexture!;
      expect(binding.imageIndex, 0);
      expect(binding.sampling.useMipmaps, isFalse);
      expect(binding.sampling.wrapS, TextureWrap.clampToEdge);

      expect(project.images.single.bytes, <int>[1, 2, 3, 4, 5]);
      expect(project.images.single.name, 'atlas');
      expect(project.images.single.mimeType, 'image/png');

      // Two objects on one row, which is the thing a table exists for.
      expect(project.objects[0].materialSlots, <int>[0]);
      expect(project.objects[1].materialSlots, <int>[0]);
    });

    test('it holds what the fixture project holds, field for field', () {
      final fromFile = fixtureOpened(1);
      final fromSource = fixtureProject();

      // The two are built by different routes — one read off a disk, one
      // constructed in this file — and every claim above is about one of them
      // in isolation. This is the claim that they are the same document, which
      // is what makes `fixture_project.dart` the readable half of the blob.
      expect(fromFile.objects.length, fromSource.objects.length);
      expect(fromFile.nextId, fromSource.nextId);
      expect(fromFile.triangleCount, fromSource.triangleCount);
      expect(fromFile.materials.length, fromSource.materials.length);
      expect(fromFile.images.length, fromSource.images.length);
      expect(fromFile.profile, fromSource.profile);
      for (var i = 0; i < fromSource.objects.length; i++) {
        expect(fromFile.objects[i].name, fromSource.objects[i].name);
        expect(fromFile.objects[i].id, fromSource.objects[i].id);
        expect(fromFile.objects[i].parent, fromSource.objects[i].parent);
        expect(
          fromFile.objects[i].transform.storage,
          fromSource.objects[i].transform.storage,
        );
      }
    });
  });

  test('every fixture directory is a version this build can read', () {
    final directory = Directory('test/fixtures');
    final versions = <int>[
      for (final FileSystemEntity each in directory.listSync())
        if (each is Directory)
          int.parse(each.path.split(Platform.pathSeparator).last.substring(1)),
    ]..sort();

    // Not a written-down list, so that adding `v2/` without a test for it is
    // caught here rather than noticed years later. Mutation: read only v1 by
    // name and a fixture directory nobody wired up sits there passing.
    expect(versions, isNotEmpty);
    for (final int version in versions) {
      expect(
        version,
        lessThanOrEqualTo(kProjectVersion),
        reason: 'a fixture from a version this build cannot read',
      );
      expect(fixtureOpened(version).objects, isNotEmpty);
    }

    // The other direction, and the one `doc-28` actually asks for: a bump
    // with no fixture is a red test, not a silent gap somebody notices when
    // an old file stops opening on somebody else's machine. Mutation: drop
    // this assertion and bump `kProjectVersion` to 2 with no `v2/` — every
    // check above still passes, since there is nothing at version 2 to be
    // wrong about.
    expect(
      versions,
      contains(kProjectVersion),
      reason:
          'kProjectVersion is $kProjectVersion and test/fixtures has no '
          'v$kProjectVersion/ — a version bump needs a fixture minted at the '
          'moment it happens, not after',
    );
  });
}
