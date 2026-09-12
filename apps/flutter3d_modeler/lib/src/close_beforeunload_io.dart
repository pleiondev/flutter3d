/// Nothing to warn about leaving: only a browser tab close needs asking
/// before the page is simply gone, and a desktop or mobile build already
/// gets `ui-24`'s own dialog through `PopScope` and the window-exit
/// listener, both of which can actually stop the close from happening.
library;

void installBeforeUnloadGuard(bool Function() isDirty) {}
