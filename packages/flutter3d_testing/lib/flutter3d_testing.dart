/// Pixel regression tests for a game, on a machine with no GPU.
///
///     import 'package:flutter3d_testing/flutter3d_testing.dart';
///
///     test('the crypt still looks like the crypt', () async {
///       final frame = await renderFrame(width: 320, height: 180, build: (
///         device,
///       ) {
///         final scene = Scene();
///         // ... put the level in it
///         return (scene: scene, camera: camera);
///       });
///       await expectMatchesGolden(frame, 'test/goldens/crypt.png');
///     });
///
/// **The thing this package exists to hand over.** The software rasteriser has
/// always been in this repository, and the engine's own thirty reference images
/// are drawn with it — but it was internal machinery. A game built on flutter3d
/// could not use it without writing the same forty lines of device, renderer,
/// read-back and comparison that every frame test here had written before
/// `cpuTestDevice` took the first fifteen of them away.
///
/// What it buys is a test that fails when the picture changes, on a continuous
/// integration runner with no display and no graphics driver. Every other engine
/// on this platform needs a real device for that, which means either a machine
/// nobody wants to pay for or a check nobody runs.
///
/// ## What it does not do
///
/// It does not compare against a *GPU* backend. The two golden sets in this
/// repository are deliberately separate — the same scene differs by a fraction
/// of a percent between a rasteriser and a driver, and one shared set would need
/// a tolerance, which is a threshold that stops watching. A game's reference
/// images made here are the software backend's, and they say what the software
/// backend draws.
///
/// That is still the right thing to regress against: a change that alters the
/// picture alters it on both.
library;

export 'src/golden.dart';
export 'src/render_frame.dart';
