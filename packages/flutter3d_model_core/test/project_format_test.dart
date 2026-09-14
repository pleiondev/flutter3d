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

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:flutter3d_mesh/testing.dart';
import 'package:flutter3d_model_core/flutter3d_model_core.dart';
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

/// A project that skins one object to a skeleton, keys the skeleton's own
/// joint with an animation clip, and gives the skinned object a shape key —
/// `anim-03`/`anim-19`'s own round trip, all three at once, every field away
/// from a default a dropped one could be mistaken for.
ModelProject riggedSample() {
  var project = const ModelProject().added(
    (int id) => ModelObject(
      id: id,
      name: 'root',
      geometry: const SocketGeometry(),
      transform: Matrix4.identity(),
    ),
  );
  final rootId = project.objects.single.id;
  final mesh = EditMesh.cuboid();
  project = project.added(
    (int id) => ModelObject(
      id: id,
      name: 'body',
      geometry: EditedGeometry(mesh),
      transform: Matrix4.identity(),
      skeletonIndex: 0,
      shapeSet: ShapeSet(
        keys: <ShapeKey>[
          ShapeKey(
            'smile',
            Float32List.fromList(<double>[
              for (var v = 0; v < mesh.vertexSlotCount; v++) ...<double>[
                v * 0.1,
                v * 0.2,
                v * 0.3,
              ],
            ]),
          ),
        ],
        weights: <double>[0.75],
      ),
    ),
  );
  return project.copyWith(
    skeletons: <ProjectSkeleton>[
      ProjectSkeleton(
        name: 'rig',
        joints: <int>[rootId],
        inverseBindMatrices: <Matrix4>[Matrix4.translation(Vector3(0, 1, 0))],
        skeletonRoot: rootId,
      ),
    ],
    clips: <ProjectClip>[
      ProjectClip(
        name: 'wave',
        extras: const <String, Object?>{'author': 'a rigger'},
        tracks: <ProjectTrack>[
          ProjectTrack(
            objectId: rootId,
            track: AnimationTrack(
              nodeIndex: 0,
              path: AnimationPath.translation,
              interpolation: AnimationInterpolation.linear,
              componentCount: 3,
              times: Float32List.fromList(<double>[0, 1]),
              values: Float32List.fromList(<double>[0, 0, 0, 1, 2, 3]),
            ),
          ),
        ],
      ),
    ],
  );
}

/// The project [bytes] hold, or the failure the refusal describes.
ModelProject opened(Uint8List bytes) {
  final read = readProject(bytes);
  if (read case ProjectOpened(:final ModelProject project)) return project;
  fail(
    'expected a project, and it refused: ${(read as ProjectRefused).because}',
  );
}

