/// A model project: what is in it, what may be done to it, and what it refuses
/// to export.
///
/// **The headless half of the modeller, and the split is the one the level
/// editor already made.** `flutter3d_editor_core` holds a level being nudged
/// and undone with no window in front of it, and everything that wanted to
/// check a level without drawing it — a linter, a service, the tool an agent
/// speaks to — could then depend on that rather than on an application. A model
/// is the same shape of thing: a document, a stack of changes, and a set of
/// rules about whether the result can leave.
///
/// Nothing here draws, reads a disk or knows what a viewport is. What it will
/// hold is `ModelProject` and the objects in it, the sealed `ModelCommand` every
/// edit is one of, the history that takes them back, and `ExportReadiness`.
///
/// What is here now is the spine: [ModelProject] with the objects in it,
/// [ProjectSelection], the sealed [ModelCommand] every edit is one of,
/// [ModelHistory] behind them, and [ExportReadiness] for what a project will
/// refuse to leave as. The commands arrive a handful at a time — see
/// `doc/model-editor-plan.md`, `doc-06` for the object ones, `doc-07` for the
/// mesh ones and `doc-32n` for the selection ones.
///
/// The two doors a project comes in and goes out through are here as well:
/// [toModelDocument] and [fromModelDocument] for what every writer and loader
/// in the repository speaks, and [writeProject]/[readProject] for the
/// container a project is saved as. They were written against their own tests
/// and reachable from nowhere else for a while, which is a thing worth not
/// repeating: a file that only its test can import is a file the application
/// cannot use.
library;

export 'src/autosave.dart';
export 'src/byte_size.dart';
export 'src/command.dart';
export 'src/command_journal.dart';
export 'src/curve_display.dart';
export 'src/history.dart';
export 'src/ik_constraint.dart';
export 'src/image_dimensions.dart';
export 'src/import_into.dart';
export 'src/job.dart';
export 'src/key_table.dart';
export 'src/listing.dart';
export 'src/lod_cache.dart';
export 'src/lod_spec.dart';
export 'src/material.dart';
export 'src/modifier_evaluation_cache.dart';
export 'src/modifier_slot.dart';
export 'src/paint_layer.dart';
export 'src/paint_weights.dart';
export 'src/param_hint.dart';
export 'src/parametric_json.dart';
export 'src/project.dart';
export 'src/project_animation.dart';
export 'src/project_document.dart';
export 'src/project_format.dart';
export 'src/project_morphs.dart';
export 'src/readiness.dart';
export 'src/readiness_cache.dart';
export 'src/render_project.dart';
export 'src/retarget_clip.dart';
export 'src/rig_issues.dart';
export 'src/rig_job.dart';
export 'src/rig_template.dart';
export 'src/scene_lighting.dart';
export 'src/selection.dart';
export 'src/shape_driver.dart';
export 'src/simulation_bake.dart';
export 'src/simulation_bake_particles.dart';
export 'src/simulation_bake_rigid.dart';
export 'src/simulation_cache.dart';
export 'src/texture_bake.dart';
export 'src/texture_budget.dart';
export 'src/texture_graph.dart';
export 'src/texture_info.dart';
export 'src/texture_resize.dart';
export 'src/world_transform.dart';
