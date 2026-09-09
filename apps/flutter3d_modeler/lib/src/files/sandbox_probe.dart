/// What this process may write to — asked on the platform that has an answer.
///
/// The macOS sandbox grants a container and the file a person picks, and the
/// difference decides where autosave lives (`ui-18`) and how a save is written
/// (`ui-14`). A browser has no such rule, so the web half says so rather than
/// inventing a table.
///
/// A conditional export for the same reason `project_files.dart` is one:
/// `path_provider` has no web implementation at all, and importing it into a
/// web build is a plugin registration that cannot succeed.
library;

export 'sandbox_probe_io.dart'
    if (dart.library.js_interop) 'sandbox_probe_web.dart';