/// What opening [bytes] warned about, or the failure the refusal describes.
List<String> warningsOf(Uint8List bytes) {
  final read = readProject(bytes);
  if (read case ProjectOpened(:final List<String> warnings)) return warnings;
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

  // The header's fourth field is the sum of the checksum table, when there is
  // one. Computed here rather than copied, because this helper is a second
  // implementation of the layout and a copied number would make it agree with
  // the writer by construction rather than by being right.
  final checksums = sections
      .where(((int, Uint8List, int) s) => s.$1 == ProjectSection.checksums)
      .map(((int, Uint8List, int) s) => s.$2);

  final out = Uint8List(at);
  final view = ByteData.sublistView(out);
  view
    ..setUint32(0, kProjectMagic, Endian.little)
    ..setUint32(4, kProjectVersion, Endian.little)
    ..setUint32(8, claimSections ?? sections.length, Endian.little)
    ..setUint32(
      kProjectChecksumOffset,
      checksums.isEmpty ? 0 : crc32(checksums.first),
      Endian.little,
    );
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

    test('a skeleton, a clip and a shape key all survive the round trip — '
        "anim-03/anim-19's own gap", () {
      final before = riggedSample();
      final after = opened(writeProject(before));

      expect(after.skeletons, hasLength(1));
      final skeletonBefore = before.skeletons.single;
      final skeletonAfter = after.skeletons.single;
      expect(skeletonAfter.name, skeletonBefore.name);
      // Mutation: drop `skeletonRoot`/`name` from `_skeletonJson` and both
      // come back null — this fixture would not notice unless both are
      // set to something a default could not produce by accident.
      expect(skeletonAfter.skeletonRoot, skeletonBefore.skeletonRoot);
      expect(skeletonAfter.joints, skeletonBefore.joints);
      expect(skeletonAfter.inverseBindMatrices, hasLength(1));
      for (var i = 0; i < 16; i++) {
        expect(
          skeletonAfter.inverseBindMatrices[0].storage[i],
          closeTo(skeletonBefore.inverseBindMatrices[0].storage[i], 1e-9),
        );
      }

      expect(after.clips, hasLength(1));
      final clipBefore = before.clips.single;
      final clipAfter = after.clips.single;
      expect(clipAfter.name, clipBefore.name);
      expect(clipAfter.extras, clipBefore.extras);
      expect(clipAfter.tracks, hasLength(1));
      final trackBefore = clipBefore.tracks.single.track;
      final trackAfter = clipAfter.tracks.single.track;
      expect(
        clipAfter.tracks.single.objectId,
        clipBefore.tracks.single.objectId,
      );
      expect(trackAfter.path, trackBefore.path);
      expect(trackAfter.interpolation, trackBefore.interpolation);
      expect(trackAfter.componentCount, trackBefore.componentCount);
      expect(trackAfter.times, trackBefore.times);
      expect(trackAfter.values, trackBefore.values);

      final bodyBefore = before.objects.firstWhere((o) => o.name == 'body');
      final bodyAfter = after.objects.firstWhere((o) => o.name == 'body');
      // Mutation: read `skeletonIndex` back as `null` unconditionally and
      // this fails directly — the object would read as unskinned.
      expect(bodyAfter.skeletonIndex, bodyBefore.skeletonIndex);
      expect(bodyAfter.shapeSet.keys, hasLength(1));
      expect(bodyAfter.shapeSet.keys.single.name, 'smile');
      expect(bodyAfter.shapeSet.weights, bodyBefore.shapeSet.weights);
      expect(
        bodyAfter.shapeSet.keys.single.positions,
        bodyBefore.shapeSet.keys.single.positions,
      );

      // The plain, unrigged objects in `sample()` still read back with no
      // skeleton and no shape keys — the absent case is `null`/empty, not
      // some other default a dropped field could be mistaken for.
      final plain = opened(writeProject(sample())).objects.first;
      expect(plain.skeletonIndex, isNull);
      expect(plain.shapeSet.isEmpty, isTrue);
    });

    test("an object's own levels of detail survive the round trip — "
        "pro-lod-03's own gap", () {
      final baseProject = sample();
      final before = baseProject.withObject(
        baseProject.objects.first.copyWith(
          lods: const <LodSpec>[
            LodSpec(ratio: 0.5, maxScreenFraction: 0.3),
            LodSpec(ratio: 0.1, maxScreenFraction: 0.05),
          ],
        ),
      );

      final after = opened(writeProject(before));
      final bodyBefore = before.objects.first;
      final bodyAfter = after.objects.first;

      // Mutation: drop `lods` from `objectsJsonFor`'s own map and this
      // reads back empty, since an absent key and a genuinely empty list
      // are indistinguishable once dropped.
      expect(bodyAfter.lods, hasLength(2));
      for (var i = 0; i < 2; i++) {
        expect(bodyAfter.lods[i].ratio, bodyBefore.lods[i].ratio);
        expect(
          bodyAfter.lods[i].maxScreenFraction,
          bodyBefore.lods[i].maxScreenFraction,
        );
      }

      // The other objects in `sample()` never had a LOD added — the
      // absent case is an empty list, not some other default a dropped
      // field could be mistaken for.
      final plain = opened(writeProject(sample())).objects.first;
      expect(plain.lods, isEmpty);
    });

    test("an object's own shape drivers survive the round trip — "
        "anim-34d's own gap", () {
      final baseProject = sample();
      final before = baseProject.withObject(
        baseProject.objects.first.copyWith(
          shapeDrivers: const <ShapeDriver>[
            ShapeDriver(
              shapeIndex: 2,
              jointId: 3,
              axis: DriverAxis.y,
              from: 0.1,
              to: 1.2,
            ),
            ShapeDriver(
              shapeIndex: 0,
              jointId: 1,
              axis: DriverAxis.z,
              from: -0.3,
              to: 0.4,
            ),
          ],
        ),
      );

      final after = opened(writeProject(before));
      final bodyBefore = before.objects.first;
      final bodyAfter = after.objects.first;

      // Mutation: drop `shapeDrivers` from `objectsJsonFor`'s own map and
      // this reads back empty, since an absent key and a genuinely empty
      // list are indistinguishable once dropped.
      expect(bodyAfter.shapeDrivers, hasLength(2));
      for (var i = 0; i < 2; i++) {
        expect(
          bodyAfter.shapeDrivers[i].shapeIndex,
          bodyBefore.shapeDrivers[i].shapeIndex,
        );
        expect(
          bodyAfter.shapeDrivers[i].jointId,
          bodyBefore.shapeDrivers[i].jointId,
        );
        expect(
          bodyAfter.shapeDrivers[i].axis.name,
          bodyBefore.shapeDrivers[i].axis.name,
        );
        expect(bodyAfter.shapeDrivers[i].from, bodyBefore.shapeDrivers[i].from);
        expect(bodyAfter.shapeDrivers[i].to, bodyBefore.shapeDrivers[i].to);
      }

      // The other objects in `sample()` never had a driver added — the
      // absent case is an empty list, not some other default a dropped
      // field could be mistaken for.
      final plain = opened(writeProject(sample())).objects.first;
      expect(plain.shapeDrivers, isEmpty);
    });

    test('an object written before anim-34d — no shapeDrivers key at all — '
        'reads back with an empty list rather than throwing', () {
      final after = opened(
        forge(manifestOf(<Map<String, Object?>>[objectJson()])),
      );
      expect(after.objects.single.shapeDrivers, isEmpty);
    });

    test('a socket writes and reads back with no mesh behind it', () {
      final before = ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'weapon mount',
          geometry: const SocketGeometry(),
          transform: Matrix4.translation(Vector3(0.0, 1.4, 0.2)),
        ),
      );

      final after = opened(writeProject(before));

      // Mutation: fall through to the `default` clause instead of a `case
      // 'socket':` in `_readGeometry` and this object refuses to open at
      // all — "geometry of kind socket, which this build does not know
      // how to read" — for a file this same build wrote.
      expect(after.objects.single.geometry, isA<SocketGeometry>());
      expect(after.objects.single.geometry.triangleCount, 0);
      expect(
        after.objects.single.transform.getTranslation(),
        Vector3(0.0, 1.4, 0.2),
      );
    });

    test('a profile keeps the fields doc-13 added, not just the original '
        'five', () {
      // Every one of these is away from the constructor's default, the way
      // `fixtureCylinder` in `fixture_project.dart` is written — a field
      // dropped on the way through the file shows up as itself rather than as
      // the number it would have had anyway.
      const before = ProjectProfile(
        target: ProfileTarget.mobile,
        maxTextureBytes: 12345678,
        requireTriangles: false,
        requireManifold: true,
        textures: TextureBudget.mobile,
        texelsPerMeter: 512.5,
        fps: 24.0,
        frameSnap: true,
      );
      final after = opened(writeProject(ModelProject(profile: before))).profile;

      expect(after, before);
      expect(after.target, ProfileTarget.mobile);
      expect(after.maxTextureBytes, 12345678);
      expect(after.requireTriangles, isFalse);
      expect(after.requireManifold, isTrue);
      expect(after.textures, TextureBudget.mobile);
      expect(after.texelsPerMeter, 512.5);
      expect(after.fps, 24.0);
      expect(after.frameSnap, isTrue);
    });

    test('a manifest written before doc-13 opens with the new fields at '
        'their defaults', () {
      // `manifestOf` is exactly this shape: the five original keys and none
      // of the five this test is about, which is what every project saved
      // before this change looks like on disk. Mutation: require the new
      // keys the way the five original ones are required, and this file —
      // and every real one like it — stops opening at all.
      final read = opened(forge(manifestOf(const <Map<String, Object?>>[])));

      expect(read.profile.target, ProfileTarget.desktop);
      expect(read.profile.maxTextureBytes, isNull);
      expect(read.profile.requireTriangles, isTrue);
      expect(read.profile.requireManifold, isFalse);
      // `textures` is younger than even `target`/`requireTriangles` — a
      // manifest with none of the five still opens with `mat-28`'s own
      // default rather than refusing or reading a budget of zero.
      expect(read.profile.textures, TextureBudget.desktop);
      // `texelsPerMeter` is younger still — `doc-35n`'s own default is
      // null, "nothing measured", not a fabricated number.
      expect(read.profile.texelsPerMeter, isNull);
      // `fps`/`frameSnap` are `syn-03`'s own, younger even than
      // `texelsPerMeter` — a manifest from before either existed opens at
      // 30 fps, unsnapped, the same defaults a fresh project already has.
      expect(read.profile.fps, 30.0);
      expect(read.profile.frameSnap, isFalse);
    });

    test('an unknown texture budget format opens as other, and says so', () {
      final bytes = forge(<String, Object?>{
        ...manifestOf(<Map<String, Object?>>[objectJson()]),
        'profile': <String, Object?>{
          'name': 'x',
          'maxTriangles': 500000,
          'maxJoints': 64,
          'maxInfluences': 4,
          'maxTextureSize': 4096,
          'textures': <String, Object?>{
            'maxSide': 2048,
            'maxBytesOnDevice': 1000,
            'targetFormat': 'bc9',
          },
        },
      });

      final read = readProject(bytes);
      expect(read, isA<ProjectOpened>());
      expect(
        (read as ProjectOpened).project.profile.textures.targetFormat,
        TextureFileFormat.other,
      );
      expect(read.warnings.single, contains('bc9'));
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
      final base = sample();
      // A profile name one character longer than the default `'desktop'`,
      // chosen so this project's manifest lands one byte short of a
      // four-byte multiple. Without it, `doc-35n`'s extra field happens to
      // leave this fixture's manifest already aligned by coincidence, and
      // the padding this test exists to check for never fires — the
      // `_align` call under test could be deleted and every assertion
      // below would still be green.
      final bytes = writeProject(
        ModelProject(
          profile: const ProjectProfile(name: 'desktop!'),
          objects: base.objects,
          materials: base.materials,
          images: base.images,
          nextId: base.nextId,
        ),
      );
      final directory = directoryOf(bytes);

      // The numbers this project's file actually lands on: a 16-byte header and
      // six 16-byte directory entries put the manifest at 112, and the manifest
      // is 1363 bytes (`anim-34d`'s own `shapeDrivers`, written even at its
      // default — absent, the same way every other optional field grown
      // since v1 is — which still costs the twenty bytes of
      // `,"shapeDrivers":null` per object; widened it from the 1303 an
      // earlier version of this fixture measured, itself `pro-lod-03`'s own
      // widening from 1267 for the same reason, one field earlier), which
      // ends at 1475 and is not a multiple of four. So the mesh table starts
      // at 1476, one byte of padding later. That one byte is the whole
      // test — a reader building an `Int32List.view` over the blob throws on
      // an offset that is not a multiple of four, and it throws on the machine
      // of whoever opens the file rather than here.
      expect(directory.map((entry) => entry.kind), <int>[
        ProjectSection.manifest,
        ProjectSection.editMeshes,
        ProjectSection.blob,
        ProjectSection.importedMeshes,
        ProjectSection.images,
        ProjectSection.checksums,
      ]);
      expect(directory[0].offset, 112);
      expect(directory[0].length, 1363);
      expect(directory[1].offset, 1476);
      expect(directory[1].length, 16);
      expect(directory[1].count, 2);
      expect(directory[2].offset, 1492);
      // This project has nothing imported and nothing textured, and both tables
      // are written all the same: every file this build produces has the same
      // five-section directory, so a reader is never deciding between "none of
      // these" and "written by something older".
      expect(directory[3].length, 0);
      expect(directory[4].length, 0);
      // One row per other section, so the table grows with the directory.
      expect(directory[5].count, 5);
      expect(directory[5].length, 5 * kProjectChecksumEntryBytes);
      expect(bytes.length, 4108);

      for (final entry in directory) {
        expect(entry.offset % 4, 0, reason: 'section ${entry.kind}');
      }

      // Mutation: return `value` from the writer's `_align` and the table lands
      // at 1379 with the blob behind it at 1395; the assertions above and the
      // two below go red together.
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
      expect(kProjectImportedEntryBytes % 4, 0);
      expect(kProjectImageEntryBytes % 4, 0);
      expect(kProjectChecksumEntryBytes % 4, 0);
      expect(
        <int>{
          ProjectSection.manifest,
          ProjectSection.editMeshes,
          ProjectSection.blob,
          ProjectSection.importedMeshes,
          ProjectSection.images,
          ProjectSection.checksums,
        },
        <int>{1, 2, 3, 4, 5, 6},
      );
      expect(kProjectMagic, 0x50443346);
    });
  });

  group('the manifest is canonical JSON', () {
    /// The decoded manifest of [bytes]. `jsonDecode` builds a `LinkedHashMap`
    /// that iterates in the order the keys appeared in the text, which is what
    /// lets a test read the actual written order back out rather than only
    /// the values.
    Map<String, Object?> manifestJsonOf(Uint8List bytes) {
      final section = sectionsOf(bytes).firstWhere(
        ((int, Uint8List, int) s) => s.$1 == ProjectSection.manifest,
      );
      return jsonDecode(utf8.decode(section.$2)) as Map<String, Object?>;
    }

    /// Every object nested anywhere in [value] has its own keys sorted.
    /// Arrays are walked without being asked to be sorted themselves — an
    /// array's order is the data, not a byproduct of how a map was built.
    void expectCanonical(Object? value) {
      switch (value) {
        case final Map<String, Object?> map:
          final keys = map.keys.toList();
          final sorted = <String>[...keys]..sort();
          expect(keys, sorted, reason: 'keys out of order: $keys');
          for (final Object? nested in map.values) {
            expectCanonical(nested);
          }
        case final List<Object?> list:
          for (final Object? nested in list) {
            expectCanonical(nested);
          }
        default:
          break;
      }
    }

    test('every object\'s keys come out sorted, top to bottom', () {
      final project = riggedSample().copyWith(
        materials: <ProjectMaterial>[
          ProjectMaterial(surface: SurfaceMaterial()),
        ],
      );
      expectCanonical(manifestJsonOf(writeProject(project)));
    });

    test('two projects built with fields assembled in a different order '
        'still write byte-identical manifests', () {
      // `ModelProject`'s own constructor takes named parameters in one fixed
      // order regardless of the order an argument list gives them in, so this
      // does not exercise a different code path inside this package — it
      // exercises the guarantee the canonical form is actually for: nothing
      // downstream of the manifest map depends on this file's own functions
      // having built it in one particular order, because the order actually
      // written is sorted, not remembered.
      final a = ModelProject(profile: const ProjectProfile(name: 'x'));
      final b = ModelProject(profile: const ProjectProfile(name: 'x'));
      expect(writeProject(a), writeProject(b));
    });

    test('reading does not care what order the keys were written in', () {
      // Mutation reversed by hand rather than applied to source: a manifest
      // built with `objects` before `profile` — the opposite of both the
      // canonical order and this file's own insertion order — still reads
      // back correctly, because a JSON object is looked up by key.
      final reordered = forge(<String, Object?>{
        'objects': <Object?>[],
        'profile': <String, Object?>{
          'name': 'reordered',
          'maxTriangles': 500000,
          'maxJoints': 64,
          'maxInfluences': 4,
          'maxTextureSize': 4096,
        },
        'nextId': 1,
        'importedMeshes': <Object?>[],
        'materials': <Object?>[],
        'images': <Object?>[],
      });
      expect(opened(reordered).profile.name, 'reordered');
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
        'past the end of a 4108-byte file.',
      );
    });

    test('a section that runs past the end of the file', () {
      // Mutation: drop the per-section check and the truncated file is refused
      // three layers further in, as 'Edited mesh 1 cannot be read: Invalid
      // value' — a sentence that sends whoever reads it after the wrong thing.
      //
      // The section named is the last one in the file, which is the checksum
      // table: a cut takes the tail, whatever the tail happens to be. The claim
      // is that the bounds are checked and the sentence carries the numbers,
      // not that any particular section is the one that goes.
      final whole = writeProject(sample());
      final cut = Uint8List.sublistView(whole, 0, whole.length - 8);
      expect(
        refusal(cut),
        'Section 6 runs from byte 4068 for 40 bytes, past the end of a '
        '4100-byte file.',
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

    test('an object\'s shape keys and weights that do not move together', () {
      final object = objectJson()
        ..['shapeSet'] = <String, Object?>{
          'keys': <Object?>[
            <String, Object?>{
              'name': 'a',
              'positions': <double>[0, 0, 0],
            },
          ],
          'weights': <double>[0.1, 0.2],
        };
      expect(
        refusal(forge(manifestOf(<Map<String, Object?>>[object]))),
        'Object 0 ("thing") has 1 shape keys but 2 weights; those move '
        'together.',
      );
    });

    test('a shape key whose position count is not three a vertex', () {
      final object = objectJson()
        ..['shapeSet'] = <String, Object?>{
          'keys': <Object?>[
            <String, Object?>{
              'name': 'a',
              'positions': <double>[0, 0, 0, 1, 1],
            },
          ],
          'weights': <double>[0.1],
        };
      expect(
        refusal(forge(manifestOf(<Map<String, Object?>>[object]))),
        'Object 0 ("thing")\'s shape key 0 ("a") has 5 position numbers, '
        'and a vertex is three.',
      );
    });

    test('a shape driver missing a field', () {
      final object = objectJson()
        ..['shapeDrivers'] = <Object?>[
          <String, Object?>{'shapeIndex': 0, 'jointId': 1, 'from': 0.0},
        ];
      expect(
        refusal(forge(manifestOf(<Map<String, Object?>>[object]))),
        'Object 0 ("thing")\'s shape driver 0 is missing a field or has one '
        'of the wrong type.',
      );
    });

    test('a track whose times and values do not fit its interpolation and '
        'component count', () {
      final bytes = forge(<String, Object?>{
        ...manifestOf(<Map<String, Object?>>[]),
        'clips': <Object?>[
          <String, Object?>{
            'name': 'broken',
            'tracks': <Object?>[
              <String, Object?>{
                'objectId': 0,
                'path': 'translation',
                'interpolation': 'LINEAR',
                'componentCount': 3,
                'times': <double>[0, 1, 2],
                'values': <double>[0, 0],
              },
            ],
          },
        ],
      });
      expect(
        refusal(bytes),
        'Clip 0, track 0 cannot be read: Track for node 0 has 3 keys and 2 '
        'values; linear interpolation of 3 components needs 9.',
      );
    });

    test('a skeleton\'s joints and inverse bind matrices that do not move '
        'together', () {
      final bytes = forge(<String, Object?>{
        ...manifestOf(<Map<String, Object?>>[objectJson()]),
        'skeletons': <Object?>[
          <String, Object?>{
            'name': 'rig',
            'joints': <int>[1],
            'inverseBindMatrices': <Object?>[],
            'skeletonRoot': null,
          },
        ],
      });
      expect(
        refusal(bytes),
        'Skeleton 0 has 1 joints but 0 inverse bind matrices; those move '
        'together.',
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

    test('an imported mesh with morph targets is refused', () {
      // The one thing an imported mesh can still carry that there is nowhere
      // to write. At the write, not at the read: a save that quietly drops a
      // face's expressions is a loss nothing downstream can detect.
      final project = const ModelProject().added(
        (int id) => ModelObject(
          id: id,
          name: 'face',
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
              morphTargets: <MorphTarget>[
                MorphTarget(
                  vertexCount: 3,
                  positions: Float32List.fromList(<double>[
                    0,
                    1,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                    0,
                  ]),
                ),
              ],
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
            contains('morph targets'),
          ),
        ),
      );
    });
  });

  group('materials and images', () {
    /// A material with every field off its default, so a field dropped on the
    /// way through the file shows up as itself rather than as the number it
    /// would have had anyway.
    SurfaceMaterial painted() => SurfaceMaterial(
      name: 'brass',
      baseColor: Vector4(0.1, 0.2, 0.3, 0.4),
      metallic: 0.75,
      roughness: 0.125,
      baseColorTexture: const TextureBinding(
        imageIndex: 1,
        texCoordSet: 0,
        sampling: TextureSampling(
          magLinear: false,
          minLinear: false,
          useMipmaps: false,
          wrapS: TextureWrap.clampToEdge,
          wrapT: TextureWrap.mirroredRepeat,
        ),
      ),
      normalTexture: const TextureBinding(imageIndex: 0),
      normalScale: 0.625,
      occlusionStrength: 0.375,
      emissive: Vector3(0.05, 0.15, 0.25),
      emissiveStrength: 2.5,
      alphaMode: SurfaceAlphaMode.mask,
      alphaCutoff: 0.875,
      doubleSided: true,
      unlit: true,
      lightingModel: LightingModel.lambert,
    );

    ModelProject painting() =>
        ModelProject(
          materials: <ProjectMaterial>[
            ProjectMaterial(surface: painted(), version: 7),
            ProjectMaterial(surface: SurfaceMaterial(name: 'plain')),
          ],
          images: <EncodedImage>[
            EncodedImage(
              bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
              name: 'normal',
              mimeType: 'image/png',
            ),
            EncodedImage(bytes: Uint8List.fromList(<int>[9, 9])),
          ],
        ).added(
          (int id) => ModelObject(
            id: id,
            name: 'bolt',
            geometry: EditedGeometry(EditMesh.cuboid()),
            transform: Matrix4.identity(),
            materialSlots: const <int>[0],
          ),
        );

    test('every field of a material comes back', () {
      final after = opened(writeProject(painting()));
      final material = after.materials.first;
      final surface = material.surface;

      // Every field is written, including the ones sitting at their default,
      // and the reader's pattern asks for all of them. Mutation: skip a field
      // whose value equals this build's default — the obvious way to make the
      // manifest smaller — and the file stops being readable at all, because a
      // missing key is a material missing a field. Writing them out is also
      // what stops the file's meaning depending on what this build thinks a
      // default is.
      expect(material.version, 7);
      expect(surface.name, 'brass');
      expect(surface.baseColor, Vector4(0.1, 0.2, 0.3, 0.4));
      expect(surface.metallic, 0.75);
      expect(surface.roughness, 0.125);
      expect(surface.normalScale, 0.625);
      expect(surface.occlusionStrength, 0.375);
      expect(surface.emissive, Vector3(0.05, 0.15, 0.25));
      expect(surface.emissiveStrength, 2.5);
      expect(surface.alphaMode, SurfaceAlphaMode.mask);
      expect(surface.alphaCutoff, 0.875);
      expect(surface.doubleSided, isTrue);
      expect(surface.unlit, isTrue);
      expect(surface.lightingModel, LightingModel.lambert);
    });

    test('a material with no lightingModel of its own opens with none, not a '
        'refusal — mat-04 is younger than the rest of this record', () {
      final after = opened(writeProject(painting()));
      expect(after.materials[1].surface.lightingModel, isNull);
    });

    test('a texture binding keeps its image, its set and its sampler', () {
      final after = opened(writeProject(painting()));
      final binding = after.materials.first.surface.baseColorTexture!;

      // Mutation: write the sampler and read it back by index into
      // `TextureWrap.values`. It round-trips today and reinterprets every file
      // already saved the moment a case is inserted into that enum.
      expect(binding.imageIndex, 1);
      expect(binding.sampling.magLinear, isFalse);
      expect(binding.sampling.useMipmaps, isFalse);
      expect(binding.sampling.wrapS, TextureWrap.clampToEdge);
      expect(binding.sampling.wrapT, TextureWrap.mirroredRepeat);
      // A slot the material does not fill stays unfilled, rather than becoming
      // image zero of a table it never named.
      expect(after.materials.first.surface.occlusionTexture, isNull);
      expect(after.materials.first.surface.normalTexture!.imageIndex, 0);
    });

    test('a sampler\'s mipLinear survives, both ways', () {
      // `fmt-05` added this field to `TextureSampling` after the rest of a
      // binding's sampler was already written here — a fixture and a round
      // trip that only ever exercised `false` would not have caught it being
      // silently dropped, so both values get their own project.
      ModelProject withMipLinear(bool value) => ModelProject(
        materials: <ProjectMaterial>[
          ProjectMaterial(
            surface: SurfaceMaterial(
              baseColorTexture: TextureBinding(
                imageIndex: 0,
                sampling: TextureSampling(mipLinear: value),
              ),
            ),
          ),
        ],
        images: <EncodedImage>[
          EncodedImage(bytes: Uint8List.fromList(<int>[1])),
        ],
      );

      // Mutation: never write `mipLinear` at all — `_bindingJson` gains no
      // key, `_bindingFrom` never reads one, and both projects below come
      // back `true` regardless of which was saved.
      expect(
        opened(
          writeProject(withMipLinear(false)),
        ).materials.single.surface.baseColorTexture!.sampling.mipLinear,
        isFalse,
      );
      expect(
        opened(
          writeProject(withMipLinear(true)),
        ).materials.single.surface.baseColorTexture!.sampling.mipLinear,
        isTrue,
      );
    });

    test('a sampler with no mipLinear key opens as the default', () {
      // What every project saved before `fmt-05`'s field existed looks like:
      // the five original sampler keys and none of the sixth. No images
      // section exists in this forged file at all, which is fine —
      // `_readImages` returns empty before it ever looks at what the
      // manifest names, so a texture's `imageIndex` here is free to dangle;
      // nothing about that is what this test is asking.
      final bytes = forge(<String, Object?>{
        ...manifestOf(<Map<String, Object?>>[]),
        'materials': <Object?>[
          <String, Object?>{
            'version': 1,
            'name': null,
            'baseColor': <double>[1, 1, 1, 1],
            'metallic': 0.0,
            'roughness': 0.5,
            'baseColorTexture': <String, Object?>{
              'imageIndex': 0,
              'texCoordSet': 0,
              'magLinear': true,
              'minLinear': true,
              'useMipmaps': true,
              'wrapS': 'repeat',
              'wrapT': 'repeat',
            },
            'metallicRoughnessTexture': null,
            'normalTexture': null,
            'normalScale': 1.0,
            'occlusionTexture': null,
            'occlusionStrength': 1.0,
            'emissiveTexture': null,
            'emissive': <double>[0, 0, 0],
            'emissiveStrength': 1.0,
            'alphaMode': 'opaque',
            'alphaCutoff': 0.5,
            'doubleSided': false,
            'unlit': false,
          },
        ],
      });

      expect(
        opened(
          bytes,
        ).materials.single.surface.baseColorTexture!.sampling.mipLinear,
        isTrue,
      );
    });

    test('a material\'s .fmat survives, and defaults to none', () {
      final withFmat = ModelProject(
        materials: <ProjectMaterial>[
          ProjectMaterial(
            surface: SurfaceMaterial(),
            fmat: 'materials/brass.fmat',
          ),
          ProjectMaterial(surface: SurfaceMaterial()),
        ],
      );

      final after = opened(writeProject(withFmat));
      // Mutation: never write the `fmat` key, or read it as required rather
      // than optional. The first loses every project that names one; the
      // second refuses every project saved before this field existed.
      expect(after.materials[0].fmat, 'materials/brass.fmat');
      expect(after.materials[1].fmat, isNull);
    });

    test('the image bytes come back whole, with what they were called', () {
      final after = opened(writeProject(painting()));

      expect(after.images.length, 2);
      expect(after.images[0].bytes, <int>[1, 2, 3, 4, 5]);
      expect(after.images[0].name, 'normal');
      expect(after.images[0].mimeType, 'image/png');
      // A file may honestly not know either, and a glTF often does not.
      expect(after.images[1].name, isNull);
      expect(after.images[1].bytes, <int>[9, 9]);
    });

    test('the slots still name the same rows', () {
      final after = opened(writeProject(painting()));

      expect(after.objects.single.materialSlots, <int>[0]);
      expect(after.materials.length, 2);
      expect(after.materials[1].surface.name, 'plain');
    });

    test('an alpha mode from a newer build draws rather than refuses', () {
      final bytes = forge(<String, Object?>{
        ...manifestOf(<Map<String, Object?>>[objectJson()]),
        'materials': <Object?>[
          <String, Object?>{
            'version': 1,
            'name': 'future',
            'baseColor': <double>[1, 1, 1, 1],
            'metallic': 0.0,
            'roughness': 0.5,
            'normalScale': 1.0,
            'occlusionStrength': 1.0,
            'emissive': <double>[0, 0, 0],
            'emissiveStrength': 1.0,
            'alphaMode': 'dither',
            'alphaCutoff': 0.5,
            'doubleSided': false,
            'unlit': false,
          },
        ],
      });

      // A name this build has not heard of is something a newer one wrote, and
      // that is a material drawn slightly wrong rather than a project nobody
      // can open. Mutation: refuse it, and a project saved by tomorrow's build
      // stops opening in today's.
      expect(
        opened(bytes).materials.single.surface.alphaMode,
        SurfaceAlphaMode.opaque,
      );
      // Mutation: fall back to `opaque` without appending anything to
      // `warnings` — the project still opens, correctly, and a silent
      // downgrade is exactly the case `doc-10`'s `warnings` field exists to
      // surface rather than hide.
      expect(warningsOf(bytes).single, contains('dither'));
    });

    test('a material missing a field is refused, and says which kind', () {
      final bytes = forge(<String, Object?>{
        ...manifestOf(<Map<String, Object?>>[objectJson()]),
        'materials': <Object?>[
          <String, Object?>{'name': 'half a material'},
        ],
      });

      // The other way round from the enum above, and deliberately: an unknown
      // name is a newer file, and a missing `baseColor` is a truncated one.
      expect(refusal(bytes), contains('Material 0 is missing a field'));
    });

    test('a colour of the wrong length is refused with its length', () {
      final bytes = forge(<String, Object?>{
        ...manifestOf(<Map<String, Object?>>[objectJson()]),
        'materials': <Object?>[
          <String, Object?>{
            'version': 1,
            'name': null,
            'baseColor': <double>[1, 1, 1],
            'metallic': 0.0,
            'roughness': 0.5,
            'normalScale': 1.0,
            'occlusionStrength': 1.0,
            'emissive': <double>[0, 0, 0],
            'emissiveStrength': 1.0,
            'alphaMode': 'opaque',
            'alphaCutoff': 0.5,
            'doubleSided': false,
            'unlit': false,
          },
        ],
      });

      // Mutation: take the first four entries of whatever list arrived. A
      // three-number colour then reads its alpha out of the next field in
      // memory, or throws — on the machine of whoever opened the file.
      expect(refusal(bytes), contains('3 numbers'));
    });

    test('an image table and a manifest that disagree are refused', () {
      final table = Uint8List(kProjectImageEntryBytes);
      final bytes = forge(
        <String, Object?>{
          ...manifestOf(<Map<String, Object?>>[objectJson()]),
          'images': const <Object?>[],
        },
        <(int, Uint8List, int)>[
          (ProjectSection.blob, Uint8List(8), 0),
          (ProjectSection.images, table, 1),
        ],
      );

      expect(refusal(bytes), contains('table holds 1'));
      expect(refusal(bytes), contains('names 0'));
    });
  });

  group('warnings', () {
    test('a project with nothing to warn about opens with none', () {
      expect(warningsOf(writeProject(sample())), isEmpty);
    });

    test(
      'an unknown wrapS or wrapT is opened as repeat, and both are named',
      () {
        final bytes = forge(<String, Object?>{
          ...manifestOf(<Map<String, Object?>>[objectJson()]),
          'materials': <Object?>[
            <String, Object?>{
              'version': 1,
              'name': null,
              'baseColor': <double>[1, 1, 1, 1],
              'metallic': 0.0,
              'roughness': 0.5,
              'normalScale': 1.0,
              'occlusionStrength': 1.0,
              'emissive': <double>[0, 0, 0],
              'emissiveStrength': 1.0,
              'alphaMode': 'opaque',
              'alphaCutoff': 0.5,
              'doubleSided': false,
              'unlit': false,
              'baseColorTexture': <String, Object?>{
                'imageIndex': 0,
                'texCoordSet': 0,
                'magLinear': true,
                'minLinear': true,
                'useMipmaps': true,
                'wrapS': 'mirror',
                'wrapT': 'repeat',
              },
            },
          ],
          'images': <Object?>[
            <String, Object?>{'name': 'a', 'mimeType': 'image/png'},
          ],
        });

        // Mutation: swap which of `wrapS`/`wrapT` is checked, or drop the
        // `context` argument down to a bare "wrap mode" — either leaves a
        // person reading the warning unable to tell which of a material's five
        // texture slots it came from.
        expect(warningsOf(bytes).single, contains('baseColorTexture'));
        expect(warningsOf(bytes).single, contains('wrapS'));
        expect(warningsOf(bytes).single, contains('mirror'));
      },
    );

    test(
      'a lightingModel this build does not ship opens unset, and says so',
      () {
        final bytes = forge(<String, Object?>{
          ...manifestOf(<Map<String, Object?>>[objectJson()]),
          'materials': <Object?>[
            <String, Object?>{
              'version': 1,
              'name': null,
              'baseColor': <double>[1, 1, 1, 1],
              'metallic': 0.0,
              'roughness': 0.5,
              'normalScale': 1.0,
              'occlusionStrength': 1.0,
              'emissive': <double>[0, 0, 0],
              'emissiveStrength': 1.0,
              'alphaMode': 'opaque',
              'alphaCutoff': 0.5,
              'doubleSided': false,
              'unlit': false,
              'lightingModel': 'Subsurface',
            },
          ],
        });

        expect(warningsOf(bytes).single, contains('lightingModel'));
        expect(warningsOf(bytes).single, contains('Subsurface'));
        expect(opened(bytes).materials.single.surface.lightingModel, isNull);
      },
    );

    test('an unknown profile target opens as desktop, and says so', () {
      final bytes = forge(<String, Object?>{
        ...manifestOf(<Map<String, Object?>>[objectJson()]),
        'profile': <String, Object?>{
          'name': 'x',
          'maxTriangles': 500000,
          'maxJoints': 64,
          'maxInfluences': 4,
          'maxTextureSize': 4096,
          'target': 'quantum',
        },
      });

      final read = readProject(bytes);
      expect(read, isA<ProjectOpened>());
      expect(
        (read as ProjectOpened).project.profile.target,
        ProfileTarget.desktop,
      );
      expect(read.warnings.single, contains('quantum'));
    });

    test('two things worth a warning both make it into the list', () {
      final bytes = forge(<String, Object?>{
        ...manifestOf(<Map<String, Object?>>[objectJson()]),
        'profile': <String, Object?>{
          'name': 'x',
          'maxTriangles': 500000,
          'maxJoints': 64,
          'maxInfluences': 4,
          'maxTextureSize': 4096,
          'target': 'quantum',
        },
        'materials': <Object?>[
          <String, Object?>{
            'version': 1,
            'name': null,
            'baseColor': <double>[1, 1, 1, 1],
            'metallic': 0.0,
            'roughness': 0.5,
            'normalScale': 1.0,
            'occlusionStrength': 1.0,
            'emissive': <double>[0, 0, 0],
            'emissiveStrength': 1.0,
            'alphaMode': 'dither',
            'alphaCutoff': 0.5,
            'doubleSided': false,
            'unlit': false,
          },
        ],
      });

      // Mutation: overwrite `warnings` instead of appending to it in one of
      // the two call sites — a material's own warning would then silently
      // erase the profile's, or the other way round, and only ever one of
      // the two problems a file actually has would reach whoever opened it.
      expect(warningsOf(bytes), hasLength(2));
    });
  });

  group('string interning', () {
    /// A distinct `MeshData` naming the same two attributes `arrived` in the
    /// "imported meshes" group below does, so two meshes' worth of "position"
    /// and "normal" reach `readProject` as two separate runs of JSON text
    /// rather than as one Dart string used twice — which is the only way this
    /// group can tell interning apart from a compiler that already
    /// canonicalises source-code string literals for free.
    MeshData meshNamed(double x) => MeshData(
      layout: VertexLayout.positionNormal,
      vertices: Float32List.fromList(<double>[x, 0, 0, 0, 0, 1]),
      indices: Uint32List.fromList(<int>[0, 0, 0]),
    );

    test('two meshes\' worth of "position" and "normal" come back as one '
        'string, not two', () {
      final project = const ModelProject()
          .added(
            (int id) => ModelObject(
              id: id,
              name: 'a',
              geometry: ImportedGeometry(meshNamed(1)),
              transform: Matrix4.identity(),
            ),
          )
          .added(
            (int id) => ModelObject(
              id: id,
              name: 'b',
              geometry: ImportedGeometry(meshNamed(2)),
              transform: Matrix4.identity(),
            ),
          );

      final after = opened(writeProject(project));
      final VertexLayout layoutA =
          (after.objects[0].geometry as ImportedGeometry).data.layout;
      final VertexLayout layoutB =
          (after.objects[1].geometry as ImportedGeometry).data.layout;

      // Mutation: read `VertexAttribute(name, components)` straight off the
      // JSON instead of through `_intern` — the layouts still compare equal
      // (`VertexAttribute`'s `name` is a plain field), so only `identical`
      // catches the regression; `==` would not.
      expect(
        identical(layoutA.attributes[0].name, layoutB.attributes[0].name),
        isTrue,
      );
      expect(
        identical(layoutA.attributes[1].name, layoutB.attributes[1].name),
        isTrue,
      );
    });

    test('two images with the same mimeType share one string', () {
      final bytes = forge(
        <String, Object?>{
          ...manifestOf(<Map<String, Object?>>[objectJson()]),
          'images': <Object?>[
            <String, Object?>{'name': 'a', 'mimeType': 'image/png'},
            <String, Object?>{'name': 'b', 'mimeType': 'image/png'},
          ],
        },
        <(int, Uint8List, int)>[
          (ProjectSection.blob, Uint8List(8), 0),
          (
            ProjectSection.images,
            Uint8List.fromList(<int>[
              0,
              0,
              0,
              0,
              4,
              0,
              0,
              0,
              4,
              0,
              0,
              0,
              4,
              0,
              0,
              0,
            ]),
            2,
          ),
        ],
      );

      final images = opened(bytes).images;
      expect(identical(images[0].mimeType, images[1].mimeType), isTrue);
    });

    test('two materials with the same name share one string', () {
      Map<String, Object?> materialNamed(String name) => <String, Object?>{
        'version': 1,
        'name': name,
        'baseColor': <double>[1, 1, 1, 1],
        'metallic': 0.0,
        'roughness': 0.5,
        'normalScale': 1.0,
        'occlusionStrength': 1.0,
        'emissive': <double>[0, 0, 0],
        'emissiveStrength': 1.0,
        'alphaMode': 'opaque',
        'alphaCutoff': 0.5,
        'doubleSided': false,
        'unlit': false,
      };
      final bytes = forge(<String, Object?>{
        ...manifestOf(<Map<String, Object?>>[objectJson()]),
        'materials': <Object?>[materialNamed('steel'), materialNamed('steel')],
      });

      final materials = opened(bytes).materials;
      expect(
        identical(materials[0].surface.name, materials[1].surface.name),
        isTrue,
      );
    });

    test(
      'the pool is per file: two separate reads do not share one string',
      () {
        final bytes = writeProject(
          const ModelProject().added(
            (int id) => ModelObject(
              id: id,
              name: 'a',
              geometry: ImportedGeometry(meshNamed(1)),
              transform: Matrix4.identity(),
            ),
          ),
        );

        final firstRead =
            (opened(bytes).objects.single.geometry as ImportedGeometry)
                .data
                .layout
                .attributes[0]
                .name;
        final secondRead =
            (opened(bytes).objects.single.geometry as ImportedGeometry)
                .data
                .layout
                .attributes[0]
                .name;

        // Not a correctness requirement of `readProject`'s own contract — two
        // reads of the same file are free to share a string or not — but it is
        // what this file's own pool actually does (one `Map` built fresh at the
        // top of every call), and a global pool instead would be a real design
        // change worth a comment of its own rather than a silent one.
        expect(identical(firstRead, secondRead), isFalse);
      },
    );
  });

  group('imported meshes', () {
    /// Buffers with distinct numbers in every slot, so a float that arrived
    /// from the wrong offset reads as the wrong number rather than as a zero
    /// that could have been anything.
    MeshData arrived() => MeshData(
      layout: VertexLayout.positionNormal,
      vertices: Float32List.fromList(<double>[
        0.5, 1.5, 2.5, 0, 0, 1, //
        3.5, 4.5, 5.5, 0, 1, 0, //
        6.5, 7.5, 8.5, 1, 0, 0, //
      ]),
      indices: Uint32List.fromList(<int>[0, 1, 2]),
    );

    ModelProject importing(int count, {MeshData? shared}) {
      var project = const ModelProject();
      for (var i = 0; i < count; i++) {
        project = project.added(
          (int id) => ModelObject(
            id: id,
            name: 'part $id',
            geometry: ImportedGeometry(shared ?? arrived()),
            transform: Matrix4.translationValues(i.toDouble(), 0, 0),
          ),
        );
      }
      return project;
    }

    test('the buffers come back byte for byte', () {
      final after = opened(writeProject(importing(1)));
      final geometry = after.objects.single.geometry;

      expect(geometry, isA<ImportedGeometry>());
      final MeshData mesh = (geometry as ImportedGeometry).data;

      // Against the source rather than against a written-down list, so that
      // changing the fixture cannot leave this passing about the wrong numbers.
      // Mutation: write the vertex length where the index offset goes, which is
      // the field order this table is easiest to get wrong in — the vertices
      // still arrive and the triangle is built out of whatever floats follow.
      expect(mesh.vertices, arrived().vertices);
      expect(mesh.indices, arrived().indices);
      expect(mesh.layout.attributes.length, 2);
      expect(
        mesh.layout.attributes.map((VertexAttribute a) => a.name),
        <String>['position', 'normal'],
      );
      expect(after.objects.single.geometry.triangleCount, 1);
    });

    test('a project of imported objects keeps its transforms and ids', () {
      final before = importing(3);
      final after = opened(writeProject(before));

      expect(after.objects.length, 3);
      expect(after.nextId, before.nextId);
      expect(
        after.objects.map((ModelObject o) => o.transform.getTranslation().x),
        <double>[0, 1, 2],
      );
    });

    test('one mesh drawn twice is written once', () {
      final shared = arrived();
      final bytes = writeProject(importing(2, shared: shared));

      final table = directoryOf(
        bytes,
      ).firstWhere((entry) => entry.kind == ProjectSection.importedMeshes);

      // Mutation: append per object rather than looking the mesh up by
      // identity. The file grows a second copy of every instanced prop, and
      // re-opening it gives two meshes where the document had one — so an edit
      // to the shared mesh stops reaching both objects.
      expect(table.count, 1);
      expect(table.length, kProjectImportedEntryBytes);

      final after = opened(bytes);
      expect(
        identical(
          (after.objects[0].geometry as ImportedGeometry).data,
          (after.objects[1].geometry as ImportedGeometry).data,
        ),
        isTrue,
      );
    });

    test('an empty table is written even when nothing was imported', () {
      final bytes = writeProject(sample());
      final kinds = directoryOf(bytes).map((entry) => entry.kind);

      expect(kinds, contains(ProjectSection.importedMeshes));
    });
  });

  group('an imported mesh the file describes wrongly', () {
    Map<String, Object?> manifestWith(Object? importedMeshes, {int mesh = 0}) =>
        <String, Object?>{
          ...manifestOf(<Map<String, Object?>>[
            objectJson(
              geometry: <String, Object?>{'kind': 'imported', 'mesh': mesh},
            ),
          ]),
          'importedMeshes': importedMeshes,
        };

    /// A table of one entry addressing [vertexBytes] and [indexBytes] at the
    /// front of a blob of [blobBytes].
    List<(int, Uint8List, int)> tableAndBlob({
      int vertexBytes = 24,
      int indexBytes = 12,
      int blobBytes = 36,
      int vertexAt = 0,
    }) {
      final table = Uint8List(kProjectImportedEntryBytes);
      ByteData.sublistView(table)
        ..setUint32(0, vertexAt, Endian.little)
        ..setUint32(4, vertexBytes, Endian.little)
        ..setUint32(8, vertexBytes, Endian.little)
        ..setUint32(12, indexBytes, Endian.little);
      return <(int, Uint8List, int)>[
        (ProjectSection.blob, Uint8List(blobBytes), 0),
        (ProjectSection.importedMeshes, table, 1),
      ];
    }

    test('a mesh index naming nothing is refused with both numbers', () {
      final bytes = forge(manifestWith(const <Object?>[], mesh: 3));

      expect(refusal(bytes), contains('imported mesh 3'));
      expect(refusal(bytes), contains('holds 0'));
    });

    test('a table and a manifest that disagree are refused', () {
      // Mutation: read down to the shorter of the two. The file then opens with
      // some of its meshes wearing another mesh's layout, which is a model that
      // draws as noise rather than one that fails.
      final bytes = forge(manifestWith(const <Object?>[]), tableAndBlob());

      expect(refusal(bytes), contains('table holds 1'));
      expect(refusal(bytes), contains('describes 0'));
    });

    test('a layout that is not one is refused', () {
      final bytes = forge(
        manifestWith(<Object?>[
          <String, Object?>{'layout': const <Object?>[]},
        ]),
        tableAndBlob(),
      );

      // An empty layout is a stride of zero, and a stride of zero makes the
      // vertex count a division by zero. Mutation: accept it and the refusal
      // becomes a crash inside `MeshData`, on the machine of whoever opened the
      // file.
      expect(refusal(bytes), contains('no vertex layout'));
    });

    test('a buffer running past the blob is refused', () {
      final bytes = forge(
        manifestWith(<Object?>[
          <String, Object?>{
            'layout': <Object?>[
              <String, Object?>{'name': 'position', 'components': 3},
            ],
          },
        ]),
        tableAndBlob(blobBytes: 8),
      );

      expect(refusal(bytes), contains('the blob is 8 bytes long'));
    });

    test('a vertex buffer that does not divide by the stride is refused', () {
      final bytes = forge(
        manifestWith(<Object?>[
          <String, Object?>{
            'layout': <Object?>[
              <String, Object?>{'name': 'position', 'components': 3},
            ],
          },
        ]),
        // 20 bytes is five floats, and a position takes three.
        tableAndBlob(vertexBytes: 20, indexBytes: 12, blobBytes: 40),
      );

      // Mutation: build the mesh anyway. `MeshData` divides to find its vertex
      // count and the last vertex is two floats of the index buffer.
      expect(refusal(bytes), contains('does not divide'));
    });

    test('a length that is not a count of four-byte values is refused', () {
      final bytes = forge(
        manifestWith(<Object?>[
          <String, Object?>{
            'layout': <Object?>[
              <String, Object?>{'name': 'position', 'components': 3},
            ],
          },
        ]),
        tableAndBlob(vertexBytes: 13, indexBytes: 12, blobBytes: 40),
      );

      // `Float32List.sublistView` throws on it, and a throw is the one thing
      // `readProject` promises not to do.
      expect(refusal(bytes), contains('four-byte values'));
    });
  });

  group('a damaged file', () {
    test('no single flipped byte opens as a different model', () {
      final whole = writeProject(sample());
      final before = sample();

      // The measurement this section exists for. Before the checksums, 7342 of
      // 10488 single-byte corruptions of this file opened — as a project, with
      // no complaint, describing a model that was not the one saved. A manifest
      // is JSON and most of its bytes are inside a float or a name, so flipping
      // one leaves something that still parses and means something else.
      //
      // One flip per byte rather than all eight, and a fixed pattern rather
      // than a random one: this has to run in a suite and it has to give the
      // same answer twice.
      var opened = 0;
      var refused = 0;
      for (var i = 0; i < whole.length; i++) {
        final broken = Uint8List.fromList(whole)..[i] ^= 0xA5;
        switch (readProject(broken)) {
          case ProjectRefused():
            refused++;
          case ProjectOpened(:final ModelProject project):
            opened++;
            // The only corruptions allowed through are the ones that changed
            // nothing anybody can see — padding between sections, which is
            // where the aligner leaves bytes nothing reads.
            expect(
              project.objects.length,
              before.objects.length,
              reason: 'byte $i opened as a different model',
            );
            expect(project.nextId, before.nextId, reason: 'byte $i');
            expect(
              project.objects.map((ModelObject o) => o.name),
              before.objects.map((ModelObject o) => o.name),
              reason: 'byte $i',
            );
        }
      }

      // Mutation: skip `_verifyChecksums` and thousands of these open as
      // something else, and the assertions inside the loop go red in bulk.
      expect(refused + opened, whole.length);
      expect(refused, greaterThan(whole.length - 32));
    });

    test('a damaged checksum table says so rather than blaming a section', () {
      final whole = writeProject(sample());
      final table = directoryOf(
        whole,
      ).firstWhere((entry) => entry.kind == ProjectSection.checksums);
      final broken = Uint8List.fromList(whole)..[table.offset + 4] ^= 0xFF;

      // The one thing the table cannot check is itself, which is what the
      // header's fourth field is for. Mutation: drop that field and this file
      // is refused as "section 1 is damaged" — a sentence that sends whoever
      // reads it after a manifest that is perfectly fine.
      expect(refusal(broken), contains('checksum table is damaged'));
    });

    test('a header claiming checksums that are not there is refused', () {
      // Zero in that field means "no checksums", so an older file keeps its
      // meaning; anything else means the file said it had a table.
      final bytes = forge(manifestOf(<Map<String, Object?>>[objectJson()]));
      final claiming = Uint8List.fromList(bytes);
      ByteData.sublistView(
        claiming,
      ).setUint32(kProjectChecksumOffset, 99, Endian.little);

      expect(refusal(claiming), contains('a table this file does not have'));
    });

    test('the checksums naming a section the directory lacks are refused', () {
      final table = Uint8List(kProjectChecksumEntryBytes);
      ByteData.sublistView(table)
        ..setUint32(0, 77, Endian.little)
        ..setUint32(4, 0, Endian.little);

      final bytes = forge(
        manifestOf(<Map<String, Object?>>[objectJson()]),
        <(int, Uint8List, int)>[(ProjectSection.checksums, table, 1)],
      );

      expect(refusal(bytes), contains('name section 77'));
    });

    test('an undamaged file agrees with its own sums', () {
      // The case that has to stay quiet: a mutation that reported damage on a
      // sound file would make every save unopenable, which is the failure a
      // checksum is least likely to be trusted through.
      expect(readProject(writeProject(sample())), isA<ProjectOpened>());
    });
  });

  group('telling a project file from anything else', () {
    test('it recognises its own output', () {
      expect(isProjectFile(writeProject(sample())), isTrue);
    });

    test('a model file is not a project', () {
      // `.f3d` begins "F3D\n" and a project begins "F3DP", which share three
      // bytes. Mutation: compare three of them and every `.f3d` a person picks
      // is handed to `readProject`, which refuses it with a sentence about a
      // magic number instead of the model being opened.
      expect(
        isProjectFile(Uint8List.fromList(<int>[0x46, 0x33, 0x44, 0x0A])),
        isFalse,
      );
      expect(isProjectFile(utf8.encode('glTF')), isFalse);
    });

    test('a file too short to have a magic is not a project', () {
      // Mutation: read the four bytes without checking the length and this
      // throws rather than answering, on a file somebody picked by mistake.
      expect(isProjectFile(Uint8List(0)), isFalse);
      expect(
        isProjectFile(Uint8List.fromList(<int>[0x46, 0x33, 0x44])),
        isFalse,
      );
    });

    test('the name is not what decides', () {
      // The whole reason this reads bytes: a project renamed `.glb` is still a
      // project, and an extension is a thing anybody can type.
      final bytes = writeProject(sample());
      expect(isProjectFile(bytes), isTrue);
      expect(readProject(bytes), isA<ProjectOpened>());
    });
  });
}
