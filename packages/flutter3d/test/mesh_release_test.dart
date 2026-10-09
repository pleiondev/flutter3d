/// `Renderer.releaseMeshAfterFrame`: a mesh an application is done with goes
/// back to the device only once no frame in flight can still draw with it.
library;

import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

void main() {
  late FakeBackend device;
  late Renderer renderer;
  late Scene scene;
  late CameraNode camera;

  setUp(() {
    device = FakeBackend();
    renderer = Renderer.create(device: device);
    scene = Scene();
    camera = CameraNode()..setPosition(0.0, 0.0, 5.0);
    scene.add(camera);
  });

  void frame() => renderer.render(
    width: 32,
    height: 24,
    scene: scene,
    views: <RenderView>[RenderView(camera: camera)],
  );

  DeviceMesh mesh() =>
      DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.0)).build());

  test('the buffers go back after the frames in flight, not before', () {
    frame();
    final stretch = mesh();
    renderer.releaseMeshAfterFrame(stretch);

    frame();
    frame();
    expect(device.releasedGeometry, isNot(contains(stretch.vertices)));

    frame();
    expect(
      device.releasedGeometry,
      containsAll(<GeometryBuffer>[stretch.vertices, stretch.indices]),
    );
  });

  test('disposing the renderer releases what no frame came to retire', () {
    final bridge = mesh();
    renderer
      ..releaseMeshAfterFrame(bridge)
      ..dispose();
    expect(
      device.releasedGeometry,
      containsAll(<GeometryBuffer>[bridge.vertices, bridge.indices]),
    );
  });
}
