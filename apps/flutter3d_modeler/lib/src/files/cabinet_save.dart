/// A model saved back to the cabinet entry it was opened from — `tut-20`.
///
/// The same conditional-export split `fetch_model.dart` and `file_drop.dart`
/// beside it already make, and for the same reason: a browser sends this
/// through `package:web`'s own `fetch`, with the origin's cookies; nothing
/// else needs to know which.
library;

export 'cabinet_save_io.dart'
    if (dart.library.js_interop) 'cabinet_save_web.dart';
export 'cabinet_save_outcome.dart';
