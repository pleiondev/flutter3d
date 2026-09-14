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
/// object with its id, name, parent, transform, material slots, which kind of
/// geometry it has, which skeleton (if any) its mesh is skinned to and its
/// own shape keys — the material table those slots index, the project's own
/// skeletons and animation clips — plus three tables of bulk and the blob
/// they all point into. An edited mesh is one chunk written by
/// `EditMesh.toBytes`, so there is exactly one half-edge encoding in this
/// repository; an imported one is its vertex and index buffers as they
/// arrived, with the layout that says how to read them kept in the manifest
/// beside its row; and an image is its encoded bytes, never decoded here,
/// because decoding needs `dart:ui` and this package has no window.
///
/// **The split between the manifest and the blob is bulk, not importance.** A
/// material is a dozen numbers and five texture slots, so it goes in the JSON
/// where a person can read it; the PNG it samples is a hundred kilobytes, so it
/// goes in the blob. That is why there is a material *section* in the plan and
/// none here: what the plan wanted was for materials to survive, and a section
/// of their own would be a second encoding to keep working. A skeleton's
/// joints and inverse bind matrices, and a clip's own tracks, are the same
/// shape of small, structured data — `anim-03`'s own `ProjectSkeleton`/
/// `ProjectClip` — so they live in the manifest beside the materials rather
/// than in a section of their own, for the identical reason.
///
/// **The undo stack rides in the file too, `doc-31d`'s own section — stale
/// wording here once called this "not written," from before that row
/// landed; corrected rather than left to mislead the next reader.** Every
/// [HistoryStep]'s own `objects` addresses the identical `editMeshes`/
/// `importedMeshes` tables the live project's own objects do, deduplicated
/// by identity the same way: a step that shares a mesh with an earlier one
/// or with the live document costs the file nothing extra to carry, since
/// [writeProject]'s own `meshAt`/`importedAt` maps are built once, walked
/// oldest step first. `history` is optional on write — a file with none is
/// not a smaller version of one with some, it is the ordinary shape most
/// calls to [writeProject] take. A shape key's own positions are
/// written as plain JSON numbers in the manifest, not blob-encoded the way a
/// mesh's own vertex buffer is — the simpler choice, and the honest cost of
/// it is a project with several heavily sculpted shape keys writing a larger
/// manifest than one with none; nothing in this row's own acceptance needs
/// more than that.
///
/// Morph targets on an imported mesh are still refused by [writeProject] rather
/// than written half. See the throw there for why refusing beats saving a model
/// that opens missing what the person could see when they pressed the button.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_core/formats.dart';
import 'package:flutter3d_core/geometry.dart';
import 'package:flutter3d_mesh/flutter3d_mesh.dart';
import 'package:vector_math/vector_math.dart';

import 'command.dart';
import 'history.dart';
import 'lod_spec.dart';
import 'material.dart';
import 'parametric_json.dart';
import 'project.dart';
import 'project_animation.dart';
import 'project_morphs.dart';
import 'selection.dart';
import 'shape_driver.dart';
import 'texture_budget.dart';
import 'texture_graph.dart';
import 'texture_info.dart';

/// `F3DP`, little-endian, so a file opened in a text editor announces itself on
/// the first line and does not collide with `.f3d`'s own `F3D\n`.
const int kProjectMagic = 0x50443346;

/// Moves only when an existing record changes meaning. A new section does not
/// need it, because an older reader steps over a kind it does not know.
const int kProjectVersion = 1;

const int kProjectHeaderBytes = 16;

/// Where the header keeps the CRC-32 of the checksum section itself.
///
/// **The one thing the checksum table cannot check is the checksum table.** A
/// corrupted table reports whichever section its damaged row names, which is a
/// refusal with the wrong sentence in it — and this file's rule is that a
/// refusal names the number that did not add up. Four bytes in the header,
/// which were reserved and zero, close that: zero still means "no checksums",
/// so nothing about an older file changes meaning.
const int kProjectChecksumOffset = 12;
const int kProjectSectionEntryBytes = 16;

/// One entry of the edited-mesh table: u32 offset into the blob, u32 length.
const int kProjectMeshEntryBytes = 8;

/// One entry of the imported-mesh table: u32 vertex offset, u32 vertex length,
/// u32 index offset, u32 index length, all into the blob.
///
/// The two buffers are addressed separately rather than as one run, because
/// they are different widths — floats and `uint32`s — and a reader that took
/// one run and split it by a count in the manifest would be trusting the
/// manifest to describe bytes it cannot see.
const int kProjectImportedEntryBytes = 16;

/// One entry of the image table: u32 offset into the blob, u32 length.
const int kProjectImageEntryBytes = 8;

/// One entry of the checksum table: u32 section kind, u32 CRC-32.
const int kProjectChecksumEntryBytes = 8;

/// Section kinds.
///
/// Explicit numbers, never an enum's index: the number goes into a file that
/// outlives this source, and reordering a declaration would silently
/// reinterpret every project already saved. The plan names further sections —
/// skins, animations and the command journal — and each takes a number of its
/// own from 8 upwards. None of them may reuse 1 to 7.
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

  /// `count` entries of [kProjectImportedEntryBytes], addressing [blob]: the
  /// vertex and index buffers of a mesh that arrived from a file with no
  /// topology behind it.
  ///
  /// A table of its own rather than more rows in [editMeshes], because the two
  /// hold different things: an edited mesh is one `EditMesh.toBytes` chunk, and
  /// an imported one is two buffers and a layout that says how to read the
  /// first. Sharing a table would mean an entry that means one thing or the
  /// other depending on which object happens to name it.
  static const int importedMeshes = 4;

  /// `count` entries of [kProjectImageEntryBytes], addressing [blob]: the
  /// encoded bytes of each image, in whatever format they arrived as.
  ///
  /// The bytes and nothing else. What an image is called and what it was
  /// encoded as are two short strings, which live in the manifest beside the
  /// row — and the pixels are never decoded here, because decoding needs
  /// `dart:ui` and this package has no window. A project saved on a machine
  /// that could not decode a texture still writes it back out whole.
  static const int images = 5;

  /// `count` entries of [kProjectChecksumEntryBytes]: a section kind and the
  /// CRC-32 of that section's bytes, for every section in the file but this
  /// one.
  ///
  /// **Per section rather than one sum over the file, because a refusal that
  /// names the damage is worth more than one that does not.** This file's whole
  /// doctrine about bad files is that "corrupt" is a thing nobody can act on
  /// and "section 3 runs from 200 for 64 bytes" is a thing somebody can take to
  /// whoever wrote it. A single digest gives one bit; a sum per section says
  /// which part went, and a reader that one day opens what it can will already
  /// know that the manifest is sound and the mesh blob is not.
  ///
  /// **Pairs of (kind, sum) rather than sums in directory order**, so that the
  /// table does not have to be read in step with the directory, and so that a
  /// section this build has never heard of is still checked.
  ///
  /// Absent from a file means nothing is verified, which is what makes this
  /// additive: it is a new section, and the rule for those is that an older
  /// reader steps over what it does not know.
  static const int checksums = 6;

  /// `doc-31d`'s own section: JSON, the same shape the manifest itself is —
  /// `{'steps': [...], 'images': [...]}`, oldest step first, each `{says,
  /// command, selectionBefore, author, objects}` — `objects` shaped exactly
  /// like the manifest's own, so a step's `geometry.mesh` index addresses the
  /// same [editMeshes]/[importedMeshes] tables the live project's objects do.
  /// `author` (`mcp-10n`) is optional, read back as a person's own step when
  /// absent — a file written before that row existed named nobody.
  ///
  /// **A step's mesh index names that step's own geometry.** A mesh command
  /// edits its `EditMesh` in place, so a kept `before` project and the live one
  /// hold the same instance; the writer rolls that mesh's journal back step by
  /// step while it writes, and a chunk is shared only between moments whose
  /// geometry really is the same.
  ///
  /// **`profile`, `nextId`, `materials`, `images`, `skeletons` and `clips` are
  /// optional on a step, and absent means "as in the state after it"** — the
  /// next step's `before`, or the live project for the newest. So a step
  /// carries a table only where a command changed it, and trimming the oldest
  /// steps never strands a newer one. `images` is a list of rows: below the
  /// live image table's length a row of [images], at or above it a row of
  /// [historyImages], whose names are the section's own top-level `images`.
  ///
  /// Absent, not present-and-empty, for a file nobody asked to carry history
  /// for — [writeProject]'s own `history` parameter is null far more often
  /// than not, and a section that is never written is one an older reader
  /// never has to skip.
  static const int history = 7;

  /// `count` entries of [kProjectImageEntryBytes], addressing [blob]: images a
  /// step of [history] still samples and the live project no longer holds —
  /// a texture replaced or removed somewhere inside the kept steps.
  ///
  /// A table of its own rather than more rows in [images], because the
  /// manifest names exactly the rows of that table and an older reader holds
  /// it to that count; rows only history needs would open in that reader as
  /// images the project does not have. Absent when history needs none.
  static const int historyImages = 8;
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
  const ProjectOpened(
    this.project, {
    this.warnings = const <String>[],
    this.history = const <HistoryStep>[],
  });

  final ModelProject project;

  /// What the file held that this build read rather than refused, in its own
  /// words: an unrecognised alpha mode, wrap mode or profile target from a
  /// newer build, opened as the fallback that name names above. Empty for a
  /// file with nothing to say about — every field it named, this build knew.
  final List<String> warnings;

  /// `doc-31d`'s own history, oldest step first — empty for a file with no
  /// `history` section, the ordinary case, not merely a possible one.
  ///
  /// A caller after undo/redo builds `ModelHistory.withSteps(project,
  /// history)` rather than the plain constructor; one with no use for
  /// history — a headless export, say — reads [project] alone and never
  /// looks at this.
  final List<HistoryStep> history;
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

/// Whether [bytes] begin the way a project file does.
///
/// **For deciding what a file is, not whether it is sound.** A person picks a
/// file out of a folder and the application has to know whether to hand it to
/// `readProject` or to a model decoder, and the answer is in the first four
/// bytes rather than in the name: a `.f3dproj` renamed to `.glb` is still a
/// project, and an extension is a thing anybody can type. Mirrors `isF3dFile`
/// next door, and for the same reason.
///
/// Says nothing about the rest of the file — [readProject] is what checks that
/// and has a sentence for every way it can be wrong.
bool isProjectFile(Uint8List bytes) {
  if (bytes.lengthInBytes < 4) return false;
  final view = ByteData.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  return view.getUint32(0, Endian.little) == kProjectMagic;
}

