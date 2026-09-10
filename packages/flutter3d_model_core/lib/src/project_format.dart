/// The project's own file: what a modeller saves and opens again.
///
/// **A format of our own, and glTF is the way out rather than the way back.**
/// There is nowhere in a glTF for the profile a project is being built
/// against, nowhere for the parameters a cylinder still knows itself by, and
/// nowhere for a modifier stack. Saving through glTF would mean a cylinder
/// that comes back as a bag of triangles, and "set segments to 48" is then a
/// sentence with nothing to say it to — which is exactly the thing
/// `ParametricGeometry` exists to keep. So the round trip goes through this,
/// and glTF is written when the model leaves.
///
/// **The container is `.f3d`'s, deliberately.** A magic, a version, a 16-byte
/// header, a directory of sections, everything on a four-byte boundary, and a
/// kind the reader does not know stepped over rather than refused. That last
/// rule is the reason to copy rather than to invent: somebody opening a project
/// made by a newer build should get their objects back, missing whatever the
/// new section carried, instead of a wall. It also means the version only moves
/// when an existing record changes meaning — adding a section does not need it.
///
/// **What is in the file today.** A manifest in JSON — the profile, and each
/// object with its id, name, parent, transform, material slots and which kind
/// of geometry it has — plus a table of edited meshes and the blob those live
/// in, each written by `EditMesh.toBytes` so there is exactly one mesh encoding
/// in this repository.
///
/// **What is not, and is not pretended to be.** The history is not written
/// here: the file carries the document, and putting the undo stack in it is
/// `doc-31d`, which wants the steps to address chunks already lying in the blob
/// rather than a second copy of every mesh. Materials, images, skins and
/// animations have sections of their own in the plan and none of them yet.
/// Imported geometry — buffers that arrived from a glTF with no topology behind
/// them — is refused by [writeProject] rather than written half: see the throw
/// there for why that beats a file whose object comes back empty.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'project.dart';

/// `F3DP`, little-endian, so a file opened in a text editor announces itself on
/// the first line and does not collide with `.f3d`'s own `F3D\n`.
const int kProjectMagic = 0x50443346;

/// Moves only when an existing record changes meaning. A new section does not
/// need it, because an older reader steps over a kind it does not know.
const int kProjectVersion = 1;

const int kProjectHeaderBytes = 16;
const int kProjectSectionEntryBytes = 16;

/// One entry of the edited-mesh table: u32 offset into the blob, u32 length.
const int kProjectMeshEntryBytes = 8;

/// Section kinds.
///
/// Explicit numbers, never an enum's index: the number goes into a file that
/// outlives this source, and reordering a declaration would silently
/// reinterpret every project already saved. The plan names further sections —
/// materials, imported meshes, images, skins, animations, the command journal
/// and the history of `doc-31d` — and each takes a number of its own from 4
/// upwards. None of them may reuse 1 to 3.
abstract final class ProjectSection {
  /// The document, as JSON. Everything that is not bulk lives here.
  static const int manifest = 1;

  /// `count` entries of [kProjectMeshEntryBytes], addressing [blob]. A table
  /// rather than an offset written beside each object, because `doc-31d` wants
  /// a step of history to name a chunk by index and share it with the object
  /// that is still using it.
  static const int editMeshes = 2;

  /// Where the bulk is. Every entry starts on a four-byte boundary.
  static const int blob = 3;
}

/// What [readProject] gives back.
///
/// **A sealed pair rather than `(ModelProject?, String?)`.** That record has
/// four states and two of them mean nothing — both null, and both set — so
/// every caller has to decide what it thinks those are, and a caller that
/// checks the wrong half of it opens an empty document while holding the
/// sentence that says why it could not. Here the compiler asks about both cases
/// and there is no third:
///
/// ```dart
/// switch (readProject(bytes)) {
///   case ProjectOpened(:final ModelProject project): ...
///   case ProjectRefused(:final String because): ...
/// }
/// ```
///
/// An exception was the other candidate and lost for the reason the plan gives:
/// opening a file the user chose is not exceptional, it is a normal Tuesday,
/// and the sentence belongs in front of them rather than in a stack trace.
sealed class ProjectRead {
  const ProjectRead();
}

