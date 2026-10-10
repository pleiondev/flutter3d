import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:vector_math/vector_math.dart';

import 'reel_shelf_io.dart' if (dart.library.js_interop) 'reel_shelf_web.dart';

/// The game time between two frames of a reel, s: a thirtieth, so a shot is
/// stepped at a fixed rate whatever the machine filming it manages.
const double reelFrameStep = 1.0 / 30.0;

/// [t], nought to one, eased in and out: a camera move that starts and ends
/// at rest. Outside the range it is held at the ends.
double reelEase(double t) {
  final x = t.clamp(0.0, 1.0);
  return x * x * (3.0 - 2.0 * x);
}

/// The file name of frame [index] of a shot: `frame_0042.png`.
String reelFrameName(int index) =>
    'frame_${index.toString().padLeft(4, '0')}.png';

/// A game filmed frame by frame for a release reel or a clip: each frame
/// drawn with `savePhoto` at a fixed size and written as a PNG into
/// `<out>/<shot>/frame_NNNN.png`.
///
/// **Filmed, not recorded.** A reel steps the game itself, [reelFrameStep]
/// a frame, and draws each step at full size however long that takes, so
/// the result is the same on a laptop and on a workstation and nothing is
/// dropped. A game's reel entry point (`lib/reel_main.dart`, run with
/// `flutter run --profile -t lib/reel_main.dart --dart-define=REEL_OUT=…`)
/// opens its world, places the camera each frame and calls
/// [ReelShot.film]; this is everything around that. Where the frames go is
/// [out], which an entry point that wants a define reads itself:
/// `Reel(renderer: r, out: const String.fromEnvironment('REEL_OUT',
/// defaultValue: 'reel'))`.
///
/// ```dart
/// final reel = Reel(renderer: renderer);
/// final shot = reel.shot('falls');
/// for (var i = 0; i < 180; i++) {
///   placeCamera(reelEase(i / 179));
///   world.step(reelFrameStep);
///   await shot.film(scene: scene, camera: camera, settings: settings);
/// }
/// ```
final class Reel {
  Reel({
    required this.renderer,
    this.width = 1280,
    this.height = 720,
    this.out = 'reel',
    int? tileWidth,
    int? tileHeight,
  }) : tileWidth = tileWidth ?? width,
       tileHeight = tileHeight ?? height;

  final Renderer renderer;

  /// The frame's size in pixels.
  final int width;
  final int height;

  /// The folder every shot is a folder in: `reel` in the working directory
  /// unless the game says otherwise.
  ///
  /// It was a constant of this package read from `--dart-define=REEL_OUT`,
  /// so every game on the engine answered to one environment variable; the
  /// entry point that films a reel is the game's, and so is the folder.
  final String out;

  /// The tiles a frame is drawn in: the whole frame by default, so nothing
  /// that reads the neighbouring pixels is cut at a tile's edge.
  final int tileWidth;
  final int tileHeight;

  /// A shot called [name]: frames from nought, in `<out>/<name>`.
  ReelShot shot(String name) => ReelShot._(this, name);
}

/// One shot of a [Reel]: its frames, numbered from nought.
final class ReelShot {
  ReelShot._(this.reel, this.name) : _shelf = reelShelf('${reel.out}/$name');

  final Reel reel;
  final String name;
  final PhotoShelf _shelf;
  int _frames = 0;

  /// The folder the frames go into.
  String get folder => '${reel.out}/$name';

  /// How many frames have been written.
  int get frames => _frames;

  /// Draws [scene] through [camera] as the next frame and writes it.
  ///
  /// Throws a [StateError] with the shelf's sentence when the frame could
  /// not be written: a reel with a hole in it is not a reel.
  Future<PhotoTaken> film({
    required Scene scene,
    required CameraNode camera,
    RenderSettings settings = const RenderSettings(),
    Vector4? clearColorSrgb,
  }) async {
    final taken = await savePhoto(
      renderer: reel.renderer,
      scene: scene,
      camera: camera,
      width: reel.width,
      height: reel.height,
      shelf: _shelf,
      name: reelFrameName(_frames),
      settings: settings,
      clearColorSrgb: clearColorSrgb,
      tileWidth: reel.tileWidth,
      tileHeight: reel.tileHeight,
    );
    if (!taken.saved.kept) throw StateError(taken.saved.message);
    _frames++;
    return taken;
  }
}
