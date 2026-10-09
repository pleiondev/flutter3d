/// A line that grows a point at a time, written in place.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_cpu/testing.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('it grows, lets go of its oldest when full, and is found where its '
      'points are', () {
    // Mutation: bound the node by the mesh it was uploaded as.
    final device = FakeBackend();
    final trail = LineStripNode(
      device: device,
      material: RenderMaterial.polyline(
        viewportWidth: 800,
        viewportHeight: 600,
      ),
      capacity: 3,
    );
    final mesh = trail.mesh;
    for (var i = 0; i < 5; i++) {
      trail.append(Vector3(0.0, 0.0, -10.0 * i));
    }
    expect(trail.count, 3);
    expect(trail.points.first.z, -20.0, reason: 'the oldest two went');
    expect(identical(trail.mesh, mesh), isTrue, reason: 'written in place');
    expect(trail.localBounds.min.z, closeTo(-40.0, 1e-6));
    expect(trail.localBounds.max.z, closeTo(-20.0, 1e-6));

    trail.clear();
    expect(trail.count, 0);
  });

  test(
    'a short trail in a long strip draws, and the unused rest does not',
    () async {
      // The points not yet reached sit a hair past the end: drawn as they
      // were, a zero direction would have made them NaN.
      final it = cpuTestDevice(width: 32, height: 32);
      final trail =
          LineStripNode(
              device: it.device,
              material: RenderMaterial.polyline(
                viewportWidth: 32,
                viewportHeight: 32,
              ),
              capacity: 16,
              width: 4.0,
              color: LinearColor(1.0, 0.2, 0.2, 1.0),
            )
            ..append(Vector3(-1.0, 0.0, -5.0))
            ..append(Vector3(1.0, 0.0, -5.0));
      final camera = CameraNode();
      final scene = Scene()
        ..add(camera)
        ..add(trail);
      final frame =
          Renderer.create(
            device: it.device,
            fallbackAlbedo: it.albedo,
            fallbackNormal: it.normal,
          ).render(
            width: 32,
            height: 32,
            scene: scene,
            views: <RenderView>[
              RenderView(
                camera: camera,
                clearColorSrgb: Vector4(0.0, 0.0, 0.0, 1.0),
              ),
            ],
            settings: const RenderSettings(tonemap: false),
          );
      final rgba = (await it.device.readback(frame.frame)).buffer.asUint8List();
      var red = 0;
      for (var i = 0; i < rgba.length; i += 4) {
        if (rgba[i] > 100) red++;
      }
      expect(red, greaterThan(20));
    },
  );
}
