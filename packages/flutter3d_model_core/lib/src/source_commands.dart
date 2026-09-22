part of 'command.dart';

/// Records where an object's geometry came from — `ux-48`.
///
/// **Importing already copies; this is the other thing people want.** A file
/// brought in with `import` becomes objects that owe the file nothing: edit
/// the file afterwards and the project does not care, which is right for a
/// prop somebody pulled in once and wrong for the mesh a modeller is
/// sculpting in another tool and checking here. Linking says "this came from
/// there", and [Reimport] is what that lets somebody do about it.
///
/// [sha] is the digest of the bytes as they were read — see [SourceLink] for
/// why a digest and not a timestamp. Which digest is the caller's business;
/// this command only stores what it is given.
final class LinkToSource extends ModelCommand {
  const LinkToSource({required this.id, required this.path, required this.sha});

  final int id;
  final String path;
  final String sha;

  @override
  String get name => 'linkToSource';

  @override
  String get says => 'link to "$path"';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'path': path,
    'sha': sha,
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final ModelObject? object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    if (path.trim().isEmpty) {
      return Outcome.refused('a link needs a path to link to');
    }
    return Outcome.done(
      project.withObject(
        object.copyWith(source: (path: path.trim(), sha: sha)),
      ),
    );
  }
}

/// Takes an object off the file it was linked to, so its geometry is the
/// project's own from here on — the inverse of [LinkToSource].
///
/// Nothing about the mesh changes: what the object looks like now *is* what
/// the file last gave it, and forgetting where that came from is the whole
/// of what unlinking means.
final class UnlinkSource extends ModelCommand {
  const UnlinkSource({required this.id});

  final int id;

  @override
  String get name => 'unlinkSource';

  @override
  String get says => 'unlink from its source file';

  @override
  Map<String, Object?> get arguments => <String, Object?>{'id': id};

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final ModelObject? object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    if (object.source == null) {
      return Outcome.refused('"${object.name}" is not linked to a file');
    }
    return Outcome.done(project.withObject(object.copyWith(clearSource: true)));
  }
}

/// Reads a linked object's geometry again, and keeps everything else —
/// `ux-48`.
///
/// **The point of the row, stated as what it does not touch.** The transform,
/// the parent, the material slots, the modifier stack, the shape keys, the
/// LOD chain and the skin binding all survive, because every one of them is
/// work done in this project about a mesh rather than work the file did. Only
/// [ModelObject.geometry] and the digest move.
///
/// [meshBytes] is an `EditMesh`, the same encoding [ApplyJobResult] carries
/// for the same reason: a command has to be replayable from its own JSON, and
/// an `EditMesh` is the one geometry in this document that can write itself
/// down. Reading a file is the caller's job — nothing in this package opens
/// one — so the app welds what the importer gave it and hands the bytes over,
/// which is also what makes the new geometry editable rather than an opaque
/// buffer.
final class Reimport extends ModelCommand {
  const Reimport({
    required this.id,
    required this.sha,
    required this.meshBytes,
  });

  final int id;

  /// The digest of the file as it has just been read.
  final String sha;

  final Uint8List meshBytes;

  @override
  String get name => 'reimport';

  @override
  String get says => 'read the source file again';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'id': id,
    'sha': sha,
    'meshBytes': base64Encode(meshBytes),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final ModelObject? object = project[id];
    if (object == null) return Outcome.refused('there is no object $id');
    final SourceLink? link = object.source;
    if (link == null) {
      return Outcome.refused(
        '"${object.name}" is not linked to a file, so there is nothing to '
        'read again — link it to one first',
      );
    }
    final EditMesh mesh;
    try {
      mesh = EditMesh.fromBytes(meshBytes);
    } on Object catch (error) {
      return Outcome.refused('${link.path} did not read as a mesh: $error');
    }
    return Outcome.done(
      project.withObject(
        object.copyWith(
          geometry: EditedGeometry(mesh),
          source: (path: link.path, sha: sha),
        ),
      ),
    );
  }
}