/// The file read.
final class ProjectOpened extends ProjectRead {
  const ProjectOpened(this.project);

  final ModelProject project;
}

/// The file not read, and one sentence saying what is wrong with it.
///
/// The sentence names the number that was wrong and what was expected instead,
/// because "corrupt file" is a thing nobody can act on and "section 3 runs from
/// 200 for 64 bytes, past the end of a 220-byte file" is a thing somebody can
/// take to whoever wrote the file.
final class ProjectRefused extends ProjectRead {
  const ProjectRefused(this.because);

  final String because;

  @override
  String toString() => 'ProjectRefused($because)';
}

/// The project as a `.f3dproj` file.
///
/// Deterministic: the same project writes the same bytes. The manifest's keys
/// go in a fixed order because they are built in one, the meshes go in the
/// order the objects do, and `EditMesh.toBytes` is deterministic itself. A file
/// that changes when the document did not is a file nobody can diff and a save
/// that dirties a repository for nothing.
///
/// Throws [ArgumentError] on an object holding [ImportedGeometry]. That is a
/// hole rather than a rule — the plan's `importedMeshes` section is what closes
/// it — and a refusal at the call site is better than the alternatives: writing
/// the object without its buffers gives a file that opens into an empty shape,
/// and dropping the object gives a file missing something the user could see on
/// the screen when they pressed save.
Uint8List writeProject(ModelProject project) {
  final meshes = <Uint8List>[];
  final objects = <Map<String, Object?>>[];

  for (final ModelObject object in project.objects) {
    final Map<String, Object?> geometry;
    switch (object.geometry) {
      case ParametricGeometry(:final ParametricShape shape):
        geometry = <String, Object?>{
          'kind': 'parametric',
          ..._shapeJson(shape),
        };
      case EditedGeometry(:final EditMesh mesh):
        geometry = <String, Object?>{'kind': 'edited', 'mesh': meshes.length};
        meshes.add(mesh.toBytes());
      case ImportedGeometry():
        throw ArgumentError(
          'object ${object.id} ("${object.name}") holds imported buffers, and '
          'this version of the format has no section for them. Writing it '
          'without them would save a file that opens with the object there and '
          'nothing in it.',
        );
    }
    objects.add(<String, Object?>{
      'id': object.id,
      'name': object.name,
      'parent': object.parent,
      'version': object.version,
      'transform': <double>[...object.transform.storage],
      'materialSlots': <int>[...object.materialSlots],
      'geometry': geometry,
    });
  }

  final manifest = utf8.encode(
    jsonEncode(<String, Object?>{
      'profile': <String, Object?>{
        'name': project.profile.name,
        'maxTriangles': project.profile.maxTriangles,
        'maxJoints': project.profile.maxJoints,
        'maxInfluences': project.profile.maxInfluences,
        'maxTextureSize': project.profile.maxTextureSize,
      },
      // Written down rather than worked out from the objects on the way back
      // in: an id belonging to something deleted must not be handed out again,
      // and `objects.length + 1` after a delete is exactly that mistake — a
      // step of history that named the old object would start naming the new
      // one the moment it was undone.
      'nextId': project.nextId,
      'objects': objects,
    }),
  );

  final meshOffsets = <int>[];
  final blobLength = meshes.fold<int>(0, (int at, Uint8List mesh) {
    meshOffsets.add(at);
    return _align(at + mesh.lengthInBytes);
  });
  final blob = Uint8List(blobLength);
  final table = Uint8List(meshes.length * kProjectMeshEntryBytes);
  final tableView = ByteData.view(table.buffer);
  for (var i = 0; i < meshes.length; i++) {
    blob.setRange(meshOffsets[i], meshOffsets[i] + meshes[i].length, meshes[i]);
    tableView
      ..setUint32(i * kProjectMeshEntryBytes, meshOffsets[i], Endian.little)
      ..setUint32(
        i * kProjectMeshEntryBytes + 4,
        meshes[i].lengthInBytes,
        Endian.little,
      );
  }

  final sections = <(int kind, Uint8List data, int count)>[
    (ProjectSection.manifest, manifest, 0),
    (ProjectSection.editMeshes, table, meshes.length),
    (ProjectSection.blob, blob, 0),
  ];

  final offsets = <int>[];
  final total = sections.fold<int>(
    _align(kProjectHeaderBytes + sections.length * kProjectSectionEntryBytes),
    (int at, (int, Uint8List, int) section) {
      offsets.add(at);
      return _align(at + section.$2.lengthInBytes);
    },
  );

  final out = Uint8List(total);
  final view = ByteData.view(out.buffer);
  view
    ..setUint32(0, kProjectMagic, Endian.little)
    ..setUint32(4, kProjectVersion, Endian.little)
    ..setUint32(8, sections.length, Endian.little)
    // Reserved, and zero. A field kept rather than dropped so the header stays
    // 16 bytes, which is what makes the directory start on a boundary.
    ..setUint32(12, 0, Endian.little);

  for (var i = 0; i < sections.length; i++) {
    final (int kind, Uint8List data, int count) = sections[i];
    final entry = kProjectHeaderBytes + i * kProjectSectionEntryBytes;
    view
      ..setUint32(entry, kind, Endian.little)
      ..setUint32(entry + 4, offsets[i], Endian.little)
      ..setUint32(entry + 8, data.lengthInBytes, Endian.little)
      // For a person reading a hex dump, and for parity with `.f3d`. The reader
      // takes the entry count from the length instead: two numbers that can
      // disagree are a file that has to say which of them wins.
      ..setUint32(entry + 12, count, Endian.little);
    out.setRange(offsets[i], offsets[i] + data.lengthInBytes, data);
  }

  return out;
}

