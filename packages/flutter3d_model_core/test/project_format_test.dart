/// The project's own file, written and opened again.
///
///     dart test test/project_format_test.dart
///
/// **The container is forged by hand here rather than by the writer.** Every
/// refusal below needs a file the writer would never produce — a magic from
/// another format, a section that runs off the end, a mesh table pointing at
/// nothing — and a test that could only build files through `writeProject`
/// could not reach any of them. [fileOf] is therefore a second, independent
/// implementation of the same twelve lines of layout, which is also what makes
/// the alignment test worth reading: when the two disagree, one of them is
/// wrong and the numbers say which.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_geometry/flutter3d_geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_mesh/testing.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:flutter3d_model_core/src/project_format.dart';
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart';

/// A cylinder that is nobody's default: every parameter is off the constructor's
/// value, so a parameter dropped on the way through the file shows up as itself
/// rather than as the number it would have had anyway.
const ParametricCylinder cylinder = ParametricCylinder(
  radiusTop: 0.25,
  radiusBottom: 0.75,
  height: 2.5,
  segments: 12,
  capped: false,
);

/// A project with the three things a format has to survive: a shape that still
/// knows its parameters, a mesh that has been edited, and a child that hangs
/// under one of them.
///
/// The fourth object is added and removed, so `nextId` is 5 while the file
/// holds three objects — which is the trap the round-trip test is set for.
ModelProject sample() {
  final project = const ModelProject()
      .added(
        (int id) => ModelObject(
          id: id,
          name: 'body',
          geometry: ParametricGeometry(cylinder),
          transform: Matrix4.identity(),
          materialSlots: <int>[0, 1],
        ),
      )
      .added(
        (int id) => ModelObject(
          id: id,
          name: 'lid',
          geometry: EditedGeometry(EditMesh.cuboid(size: Vector3(2, 1, 3))),
          transform: Matrix4.translationValues(1, 2, 3),
        ),
      )
      .added(
        (int id) => ModelObject(
          id: id,
          name: 'handle',
          geometry: EditedGeometry(extrudedBox()),
          transform: Matrix4.rotationY(0.6)..setTranslation(Vector3(0, 0.5, 0)),
          parent: 2,
        ),
      )
      .added(
        (int id) => ModelObject(
          id: id,
          name: 'doomed',
          geometry: ParametricGeometry(const ParametricSphere()),
          transform: Matrix4.identity(),
        ),
      )
      .removed(4);
  // A second version on one object, so a file that wrote 1 everywhere would be
  // caught rather than agreeing with the default.
  return project.withObject(project.objects[1].copyWith(name: 'lid'));
}

/// The project [bytes] hold, or the failure the refusal describes.
ModelProject opened(Uint8List bytes) {
  final read = readProject(bytes);
  if (read case ProjectOpened(:final ModelProject project)) return project;
  fail(
    'expected a project, and it refused: ${(read as ProjectRefused).because}',
  );
}

/// The sentence [bytes] are refused with, or a failure if they were read.
String refusal(Uint8List bytes) {
  final read = readProject(bytes);
  if (read case ProjectRefused(:final String because)) return because;
  fail('expected a refusal and the file was read');
}

int align(int value) => (value + 3) & ~3;

/// The section directory of [file], as it is on disk.
List<({int kind, int offset, int length, int count})> directoryOf(
  Uint8List file,
) {
  final view = ByteData.sublistView(file);
  final entries = <({int kind, int offset, int length, int count})>[];
  for (var i = 0; i < view.getUint32(8, Endian.little); i++) {
    final at = kProjectHeaderBytes + i * kProjectSectionEntryBytes;
    entries.add((
      kind: view.getUint32(at, Endian.little),
      offset: view.getUint32(at + 4, Endian.little),
      length: view.getUint32(at + 8, Endian.little),
      count: view.getUint32(at + 12, Endian.little),
    ));
  }
  return entries;
}