/// The project as a `.f3dproj` file.
///
/// Deterministic: the same project writes the same bytes. The manifest's keys
/// go in a fixed order because they are built in one, the meshes go in the
/// order the objects do, and `EditMesh.toBytes` is deterministic itself. A file
/// that changes when the document did not is a file nobody can diff and a save
/// that dirties a repository for nothing.
///
/// Throws [ArgumentError] on an imported mesh carrying morph targets, which is
/// the one thing a project can hold that there is still nowhere to write. A
/// refusal at the call site beats the alternative: dropping a face's
/// expressions gives a file whose loss nothing downstream can detect.
Uint8List writeProject(
  ModelProject project, {
  ModelHistory? history,
  int maxHistoryBytes = 4 * 1024 * 1024,
}) {
  final meshes = <Uint8List>[];

  // Edited meshes, deduplicated by identity *and* by how far that mesh's
  // journal has been rolled back: `doc-31d`'s own reason this exists at all —
  // a history step's `before` project and the live one share every
  // `EditMesh` neither of them touched, and writing each of those once,
  // addressed by index, is the whole of what keeps a file with history from
  // costing one full mesh copy a step. Identity alone is not enough, because
  // a mesh command edits its mesh in place: the step before an extrusion
  // holds the very instance the live project does, at a different point in
  // its journal. `EditMesh` has no `==`, so a record of the instance and a
  // depth is identity-keyed on the mesh and value-keyed on the depth.
  final meshAt = <(EditMesh, int), int>{};

  // How many journal steps each mesh has been rolled back while the history
  // is walked newest first; every one is rolled forward again before this
  // function returns, whatever it returns with.
  final rolledBack = <EditMesh, int>{};

  // Every image row the file names. The live project's own come first and
  // keep their order — they are the image table the manifest describes —
  // and an image only a kept step still samples is appended after them.
  final imageAt = Map<EncodedImage, int>.identity();
  for (var i = 0; i < project.images.length; i++) {
    imageAt.putIfAbsent(project.images[i], () => i);
  }
  final historyImages = <EncodedImage>[];
  int imageRow(EncodedImage image) => imageAt.putIfAbsent(image, () {
    historyImages.add(image);
    return project.images.length + historyImages.length - 1;
  });

  // Imported buffers, deduplicated by identity: two objects drawing the same
  // `MeshData` — which is what an instanced prop becomes — write it once and
  // name the same row. Compared by identity rather than by content, for the
  // reason `SceneSync` gives about the same question: comparing two buffers of
  // ten thousand floats costs more than writing the second copy would.
  final imported = <MeshData>[];
  final importedAt = <MeshData, int>{};
  final importedJson = <Map<String, Object?>>[];

  List<Map<String, Object?>> objectsJsonFor(List<ModelObject> objectList) {
    final out = <Map<String, Object?>>[];
    for (final ModelObject object in objectList) {
      final Map<String, Object?> geometry;
      switch (object.geometry) {
        case ParametricGeometry(:final ParametricShape shape):
          geometry = <String, Object?>{
            'kind': 'parametric',
            ...parametricShapeJson(shape),
          };
        case EditedGeometry(:final EditMesh mesh):
          final at = meshAt.putIfAbsent((mesh, rolledBack[mesh] ?? 0), () {
            meshes.add(mesh.toBytes());
            return meshes.length - 1;
          });
          geometry = <String, Object?>{'kind': 'edited', 'mesh': at};
        case ImportedGeometry(:final MeshData data):
          // Morph targets are the one thing an imported mesh can carry that
          // there is still nowhere to put. Refused rather than dropped, on
          // the rule the rest of this file keeps: a file that opens with the
          // face there and none of its expressions is a loss nothing
          // downstream can detect.
          if (data.morphTargets.isNotEmpty) {
            throw ArgumentError(
              'object ${object.id} ("${object.name}") holds a mesh with '
              '${data.morphTargets.length} morph targets, and this version '
              'of the format has nowhere to write them.',
            );
          }
          final at = importedAt.putIfAbsent(data, () {
            imported.add(data);
            importedJson.add(<String, Object?>{
              'layout': _layoutJson(data.layout),
            });
            return imported.length - 1;
          });
          geometry = <String, Object?>{'kind': 'imported', 'mesh': at};
        case SocketGeometry():
          geometry = <String, Object?>{'kind': 'socket'};
      }
      out.add(<String, Object?>{
        'id': object.id,
        'name': object.name,
        'parent': object.parent,
        'version': object.version,
        'transform': <double>[...object.transform.storage],
        'materialSlots': <int>[...object.materialSlots],
        'geometry': geometry,
        // `anim-03`/`anim-19`, both younger than the rest of this record and
        // read back the same optional way every other field grown since v1
        // is: absent means unskinned and shapeless, the ordinary case for
        // most objects most files ever hold.
        'skeletonIndex': object.skeletonIndex,
        'shapeSet': _shapeSetJson(object.shapeSet),
        // `anim-34d`, younger still — absent reads back as
        // `<ShapeDriver>[]`, the ordinary case of a shape key nobody has
        // wired to a bone yet.
        'shapeDrivers': _shapeDriversJson(object.shapeDrivers),
        // `pro-lod-03`, younger still — absent reads back as `<LodSpec>[]`,
        // the ordinary case of an object nobody has asked to simplify.
        'lods': _lodsJson(object.lods),
      });
    }
    return out;
  }

  // The live project first, with every mesh where the document holds it.
  final objects = objectsJsonFor(project.objects);

  // Every history step's own objects and tables, walked **newest first**,
  // because that is the only direction a journal can be walked: each step's
  // mesh steps are rolled back before its `before` is written, so a mesh
  // chunk names the geometry of that moment rather than of now. `history`
  // is null for the overwhelming majority of calls (every existing fixture
  // and every writer that does not ask for it), and stays that way rather
  // than defaulting to an empty `ModelHistory`: a file with no `history`
  // section and a file with an empty one both open with an empty history.
  //
  // A step whose meshes cannot be rolled back far enough — a journal cleared
  // underneath the history — stops the walk, and it and everything older are
  // left out: a step that would reopen holding the wrong geometry is worse
  // than one that is not there. `project` is `history.project`, so a
  // transaction still open has taken mesh steps no kept step accounts for,
  // and those go back first.
  final List<HistoryStep> steps = history?.steps ?? const <HistoryStep>[];
  final walked = List<Map<String, Object?>?>.filled(steps.length, null);
  var oldestWritten = steps.length;
  try {
    if (history != null && _rollBack(history.openMeshSteps, rolledBack)) {
      for (var k = steps.length - 1; k >= 0; k--) {
        final HistoryStep step = steps[k];
        if (!_rollBack(step.meshSteps, rolledBack)) break;
        walked[k] = _stepJson(
          step,
          after: k == steps.length - 1 ? project : steps[k + 1].before,
          objects: objectsJsonFor(step.before.objects),
          imageRow: imageRow,
        );
        oldestWritten = k;
      }
    }
  } finally {
    for (final MapEntry<EditMesh, int> each in rolledBack.entries) {
      for (var i = 0; i < each.value; i++) {
        each.key.redo();
      }
    }
  }
  final stepJson = <Map<String, Object?>>[
    for (var k = oldestWritten; k < steps.length; k++) walked[k]!,
  ];

  final manifest = utf8.encode(
    jsonEncode(
      _canonical(<String, Object?>{
        'profile': _profileJson(project.profile),
        // Written down rather than worked out from the objects on the way back
        // in: an id belonging to something deleted must not be handed out again,
        // and `objects.length + 1` after a delete is exactly that mistake — a
        // step of history that named the old object would start naming the new
        // one the moment it was undone.
        'nextId': project.nextId,
        // Parallel to the imported-mesh table, one entry each: the table holds
        // where the bytes are and this holds how to read them. The layout is
        // structure rather than bulk, and structure lives in the manifest — a
        // layout encoded into a fixed-width table row would need a length and a
        // name table of its own to hold "position", "texcoord" and the rest.
        'importedMeshes': importedJson,
        // Materials are structure rather than bulk — a handful of numbers and
        // five texture slots each — so they live in the manifest with everything
        // else that is not a buffer. Only the images they sample go in the blob.
        'materials': <Object?>[
          for (final ProjectMaterial each in project.materials)
            _materialJson(each),
        ],
        // Parallel to the image table: the table says where the bytes are and
        // this says what they are called and what they were encoded as. Both are
        // written even when there are none, so the manifest's shape does not
        // depend on what the project happens to hold.
        'images': <Object?>[
          for (final EncodedImage each in project.images)
            <String, Object?>{'name': each.name, 'mimeType': each.mimeType},
        ],
        // `anim-03`, the same "structure, not bulk" reasoning as materials
        // above — a skeleton's own joints and matrices, and a clip's own
        // tracks, are numbers and names, not the multi-kilobyte buffer a
        // mesh chunk is. Written even when there are none, for the same
        // reason `images` is.
        'skeletons': <Object?>[
          for (final ProjectSkeleton each in project.skeletons)
            _skeletonJson(each),
        ],
        'clips': <Object?>[
          for (final ProjectClip each in project.clips) _clipJson(each),
        ],
        'objects': objects,
      }),
    ),
  );

  // One blob for both tables. Everything that goes in it is placed here, in
  // the order it is written, so that an offset is recorded by the same code
  // that reserves the room for it — the shape the old two-pass version got
  // wrong once already by aligning in one pass and copying in the other.
  final chunks = <Uint8List>[];
  final placed = <int>[];
  var blobLength = 0;
  int place(Uint8List chunk) {
    final at = blobLength;
    chunks.add(chunk);
    placed.add(at);
    blobLength = _align(at + chunk.lengthInBytes);
    return at;
  }

  final editedOffsets = <int>[for (final Uint8List mesh in meshes) place(mesh)];
  // Left to right, so the vertices are placed before the indices and the pair
  // reads in the order the table row holds them.
  final importedOffsets = <(int, int, int, int)>[
    for (final MeshData mesh in imported)
      (
        place(_rawBytes(mesh.vertices)),
        mesh.vertices.lengthInBytes,
        place(_rawBytes(mesh.indices)),
        mesh.indices.lengthInBytes,
      ),
  ];

  final imageOffsets = <(int, int)>[
    for (final EncodedImage each in project.images)
      (place(each.bytes), each.bytes.lengthInBytes),
  ];
  final historyImageOffsets = <(int, int)>[
    for (final EncodedImage each in historyImages)
      (place(each.bytes), each.bytes.lengthInBytes),
  ];

  final blob = Uint8List(blobLength);
  for (var i = 0; i < chunks.length; i++) {
    blob.setRange(placed[i], placed[i] + chunks[i].lengthInBytes, chunks[i]);
  }

  final table = Uint8List(meshes.length * kProjectMeshEntryBytes);
  final tableView = ByteData.view(table.buffer);
  for (var i = 0; i < meshes.length; i++) {
    tableView
      ..setUint32(i * kProjectMeshEntryBytes, editedOffsets[i], Endian.little)
      ..setUint32(
        i * kProjectMeshEntryBytes + 4,
        meshes[i].lengthInBytes,
        Endian.little,
      );
  }

  final importedTable = Uint8List(imported.length * kProjectImportedEntryBytes);
  final importedView = ByteData.view(importedTable.buffer);
  for (var i = 0; i < imported.length; i++) {
    final (int vertexAt, int vertexBytes, int indexAt, int indexBytes) =
        importedOffsets[i];
    final entry = i * kProjectImportedEntryBytes;
    importedView
      ..setUint32(entry, vertexAt, Endian.little)
      ..setUint32(entry + 4, vertexBytes, Endian.little)
      ..setUint32(entry + 8, indexAt, Endian.little)
      ..setUint32(entry + 12, indexBytes, Endian.little);
  }

  final imageTable = Uint8List(project.images.length * kProjectImageEntryBytes);
  final imageView = ByteData.view(imageTable.buffer);
  for (var i = 0; i < imageOffsets.length; i++) {
    final (int at, int length) = imageOffsets[i];
    imageView
      ..setUint32(i * kProjectImageEntryBytes, at, Endian.little)
      ..setUint32(i * kProjectImageEntryBytes + 4, length, Endian.little);
  }

  final historyImageTable = Uint8List(
    historyImages.length * kProjectImageEntryBytes,
  );
  final historyImageView = ByteData.view(historyImageTable.buffer);
  for (var i = 0; i < historyImageOffsets.length; i++) {
    final (int at, int length) = historyImageOffsets[i];
    historyImageView
      ..setUint32(i * kProjectImageEntryBytes, at, Endian.little)
      ..setUint32(i * kProjectImageEntryBytes + 4, length, Endian.little);
  }

  // Г5's own byte limit, trimming the *oldest* steps first — the same
  // direction `ModelHistory`'s own depth limit already trims in
  // (`_done.removeAt(0)`). A mesh a trimmed step alone referenced stays in
  // the blob unreferenced by anything the history section still names,
  // spent rather than reclaimed, which is the one honest cost of deciding
  // what to keep after the blob is already built.
  final trimmedSteps = _trimmedToFit(stepJson, maxHistoryBytes);

  final sections = <(int kind, Uint8List data, int count)>[
    (ProjectSection.manifest, manifest, 0),
    (ProjectSection.editMeshes, table, meshes.length),
    (ProjectSection.blob, blob, 0),
    // Written even when empty, so that the directory of every file this build
    // produces has the same shape and a reader is never deciding between "no
    // imported meshes" and "an older writer".
    (ProjectSection.importedMeshes, importedTable, imported.length),
    (ProjectSection.images, imageTable, project.images.length),
    // Absent, not merely empty, when nobody asked for history at all — see
    // `stepJson`'s own comment.
    if (history != null)
      (
        ProjectSection.history,
        utf8.encode(
          jsonEncode(
            _canonical(<String, Object?>{
              'steps': trimmedSteps,
              if (historyImages.isNotEmpty)
                'images': <Object?>[
                  for (final EncodedImage each in historyImages)
                    <String, Object?>{
                      'name': each.name,
                      'mimeType': each.mimeType,
                    },
                ],
            }),
          ),
        ),
        trimmedSteps.length,
      ),
    if (historyImages.isNotEmpty)
      (ProjectSection.historyImages, historyImageTable, historyImages.length),
  ];

  // Computed over the section data, before anything knows where in the file it
  // will land: an offset is the directory's business and a sum is about the
  // bytes. That is also what lets the table be built here, one row per section
  // written so far, with itself left out.
  final checksums = Uint8List(sections.length * kProjectChecksumEntryBytes);
  final checksumView = ByteData.view(checksums.buffer);
  for (var i = 0; i < sections.length; i++) {
    final (int kind, Uint8List data, int _) = sections[i];
    checksumView
      ..setUint32(i * kProjectChecksumEntryBytes, kind, Endian.little)
      ..setUint32(
        i * kProjectChecksumEntryBytes + 4,
        crc32(data),
        Endian.little,
      );
  }
  sections.add((ProjectSection.checksums, checksums, sections.length));

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
    // The sum of the checksum table, which is the one thing the table cannot
    // sum. Zero means a file with no checksums in it, so an older file keeps
    // its meaning.
    ..setUint32(kProjectChecksumOffset, crc32(checksums), Endian.little);

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

  // Before anything is decoded. A manifest that parses as JSON after a byte
  // flip is the case this exists for: it opens as a silently different model,
  // and everything downstream believes it.
  final String? damaged = _verifyChecksums(bytes, view, sections);
  if (damaged != null) return ProjectRefused(damaged);

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

  // One pool, and one only, for the whole file: every string this build reads
  // out of the manifest — a vertex attribute's name repeated on every mesh
  // that has one, an image's mimeType, a material's own name or its `.fmat`
  // path, an object's name — goes through it, so a project holding thousands
  // of copies of "position" or "image/png" holds one Dart string for each,
  // not thousands. See `_intern`'s own doc comment for the number this
  // actually matters at.
  final pool = <String, String>{};

  final (List<MeshData> arrived, String? importRefusal) = _readImported(
    bytes,
    sections,
    document is Map<String, Object?> ? document['importedMeshes'] : null,
    pool,
  );
  if (importRefusal != null) return ProjectRefused(importRefusal);

  final (List<EncodedImage> images, String? imageRefusal) = _readImages(
    bytes,
    sections,
    document is Map<String, Object?> ? document['images'] : null,
    pool,
  );
  if (imageRefusal != null) return ProjectRefused(imageRefusal);

  // Collected rather than returned as they are found, because a warning is
  // never the reason to stop: everything that could add one already has a
  // fallback in hand, and a file worth opening at all is a file worth opening
  // whole.
  final warnings = <String>[];

  final (
    List<ProjectMaterial> materials,
    String? materialRefusal,
  ) = _readMaterials(
    document is Map<String, Object?> ? document['materials'] : null,
    warnings,
    pool,
  );
  if (materialRefusal != null) return ProjectRefused(materialRefusal);

  final (
    List<ProjectSkeleton> skeletons,
    String? skeletonRefusal,
  ) = _readSkeletons(
    document is Map<String, Object?> ? document['skeletons'] : null,
  );
  if (skeletonRefusal != null) return ProjectRefused(skeletonRefusal);

  final (List<ProjectClip> clips, String? clipRefusal) = _readClips(
    document is Map<String, Object?> ? document['clips'] : null,
  );
  if (clipRefusal != null) return ProjectRefused(clipRefusal);

  if (document case {
    'profile': final Object? profileJson,
    'nextId': final int nextId,
    'objects': final List<Object?> entries,
  }) {
    final ProjectProfile? profile = _readProfile(profileJson, warnings);
    if (profile == null) {
      return const ProjectRefused(
        'The manifest is not shaped like a project: it needs a profile with '
        'its five original limits, the nextId, and a list of objects.',
      );
    }
    final objects = <ModelObject>[];
    for (var i = 0; i < entries.length; i++) {
      final (ModelObject? object, String? refusal) = _readObject(
        entries[i],
        i,
        meshes,
        arrived,
        pool,
      );
      if (refusal != null) return ProjectRefused(refusal);
      objects.add(object!);
    }

    final (List<HistoryStep> history, String? historyRefusal) = _readHistory(
      bytes,
      sections,
      meshes,
      arrived,
      pool,
      profile: profile,
      materials: materials,
      images: images,
      skeletons: skeletons,
      clips: clips,
      nextId: nextId,
      warnings: warnings,
    );
    if (historyRefusal != null) return ProjectRefused(historyRefusal);

    return ProjectOpened(
      ModelProject(
        profile: profile,
        objects: objects,
        materials: materials,
        images: images,
        skeletons: skeletons,
        clips: clips,
        nextId: nextId,
      ),
      warnings: warnings,
      history: history,
    );
  }

  return const ProjectRefused(
    'The manifest is not shaped like a project: it needs a profile with its '
    'five limits, the nextId, and a list of objects.',
  );
}