/// The project in [bytes], or one sentence saying why not.
///
/// Nothing here throws on a bad file. A file is something a person picked out
/// of a folder, and half the files in any folder are the wrong file. So every
/// way of being wrong gets a sentence of its own, each naming the number that
/// did not add up: a file too short to hold a header, a magic from another
/// format, a version from the future and a section whose length runs past the
/// end are four different faults and never share a wording.
ProjectRead readProject(Uint8List bytes) {
  if (bytes.lengthInBytes < kProjectHeaderBytes) {
    return ProjectRefused(
      'A project file starts with a $kProjectHeaderBytes-byte header and this '
      'one is ${bytes.lengthInBytes} bytes long.',
    );
  }

  final view = ByteData.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );

  final magic = view.getUint32(0, Endian.little);
  if (magic != kProjectMagic) {
    return ProjectRefused(
      'Not a project file: it begins 0x${magic.toRadixString(16)} where a '
      'project begins 0x${kProjectMagic.toRadixString(16)}, which is "F3DP".',
    );
  }

  final version = view.getUint32(4, Endian.little);
  if (version > kProjectVersion) {
    return ProjectRefused(
      'This project was written by version $version and this build reads '
      'version $kProjectVersion. Open it in a newer build; there is nothing '
      'here that can guess what it added.',
    );
  }

  final sectionCount = view.getUint32(8, Endian.little);
  final directoryEnd =
      kProjectHeaderBytes + sectionCount * kProjectSectionEntryBytes;
  if (directoryEnd > bytes.lengthInBytes) {
    return ProjectRefused(
      'The header claims $sectionCount sections, whose directory ends at byte '
      '$directoryEnd, past the end of a ${bytes.lengthInBytes}-byte file.',
    );
  }

  final sections = <int, ({int offset, int length})>{};
  for (var i = 0; i < sectionCount; i++) {
    final entry = kProjectHeaderBytes + i * kProjectSectionEntryBytes;
    final kind = view.getUint32(entry, Endian.little);
    final offset = view.getUint32(entry + 4, Endian.little);
    final length = view.getUint32(entry + 8, Endian.little);
    if (offset + length > bytes.lengthInBytes) {
      return ProjectRefused(
        'Section $kind runs from byte $offset for $length bytes, past the end '
        'of a ${bytes.lengthInBytes}-byte file.',
      );
    }
    // A kind this build has never heard of is kept in the map and never looked
    // at, which is the whole point of a directory: a project saved by a build
    // that writes materials opens here as the objects it also wrote.
    sections[kind] = (offset: offset, length: length);
  }

  final manifestAt = sections[ProjectSection.manifest];
  if (manifestAt == null) {
    return const ProjectRefused(
      'This file has no manifest section, so nothing in it says what the '
      'objects are.',
    );
  }

  final Object? document;
  try {
    document = jsonDecode(
      utf8.decode(
        Uint8List.sublistView(
          bytes,
          manifestAt.offset,
          manifestAt.offset + manifestAt.length,
        ),
      ),
    );
  } on FormatException catch (error) {
    return ProjectRefused('The manifest is not JSON: ${error.message}');
  }

  final (List<EditMesh> meshes, String? meshRefusal) = _readMeshes(
    bytes,
    sections,
  );
  if (meshRefusal != null) return ProjectRefused(meshRefusal);

  if (document case {
    'profile': {
      'name': final String profileName,
      'maxTriangles': final int maxTriangles,
      'maxJoints': final int maxJoints,
      'maxInfluences': final int maxInfluences,
      'maxTextureSize': final int maxTextureSize,
    },
    'nextId': final int nextId,
    'objects': final List<Object?> entries,
  }) {
    final objects = <ModelObject>[];
    for (var i = 0; i < entries.length; i++) {
      final (ModelObject? object, String? refusal) = _readObject(
        entries[i],
        i,
        meshes,
      );
      if (refusal != null) return ProjectRefused(refusal);
      objects.add(object!);
    }
    return ProjectOpened(
      ModelProject(
        profile: ProjectProfile(
          name: profileName,
          maxTriangles: maxTriangles,
          maxJoints: maxJoints,
          maxInfluences: maxInfluences,
          maxTextureSize: maxTextureSize,
        ),
        objects: objects,
        nextId: nextId,
      ),
    );
  }

  return const ProjectRefused(
    'The manifest is not shaped like a project: it needs a profile with its '
    'five limits, the nextId, and a list of objects.',
  );
}

