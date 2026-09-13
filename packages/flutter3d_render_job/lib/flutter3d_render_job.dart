/// A model project rendered off the main viewport's own device —
/// `pro-rn-02`'s own row.
///
///     final job = RenderSnapshotJob(project, RenderPreset(
///       width: 480,
///       height: 360,
///       camera: SnapshotCamera(
///         position: Vector3(2.2, 1.4, 3.4),
///         target: Vector3.zero(),
///       ),
///     ));
///     final png = await job.run();
library;

export 'src/render_preset.dart';
export 'src/render_snapshot_job.dart';
export 'src/scene_from_project.dart';
