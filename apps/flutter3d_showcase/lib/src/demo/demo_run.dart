/// A demo that has been started: its scene built and a renderer behind it.
///
/// **Apart from the widget so a test can run a page with no window.** The
/// viewport and a test both do the same three things, build the context, build
/// the scene and draw a frame, and a test that had to pump a widget tree to
/// get them would be testing Flutter's layout more than the page. Both go
/// through here, so what a test proves about a page is what the person sees.
library;

import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_showcase/src/demo/capability_report.dart';
import 'package:flutter3d_showcase/src/demo/demo.dart';
import 'package:vector_math/vector_math.dart' hide Colors;

final class DemoRun {
  DemoRun._(this.demo, this.context, this.scene);

  /// Builds the context on [device], lets [demo] load and build, and returns
  /// the run. The device is the caller's: one is opened for the whole app and
  /// every page draws on it, because a browser gives a page a handful of GL
  /// contexts and a page that opened its own would leak one per visit.
  static Future<DemoRun> start(GraphicsDevice device, ShowcaseDemo demo) async {
    final CameraNode camera = CameraNode(name: 'eye');
    final RenderView view = RenderView(
      camera: camera,
      clearColor: Vector4(0.05, 0.05, 0.07, 1.0),
    );
    final OrbitController orbit = OrbitController(
      camera,
      distance: 3.5,
      yaw: 0.6,
      pitch: 0.45,
    );
    final DemoContext context = DemoContext(
      device: device,
      renderer: Renderer.create(device: device),
      camera: camera,
      view: view,
      orbit: orbit,
      caps: CapabilityReport.of(device),
    );
    demo.configureView(context);
    // `OrbitController`'s own constructor already called `apply()` once, with
    // the defaults above — not with whatever a page's `configureView` just
    // set. Most pages never called it again, so the first frame drew the
    // camera at the constructor's distance/yaw/pitch, not the page's, and the
    // two only agreed the moment a drag's own `rotate()` called `apply()`
    // internally — which is what made the very first pixel of a drag look
    // like the view jumping to where it should have started.
    context.orbit.apply();
    await demo.prepare(context);
    final Scene scene = demo.build(context)..add(camera);
    return DemoRun._(demo, context, scene);
  }

  final ShowcaseDemo demo;
  final DemoContext context;
  final Scene scene;

  void update(double dt) => demo.update(context, dt);

  /// One frame at [width] by [height] pixels.
  FrameResult render(int width, int height) {
    context.orbit.syncProjectionDepth(context.camera);
    return context.renderer.render(
      width: width,
      height: height,
      scene: scene,
      views: <RenderView>[context.view],
      settings: demo.settings(context),
    );
  }

  /// Gives back what the renderer holds. The device stays open.
  void dispose() => context.renderer.dispose();
}
