part of 'command.dart';

/// Writes a [JobResult] into the object it answers for — the one command
/// that ever does, and the only step a finished [JobRequest] ever takes in
/// the history.
///
/// **Refused rather than applied when [baseVersion] has moved on.** A job
/// captures the mesh it started from and can run for real time — long
/// enough that something else edits the same object before it finishes.
/// Writing the answer in regardless would silently discard whatever that
/// other edit did; refusing says so, in the same words `SetModifierField`
/// and every other command here already refuses with, so whoever asked for
/// the bake can ask again against the object as it now stands.
final class ApplyJobResult extends ModelCommand {
  const ApplyJobResult({
    required this.objectId,
    required this.baseVersion,
    required this.meshBytes,
  });

  final int objectId;
  final int baseVersion;
  final Uint8List meshBytes;

  /// [result] as the command that writes it in.
  factory ApplyJobResult.of(JobResult result) => ApplyJobResult(
    objectId: result.objectId,
    baseVersion: result.baseVersion,
    meshBytes: result.meshBytes,
  );

  @override
  String get name => 'applyJobResult';

  @override
  String get says => 'finish the background job';

  @override
  Map<String, Object?> get arguments => <String, Object?>{
    'objectId': objectId,
    'baseVersion': baseVersion,
    'meshBytes': base64Encode(meshBytes),
  };

  @override
  Outcome apply(ModelProject project, ProjectSelection selection) {
    final object = project[objectId];
    if (object == null) return Outcome.refused('there is no object $objectId');
    if (object.version != baseVersion) {
      return Outcome.refused(
        'object $objectId has changed since this job started (it is now '
        'version ${object.version}, the job started at $baseVersion); its '
        'result no longer answers what the object currently is',
      );
    }
    return Outcome.done(
      project.withObject(
        object.copyWith(
          geometry: EditedGeometry(EditMesh.fromBytes(meshBytes)),
        ),
      ),
    );
  }
}