/// `doc-31d`'s own `history` section, or the sentence that stops the file
/// being read — empty, not refused, when the section is simply absent, which
/// is the ordinary shape of a file nobody asked to carry history for.
///
/// [meshes] and [arrived] are the same decoded tables the live project's own
/// objects were just read against: a step's own `objects` addresses the
/// identical `editMeshes`/`importedMeshes` indices, since [writeProject]
/// built both from the same shared tables.
///
/// **[profile], [materials], [images], [skeletons], [clips] and [nextId] are
/// the live project's own, and they are where the walk starts.** Steps are
/// read newest first: a table a step names is that step's `before`, and a
/// table it leaves out is the one the state after it holds — so a file whose
/// steps name no tables, which is every file written before steps could,
/// opens exactly as it always did, every `before` borrowing the current
/// tables. Image rows address the live table first and the
/// [ProjectSection.historyImages] table after it; see [ProjectSection.history].
(List<HistoryStep>, String?) _readHistory(
  Uint8List bytes,
  Map<int, ({int offset, int length})> sections,
  List<EditMesh> meshes,
  List<MeshData> arrived,
  Map<String, String> pool, {
  required ProjectProfile profile,
  required List<ProjectMaterial> materials,
  required List<EncodedImage> images,
  required List<ProjectSkeleton> skeletons,
  required List<ProjectClip> clips,
  required int nextId,
  required List<String> warnings,
}) {
  final at = sections[ProjectSection.history];
  if (at == null) return (const <HistoryStep>[], null);

  final Object? document;
  try {
    document = jsonDecode(
      utf8.decode(
        Uint8List.sublistView(bytes, at.offset, at.offset + at.length),
      ),
    );
  } on FormatException catch (error) {
    return (
      const <HistoryStep>[],
      'The history section is not JSON: ${error.message}',
    );
  }
  if (document is! Map<String, Object?> || document['steps'] is! List) {
    return (
      const <HistoryStep>[],
      'The history section is not shaped like a list of steps.',
    );
  }

  final entries = document['steps']! as List;

  final (List<EncodedImage> historyImages, String? imageRefusal) = _readImages(
    bytes,
    sections,
    document['images'],
    pool,
    tableKind: ProjectSection.historyImages,
  );
  if (imageRefusal != null) {
    return (const <HistoryStep>[], 'The history\'s own images: $imageRefusal');
  }
  final rows = <EncodedImage>[...images, ...historyImages];

  // What the state after the step being read holds, table by table — the
  // live project's to begin with, then each `before` in turn. State, because
  // the walk is what it describes.
  var carriedProfile = profile;
  var carriedNextId = nextId;
  var carriedMaterials = materials;
  var carriedImages = images;
  var carriedSkeletons = skeletons;
  var carriedClips = clips;
  final noticed = <String>[];

  final steps = List<HistoryStep?>.filled(entries.length, null);
  for (var i = entries.length - 1; i >= 0; i--) {
    if (entries[i]
        case final Map<String, Object?> step &&
            {
              'says': final String says,
              'command': final Map<String, Object?> commandJson,
              'selectionBefore': final Object? selectionJson,
              'objects': final List<Object?> objectEntries,
            }) {
      final ModelCommand? command = modelCommandFromJson(commandJson);
      if (command == null) {
        return (
          const <HistoryStep>[],
          'History step $i ("$says") names a command this build does not '
              'know.',
        );
      }
      final ProjectSelection? selection = ProjectSelection.fromJson(
        selectionJson,
      );
      if (selection == null) {
        return (
          const <HistoryStep>[],
          'History step $i ("$says") has no readable selection.',
        );
      }
      final objects = <ModelObject>[];
      for (var j = 0; j < objectEntries.length; j++) {
        final (ModelObject? object, String? refusal) = _readObject(
          objectEntries[j],
          j,
          meshes,
          arrived,
          pool,
        );
        if (refusal != null) {
          return (const <HistoryStep>[], 'History step $i: $refusal');
        }
        objects.add(object!);
      }
      final author = switch (entries[i]) {
        {'author': 'agent'} => StepAuthor.agent,
        _ => StepAuthor.person,
      };
      if (step.containsKey('profile')) {
        final ProjectProfile? read = _readProfile(step['profile'], noticed);
        if (read == null) {
          return (
            const <HistoryStep>[],
            'History step $i ("$says") has a profile this build cannot read.',
          );
        }
        carriedProfile = read;
      }
      if (step.containsKey('nextId')) {
        final Object? id = step['nextId'];
        if (id is! int) {
          return (
            const <HistoryStep>[],
            'History step $i ("$says") has a nextId that is not a whole '
                'number.',
          );
        }
        carriedNextId = id;
      }
      if (step.containsKey('materials')) {
        final (List<ProjectMaterial> read, String? refusal) = _readMaterials(
          step['materials'],
          noticed,
          pool,
        );
        if (refusal != null) {
          return (const <HistoryStep>[], 'History step $i: $refusal');
        }
        carriedMaterials = read;
      }
      if (step.containsKey('images')) {
        final Object? picked = step['images'];
        if (picked is! List ||
            !picked.every(
              (Object? row) => row is int && row >= 0 && row < rows.length,
            )) {
          return (
            const <HistoryStep>[],
            'History step $i ("$says") names image rows that are not among '
                'the ${rows.length} the file holds.',
          );
        }
        carriedImages = <EncodedImage>[
          for (final Object? row in picked) rows[row! as int],
        ];
      }
      if (step.containsKey('skeletons')) {
        final (List<ProjectSkeleton> read, String? refusal) = _readSkeletons(
          step['skeletons'],
        );
        if (refusal != null) {
          return (const <HistoryStep>[], 'History step $i: $refusal');
        }
        carriedSkeletons = read;
      }
      if (step.containsKey('clips')) {
        final (List<ProjectClip> read, String? refusal) = _readClips(
          step['clips'],
        );
        if (refusal != null) {
          return (const <HistoryStep>[], 'History step $i: $refusal');
        }
        carriedClips = read;
      }
      steps[i] = HistoryStep(
        command: command,
        before: ModelProject(
          profile: carriedProfile,
          objects: objects,
          materials: carriedMaterials,
          images: carriedImages,
          skeletons: carriedSkeletons,
          clips: carriedClips,
          nextId: carriedNextId,
        ),
        selectionBefore: selection,
        author: author,
      );
    } else {
      return (
        const <HistoryStep>[],
        'History step $i is not shaped like a step: it needs says, a '
            'command, a selection and a list of objects.',
      );
    }
  }
  // Said once rather than once a step: a newer build's value a kept table
  // names is the same news however many steps carry it.
  for (final String each in noticed) {
    if (!warnings.contains(each)) warnings.add(each);
  }
  return (<HistoryStep>[for (final HistoryStep? each in steps) each!], null);
}

