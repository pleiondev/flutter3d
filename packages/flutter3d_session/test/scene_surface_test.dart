/// The seam between the renderer and the widget tree.
///
///     flutter test test/scene_surface_test.dart
///
/// **Three copies of this widget existed and none of them was tested**, because
/// each lived inside an application nothing mounts. What is checked here is the
/// order of the two things it does per frame, which is the whole reason its
/// settings are a function rather than an object: a game that places its camera
/// in `onBeforeFrame` can only derive what the frame is drawn with *after* that
/// has run.
library;

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_session/flutter3d_session.dart';
import 'package:flutter_test/flutter_test.dart';

/// A renderer with no GPU under it, as small as it can be and still be one.
///
/// Sixteen by nine, because nothing here looks at the picture: every pump draws
/// a frame in software, and the cost is per pixel.
({Renderer renderer, Scene scene, RenderView view}) _stage() {
  final device = CpuDevice(
    width: 16,
    height: 9,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  return (
    renderer: Renderer.create(
      device: device,
      fallbackAlbedo: SolidColorTexture.white.upload(device),
      fallbackNormal: SolidColorTexture.flatNormal.upload(device),
    ),
    scene: Scene(),
    view: RenderView(camera: CameraNode()),
  );
}

void main() {
  testWidgets('asks what to draw with after the camera has been placed',
      (WidgetTester tester) async {
    // **The order this widget exists to guarantee.** A settings *object* is
    // built by the parent, before the frame; a function is called here, after
    // `onBeforeFrame`. The crypt places its camera in that callback, so with an
    // object it could not derive anything from where the camera ended up — and
    // the circuit's fog is exactly that derivation.
    final it = _stage();
    final order = <String>[];

    await tester.pumpWidget(MaterialApp(
      home: SceneSurface(
        renderer: it.renderer,
        scene: it.scene,
        view: it.view,
        onBeforeFrame: () => order.add('camera'),
        settings: () {
          order.add('settings');
          return const RenderSettings();
        },
      ),
    ));

    expect(order, <String>['camera', 'settings'],
        reason: 'the frame was described before the camera moved');
  });

  testWidgets('and asks again on every frame, not once', (
    WidgetTester tester,
  ) async {
    // Mutation: hoist the call out of the builder. The fog stops following the
    // camera and a circuit fades into the same grey whichever way it is
    // pointing — which is the failure the racing game wrote 416 lines to avoid.
    final it = _stage();
    var asked = 0;

    Widget surface(double width) => MaterialApp(
          home: Center(
            child: SizedBox(
              width: width,
              height: 90,
              child: SceneSurface(
                renderer: it.renderer,
                scene: it.scene,
                view: it.view,
                onBeforeFrame: () {},
                settings: () {
                  asked++;
                  return const RenderSettings();
                },
              ),
            ),
          ),
        );

    await tester.pumpWidget(surface(160));
    final once = asked;
    await tester.pumpWidget(surface(200));

    expect(once, 1);
    expect(asked, greaterThan(once), reason: 'it was described once and reused');
  });

  testWidgets('and a surface with no size still renders something', (
    WidgetTester tester,
  ) async {
    // A real state: a panel animating open, a window dragged to nothing. A
    // render target of zero pixels is not, which is what the clamp is for —
    // and without it this throws rather than drawing a frame nobody sees.
    final it = _stage();

    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 0,
          height: 0,
          child: SceneSurface(
            renderer: it.renderer,
            scene: it.scene,
            view: it.view,
            onBeforeFrame: () {},
            settings: () => const RenderSettings(),
          ),
        ),
      ),
    ));

    expect(tester.takeException(), isNull);
  });
}