/// The sections of [file], kind and bytes, in the order the directory lists.
List<(int, Uint8List, int)> sectionsOf(
  Uint8List file,
) => <(int, Uint8List, int)>[
  for (final entry in directoryOf(file))
    (
      entry.kind,
      Uint8List.sublistView(file, entry.offset, entry.offset + entry.length),
      entry.count,
    ),
];

/// A container built from [sections], optionally claiming in its header to hold
/// more of them than it does.
///
/// The magic and the version are not options here: a test that wants either of
/// them wrong writes over the four bytes of a real file, which is nearer to
/// what a wrong file is.
Uint8List fileOf(List<(int, Uint8List, int)> sections, {int? claimSections}) {
  final offsets = <int>[];
  var at = align(
    kProjectHeaderBytes + sections.length * kProjectSectionEntryBytes,
  );
  for (final (_, data, _) in sections) {
    offsets.add(at);
    at = align(at + data.length);
  }

  final out = Uint8List(at);
  final view = ByteData.sublistView(out);
  view
    ..setUint32(0, kProjectMagic, Endian.little)
    ..setUint32(4, kProjectVersion, Endian.little)
    ..setUint32(8, claimSections ?? sections.length, Endian.little)
    ..setUint32(12, 0, Endian.little);
  for (var i = 0; i < sections.length; i++) {
    final (int kind, Uint8List data, int count) = sections[i];
    final entry = kProjectHeaderBytes + i * kProjectSectionEntryBytes;
    view
      ..setUint32(entry, kind, Endian.little)
      ..setUint32(entry + 4, offsets[i], Endian.little)
      ..setUint32(entry + 8, data.length, Endian.little)
      ..setUint32(entry + 12, count, Endian.little);
    out.setRange(offsets[i], offsets[i] + data.length, data);
  }
  return out;
}

/// One object of a manifest, valid unless the caller breaks a piece of it.
Map<String, Object?> objectJson({
  Map<String, Object?> geometry = const <String, Object?>{
    'kind': 'parametric',
    'shape': 'sphere',
    'radius': 0.5,
    'segments': 8,
    'rings': 4,
  },
}) => <String, Object?>{
  'id': 1,
  'name': 'thing',
  'parent': null,
  'version': 1,
  'transform': <double>[...Matrix4.identity().storage],
  'materialSlots': <int>[],
  'geometry': geometry,
};

/// A file whose manifest is [manifest], plus whatever [extra] sections.
Uint8List forge(
  Object? manifest, [
  List<(int, Uint8List, int)> extra = const <(int, Uint8List, int)>[],
]) => fileOf(<(int, Uint8List, int)>[
  (ProjectSection.manifest, utf8.encode(jsonEncode(manifest)), 0),
  ...extra,
]);

/// A manifest around [objects], shaped the way the reader wants it.
Map<String, Object?> manifestOf(List<Map<String, Object?>> objects) =>
    <String, Object?>{
      'profile': <String, Object?>{
        'name': 'mobile',
        'maxTriangles': 100000,
        'maxJoints': 64,
        'maxInfluences': 4,
        'maxTextureSize': 2048,
      },
      'nextId': 9,
      'objects': objects,
    };