/// The imported meshes, or the sentence that stops the file being read.
///
/// Two halves that have to agree: the table says where the bytes are and
/// [layouts] — the manifest's `importedMeshes` — says how to read them. A file
/// whose table holds three rows and whose manifest describes two is a file
/// nothing can open honestly, so it is refused with both numbers rather than
/// read down to the shorter of them.
(List<MeshData>, String?) _readImported(
  Uint8List bytes,
  Map<int, ({int offset, int length})> sections,
  Object? layouts,
  Map<String, String> pool,
) {
  final table = sections[ProjectSection.importedMeshes];
  final blob = sections[ProjectSection.blob];
  if (table == null || table.length == 0) return (const <MeshData>[], null);
  if (blob == null) {
    return (
      const <MeshData>[],
      'This file has an imported-mesh table and no blob for it to point into.',
    );
  }

  final count = table.length ~/ kProjectImportedEntryBytes;
  final described = layouts is List ? layouts.length : 0;
  if (described != count) {
    return (
      const <MeshData>[],
      'The imported-mesh table holds $count meshes and the manifest describes '
          '$described of them.',
    );
  }

  final view = ByteData.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  final meshes = <MeshData>[];
  for (var i = 0; i < count; i++) {
    final entry = table.offset + i * kProjectImportedEntryBytes;
    final vertexAt = view.getUint32(entry, Endian.little);
    final vertexBytes = view.getUint32(entry + 4, Endian.little);
    final indexAt = view.getUint32(entry + 8, Endian.little);
    final indexBytes = view.getUint32(entry + 12, Endian.little);

    if (vertexAt + vertexBytes > blob.length ||
        indexAt + indexBytes > blob.length) {
      return (
        const <MeshData>[],
        'Imported mesh $i runs from $vertexAt for $vertexBytes bytes and from '
            '$indexAt for $indexBytes, and the blob is ${blob.length} bytes long.',
      );
    }
    // Four bytes to a float and four to an index, so a length that is not a
    // multiple of four cannot be either. Checked because `Float32List.view`
    // throws on it, and a throw here is the one thing this function promises
    // not to do.
    if (vertexBytes % 4 != 0 || indexBytes % 4 != 0) {
      return (
        const <MeshData>[],
        'Imported mesh $i has $vertexBytes vertex bytes and $indexBytes index '
            'bytes, and both are counts of four-byte values.',
      );
    }

    final Object? described = (layouts! as List)[i];
    final layout = _layoutFrom(
      described is Map<String, Object?> ? described['layout'] : null,
      pool,
    );
    if (layout == null) {
      return (
        const <MeshData>[],
        'Imported mesh $i has no vertex layout this build can read; a layout '
            'is a non-empty list of attributes, each a name and a count of '
            'components.',
      );
    }
    final floats = vertexBytes ~/ 4;
    if (floats % layout.floatsPerVertex != 0) {
      return (
        const <MeshData>[],
        'Imported mesh $i holds $floats floats and its layout takes '
            '${layout.floatsPerVertex} to a vertex, which does not divide.',
      );
    }

    // Copied rather than viewed over the file, for two reasons. A view keeps
    // the whole file alive for as long as any mesh in it is drawn, and
    // `Float32List.view` refuses a byte offset that is not a multiple of four
    // — which the blob's own alignment happens to guarantee today and would
    // stop guaranteeing the moment anything wrote an unaligned section.
    Float32List floatsAt(int at, int length) => Float32List.sublistView(
      Uint8List.fromList(
        Uint8List.sublistView(
          bytes,
          blob.offset + at,
          blob.offset + at + length,
        ),
      ),
    );
    Uint32List indicesAt(int at, int length) => Uint32List.sublistView(
      Uint8List.fromList(
        Uint8List.sublistView(
          bytes,
          blob.offset + at,
          blob.offset + at + length,
        ),
      ),
    );

    meshes.add(
      MeshData(
        layout: layout,
        vertices: floatsAt(vertexAt, vertexBytes),
        indices: indicesAt(indexAt, indexBytes),
      ),
    );
  }
  return (meshes, null);
}

/// A material as JSON.
///
/// **Every field written, including the ones that are at their default.** A
/// codec that skipped defaults would be shorter and would make the file's
/// meaning depend on this build's idea of what a default is: change
/// `roughness`'s default one day and every project already saved quietly
/// becomes a different model. The file says what the material is.
///
/// **Enums are written by name, never by index**, for the reason the section
/// numbers are: `SurfaceAlphaMode.values` is a declaration order, and inserting
/// a case into it would reinterpret every file already written. A name this
/// build does not know reads back as the default rather than refusing, because
/// an alpha mode from a newer build is a material that draws slightly wrong,
/// not a project nobody can open.
/// [shapeSet] as JSON — `null` for the ordinary, shapeless object, so a
/// project that never touched `anim-19` writes exactly the file it would
/// have written before that row existed, modulo the `skeletonIndex`/
/// `shapeSet` keys themselves both being present and `null`.
Map<String, Object?>? _shapeSetJson(ShapeSet shapeSet) {
  if (shapeSet.isEmpty) return null;
  return <String, Object?>{
    'keys': <Object?>[
      for (final ShapeKey key in shapeSet.keys) _shapeKeyJson(key),
    ],
    'weights': <double>[...shapeSet.weights],
  };
}

Map<String, Object?> _shapeKeyJson(ShapeKey key) => <String, Object?>{
  'name': key.name,
  'positions': <double>[...key.positions],
};

/// [drivers] as JSON — `null` for the ordinary object with no shape
/// drivers, the same absent-means-empty shape [_shapeSetJson]/[_lodsJson]
/// keep for the same reason: a project that never touched `anim-34d`
/// writes exactly the file it would have written before this row existed.
List<Object?>? _shapeDriversJson(List<ShapeDriver> drivers) {
  if (drivers.isEmpty) return null;
  return <Object?>[for (final ShapeDriver driver in drivers) driver.toJson()];
}