int _align(int value) => (value + 3) & ~3;

/// The edited meshes, or the sentence that stops the file being read.
///
/// Eager rather than lazy, unlike `.f3d`'s geometry: a mesh here is decoded
/// into a half-edge structure the moment anything touches it, so there is no
/// view-over-the-file trick to protect and nothing gained by finding out about
/// a broken one halfway through building the project.
(List<EditMesh>, String?) _readMeshes(
  Uint8List bytes,
  Map<int, ({int offset, int length})> sections,
) {
  final table = sections[ProjectSection.editMeshes];
  final blob = sections[ProjectSection.blob];
  if (table == null || blob == null) return (const <EditMesh>[], null);

  final view = ByteData.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  final meshes = <EditMesh>[];
  final count = table.length ~/ kProjectMeshEntryBytes;
  for (var i = 0; i < count; i++) {
    final entry = table.offset + i * kProjectMeshEntryBytes;
    final offset = view.getUint32(entry, Endian.little);
    final length = view.getUint32(entry + 4, Endian.little);
    if (offset + length > blob.length) {
      return (
        const <EditMesh>[],
        'Edited mesh $i runs from byte $offset of the blob for $length bytes, '
            'and the blob is ${blob.length} bytes long.',
      );
    }
    try {
      meshes.add(
        EditMesh.fromBytes(
          Uint8List.sublistView(
            bytes,
            blob.offset + offset,
            blob.offset + offset + length,
          ),
        ),
      );
    } on ArgumentError catch (error) {
      // What `EditMesh.fromBytes` throws for every way its own bytes can be
      // wrong, `RangeError` included — it is a subclass. Caught here and handed
      // back as a sentence, because the caller of this is opening a file and a
      // file is not an argument somebody in this program got wrong.
      return (
        const <EditMesh>[],
        'Edited mesh $i cannot be read: ${error.message}',
      );
    }
  }
  return (meshes, null);
}

