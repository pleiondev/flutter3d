/// What platform a bug report should say it ran on — `rel-15`'s own
/// substitute for `flutter --version`'s output.
///
/// **Why not the real thing.** The row's own wording asks for
/// `flutter --version`'s output plus the platform. Getting the former needs
/// a process shell-out, which a running app cannot make on every platform it
/// ships to — a browser tab has no process to shell out to at all. This
/// reports the platform half honestly instead of pretending to a build
/// number this file cannot actually read.
///
/// Kept out of `report_problem.dart` on purpose: that file's own doc comment
/// says "without Flutter" and its own test runs under plain `dart test` —
/// [defaultTargetPlatform] and [kIsWeb] need the Flutter SDK, so this one
/// small function is the one place in this feature that does.
library;

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb;

/// "web", or the native platform's own name (`macOS`, `windows`, `linux`,
/// `android`, `iOS`) — whichever this build is actually running as.
String environmentSummary() =>
    kIsWeb ? 'web' : defaultTargetPlatform.name;
