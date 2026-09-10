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

export 'src/command.dart';
export 'src/history.dart';
export 'src/project.dart';
export 'src/project_document.dart';
export 'src/project_format.dart';
export 'src/readiness.dart';
export 'src/selection.dart';