/// [lods] as JSON — `null` for the ordinary object with no levels of detail,
/// the same absent-means-empty shape [_shapeSetJson] keeps for the same
/// reason: a project that never touched `pro-lod-03` writes exactly the
/// file it would have written before this row existed.
List<Object?>? _lodsJson(List<LodSpec> lods) {
  if (lods.isEmpty) return null;
  return <Object?>[
    for (final LodSpec lod in lods)
      <String, Object?>{
        'ratio': lod.ratio,
        'maxScreenFraction': lod.maxScreenFraction,
      },
  ];
}

/// Rolls each mesh in [steps] back by its count, noting every step taken in
/// [rolledBack] so the caller can roll exactly that far forward again. False
/// the moment a journal has nothing further back to give.
bool _rollBack(Map<EditMesh, int> steps, Map<EditMesh, int> rolledBack) {
  for (final MapEntry<EditMesh, int> each in steps.entries) {
    for (var i = 0; i < each.value; i++) {
      if (!each.key.undo()) return false;
      rolledBack[each.key] = (rolledBack[each.key] ?? 0) + 1;
    }
  }
  return true;
}

/// One history step as the `history` section writes it: what was done, and
/// the project before it — its objects always, and each table only where it
/// differs from [after], the state the step led to. See
/// [ProjectSection.history] for why absent means "as in the state after".
///
/// Compared by identity, the way `ModelProject` shares what an edit did not
/// touch: a false "changed" only costs a table written twice, never a wrong
/// one read back.
Map<String, Object?> _stepJson(
  HistoryStep step, {
  required ModelProject after,
  required List<Map<String, Object?>> objects,
  required int Function(EncodedImage image) imageRow,
}) {
  final ModelProject before = step.before;
  return <String, Object?>{
    'says': step.command.says,
    'command': step.command.toJson(),
    'selectionBefore': step.selectionBefore.toJson(),
    // `mcp-10n`, younger than the section itself — read back as
    // `StepAuthor.person` when absent, the same optional shape every field
    // this file has grown since v1 already takes.
    'author': step.author.name,
    'objects': objects,
    if (!identical(before.profile, after.profile))
      'profile': _profileJson(before.profile),
    if (before.nextId != after.nextId) 'nextId': before.nextId,
    if (!identical(before.materials, after.materials))
      'materials': <Object?>[
        for (final ProjectMaterial each in before.materials)
          _materialJson(each),
      ],
    if (!identical(before.images, after.images))
      'images': <int>[
        for (final EncodedImage each in before.images) imageRow(each),
      ],
    if (!identical(before.skeletons, after.skeletons))
      'skeletons': <Object?>[
        for (final ProjectSkeleton each in before.skeletons)
          _skeletonJson(each),
      ],
    if (!identical(before.clips, after.clips))
      'clips': <Object?>[
        for (final ProjectClip each in before.clips) _clipJson(each),
      ],
  };
}

Map<String, Object?> _profileJson(ProjectProfile profile) => <String, Object?>{
  'name': profile.name,
  'maxTriangles': profile.maxTriangles,
  'maxJoints': profile.maxJoints,
  'maxInfluences': profile.maxInfluences,
  'maxTextureSize': profile.maxTextureSize,
  // Written from `doc-13` on, and read back as a default rather than
  // required when absent — see `_readProfileExtras` — so a v1 file
  // written before these existed still opens.
  'target': profile.target.name,
  'maxTextureBytes': profile.maxTextureBytes,
  'requireTriangles': profile.requireTriangles,
  'requireManifold': profile.requireManifold,
  // `mat-28`, younger still than the four above and read back the
  // same optional way.
  'textures': <String, Object?>{
    'maxSide': profile.textures.maxSide,
    'maxBytesOnDevice': profile.textures.maxBytesOnDevice,
    'targetFormat': profile.textures.targetFormat.name,
    'requirePowerOfTwo': profile.textures.requirePowerOfTwo,
  },
  // `doc-35n`, younger even than `textures`, read back the same
  // optional way.
  'texelsPerMeter': profile.texelsPerMeter,
  // `syn-03`, younger still, read back the same optional way.
  'fps': profile.fps,
  'frameSnap': profile.frameSnap,
};

Map<String, Object?> _skeletonJson(ProjectSkeleton skeleton) =>
    <String, Object?>{
      'name': skeleton.name,
      'joints': <int>[...skeleton.joints],
      'inverseBindMatrices': <Object?>[
        for (final Matrix4 m in skeleton.inverseBindMatrices)
          <double>[...m.storage],
      ],
      'skeletonRoot': skeleton.skeletonRoot,
      'constraints': <Object?>[
        for (final IkConstraint c in skeleton.constraints) _ikConstraintJson(c),
      ],
    };

Map<String, Object?> _ikConstraintJson(IkConstraint c) => <String, Object?>{
  'rootJointId': c.rootJointId,
  'midJointId': c.midJointId,
  'effectorJointId': c.effectorJointId,
  'target': <double>[c.target.x, c.target.y, c.target.z],
  'pole': <double>[c.pole.x, c.pole.y, c.pole.z],
};

Map<String, Object?> _clipJson(ProjectClip clip) => <String, Object?>{
  'name': clip.name,
  'tracks': <Object?>[
    for (final ProjectTrack track in clip.tracks) _trackJson(track),
  ],
  'extras': clip.extras,
};

Map<String, Object?> _trackJson(ProjectTrack track) => <String, Object?>{
  'objectId': track.objectId,
  'path': track.track.path.toGltf(),
  'interpolation': track.track.interpolation.toGltf(),
  'componentCount': track.track.componentCount,
  'times': <double>[...track.track.times],
  'values': <double>[...track.track.values],
};

Map<String, Object?> _materialJson(ProjectMaterial material) {
  final surface = material.surface;
  return <String, Object?>{
    'version': material.version,
    'fmat': material.fmat,
    'graph': material.graph?.toJson(),
    'bakedAtVersion': material.bakedAtVersion,
    'name': surface.name,
    'baseColor': <double>[
      surface.baseColor.x,
      surface.baseColor.y,
      surface.baseColor.z,
      surface.baseColor.w,
    ],
    'metallic': surface.metallic,
    'roughness': surface.roughness,
    'baseColorTexture': _bindingJson(surface.baseColorTexture),
    'metallicRoughnessTexture': _bindingJson(surface.metallicRoughnessTexture),
    'normalTexture': _bindingJson(surface.normalTexture),
    'normalScale': surface.normalScale,
    'occlusionTexture': _bindingJson(surface.occlusionTexture),
    'occlusionStrength': surface.occlusionStrength,
    'emissiveTexture': _bindingJson(surface.emissiveTexture),
    'emissive': <double>[
      surface.emissive.x,
      surface.emissive.y,
      surface.emissive.z,
    ],
    'emissiveStrength': surface.emissiveStrength,
    'alphaMode': surface.alphaMode.name,
    'alphaCutoff': surface.alphaCutoff,
    'doubleSided': surface.doubleSided,
    'unlit': surface.unlit,
    // Younger than the fields above, read the same optional way `fmat` and
    // `graph` are (`_readMaterials`'s own doc comment): absent means no
    // shader has been chosen, not a refusal. Only a built-in shader's own
    // name travels here — `.fmat`'s own `_writeLighting` also writes a
    // custom shader as an object, which a project file has no reader for
    // yet, since nothing here builds one.
    if (surface.lightingModel case final LightingModel model)
      'lightingModel': model.shaderName,
  };
}

Map<String, Object?>? _bindingJson(TextureBinding? binding) => binding == null
    ? null
    : <String, Object?>{
        'imageIndex': binding.imageIndex,
        'texCoordSet': binding.texCoordSet,
        'magLinear': binding.sampling.magLinear,
        'minLinear': binding.sampling.minLinear,
        'useMipmaps': binding.sampling.useMipmaps,
        'mipLinear': binding.sampling.mipLinear,
        'wrapS': binding.sampling.wrapS.name,
        'wrapT': binding.sampling.wrapT.name,
      };

/// The materials [json] describes, or the sentence that stops the file.
///
/// A missing key is a refusal rather than a default, which is the opposite of
/// the rule for an unknown enum name and is the right way round: a name this
/// build has not heard of is something a newer build wrote, and a missing
/// `baseColor` is a file that was truncated or was never a project.
(List<ProjectMaterial>, String?) _readMaterials(
  Object? json,
  List<String> warnings,
  Map<String, String> pool,
) {
  if (json == null) return (const <ProjectMaterial>[], null);
  if (json is! List) {
    return (
      const <ProjectMaterial>[],
      'The manifest\'s materials are not a list.',
    );
  }

  final materials = <ProjectMaterial>[];
  for (var i = 0; i < json.length; i++) {
    final Object? entry = json[i];
    if (entry case <String, Object?>{
      'version': final int version,
      'name': final String? name,
      'baseColor': final List<Object?> baseColor,
      'metallic': final num metallic,
      'roughness': final num roughness,
      'normalScale': final num normalScale,
      'occlusionStrength': final num occlusionStrength,
      'emissive': final List<Object?> emissive,
      'emissiveStrength': final num emissiveStrength,
      'alphaMode': final String alphaMode,
      'alphaCutoff': final num alphaCutoff,
      'doubleSided': final bool doubleSided,
      'unlit': final bool unlit,
    } when version > 0) {
      if (baseColor.length != 4 || baseColor.any((Object? v) => v is! num)) {
        return (
          const <ProjectMaterial>[],
          'Material $i has a base colour of ${baseColor.length} numbers, and a '
              'colour is four.',
        );
      }
      if (emissive.length != 3 || emissive.any((Object? v) => v is! num)) {
        return (
          const <ProjectMaterial>[],
          'Material $i has an emissive colour of ${emissive.length} numbers, '
              'and that one is three.',
        );
      }
      materials.add(
        ProjectMaterial(
          version: version,
          // Younger than the rest of this record (`doc-10`), read the same
          // optional way `mipLinear` above is: absent means the ordinary
          // case, a material with no external file, not a refusal.
          fmat: switch (entry['fmat']) {
            final String s => _intern(s, pool),
            _ => null,
          },
          // Younger than `fmat` above, read the same optional way: absent
          // means a material painted by hand, never touched by
          // `SetMaterialGraph`.
          graph: switch (entry['graph']) {
            final Map<String, Object?> g => TextureGraph.fromJson(g),
            _ => null,
          },
          bakedAtVersion: entry['bakedAtVersion'] as int?,
          surface: SurfaceMaterial(
            name: name == null ? null : _intern(name, pool),
            baseColor: Vector4(
              (baseColor[0]! as num).toDouble(),
              (baseColor[1]! as num).toDouble(),
              (baseColor[2]! as num).toDouble(),
              (baseColor[3]! as num).toDouble(),
            ),
            metallic: metallic.toDouble(),
            roughness: roughness.toDouble(),
            baseColorTexture: _bindingFrom(
              entry['baseColorTexture'],
              warnings,
              'Material $i\'s baseColorTexture',
            ),
            metallicRoughnessTexture: _bindingFrom(
              entry['metallicRoughnessTexture'],
              warnings,
              'Material $i\'s metallicRoughnessTexture',
            ),
            normalTexture: _bindingFrom(
              entry['normalTexture'],
              warnings,
              'Material $i\'s normalTexture',
            ),
            normalScale: normalScale.toDouble(),
            occlusionTexture: _bindingFrom(
              entry['occlusionTexture'],
              warnings,
              'Material $i\'s occlusionTexture',
            ),
            occlusionStrength: occlusionStrength.toDouble(),
            emissiveTexture: _bindingFrom(
              entry['emissiveTexture'],
              warnings,
              'Material $i\'s emissiveTexture',
            ),
            emissive: Vector3(
              (emissive[0]! as num).toDouble(),
              (emissive[1]! as num).toDouble(),
              (emissive[2]! as num).toDouble(),
            ),
            emissiveStrength: emissiveStrength.toDouble(),
            alphaMode: _named(
              SurfaceAlphaMode.values,
              alphaMode,
              SurfaceAlphaMode.opaque,
              warnings: warnings,
              context: 'Material $i\'s alphaMode',
            ),
            alphaCutoff: alphaCutoff.toDouble(),
            doubleSided: doubleSided,
            unlit: unlit,
            lightingModel: _lightingModelNamed(
              entry['lightingModel'],
              warnings,
              'Material $i\'s lightingModel',
            ),
          ),
        ),
      );
      continue;
    }
    return (
      const <ProjectMaterial>[],
      'Material $i is missing a field or has one of the wrong type: a material '
          'is a version above zero, a name, two colours, its factors, its texture '
          'slots and how it treats alpha.',
    );
  }
  return (materials, null);
}

