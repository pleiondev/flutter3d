/// The one browser-only half of `ui-24`: `window.onbeforeunload`.
///
/// **[isDirty] is a callback, not a bool, and read fresh at the moment a
/// person actually tries to leave.** The handler is wired once, in
/// `initState`; the document's own dirty state changes on every edit and
/// every save afterward, and a snapshot taken when this was installed
/// would still be answering for whatever the document looked like then.
library;

import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Makes the browser ask before the tab closes while [isDirty] answers true.
///
/// [isDirty] is asked at the moment of closing, not once here, so the
/// answer follows every edit and save made after this was installed.
void installBeforeUnloadGuard(bool Function() isDirty) {
  web.window.onbeforeunload = ((web.Event event) {
    if (!isDirty()) return;
    // Both set: `preventDefault` is what current browsers actually key the
    // prompt off, and `returnValue` is the legacy signal older ones read —
    // `package:web`'s own binding of it, a bool rather than the historical
    // string, still prevents the default action either way.
    event.preventDefault();
    event.returnValue = false;
  }).toJS;
}