(ModelObject?, String?) _readObject(
  Object? entry,
  int index,
  List<EditMesh> meshes,
) {
  if (entry case {
    'id': final int id,
    'name': final String name,
    'parent': final int? parent,
    'version': final int version,
    'transform': final List<Object?> transform,
    'materialSlots': final List<Object?> slots,
    'geometry': final Map<String, Object?> geometry,
  }) {
    if (transform.length != 16 || transform.any((Object? v) => v is! num)) {
      return (
        null,
        'Object $index ("$name") has a transform of ${transform.length} '
            'entries, and a matrix is sixteen numbers.',
      );
    }
    if (slots.any((Object? v) => v is! int)) {
      return (
        null,
        'Object $index ("$name") has a material slot that is not a number.',
      );
    }

    final (Geometry? shape, String? refusal) = _readGeometry(
      geometry,
      index,
      name,
      meshes,
    );
    if (refusal != null) return (null, refusal);

    return (
      ModelObject(
        id: id,
        name: name,
        geometry: shape!,
        transform: Matrix4.fromList(<double>[
          for (final Object? value in transform) (value! as num).toDouble(),
        ]),
        parent: parent,
        version: version,
        materialSlots: <int>[for (final Object? slot in slots) slot! as int],
      ),
      null,
    );
  }
  return (
    null,
    'Object $index in the manifest is missing a field or has one of the wrong '
        'type: an object is an id, a name, a parent, a version, a transform, its '
        'material slots and its geometry.',
  );
}

(Geometry?, String?) _readGeometry(
  Map<String, Object?> geometry,
  int index,
  String name,
  List<EditMesh> meshes,
) {
  switch (geometry['kind']) {
    case 'parametric':
      final shape = _shapeFrom(geometry);
      if (shape != null) return (ParametricGeometry(shape), null);
      final Object? kind = geometry['shape'];
      return (
        null,
        _shapeNames.contains(kind)
            ? 'Object $index ("$name") is a parametric "$kind" whose '
                  'parameters are missing or are not numbers.'
            : 'Object $index ("$name") is a parametric "$kind", and this build '
                  'knows ${_shapeNames.join(", ")}.',
      );
    case 'edited':
      final Object? at = geometry['mesh'];
      if (at is! int || at < 0 || at >= meshes.length) {
        return (
          null,
          'Object $index ("$name") is edited mesh $at and this file holds '
              '${meshes.length}.',
        );
      }
      return (EditedGeometry(meshes[at]), null);
    default:
      return (
        null,
        'Object $index ("$name") has geometry of kind "${geometry['kind']}", '
            'which this build does not know how to read.',
      );
  }
}

/// The shapes this version can write and read back, in the sentence a refusal
/// prints them in.
const List<String> _shapeNames = <String>[
  'cuboid',
  'plane',
  'lathe',
  'sphere',
  'cylinder',
  'torus',
];

/// A parametric shape as JSON.
///
/// **The parameters, not the mesh they build.** This is the one thing glTF
/// cannot hold and therefore the whole reason the format exists: a cylinder
/// that comes back knowing it is a cylinder of 32 segments can be made a
/// cylinder of 48, and one that comes back as faces cannot.
///
/// The `shape` key is spelled out rather than taken from `ParametricShape.name`
/// — that one answers "cone" for a cylinder with a zero radius and is free text
/// on a lathe, so a file keyed by it would not read back as what it was.
Map<String, Object?> _shapeJson(ParametricShape shape) => switch (shape) {
  ParametricCuboid(:final Vector3 size) => <String, Object?>{
    'shape': 'cuboid',
    'size': <double>[size.x, size.y, size.z],
  },
  ParametricPlane(
    :final double width,
    :final double depth,
    :final int widthSegments,
    :final int depthSegments,
  ) =>
    <String, Object?>{
      'shape': 'plane',
      'width': width,
      'depth': depth,
      'widthSegments': widthSegments,
      'depthSegments': depthSegments,
    },
  ParametricLathe(
    :final List<Vector2> profile,
    :final int segments,
    :final double startAngle,
    :final double sweepAngle,
    :final bool closedProfile,
    :final String name,
  ) =>
    <String, Object?>{
      'shape': 'lathe',
      'profile': <List<double>>[
        for (final Vector2 point in profile) <double>[point.x, point.y],
      ],
      'segments': segments,
      'startAngle': startAngle,
      'sweepAngle': sweepAngle,
      'closedProfile': closedProfile,
      'name': name,
    },
  ParametricSphere(
    :final double radius,
    :final int segments,
    :final int rings,
  ) =>
    <String, Object?>{
      'shape': 'sphere',
      'radius': radius,
      'segments': segments,
      'rings': rings,
    },
  ParametricCylinder(
    :final double radiusTop,
    :final double radiusBottom,
    :final double height,
    :final int segments,
    :final bool capped,
  ) =>
    <String, Object?>{
      'shape': 'cylinder',
      'radiusTop': radiusTop,
      'radiusBottom': radiusBottom,
      'height': height,
      'segments': segments,
      'capped': capped,
    },
  ParametricTorus(
    :final double radius,
    :final double tubeRadius,
    :final int segments,
    :final int tubeSegments,
  ) =>
    <String, Object?>{
      'shape': 'torus',
      'radius': radius,
      'tubeRadius': tubeRadius,
      'segments': segments,
      'tubeSegments': tubeSegments,
    },
};

