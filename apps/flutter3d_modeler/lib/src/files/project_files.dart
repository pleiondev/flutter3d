/// Opening a model and handing one back, on whichever platform this is.
///
/// **Two implementations behind one name, chosen by a conditional export.** A
/// browser has no file system: a "save" is a download the person then files
/// somewhere, and an "open" is bytes handed over by a picker with no path
/// attached. A desktop has both, and under the macOS sandbox it has them only
/// for the file somebody actually chose. Writing one function with `kIsWeb`
/// inside it would compile `dart:io` into the web build and `package:web` into
/// the desktop one; the conditional export means each build carries only the
/// half it can run.
///
/// What is deliberately *not* here: anything that knows what a model is. This
/// layer moves bytes and names, and `ui-16`/`ui-17` decide what to do with
/// them — which is what lets the whole of it be exercised without a decoder.
library;

export 'project_files_io.dart'
    if (dart.library.js_interop) 'project_files_web.dart';
