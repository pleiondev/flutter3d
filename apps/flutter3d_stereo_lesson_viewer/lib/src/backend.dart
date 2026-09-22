/// Which backend this build draws through — see
/// `packages/flutter3d_game/example/lib/src/backend.dart`'s own doc comment for why
/// this is a re-export rather than naming a backend directly: `openDevice`
/// is also the runtime fallback to the software rasteriser when the GPU
/// backend will not start, on desktop and on the web both.
library;

export 'package:flutter3d_app/flutter3d_app.dart' show openDevice;