void main() {
  group('the file', () {
    test('a project comes back with every field, ids included', () {
      final before = sample();
      final after = opened(writeProject(before));

      expect(after.profile, before.profile);
      // Mutation: write `objects.length + 1` for `nextId` instead of the
      // project's own — the number looks right on a project nobody has deleted
      // from, and this one has: 5 against 4. An id handed out twice is a step
      // of history that names the wrong object after an undo.
      expect(after.nextId, 5);
      expect(after.objects.length, 3);

      for (var i = 0; i < after.objects.length; i++) {
        final ModelObject was = before.objects[i];
        final ModelObject now = after.objects[i];
        expect(now.id, was.id);
        expect(now.name, was.name);
        // Mutation: drop `parent` from the manifest and every object comes back
        // at the root, which draws the handle where the lid is not.
        expect(now.parent, was.parent);
        // Mutation: leave `version` out and it reads back as 1, so a viewport
        // that uploads on a version change uploads nothing after a reopen.
        expect(now.version, was.version);
        expect(now.transform.storage, was.transform.storage);
        expect(now.materialSlots, was.materialSlots);
      }

      expect(after.objects[2].parent, 2);
      expect(after.objects[1].version, 2);
      expect(after.objects[0].materialSlots, <int>[0, 1]);

      // The meshes are the same meshes, compared through the one encoding this
      // repository has rather than through a second one written for the test.
      for (final int at in <int>[1, 2]) {
        final EditedGeometry was =
            before.objects[at].geometry as EditedGeometry;
        final EditedGeometry now = after.objects[at].geometry as EditedGeometry;
        expect(now.mesh.toBytes(), was.mesh.toBytes());
      }
    });

    test('a parametric object keeps its parameters', () {
      final read = opened(writeProject(sample())).objects[0].geometry;

      // The whole reason for a format of our own: a cylinder that came back as
      // faces could not be told to have 48 segments instead of 12.
      //
      // Mutation: write the constructor's default 32 for `segments` instead of
      // the shape's own, which is what a parameter table filled in from the
      // wrong side looks like — 32 against 12 here, and a different mesh in the
      // shapes test below.
      expect(read, isA<ParametricGeometry>());
      final ParametricShape shape = (read as ParametricGeometry).shape;
      expect(shape, isA<ParametricCylinder>());
      final ParametricCylinder back = shape as ParametricCylinder;
      expect(back.radiusTop, 0.25);
      expect(back.radiusBottom, 0.75);
      expect(back.height, 2.5);
      expect(back.segments, 12);
      expect(back.capped, isFalse);
    });

    test('every shape this build writes comes back as itself', () {
      // Two claims, because neither is enough alone and shapes have no equality
      // operator to lean on. Byte equality of write → read → write catches a
      // parameter lost on the way in or out; it cannot catch one written wrong
      // in both passes, which is what the mesh comparison is for — a cylinder
      // saved with 32 segments where it had 12 writes the same file twice and
      // builds a different mesh.
      final shapes = <ParametricShape>[
        ParametricCuboid(size: Vector3(2, 3, 4)),
        const ParametricPlane(
          width: 3,
          depth: 5,
          widthSegments: 2,
          depthSegments: 7,
        ),
        ParametricLathe(
          profile: <Vector2>[Vector2(0, 0), Vector2(0.4, 0.2), Vector2(0, 0.9)],
          segments: 9,
          startAngle: 0.25,
          sweepAngle: 3,
          name: 'goblet',
        ),
        const ParametricSphere(radius: 0.7, segments: 9, rings: 5),
        cylinder,
        const ParametricTorus(
          radius: 0.4,
          tubeRadius: 0.1,
          segments: 7,
          tubeSegments: 5,
        ),
      ];

      for (final ParametricShape shape in shapes) {
        final project = const ModelProject().added(
          (int id) => ModelObject(
            id: id,
            name: shape.name,
            geometry: ParametricGeometry(shape),
            transform: Matrix4.identity(),
          ),
        );
        final bytes = writeProject(project);
        final ModelProject back = opened(bytes);
        expect(writeProject(back), bytes, reason: shape.name);
        expect(
          (back.objects.single.geometry as ParametricGeometry).shape
              .toEditMesh()
              .toBytes(),
          shape.toEditMesh().toBytes(),
          reason: shape.name,
        );
      }
    });

    test('the same project writes the same bytes', () {
      // A file that changes when the document did not is a file nobody can
      // diff, and an autosave that dirties a repository for nothing.
      expect(writeProject(sample()), writeProject(sample()));
      expect(
        writeProject(opened(writeProject(sample()))),
        writeProject(sample()),
      );
    });

    test('everything lands on a four-byte boundary', () {
      final bytes = writeProject(sample());
      final directory = directoryOf(bytes);

      // The numbers this project's file actually lands on: a 16-byte header and
      // three 16-byte directory entries put the manifest at 64, and the
      // manifest is 838 bytes, which ends at 902 and is not a multiple of four.
      // So the mesh table starts at 904, two bytes of padding later. Those two
      // bytes are the whole test — a reader building an `Int32List.view` over
      // the blob throws on an offset that is not a multiple of four, and it
      // throws on the machine of whoever opens the file rather than here.
      expect(directory.map((entry) => entry.kind), <int>[
        ProjectSection.manifest,
        ProjectSection.editMeshes,
        ProjectSection.blob,
      ]);
      expect(directory[0].offset, 64);
      expect(directory[0].length, 838);
      expect(directory[1].offset, 904);
      expect(directory[1].length, 16);
      expect(directory[1].count, 2);
      expect(directory[2].offset, 920);
      expect(bytes.length, 3496);

      for (final entry in directory) {
        expect(entry.offset % 4, 0, reason: 'section ${entry.kind}');
      }

      // Mutation: return `value` from the writer's `_align` and the table lands
      // at 902 with the blob behind it at 918; the assertions above and the two
      // below go red together.
      final view = ByteData.sublistView(bytes);
      final blob = directory[2];
      for (var i = 0; i < directory[1].length ~/ kProjectMeshEntryBytes; i++) {
        final at = view.getUint32(
          directory[1].offset + i * kProjectMeshEntryBytes,
          Endian.little,
        );
        expect(at % 4, 0, reason: 'mesh $i inside the blob');
        expect((blob.offset + at) % 4, 0, reason: 'mesh $i in the file');
      }
      expect(bytes.length % 4, 0);
    });

    test('the constants are written down rather than counted', () {
      // Every record is a whole number of four-byte fields, which is what lets
      // the layout above hold; and the kinds are numbers chosen once, because
      // they are in every file already saved.
      expect(kProjectHeaderBytes % 4, 0);
      expect(kProjectSectionEntryBytes % 4, 0);
      expect(kProjectMeshEntryBytes % 4, 0);
      expect(
        <int>{
          ProjectSection.manifest,
          ProjectSection.editMeshes,
          ProjectSection.blob,
        },
        <int>{1, 2, 3},
      );
      expect(kProjectMagic, 0x50443346);
    });
  });

  group('what it steps over', () {
    test('a section this build has never heard of is skipped', () {
      final bytes = writeProject(sample());
      final sections = sectionsOf(bytes);
      // In the middle, which is the case that matters: a reader that stepped
      // over it by guessing a length rather than by reading one would land
      // inside the blob and refuse a file that is fine.
      final withStranger = fileOf(<(int, Uint8List, int)>[
        sections[0],
        (4242, Uint8List.fromList(utf8.encode('a section from later')), 3),
        ...sections.skip(1),
      ]);

      // Mutation: refuse an unknown kind in the reader — a defensible-looking
      // guard — and this goes red while every other test stays green, which is
      // exactly how a build that adds a materials section locks out the build
      // before it.
      final project = opened(withStranger);
      expect(project.objects.length, 3);
      expect(project.nextId, 5);
      expect(
        (project.objects[1].geometry as EditedGeometry).mesh.toBytes(),
        (sample().objects[1].geometry as EditedGeometry).mesh.toBytes(),
      );
    });
  });

  group('what it refuses, and each in its own words', () {
    // Mutation: the four header guards below were taken out together, and each
    // of these four tests went red on its own account — the short file and the
    // runaway directory with `RangeError (byteOffset)` out of `readProject`
    // itself, the foreign magic and the future version by reading a file that
    // should have been refused. A reader that throws is a reader an application
    // has to wrap in a try, and the sentence is then a stack trace.
    test('a file too short to hold a header', () {
      expect(
        refusal(Uint8List.sublistView(writeProject(sample()), 0, 8)),
        'A project file starts with a 16-byte header and this one is 8 bytes '
        'long.',
      );
    });

    test('a file that is not one of ours', () {
      final bytes = writeProject(sample());
      ByteData.sublistView(bytes).setUint32(0, 0x0A443346, Endian.little);
      // `.f3d`'s own magic, which is the mistake somebody actually makes.
      expect(
        refusal(bytes),
        'Not a project file: it begins 0xa443346 where a project begins '
        '0x50443346, which is "F3DP".',
      );
    });

    test('a file from a version that has not been written yet', () {
      final bytes = writeProject(sample());
      ByteData.sublistView(
        bytes,
      ).setUint32(4, kProjectVersion + 1, Endian.little);
      expect(
        refusal(bytes),
        'This project was written by version 2 and this build reads version 1. '
        'Open it in a newer build; there is nothing here that can guess what it '
        'added.',
      );
    });

    test('a directory that runs past the end of the file', () {
      // The header says a hundred sections and there is room for three, so the
      // directory itself is off the end — a different sentence from a section
      // being off the end, because nothing in the file can be trusted yet.
      final bytes = fileOf(
        sectionsOf(writeProject(sample())),
        claimSections: 500,
      );
      expect(
        refusal(bytes),
        'The header claims 500 sections, whose directory ends at byte 8016, '
        'past the end of a 3496-byte file.',
      );
    });

    test('a section that runs past the end of the file', () {
      // Mutation: drop the per-section check and the truncated file is refused
      // three layers further in, as 'Edited mesh 1 cannot be read: Invalid
      // value' — a sentence that sends whoever reads it after the wrong thing.
      final whole = writeProject(sample());
      final cut = Uint8List.sublistView(whole, 0, whole.length - 8);
      expect(
        refusal(cut),
        'Section 3 runs from byte 920 for 2576 bytes, past the end of a '
        '3488-byte file.',
      );
    });

    test('a file with no manifest in it', () {
      expect(
        refusal(fileOf(const <(int, Uint8List, int)>[])),
        'This file has no manifest section, so nothing in it says what the '
        'objects are.',
      );
    });

    test('a manifest that is not JSON', () {
      expect(
        refusal(
          fileOf(<(int, Uint8List, int)>[
            (
              ProjectSection.manifest,
              Uint8List.fromList(utf8.encode('{ this is not JSON')),
              0,
            ),
          ]),
        ),
        startsWith('The manifest is not JSON:'),
      );
    });

    test('a manifest that is JSON and is not a project', () {
      expect(
        refusal(forge(<String, Object?>{'objects': <Object?>[]})),
        'The manifest is not shaped like a project: it needs a profile with '
        'its five limits, the nextId, and a list of objects.',
      );
    });

    test('an object missing a field', () {
      expect(
        refusal(
          forge(
            manifestOf(<Map<String, Object?>>[
              <String, Object?>{'id': 1, 'name': 'half an object'},
            ]),
          ),
        ),
        'Object 0 in the manifest is missing a field or has one of the wrong '
        'type: an object is an id, a name, a parent, a version, a transform, '
        'its material slots and its geometry.',
      );
    });

    test('an object whose transform is not a matrix', () {
      final object = objectJson()..['transform'] = <double>[1, 0, 0];
      expect(
        refusal(forge(manifestOf(<Map<String, Object?>>[object]))),
        'Object 0 ("thing") has a transform of 3 entries, and a matrix is '
        'sixteen numbers.',
      );
    });

    test('an object made of something this build does not know', () {
      expect(
        refusal(
          forge(
            manifestOf(<Map<String, Object?>>[
              objectJson(geometry: const <String, Object?>{'kind': 'sculpted'}),
            ]),
          ),
        ),
        'Object 0 ("thing") has geometry of kind "sculpted", which this build '
        'does not know how to read.',
      );
    });

    test('a parametric shape from a later build', () {
      expect(
        refusal(
          forge(
            manifestOf(<Map<String, Object?>>[
              objectJson(
                geometry: const <String, Object?>{
                  'kind': 'parametric',
                  'shape': 'helix',
                  'turns': 3,
                },
              ),
            ]),
          ),
        ),
        'Object 0 ("thing") is a parametric "helix", and this build knows '
        'cuboid, plane, lathe, sphere, cylinder, torus.',
      );
    });

    test('a parametric shape missing a parameter', () {
      // A shape this build does know, written without its segments. Guessing
      // 32 here would give back a cylinder that is not the saved one, and the
      // person who finds out is the one who exports it.
      expect(
        refusal(
          forge(
            manifestOf(<Map<String, Object?>>[
              objectJson(
                geometry: const <String, Object?>{
                  'kind': 'parametric',
                  'shape': 'sphere',
                  'radius': 0.5,
                  'rings': 4,
                },
              ),
            ]),
          ),
        ),
        'Object 0 ("thing") is a parametric "sphere" whose parameters are '
        'missing or are not numbers.',
      );
    });

    test('an object naming a mesh the file does not hold', () {
      // Mutation: keep the type check and drop `at >= meshes.length`, which is
      // the half somebody removes as obviously redundant, and the reader throws
      // `RangeError (length)` at the caller instead of refusing the file.
      expect(
        refusal(
          forge(
            manifestOf(<Map<String, Object?>>[
              objectJson(
                geometry: const <String, Object?>{'kind': 'edited', 'mesh': 3},
              ),
            ]),
          ),
        ),
        'Object 0 ("thing") is edited mesh 3 and this file holds 0.',
      );
    });

    test('a mesh entry that runs past the end of the blob', () {
      // Mutation: drop the range check and the file is still refused — the
      // decoder throws on the short view and the catch turns it into a
      // sentence — but the sentence blames the mesh's bytes for a table entry
      // that is the thing pointing off the end. The guard buys the right
      // sentence rather than the refusal.
      final table = Uint8List(kProjectMeshEntryBytes);
      ByteData.sublistView(table)
        ..setUint32(0, 0, Endian.little)
        ..setUint32(4, 64, Endian.little);
      expect(
        refusal(
          forge(manifestOf(<Map<String, Object?>>[]), <(int, Uint8List, int)>[
            (ProjectSection.editMeshes, table, 1),
            (ProjectSection.blob, Uint8List(8), 0),
          ]),
        ),
        'Edited mesh 0 runs from byte 0 of the blob for 64 bytes, and the blob '
        'is 8 bytes long.',
      );
    });

    test('a mesh whose bytes are not a mesh', () {
      // Mutation: narrow the catch to `StateError` and `EditMesh.fromBytes`
      // throws its own 'not an editable mesh' out through `readProject`, which
      // is the rule this file is built on broken in one word.
      final table = Uint8List(kProjectMeshEntryBytes);
      ByteData.sublistView(table)
        ..setUint32(0, 0, Endian.little)
        ..setUint32(4, 8, Endian.little);
      expect(
        refusal(
          forge(manifestOf(<Map<String, Object?>>[]), <(int, Uint8List, int)>[
            (ProjectSection.editMeshes, table, 1),
            (ProjectSection.blob, Uint8List(8), 0),
          ]),
        ),
        startsWith('Edited mesh 0 cannot be read: not an editable mesh'),
      );
    });

    test('an object holding buffers the format has no section for', () {
      // At the write, not at the read: the file has nowhere to put them yet,
      // and a save that quietly loses an object is worse than one that stops.
      final project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'imported',
          geometry: ImportedGeometry(
            MeshData(
              layout: VertexLayout.positionOnly,
              vertices: Float32List.fromList(<double>[
                0,
                0,
                0,
                1,
                0,
                0,
                0,
                1,
                0,
              ]),
              indices: Uint32List.fromList(<int>[0, 1, 2]),
            ),
          ),
          transform: Matrix4.identity(),
        ),
      );
      expect(
        () => writeProject(project),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains('has no section for them'),
          ),
        ),
      );
    });
  });
}
