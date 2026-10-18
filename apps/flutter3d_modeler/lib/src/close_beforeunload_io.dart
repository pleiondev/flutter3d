/// Nothing to warn about leaving: only a browser tab close needs asking
/// before the page is simply gone, and a desktop or mobile build already
/// gets `ui-24`'s own dialog through `PopScope` and the window-exit
/// listener, both of which can actually stop the close from happening.
library;

/// Does nothing: off the web there is no tab close to ask about, and the
/// dialogs that guard leaving already run.
void installBeforeUnloadGuard(bool Function() isDirty) {}
