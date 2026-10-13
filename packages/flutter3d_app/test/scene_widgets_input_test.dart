/// A scene of widgets answers the hand: `Mesh3D.onTap`, `Model3D.onTap`
/// with the part tapped, and `OrbitCamera3D` turned by a drag and moved by
/// a scroll.
///
///     flutter test test/scene_widgets_input_test.dart
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/flutter3d.dart' as engine show RenderMaterial;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';

const double _width = 160;
const double _height = 120;

CpuDevice _device() => CpuDevice(
  width: _width.toInt(),
  height: _height.toInt(),
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

final GlobalKey _sceneKey = GlobalKey();

Widget _scene(
  CpuDevice device,
  List<Widget> children, {
  void Function(Scene3DController)? onCreated,
  bool continuous = false,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: SizedBox(
      width: _width,
      height: _height,
      child: Scene3D(
        key: _sceneKey,
        device: DeviceSettings(device: device, presenter: _noPresenter),
        view: ViewSettings(
          continuous: continuous,
          settings: const RenderSettings(bloom: BloomSettings(enabled: false)),
        ),
        onSceneCreated: onCreated,
        children: children,
      ),
    ),
  ),
);

/// Pumps until the device is open, the children built, and the gestures
/// they asked for attached.
Future<Scene3DController> _pump(
  WidgetTester tester,
  CpuDevice device,
  List<Widget> children, {
  bool continuous = false,
}) async {
  Scene3DController? controller;
  await tester.pumpWidget(
    _scene(
      device,
      children,
      onCreated: (c) => controller = c,
      continuous: continuous,
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  return controller!;
}

Offset get _middle => const Offset(400.0, 300.0);

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view
      ..devicePixelRatio = 1.0
      ..physicalSize = const Size(800.0, 600.0);
    addTearDown(view.reset);
  });

  group('a tap', () {
    testWidgets('reaches the mesh under it, with where it landed', (
      tester,
    ) async {
      // Mutation: leave the GestureDetector's `onTapUp` null, or call the
      // handler of the first mesh registered rather than the one hit.
      final taps = <String>[];
      Tap3D? landed;
      await _pump(tester, _device(), <Widget>[
        Mesh3D(
          shape: CuboidShape(),
          material: _grey,
          name: 'crate',
          onTap: (Tap3D tap) {
            taps.add('crate');
            landed = tap;
          },
        ),
        Mesh3D(
          shape: CuboidShape(),
          material: _grey,
          name: 'aside',
          position: Vector3(40.0, 0.0, 0.0),
          onTap: (Tap3D tap) => taps.add('aside'),
        ),
      ]);
      await tester.tapAt(_middle);
      expect(taps, <String>['crate']);
      // The default camera stands at z = 5 looking at the cube's +Z face.
      expect(landed!.hit.point.z, closeTo(0.5, 1e-3));
      expect(landed!.hit.normal.z, closeTo(1.0, 1e-3));
    });

    testWidgets('hands the pointer with the hit: where in the scene, which '
        'device, which buttons', (tester) async {
      // Mutation: build the tap from the hit alone, dropping the details,
      // and the position and the device are lost.
      final taps = <Tap3D>[];
      await _pump(tester, _device(), <Widget>[
        Mesh3D(shape: CuboidShape(), material: _grey, onTap: taps.add),
      ]);
      await tester.tapAt(_middle + const Offset(3.0, -2.0));
      await tester.tapAt(_middle, kind: PointerDeviceKind.mouse);
      expect(taps, hasLength(2));
      // The scene is 160 by 120 in the middle of an 800 by 600 window.
      expect(taps[0].localPosition, const Offset(83.0, 58.0));
      expect(taps[0].kind, PointerDeviceKind.touch);
      expect(taps[0].buttons, kPrimaryButton);
      expect(taps[1].kind, PointerDeviceKind.mouse);
      // Each tap its own hit: the second cast did not rewrite the first.
      expect(taps[0].hit, isNot(same(taps[1].hit)));
      expect(taps[0].hit.point.x, greaterThan(taps[1].hit.point.x));
    });

    testWidgets('on empty space, or on a mesh that does not listen in front '
        'of one that does, reaches nothing', (tester) async {
      var tapped = 0;
      await _pump(tester, _device(), <Widget>[
        Mesh3D(
          shape: CuboidShape(),
          material: _grey,
          name: 'wall',
          position: Vector3(0.0, 0.0, 1.5),
        ),
        Mesh3D(
          shape: CuboidShape(),
          material: _grey,
          name: 'behind',
          onTap: (Tap3D tap) => tapped++,
        ),
      ]);
      await tester.tapAt(_middle);
      await tester.tapAt(_middle + const Offset(70.0, 50.0));
      expect(tapped, 0);
    });

    testWidgets('reaches a model with the part it landed on', (tester) async {
      MeshNode? part;
      ModelInstance? loaded;
      await _pump(tester, _device(), <Widget>[
        Model3D(
          load: (GraphicsDevice device) async =>
              ModelAsset.fromMesh(device, CuboidShape().build(), name: 'hull'),
          onLoaded: (ModelInstance instance) => loaded = instance,
          // The part is the hit's node: one shape for every onTap.
          onTap: (Tap3D tap) => part = tap.hit.node,
        ),
      ]);
      await tester.pump();
      await tester.pump();
      expect(loaded, isNotNull);
      await tester.tapAt(_middle);
      expect(part, isNotNull);
      expect(loaded!.meshes, contains(part));
    });

    testWidgets('is not listened for while nothing answers it', (tester) async {
      // A scene with no listener must take no gesture from what it sits in.
      await _pump(tester, _device(), <Widget>[
        Mesh3D(shape: CuboidShape(), material: _grey),
      ]);
      final detector = tester.widget<GestureDetector>(
        find
            .descendant(
              of: find.byKey(_sceneKey),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      expect(detector.onTapUp, isNull);
      expect(detector.onScaleUpdate, isNull);
    });
  });

  group('OrbitCamera3D', () {
    testWidgets('starts where it is told and is the camera drawn through', (
      tester,
    ) async {
      final controller = await _pump(tester, _device(), const <Widget>[
        OrbitCamera3D(distance: 4.0, pitch: 0.0),
      ]);
      expect(
        controller.camera.worldMatrix.getTranslation(),
        _closeTo(Vector3(0.0, 0.0, 4.0)),
      );
    });

    testWidgets('a horizontal drag swings it round the target at the same '
        'distance, and a scroll moves it in, no closer than its floor', (
      tester,
    ) async {
      // Mutation: hand the drag to nothing (`onScaleUpdate` null), and the
      // camera stays at +Z.
      final controller = await _pump(tester, _device(), const <Widget>[
        OrbitCamera3D(distance: 4.0, pitch: 0.0, minDistance: 2.0),
      ]);
      await tester.dragFrom(_middle, const Offset(-120.0, 0.0));
      await tester.pump();
      final at = controller.camera.worldMatrix.getTranslation();
      expect(at.x.abs(), greaterThan(0.5));
      expect(at.length, closeTo(4.0, 1e-6));

      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          position: _middle,
          scrollDelta: const Offset(0.0, -100.0),
        ),
      );
      await tester.pump();
      final closer = controller.camera.worldMatrix.getTranslation().length;
      expect(closer, lessThan(4.0));

      for (var i = 0; i < 20; i++) {
        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: _middle,
            scrollDelta: const Offset(0.0, -500.0),
          ),
        );
      }
      await tester.pump();
      expect(
        controller.camera.worldMatrix.getTranslation().length,
        closeTo(2.0, 1e-6),
      );
    });

    testWidgets('a fling keeps turning after the finger lifts, and slows', (
      tester,
    ) async {
      // Mutation: drop the spin from `advance`, and the camera stops dead.
      final controller = await _pump(tester, _device(), const <Widget>[
        OrbitCamera3D(distance: 4.0, pitch: 0.0),
      ], continuous: true);
      await tester.flingFrom(_middle, const Offset(-150.0, 0.0), 1500.0);
      await tester.pump(const Duration(milliseconds: 16));
      Vector3 at() => controller.camera.worldMatrix.getTranslation();
      final released = at();
      await tester.pump(const Duration(milliseconds: 100));
      final later = at();
      expect(later.distanceTo(released), greaterThan(1e-3));
      await tester.pump(const Duration(seconds: 3));
      final settled = at();
      await tester.pump(const Duration(milliseconds: 100));
      expect(at().distanceTo(settled), lessThan(1e-3));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('with no damping it stops when the finger lifts', (
      tester,
    ) async {
      final controller = await _pump(tester, _device(), const <Widget>[
        OrbitCamera3D(distance: 4.0, pitch: 0.0, damping: null),
      ], continuous: true);
      await tester.flingFrom(_middle, const Offset(-150.0, 0.0), 1500.0);
      await tester.pump(const Duration(milliseconds: 16));
      final released = controller.camera.worldMatrix.getTranslation();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        controller.camera.worldMatrix.getTranslation().distanceTo(released),
        lessThan(1e-9),
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}

Matcher _closeTo(Vector3 expected) => predicate<Vector3>(
  (Vector3 v) => v.distanceTo(expected) < 1e-6,
  'within 1e-6 of $expected',
);
