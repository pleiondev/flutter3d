/// How a game's shared device is opened for its `Model3dComponent`s: not
/// exported by the package's main library, set only through `testing.dart`.
library;

import 'package:flutter3d/flutter3d.dart' show GraphicsDevice;
import 'package:flutter3d_app/flutter3d_app.dart' show openDevice;

/// `flutter3d_app`'s `openDevice`, or what a test put in its place.
Future<GraphicsDevice> Function({required int width, required int height})
sharedDeviceOpener = openDevice;
