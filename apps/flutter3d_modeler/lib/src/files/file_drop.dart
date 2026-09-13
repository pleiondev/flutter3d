/// A window that already has a file dragged onto it — `ui-31n`.
///
/// **The same conditional-export split `project_files.dart` already made, and
/// for the same reason.** A desktop learns about a drop through a platform
/// channel a browser has none of; a browser learns about one through
/// `dragover`/`drop` DOM events a desktop process never fires. Each build
/// carries only the half it can run.
///
/// Both halves hand back a name and bytes — the same shape [openModel]'s own
/// [PickedFile] carries — so whatever calls this ends at the same open path a
/// manual pick already uses.
library;

export 'file_drop_io.dart' if (dart.library.js_interop) 'file_drop_web.dart';