TextureBinding? _bindingFrom(
  Object? json,
  List<String> warnings,
  String context,
) {
  if (json case <String, Object?>{
    'imageIndex': final int imageIndex,
    'texCoordSet': final int texCoordSet,
    'magLinear': final bool magLinear,
    'minLinear': final bool minLinear,
    'useMipmaps': final bool useMipmaps,
    'wrapS': final String wrapS,
    'wrapT': final String wrapT,
  } when imageIndex >= 0 && texCoordSet >= 0) {
    return TextureBinding(
      imageIndex: imageIndex,
      texCoordSet: texCoordSet,
      sampling: TextureSampling(
        magLinear: magLinear,
        minLinear: minLinear,
        useMipmaps: useMipmaps,
        // Younger than the other four (`fmt-05`) and read the way `doc-13`'s
        // profile fields are: optional, so a file saved before it existed
        // opens as the default it already meant rather than being refused.
        mipLinear: json['mipLinear'] as bool? ?? true,
        wrapS: _named(
          TextureWrap.values,
          wrapS,
          TextureWrap.repeat,
          warnings: warnings,
          context: '$context\'s wrapS',
        ),
        wrapT: _named(
          TextureWrap.values,
          wrapT,
          TextureWrap.repeat,
          warnings: warnings,
          context: '$context\'s wrapT',
        ),
      ),
    );
  }
  // A slot the file does not fill, or fills with something this build cannot
  // read, is a slot the material does without — which is a material drawn from
  // its factors, and is what every material with no normal map already is.
  return null;
}

/// The profile [json] describes, or null when it is missing one of the five
/// original limits.
///
/// **Eight fields younger than the other five, and each one optional here.**
/// `target`, `maxTextureBytes`, `requireTriangles` and `requireManifold`
/// arrived with `doc-13`; `textures` arrived later still with `mat-28`,
/// `texelsPerMeter` later still with `doc-35n`, and `fps`/`frameSnap` later
/// even than that with `syn-03`. A v1 file predates all eight, and reading
/// them as required would refuse every
/// project saved before this change over a difference that changes what a
/// *new* save means, not what an old one did — exactly the version bump
/// `doc-28` says not to spend on this. Each reads back as the default
/// `ProjectProfile` already has.
ProjectProfile? _readProfile(Object? json, List<String> warnings) {
  if (json case {
    'name': final String name,
    'maxTriangles': final int maxTriangles,
    'maxJoints': final int maxJoints,
    'maxInfluences': final int maxInfluences,
    'maxTextureSize': final int maxTextureSize,
  }) {
    const fallback = ProjectProfile();
    return ProjectProfile(
      name: name,
      target: switch (json['target']) {
        final String word => _named(
          ProfileTarget.values,
          word,
          fallback.target,
          warnings: warnings,
          context: 'The profile\'s target',
        ),
        _ => fallback.target,
      },
      maxTriangles: maxTriangles,
      maxJoints: maxJoints,
      maxInfluences: maxInfluences,
      maxTextureSize: maxTextureSize,
      maxTextureBytes: switch (json['maxTextureBytes']) {
        final int bytes => bytes,
        _ => fallback.maxTextureBytes,
      },
      requireTriangles:
          json['requireTriangles'] as bool? ?? fallback.requireTriangles,
      requireManifold:
          json['requireManifold'] as bool? ?? fallback.requireManifold,
      textures:
          _readTextureBudget(json['textures'], warnings) ?? fallback.textures,
      texelsPerMeter: switch (json['texelsPerMeter']) {
        final num value => value.toDouble(),
        _ => fallback.texelsPerMeter,
      },
      fps: switch (json['fps']) {
        final num value => value.toDouble(),
        _ => fallback.fps,
      },
      frameSnap: json['frameSnap'] as bool? ?? fallback.frameSnap,
    );
  }
  return null;
}

/// [json]'s `textures` object as a [TextureBudget], or null if it is absent
/// or not the shape a `mat-28` write makes — a v1 or v2 file, or a hand-edited
/// one, either of which falls back to the caller's own default the same way
/// every other field younger than `doc-13` does.
TextureBudget? _readTextureBudget(Object? json, List<String> warnings) {
  if (json case {
    'maxSide': final int maxSide,
    'maxBytesOnDevice': final int maxBytesOnDevice,
  }) {
    return TextureBudget(
      maxSide: maxSide,
      maxBytesOnDevice: maxBytesOnDevice,
      targetFormat: switch (json['targetFormat']) {
        final String word => _named(
          TextureFileFormat.values,
          word,
          TextureFileFormat.other,
          warnings: warnings,
          context: 'A texture budget\'s target format',
        ),
        _ => TextureFileFormat.other,
      },
      requirePowerOfTwo: json['requirePowerOfTwo'] as bool? ?? false,
    );
  }
  return null;
}

/// The value of [values] called [name], or [fallback] with a note in
/// [warnings] naming [context] — the rule for an unknown enum name (see
/// `_readMaterials`'s own doc comment): a name this build has never heard of
/// is something a newer build wrote, read rather than refused, but silently
/// is not the same as safely. `doc-10`'s own `warnings` gap is exactly this:
/// a project that opens with an alpha mode or a wrap mode quietly downgraded
/// is a project whose next save can no longer tell the two apart.
T _named<T extends Enum>(
  List<T> values,
  String name,
  T fallback, {
  required List<String> warnings,
  required String context,
}) {
  for (final T value in values) {
    if (value.name == name) return value;
  }
  warnings.add(
    '$context names "$name", which this build does not know; opened as '
    '${fallback.name}.',
  );
  return fallback;
}

/// The [LightingModel] [value] names by its `shaderName`, or null.
///
/// Unlike [_named], a missing [value] is not a refusal or a fallback — it is
/// `mat-04`'s own "not chosen" case, the same as a material with no [fmat]
/// bound. `LightingModel` is not an [Enum] (it is `final` with `const`
/// instances, the shape a genre-open vocabulary takes in this repository),
/// so the lookup is by [LightingModel.shaderName] rather than [_named]'s
/// `Enum.name`. Only [LightingModel.builtIn] is searched: a custom shader
/// `.fmat` can describe as an object has no representation here yet, since
/// nothing that writes a project file builds one.
LightingModel? _lightingModelNamed(
  Object? value,
  List<String> warnings,
  String context,
) {
  if (value == null) return null;
  if (value is! String) {
    warnings.add('$context is not a shader name; ignored.');
    return null;
  }
  for (final LightingModel model in LightingModel.builtIn) {
    if (model.shaderName == value) return model;
  }
  warnings.add(
    '$context names "$value", which this build does not know; opened as '
    'unset.',
  );
  return null;
}

/// The images, or the sentence that stops the file being read.
///
/// The bytes are copied out of the file rather than viewed over it, so that a
/// project holding one texture does not keep the whole `.f3dproj` alive for as
/// long as anything draws.
(List<EncodedImage>, String?) _readImages(
  Uint8List bytes,
  Map<int, ({int offset, int length})> sections,
  Object? described,
  Map<String, String> pool, {
  int tableKind = ProjectSection.images,
}) {
  final table = sections[tableKind];
  final blob = sections[ProjectSection.blob];
  if (table == null || table.length == 0) return (const <EncodedImage>[], null);
  if (blob == null) {
    return (
      const <EncodedImage>[],
      'This file has an image table and no blob for it to point into.',
    );
  }

  final count = table.length ~/ kProjectImageEntryBytes;
  final names = described is List ? described.length : 0;
  if (names != count) {
    return (
      const <EncodedImage>[],
      'The image table holds $count images and the manifest names $names of '
          'them.',
    );
  }

  final view = ByteData.view(
    bytes.buffer,
    bytes.offsetInBytes,
    bytes.lengthInBytes,
  );
  final images = <EncodedImage>[];
  for (var i = 0; i < count; i++) {
    final entry = table.offset + i * kProjectImageEntryBytes;
    final at = view.getUint32(entry, Endian.little);
    final length = view.getUint32(entry + 4, Endian.little);
    if (at + length > blob.length) {
      return (
        const <EncodedImage>[],
        'Image $i runs from $at for $length bytes and the blob is '
            '${blob.length} bytes long.',
      );
    }
    final Object? entryJson = (described! as List)[i];
    images.add(
      EncodedImage(
        bytes: Uint8List.fromList(
          Uint8List.sublistView(
            bytes,
            blob.offset + at,
            blob.offset + at + length,
          ),
        ),
        // A name and an encoding are both things a file may honestly not know:
        // a glTF can carry an image with neither. Missing is null rather than a
        // refusal, and anything of the wrong type is treated as missing.
        name: entryJson is Map<String, Object?>
            ? switch (entryJson['name']) {
                final String s => _intern(s, pool),
                _ => null,
              }
            : null,
        // `mimeType` is one of a handful of strings — "image/png",
        // "image/jpeg" — repeated once per image, which is the other place
        // this file's own strings actually repeat at scale.
        mimeType: entryJson is Map<String, Object?>
            ? switch (entryJson['mimeType']) {
                final String s => _intern(s, pool),
                _ => null,
              }
            : null,
      ),
    );
  }
  return (images, null);
}

