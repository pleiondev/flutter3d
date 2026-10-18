/// Which backend this build draws through.
///
/// **Two answers, chosen at compile time, and they are not the same kind of
/// answer.** A desktop build names Impeller and nothing else: an editor that
/// fell back to the software rasteriser without saying so would be an editor
/// whose picture is slow for a reason nobody can see, and the games' shared
/// `openDevice` does exactly that fallback. A browser has no Impeller to
/// name, so the web build (P11) takes the games' own choice — WebGPU first,
/// WebGL2 where it will not start — because there it is the only choice
/// there is.
///
/// A conditional export rather than a runtime branch for the reason every
/// application here gives: `flutter_gpu` reaches `dart:ffi`, and a web build
/// that can see it at all does not compile.
library;

export 'backend_native.dart' if (dart.library.js_interop) 'backend_web.dart';
