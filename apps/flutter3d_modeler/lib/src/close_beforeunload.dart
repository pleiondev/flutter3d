/// Wires the browser's own "are you sure?" prompt to `ui-24`'s own dirty
/// state — a no-op everywhere else, the same conditional-export split
/// `project_files.dart` already uses and for the same reason:
/// `package:web` has no native counterpart to compile against, and a
/// `kIsWeb` branch inside one file would still pull it into every build.
library;

export 'close_beforeunload_io.dart'
    if (dart.library.js_interop) 'close_beforeunload_web.dart';