/// The CRC-32 of [bytes], the polynomial PNG and zip use.
///
/// **Written here rather than reached for, because there is nowhere to reach.**
/// The only other one in the repository is private to `cpu_png.dart`, which is
/// a backend and a layer this package may not depend on. Twelve lines and a
/// table against a dependency inversion is the right trade, and the table is
/// built once.
///
/// CRC-32 rather than a cryptographic digest: this is here to catch a flipped
/// bit on a disk or a truncated copy, not to catch somebody editing the file on
/// purpose. Nothing in a project file is a secret and nothing signs it.
int crc32(List<int> bytes) {
  var c = 0xFFFFFFFF;
  for (final int byte in bytes) {
    c = _crcTable[(c ^ byte) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

final List<int> _crcTable = List<int>.generate(256, (int n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

/// What the checksums say about the sections, or null when they agree.
///
/// A file with no checksum section is a file nothing is claimed about, and
/// says nothing: that is what makes the section additive rather than a version
/// bump. A file that has one is checked in full — including the table itself,
/// against the header — because a table that has been damaged names the wrong
/// section, and a refusal with the wrong sentence in it is worse than none.
String? _verifyChecksums(
  Uint8List bytes,
  ByteData view,
  Map<int, ({int offset, int length})> sections,
) {
  final table = sections[ProjectSection.checksums];
  final claimed = view.getUint32(kProjectChecksumOffset, Endian.little);
  if (table == null) {
    return claimed == 0
        ? null
        : 'The header carries a checksum for a table this file does not have.';
  }

  final stored = Uint8List.sublistView(
    bytes,
    table.offset,
    table.offset + table.length,
  );
  if (crc32(stored) != claimed) {
    return 'The checksum table is damaged: it sums to '
        '0x${crc32(stored).toRadixString(16)} and the header says '
        '0x${claimed.toRadixString(16)}. Nothing else in the file can be '
        'checked, because the thing that would check it is what went.';
  }
  if (table.length % kProjectChecksumEntryBytes != 0) {
    return 'The checksum table is ${table.length} bytes and each entry is '
        '$kProjectChecksumEntryBytes.';
  }

  final storedView = ByteData.sublistView(stored);
  for (var i = 0; i < table.length ~/ kProjectChecksumEntryBytes; i++) {
    final kind = storedView.getUint32(
      i * kProjectChecksumEntryBytes,
      Endian.little,
    );
    final want = storedView.getUint32(
      i * kProjectChecksumEntryBytes + 4,
      Endian.little,
    );
    final at = sections[kind];
    if (at == null) {
      return 'The checksums name section $kind and the directory does not '
          'hold it.';
    }
    final found = crc32(
      Uint8List.sublistView(bytes, at.offset, at.offset + at.length),
    );
    if (found != want) {
      return 'Section $kind is damaged: its ${at.length} bytes sum to '
          '0x${found.toRadixString(16)} and the file says '
          '0x${want.toRadixString(16)}.';
    }
  }
  return null;
}

int _align(int value) => (value + 3) & ~3;

/// [steps], oldest dropped first, until `jsonEncode({'steps': steps})` fits
/// [maxBytes] — Г5's own byte limit on the history a file carries, read
/// literally: "the limit trims the tail on write." Kept simple on purpose —
/// re-encoding the whole array on every drop is quadratic in step count, and
/// sixty-odd steps (`ModelHistory`'s own default depth) is nowhere near
/// where that would be felt.
List<Map<String, Object?>> _trimmedToFit(
  List<Map<String, Object?>> steps,
  int maxBytes,
) {
  var kept = steps;
  while (kept.isNotEmpty &&
      utf8.encode(jsonEncode(<String, Object?>{'steps': kept})).length >
          maxBytes) {
    kept = kept.sublist(1);
  }
  return kept;
}

/// [s], or the equal string already in [pool] if one has been read before.
///
/// **`jsonDecode` allocates a new `String` for every literal it parses, even
/// when the text is byte-for-byte one this call has already seen.** A vertex
/// layout is five or six attribute names — `position`, `normal`, `texcoord`
/// — repeated on every one of however many imported meshes a scene holds,
/// and at the plan's own "200k vertices" scale that is not five or six
/// strings but thousands of copies of them, each a separate heap object the
/// garbage collector now has to know about. Pooled here, a whole file shares
/// one `"position"` no matter how many meshes name it. One pool per call to
/// [readProject] — a string interned while opening one file is not assumed
/// to be the same string some other file happens to spell the same way.
String _intern(String s, Map<String, String> pool) =>
    pool.putIfAbsent(s, () => s);

/// [value] with every JSON object's keys sorted, recursively.
///
/// **The manifest is built by code, and code builds a map in whatever order
/// its own lines happen to run.** `writeProject`'s own doc comment already
/// promised "the same project writes the same bytes" — true as long as the
/// building code never changes — but a canonical form makes that true for a
/// reason that has nothing to do with which order this file's own functions
/// run in: two builds that construct the identical manifest map through
/// different code paths (a refactor that reorders which field is added
/// first, say) still write the same bytes, because the order actually
/// written is sorted rather than remembered. `readProject` needs no
/// matching change — a JSON object is looked up by key, and nothing here
/// reads position out of one.
///
/// Arrays are walked but never reordered: `objects`, `materialSlots`, a
/// transform's sixteen numbers — position there is the object's own data,
/// not an accident of how the encoder visited a map.
Object? _canonical(Object? value) => switch (value) {
  final Map<String, Object?> map => <String, Object?>{
    for (final String key in map.keys.toList()..sort())
      key: _canonical(map[key]),
  },
  final List<Object?> list => <Object?>[
    for (final item in list) _canonical(item),
  ],
  _ => value,
};

/// [data]'s bytes as they sit in memory.
///
/// Host order, matching `.f3d`'s own blob — see `F3dWriter._blobAppend`. Every
/// target this engine builds for is little-endian, and one bulk encoding across
/// the repository is worth more than a byte-swap nothing here can exercise.
Uint8List _rawBytes(TypedData data) =>
    Uint8List.view(data.buffer, data.offsetInBytes, data.lengthInBytes);

/// A vertex layout as JSON: the attribute names, in order, with how many floats
/// each of them takes.
///
/// The names are written out rather than an index into a fixed list, because
/// the fixed list is `VertexLayout`'s own constants and adding one in the
/// middle of it would silently renumber every file already saved.
List<Object?> _layoutJson(VertexLayout layout) => <Object?>[
  for (final VertexAttribute attribute in layout.attributes)
    <String, Object?>{
      'name': attribute.name,
      'components': attribute.componentCount,
    },
];

/// The layout [json] describes, or null when it is not one.
VertexLayout? _layoutFrom(Object? json, Map<String, String> pool) {
  if (json is! List) return null;
  final attributes = <VertexAttribute>[];
  for (final Object? each in json) {
    if (each case <String, Object?>{
      'name': final String name,
      'components': final int components,
    } when components > 0) {
      attributes.add(VertexAttribute(_intern(name, pool), components));
      continue;
    }
    return null;
  }
  // An empty layout is a stride of zero, and a stride of zero makes
  // `vertexCount` a division by zero rather than an error. Refused here, where
  // the sentence can say what was wrong with the file.
  return attributes.isEmpty ? null : VertexLayout(attributes);
}

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

/// [json] as a [ShapeSet], or the sentence that stops the file — `(null,
/// null)` for the ordinary absent case, an object that has never had a shape
/// key added to it.
(ShapeSet?, String?) _readShapeSet(Object? json, int index, String name) {
  if (json == null) return (null, null);
  if (json case {
    'keys': final List<Object?> keyEntries,
    'weights': final List<Object?> weightEntries,
  }) {
    if (keyEntries.length != weightEntries.length) {
      return (
        null,
        'Object $index ("$name") has ${keyEntries.length} shape keys but '
            '${weightEntries.length} weights; those move together.',
      );
    }
    final keys = <ShapeKey>[];
    for (var i = 0; i < keyEntries.length; i++) {
      if (keyEntries[i] case {
        'name': final String keyName,
        'positions': final List<Object?> positions,
      }) {
        if (positions.any((Object? v) => v is! num)) {
          return (
            null,
            'Object $index ("$name")\'s shape key $i ("$keyName") has a '
                'position that is not a number.',
          );
        }
        // `ShapeKey`'s own constructor throws on this, and a file is not an
        // argument somebody in this program got wrong — checked here so a
        // corrupted position count is a sentence rather than a stack trace.
        if (positions.length % 3 != 0) {
          return (
            null,
            'Object $index ("$name")\'s shape key $i ("$keyName") has '
                '${positions.length} position numbers, and a vertex is '
                'three.',
          );
        }
        keys.add(
          ShapeKey(
            keyName,
            Float32List.fromList(<double>[
              for (final Object? v in positions) (v! as num).toDouble(),
            ]),
          ),
        );
      } else {
        return (
          null,
          'Object $index ("$name")\'s shape key $i is missing a name or its '
              'positions.',
        );
      }
    }
    if (weightEntries.any((Object? v) => v is! num)) {
      return (
        null,
        'Object $index ("$name") has a shape weight that is not a number.',
      );
    }
    return (
      ShapeSet(
        keys: keys,
        weights: <double>[
          for (final Object? v in weightEntries) (v! as num).toDouble(),
        ],
      ),
      null,
    );
  }
  return (
    null,
    'Object $index ("$name") has a shapeSet that is missing its keys or its '
        'weights.',
  );
}

/// [json] as a list of [LodSpec], or the sentence that stops the file —
/// `(null, null)` for the ordinary absent case, an object that has never
/// had a level of detail added to it. Mirrors [_readShapeSet]'s own shape.
(List<LodSpec>?, String?) _readLods(Object? json, int index, String name) {
  if (json == null) return (null, null);
  if (json is! List<Object?>) {
    return (
      null,
      'Object $index ("$name") has a lods entry that is not a list.',
    );
  }
  final lods = <LodSpec>[];
  for (var i = 0; i < json.length; i++) {
    if (json[i] case {
      'ratio': final num ratio,
      'maxScreenFraction': final num maxScreenFraction,
    }) {
      lods.add(
        LodSpec(
          ratio: ratio.toDouble(),
          maxScreenFraction: maxScreenFraction.toDouble(),
        ),
      );
    } else {
      return (
        null,
        'Object $index ("$name")\'s level of detail $i is missing its ratio '
            'or its maxScreenFraction.',
      );
    }
  }
  return (lods, null);
}

/// [json] as a list of [ShapeDriver], or the sentence that stops the file —
/// `(null, null)` for the ordinary absent case, an object no driver has
/// ever been added to (every project saved before `anim-34d`, among
/// others). Mirrors [_readLods]'s own shape.
(List<ShapeDriver>?, String?) _readShapeDrivers(
  Object? json,
  int index,
  String name,
) {
  if (json == null) return (null, null);
  if (json is! List<Object?>) {
    return (
      null,
      'Object $index ("$name") has a shapeDrivers entry that is not a '
          'list.',
    );
  }
  final drivers = <ShapeDriver>[];
  for (var i = 0; i < json.length; i++) {
    final driver = ShapeDriver.fromJson(json[i]);
    if (driver == null) {
      return (
        null,
        'Object $index ("$name")\'s shape driver $i is missing a field or '
            'has one of the wrong type.',
      );
    }
    drivers.add(driver);
  }
  return (drivers, null);
}

/// The skeletons [json] describes, or the sentence that stops the file.
///
/// Absent (a file saved before `anim-03` existed) reads as no skeletons at
/// all, the same optional-field rule every other row named after `doc-13`
/// already follows in this file.
(List<ProjectSkeleton>, String?) _readSkeletons(Object? json) {
  if (json == null) return (const <ProjectSkeleton>[], null);
  if (json is! List) {
    return (
      const <ProjectSkeleton>[],
      'The manifest\'s skeletons are not a list.',
    );
  }
  final skeletons = <ProjectSkeleton>[];
  for (var i = 0; i < json.length; i++) {
    if (json[i] case {
      'joints': final List<Object?> joints,
      'inverseBindMatrices': final List<Object?> matrices,
      'skeletonRoot': final int? skeletonRoot,
      'name': final String? name,
    }) {
      if (joints.any((Object? v) => v is! int)) {
        return (
          const <ProjectSkeleton>[],
          'Skeleton $i has a joint that is not an id.',
        );
      }
      if (matrices.length != joints.length) {
        return (
          const <ProjectSkeleton>[],
          'Skeleton $i has ${joints.length} joints but ${matrices.length} '
              'inverse bind matrices; those move together.',
        );
      }
      final readMatrices = <Matrix4>[];
      for (var m = 0; m < matrices.length; m++) {
        final Object? entry = matrices[m];
        if (entry is! List ||
            entry.length != 16 ||
            entry.any((Object? v) => v is! num)) {
          return (
            const <ProjectSkeleton>[],
            'Skeleton $i\'s inverse bind matrix $m is not sixteen numbers.',
          );
        }
        readMatrices.add(
          Matrix4.fromList(<double>[
            for (final Object? v in entry) (v! as num).toDouble(),
          ]),
        );
      }
      final (readConstraints, constraintRefusal) = _readIkConstraints(
        (json[i] as Map)['constraints'],
      );
      if (constraintRefusal != null) {
        return (const <ProjectSkeleton>[], 'Skeleton $i: $constraintRefusal');
      }
      skeletons.add(
        ProjectSkeleton(
          joints: <int>[for (final Object? v in joints) v! as int],
          inverseBindMatrices: readMatrices,
          skeletonRoot: skeletonRoot,
          name: name,
          constraints: readConstraints,
        ),
      );
    } else {
      return (
        const <ProjectSkeleton>[],
        'Skeleton $i is missing its joints or its inverse bind matrices.',
      );
    }
  }
  return (skeletons, null);
}

/// The `IkConstraint`s [json] describes, or the sentence that stops the
/// file. Absent — every skeleton saved before `anim-15` existed — reads as
/// no constraints at all, the same optional-field rule [_readSkeletons]
/// itself follows for a whole absent skeleton list.
(List<IkConstraint>, String?) _readIkConstraints(Object? json) {
  if (json == null) return (const <IkConstraint>[], null);
  if (json is! List) {
    return (const <IkConstraint>[], 'its constraints are not a list.');
  }
  final constraints = <IkConstraint>[];
  for (var i = 0; i < json.length; i++) {
    if (json[i] case {
      'rootJointId': final int rootJointId,
      'midJointId': final int midJointId,
      'effectorJointId': final int effectorJointId,
      'target': [final num tx, final num ty, final num tz],
      'pole': [final num px, final num py, final num pz],
    }) {
      constraints.add(
        IkConstraint(
          rootJointId: rootJointId,
          midJointId: midJointId,
          effectorJointId: effectorJointId,
          target: Vector3(tx.toDouble(), ty.toDouble(), tz.toDouble()),
          pole: Vector3(px.toDouble(), py.toDouble(), pz.toDouble()),
        ),
      );
    } else {
      return (
        const <IkConstraint>[],
        'constraint $i is not a well-formed IkConstraint.',
      );
    }
  }
  return (constraints, null);
}

/// The clips [json] describes, or the sentence that stops the file.
///
/// Absent reads as no clips at all, the same rule [_readSkeletons] follows.
(List<ProjectClip>, String?) _readClips(Object? json) {
  if (json == null) return (const <ProjectClip>[], null);
  if (json is! List) {
    return (const <ProjectClip>[], 'The manifest\'s clips are not a list.');
  }
  final clips = <ProjectClip>[];
  for (var i = 0; i < json.length; i++) {
    if (json[i] case {'tracks': final List<Object?> trackEntries}) {
      final tracks = <ProjectTrack>[];
      for (var t = 0; t < trackEntries.length; t++) {
        final (ProjectTrack? track, String? refusal) = _readTrack(
          trackEntries[t],
          i,
          t,
        );
        if (refusal != null) return (const <ProjectClip>[], refusal);
        tracks.add(track!);
      }
      final entry = json[i]! as Map<String, Object?>;
      clips.add(
        ProjectClip(
          name: entry['name'] as String?,
          tracks: tracks,
          extras: entry['extras'] as Map<String, Object?>?,
        ),
      );
    } else {
      return (const <ProjectClip>[], 'Clip $i is missing its tracks.');
    }
  }
  return (clips, null);
}

(ProjectTrack?, String?) _readTrack(
  Object? json,
  int clipIndex,
  int trackIndex,
) {
  if (json case {
    'objectId': final int objectId,
    'path': final String pathName,
    'interpolation': final String interpolationName,
    'componentCount': final int componentCount,
    'times': final List<Object?> times,
    'values': final List<Object?> values,
  }) {
    if (times.any((Object? v) => v is! num) ||
        values.any((Object? v) => v is! num)) {
      return (
        null,
        'Clip $clipIndex, track $trackIndex has a time or a value that is '
            'not a number.',
      );
    }
    final path = AnimationPath.fromGltf(pathName);
    if (path == null) {
      return (
        null,
        'Clip $clipIndex, track $trackIndex names path "$pathName", which '
            'this build does not know.',
      );
    }
    // `AnimationInterpolation.fromGltf` already defaults an unrecognised
    // string to `linear`, the same permissive rule the glTF spec itself
    // states for an omitted or unknown sampler interpolation — the same
    // default this file's own writer never omits, so the only way to reach
    // it here is a hand-edited or future-written file.
    final interpolation = AnimationInterpolation.fromGltf(interpolationName);
    try {
      return (
        ProjectTrack(
          objectId: objectId,
          track: AnimationTrack(
            nodeIndex: 0,
            path: path,
            interpolation: interpolation,
            componentCount: componentCount,
            times: Float32List.fromList(<double>[
              for (final Object? v in times) (v! as num).toDouble(),
            ]),
            values: Float32List.fromList(<double>[
              for (final Object? v in values) (v! as num).toDouble(),
            ]),
          ),
        ),
        null,
      );
    } on ArgumentError catch (error) {
      // What `AnimationTrack`'s own constructor throws for a times/values
      // count that does not match `componentCount` and `interpolation`
      // together — caught here for the same reason `_readMeshes` catches
      // `EditMesh.fromBytes`'s: a file is not an argument somebody in this
      // program got wrong, and a reader that throws is a reader an
      // application has to wrap in a try, and the sentence is then a stack
      // trace instead of a sentence about the file.
      return (
        null,
        'Clip $clipIndex, track $trackIndex cannot be read: ${error.message}',
      );
    }
  }
  return (
    null,
    'Clip $clipIndex, track $trackIndex is missing a field: an object id, a '
        'path, an interpolation, a component count, times and values.',
  );
}

(ModelObject?, String?) _readObject(
  Object? entry,
  int index,
  List<EditMesh> meshes,
  List<MeshData> arrived,
  Map<String, String> pool,
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
      arrived,
    );
    if (refusal != null) return (null, refusal);

    final (ShapeSet? shapeSet, String? shapeRefusal) = _readShapeSet(
      entry['shapeSet'],
      index,
      name,
    );
    if (shapeRefusal != null) return (null, shapeRefusal);

    final (List<ShapeDriver>? shapeDrivers, String? driversRefusal) =
        _readShapeDrivers(entry['shapeDrivers'], index, name);
    if (driversRefusal != null) return (null, driversRefusal);

    final (List<LodSpec>? lods, String? lodsRefusal) = _readLods(
      entry['lods'],
      index,
      name,
    );
    if (lodsRefusal != null) return (null, lodsRefusal);

    return (
      ModelObject(
        id: id,
        name: _intern(name, pool),
        geometry: shape!,
        transform: Matrix4.fromList(<double>[
          for (final Object? value in transform) (value! as num).toDouble(),
        ]),
        parent: parent,
        version: version,
        materialSlots: <int>[for (final Object? slot in slots) slot! as int],
        // `anim-03`/`anim-19`, both younger than the rest of this record —
        // absent (a file saved before either existed) reads as unskinned
        // and shapeless, the ordinary case `ModelObject`'s own defaults
        // already are.
        skeletonIndex: entry['skeletonIndex'] as int?,
        shapeSet: shapeSet ?? const ShapeSet(),
        shapeDrivers: shapeDrivers ?? const <ShapeDriver>[],
        lods: lods ?? const <LodSpec>[],
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
  List<MeshData> arrived,
) {
  switch (geometry['kind']) {
    case 'parametric':
      final shape = parametricShapeFrom(geometry);
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
    case 'imported':
      final Object? at = geometry['mesh'];
      if (at is! int || at < 0 || at >= arrived.length) {
        return (
          null,
          'Object $index ("$name") is imported mesh $at and this file holds '
              '${arrived.length}.',
        );
      }
      return (ImportedGeometry(arrived[at]), null);
    case 'socket':
      return (const SocketGeometry(), null);
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