/// The shape [json] describes, or null if this build cannot build it.
///
/// Every parameter is required rather than defaulted. A missing `segments` that
/// quietly became 32 would give back a cylinder that is not the one that was
/// saved, and the person who notices is the one who exported it.
ParametricShape? _shapeFrom(Map<String, Object?> json) => switch (json) {
  {'shape': 'cuboid', 'size': [final num x, final num y, final num z]} =>
    ParametricCuboid(size: Vector3(x.toDouble(), y.toDouble(), z.toDouble())),
  {
    'shape': 'plane',
    'width': final num width,
    'depth': final num depth,
    'widthSegments': final int widthSegments,
    'depthSegments': final int depthSegments,
  } =>
    ParametricPlane(
      width: width.toDouble(),
      depth: depth.toDouble(),
      widthSegments: widthSegments,
      depthSegments: depthSegments,
    ),
  {
    'shape': 'lathe',
    'profile': final List<Object?> profile,
    'segments': final int segments,
    'startAngle': final num startAngle,
    'sweepAngle': final num sweepAngle,
    'closedProfile': final bool closedProfile,
    'name': final String name,
  } =>
    _latheFrom(
      profile,
      segments: segments,
      startAngle: startAngle.toDouble(),
      sweepAngle: sweepAngle.toDouble(),
      closedProfile: closedProfile,
      name: name,
    ),
  {
    'shape': 'sphere',
    'radius': final num radius,
    'segments': final int segments,
    'rings': final int rings,
  } =>
    ParametricSphere(
      radius: radius.toDouble(),
      segments: segments,
      rings: rings,
    ),
  {
    'shape': 'cylinder',
    'radiusTop': final num radiusTop,
    'radiusBottom': final num radiusBottom,
    'height': final num height,
    'segments': final int segments,
    'capped': final bool capped,
  } =>
    ParametricCylinder(
      radiusTop: radiusTop.toDouble(),
      radiusBottom: radiusBottom.toDouble(),
      height: height.toDouble(),
      segments: segments,
      capped: capped,
    ),
  {
    'shape': 'torus',
    'radius': final num radius,
    'tubeRadius': final num tubeRadius,
    'segments': final int segments,
    'tubeSegments': final int tubeSegments,
  } =>
    ParametricTorus(
      radius: radius.toDouble(),
      tubeRadius: tubeRadius.toDouble(),
      segments: segments,
      tubeSegments: tubeSegments,
    ),
  _ => null,
};

ParametricLathe? _latheFrom(
  List<Object?> profile, {
  required int segments,
  required double startAngle,
  required double sweepAngle,
  required bool closedProfile,
  required String name,
}) {
  final points = <Vector2>[];
  for (final Object? point in profile) {
    if (point case [final num x, final num y]) {
      points.add(Vector2(x.toDouble(), y.toDouble()));
    } else {
      return null;
    }
  }
  return ParametricLathe(
    profile: points,
    segments: segments,
    startAngle: startAngle,
    sweepAngle: sweepAngle,
    closedProfile: closedProfile,
    name: name,
  );
}
