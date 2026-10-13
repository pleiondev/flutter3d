/// A widget's position is a place in the world: a scene whose origin moved
/// under it rebuilds every node where it stood.
///
///     flutter test test/scene_widgets_origin_test.dart
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/flutter3d.dart' as engine show RenderMaterial;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

CpuDevice _device() => CpuDevice(
  width: 32,
  height: 24,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

Widget _noPresenter(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.contain,
  FilterQuality quality = FilterQuality.low,
}) => const SizedBox.expand();

final engine.RenderMaterial _grey = engine.RenderMaterial(
  baseColor: LinearColor.fromSrgb(0.6, 0.6, 0.6, 1.0),
);

/// No warm-up and no frame per vsync: the claims are about the graph.
const ViewSettings _view = ViewSettings(continuous: false, warmUp: false);

/// The world 1.5 km out along X, where a twin's far building stands.
const double _far = 1500.0;

/// The scene, built from fresh vectors each call as a `build` method makes
/// them, so a rebuild hands every widget its position again.
Widget _tree(CpuDevice device, void Function(Scene3DController) created) =>
    Directionality(
      textDirection: TextDirection.ltr,
      child: Scene3D(
        device: DeviceSettings(device: device, presenter: _noPresenter),
        view: _view,
        onSceneCreated: created,
        children: <Widget>[
          Camera3D(
            position: Vector3(_far, 2.0, 10.0),
            target: Vector3(_far, 0.0, 0.0),
          ),
          Mesh3D(
            shape: CuboidShape(),
            material: _grey,
            name: 'tower',
            position: Vector3(_far, 0.0, 0.0),
          ),
          Node3D(
            name: 'yard',
            position: Vector3(_far, 0.0, 5.0),
            children: <Widget>[
              Mesh3D(
                shape: CuboidShape(),
                material: _grey,
                name: 'shed',
                position: Vector3(1.0, 0.0, 0.0),
              ),
            ],
          ),
          Light3D.point(position: Vector3(_far, 4.0, 0.0)),
        ],
      ),
    );

Matcher _at(double x, double y, double z) => predicate<WorldPosition>(
  (WorldPosition p) =>
      (p.x - x).abs() < 1e-3 &&
      (p.y - y).abs() < 1e-3 &&
      (p.z - z).abs() < 1e-3,
  'within a millimetre of ($x, $y, $z)',
);

void main() {
  testWidgets('a rebuild after the origin shifted keeps every node at its '
      'world position', (tester) async {
    // Mutation: write `position` into the node as it is, without
    // `Scene.toScene`, and the tower jumps 1.5 km on the rebuild.
    final device = _device();
    Scene3DController? controller;
    await tester.pumpWidget(_tree(device, (c) => controller = c));
    await tester.pump();
    await tester.pump();
    final scene = controller!.scene;
    SceneNode named(String name) {
      SceneNode? found;
      scene.root.traverse((SceneNode n) {
        if (n.name == name) found = n;
      });
      return found!;
    }

    expect(named('tower').worldPosition, _at(_far, 0.0, 0.0));

    // What the view does when its camera wanders past `originShift`.
    scene.shiftOrigin(const WorldPosition(_far, 0.0, 0.0));
    await tester.pumpWidget(_tree(device, (c) => controller = c));
    await tester.pump();

    expect(named('tower').worldPosition, _at(_far, 0.0, 0.0));
    // A child's position is its parent's space, not the world's.
    expect(named('shed').worldPosition, _at(_far + 1.0, 0.0, 5.0));
    expect(scene.lights.single.worldPosition, _at(_far, 4.0, 0.0));
    final camera = controller!.camera;
    expect(camera.worldPosition, _at(_far, 2.0, 10.0));
    // The target is a world point too: the camera still looks at the tower.
    // A camera looks down its −Z, so its +Z (the third column) points
    // back along +Z, away from the tower.
    final m = camera.worldMatrix.storage;
    expect(m[10], greaterThan(0.9));
  });

  testWidgets('an OrbitCamera3D keeps orbiting its world target across a '
      'shift', (tester) async {
    // Mutation: leave the controller's target in the old scene space, and
    // the next apply swings the camera round a point 1.5 km away.
    Scene3DController? controller;
    Widget tree() => Directionality(
      textDirection: TextDirection.ltr,
      child: Scene3D(
        device: DeviceSettings(device: _device(), presenter: _noPresenter),
        view: _view,
        onSceneCreated: (c) => controller = c,
        children: <Widget>[
          OrbitCamera3D(target: Vector3(_far, 0.0, 0.0), distance: 4.0),
        ],
      ),
    );
    await tester.pumpWidget(tree());
    await tester.pump();
    await tester.pump();
    final before = controller!.camera.worldPosition;
    controller!.scene.shiftOrigin(const WorldPosition(_far, 0.0, 0.0));
    await tester.pumpWidget(tree());
    await tester.pump();
    expect(controller!.camera.worldPosition, _at(before.x, before.y, before.z));
  });
}
