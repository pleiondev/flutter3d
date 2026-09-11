/// Heavy work on one object's mesh, described as values rather than run in
/// place.
///
/// **`ApplyModifier`'s own doc comment already named this**: a modifier
/// stack costs nothing to describe and can cost real time to fold — a
/// `SubdivisionModifier` at a real resolution, say, once `mesh-45` exists —
/// and running that on the thread a person is dragging a gizmo on is a
/// frozen frame. [JobRequest] is the description; [JobRequest.run] is where
/// it actually happens, off this isolate when one is available (see
/// `editInIsolate` in `flutter3d_mesh`) and on it otherwise; [ApplyJobResult]
/// is the one command that ever writes a job's own answer into a project.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter3d_mesh/flutter3d_mesh.dart';

import 'project.dart';

/// One object's modifier stack, folded over a mesh captured at the moment
/// this was built — a value, not a live reference to the project or the
/// object it came from.
///
/// **Every field is a plain value, on purpose.** `meshBytes` is
/// [EditMesh.toBytes], not the `EditMesh` itself, and `modifiers` is the
/// same [Modifier] list [ApplyModifier] would fold synchronously — both
/// cross an isolate boundary without carrying anything alive with them,
/// which is the whole reason `run` can hand this to `editInIsolate` rather
/// than running it here.
final class JobRequest {
  const JobRequest({
    required this.objectId,
    required this.baseVersion,
    required this.meshBytes,
    required this.modifiers,
  });

  /// Which object this answers for.
  final int objectId;

  /// [ModelObject.version] at the moment this was built. [ApplyJobResult]
  /// refuses a [JobResult] whose own `baseVersion` no longer matches —
  /// something else changed the object while this ran, and the mesh this
  /// produced is an answer to a question that is no longer being asked.
  final int baseVersion;

  /// The base mesh, as [EditMesh.toBytes] wrote it when this was built.
  final Uint8List meshBytes;

  /// The modifiers to fold, top of the list first — the same list
  /// [ApplyModifier] would build synchronously for the same bake.
  final List<Modifier> modifiers;

  /// Folds [modifiers] over [meshBytes], off this isolate when one is
  /// available.
  Future<JobResult> run() async {
    final base = EditMesh.fromBytes(meshBytes);
    final baked = await editInIsolate(
      base,
      (EditMesh mesh) =>
          ModifierStack(modifiers).evaluate(mesh, const ModifierContext()),
    );
    return JobResult(
      objectId: objectId,
      baseVersion: baseVersion,
      meshBytes: baked.toBytes(),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'objectId': objectId,
    'baseVersion': baseVersion,
    'meshBytes': base64Encode(meshBytes),
    'modifiers': <Object?>[for (final m in modifiers) m.toJson()],
  };

  /// A [JobRequest] from its own [toJson], or null when a field is missing,
  /// of the wrong type, or names a modifier this build does not have.
  static JobRequest? fromJson(Map<String, Object?> json) {
    if (json case {
      'objectId': final int objectId,
      'baseVersion': final int baseVersion,
      'meshBytes': final String encoded,
      'modifiers': final List<Object?> modifiersJson,
    }) {
      final modifiers = _modifiersFrom(modifiersJson);
      if (modifiers == null) return null;
      return JobRequest(
        objectId: objectId,
        baseVersion: baseVersion,
        meshBytes: base64Decode(encoded),
        modifiers: modifiers,
      );
    }
    return null;
  }
}

List<Modifier>? _modifiersFrom(List<Object?> json) {
  final out = <Modifier>[];
  for (final Object? each in json) {
    final Modifier? modifier = modifierFromJson(each);
    if (modifier == null) return null;
    out.add(modifier);
  }
  return out;
}

/// What [JobRequest.run] answered.
final class JobResult {
  const JobResult({
    required this.objectId,
    required this.baseVersion,
    required this.meshBytes,
  });

  final int objectId;
  final int baseVersion;
  final Uint8List meshBytes;

  Map<String, Object?> toJson() => <String, Object?>{
    'objectId': objectId,
    'baseVersion': baseVersion,
    'meshBytes': base64Encode(meshBytes),
  };

  static JobResult? fromJson(Map<String, Object?> json) => switch (json) {
    {
      'objectId': final int objectId,
      'baseVersion': final int baseVersion,
      'meshBytes': final String encoded,
    } =>
      JobResult(
        objectId: objectId,
        baseVersion: baseVersion,
        meshBytes: base64Decode(encoded),
      ),
    _ => null,
  };
}

/// [project]'s own object [objectId], its modifiers `0..uptoIndex` captured
/// as a [JobRequest] the same way [ApplyModifier] would bake them
/// synchronously — the modifier at `uptoIndex` folded in even when its own
/// slot is disabled, for the reason `ApplyModifier`'s own doc comment gives.
///
/// Null when [objectId] names no object, [uptoIndex] names no modifier on
/// it, or the object has no edited mesh to bake into.
JobRequest? jobRequestFor(ModelProject project, int objectId, int uptoIndex) {
  final object = project[objectId];
  if (object == null) return null;
  if (uptoIndex < 0 || uptoIndex >= object.modifiers.length) return null;
  final EditMesh? base = switch (object.geometry) {
    final EditedGeometry g => g.mesh,
    _ => null,
  };
  if (base == null) return null;
  return JobRequest(
    objectId: objectId,
    baseVersion: object.version,
    meshBytes: base.toBytes(),
    modifiers: <Modifier>[
      for (var i = 0; i <= uptoIndex; i++)
        if (i == uptoIndex || object.modifiers[i].enabled)
          object.modifiers[i].modifier,
    ],
  );
}
