/// How `Scene3D` reconciles its widgets with the scene underneath: the
/// contract a hot reload of assets and materials stands on.
///
///     flutter test test/scene3d_reconciliation_test.dart
///
/// Three rules. **Identity is the key**: a keyed widget moved among its
/// siblings, or nested under another parent, keeps its node. **A rebuild
/// loads nothing**: a model rebuilt with new properties is the instance it
/// was. **Gone is released**: a widget's node leaves the scene, and what the
/// widget made on the device — an uploaded mesh, a loaded model — goes back
/// to it.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/flutter3d.dart' as engine show RenderMaterial;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/testing.dart' show FakeBackend;
import 'package:flutter_test/flutter_test.dart';

final engine.RenderMaterial _grey = engine.RenderMaterial(
  baseColor: LinearColor.fromSrgb(0.6, 0.6, 0.6, 1.0),
);

/// A mount over a scene of its own, and the renderer it releases through.
final class _Stage {
  _Stage({GraphicsDevice? device})
    : device =
          device ??
          CpuDevice(
            width: 8,
            height: 8,
            shaders: CpuShaderLibrary(builtinCpuShaders()),
          ) {
    mount = SceneWidgets.mount(
      scene: scene,
      renderer: renderer,
      device: this.device,
    );
  }

  final GraphicsDevice device;
  late final Renderer renderer = Renderer.create(device: device);
  final Scene scene = Scene();
  late final SceneWidgetsMount mount;
  late final CameraNode camera = CameraNode()..setPosition(0.0, 0.0, 5.0);

  /// Enough frames for anything released after a frame to have gone back.
  void frames() {
    for (var i = 0; i < 4; i++) {
      renderer.render(
        width: 8,
        height: 8,
        scene: scene,
        views: <RenderView>[RenderView(camera: camera)],
      );
    }
  }

  MeshNode mesh(String name) => scene.meshes.firstWhere((m) => m.name == name);
}

Scene3DController? controller;

/// Shows nothing: the test reads the scene, not the picture.
Widget _noPresenter(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.contain,
  FilterQuality quality = FilterQuality.low,
}) => const SizedBox.expand();

Widget _box(String name, {Vector3? at}) => Mesh3D(
  key: ValueKey<String>(name),
  shape: CuboidShape(),
  material: _grey,
  position: at,
  name: name,
);

void main() {
  group('identity is the key', () {
    test('a keyed mesh moved among its siblings keeps its node', () {
      final stage = _Stage();
      stage.mount.update(<Widget>[_box('a'), _box('b'), _box('c')]);
      final a = stage.mesh('a');
      final c = stage.mesh('c');
      stage.mount.update(<Widget>[_box('c'), _box('b'), _box('a')]);
      expect(identical(stage.mesh('a'), a), isTrue);
      expect(identical(stage.mesh('c'), c), isTrue);
      stage.mount.dispose();
    });

    testWidgets('a keyed mesh moved under another parent keeps its node, '
        'and its mesh on the device', (WidgetTester tester) async {
      // Mutation: drop the `GlobalKey` reparent in `_SpatialState` — a node
      // made again would upload its mesh again. In a `Scene3D`, the tree an
      // application builds: a `GlobalKey` is found through the widgets
      // binding's own build owner, which a `SceneWidgets.mount` does not use.
      final key = GlobalKey();
      Widget crate() => Mesh3D(
        key: key,
        shape: CuboidShape(),
        material: _grey,
        name: 'crate',
      );
      Widget scene(bool onTheLeft) => Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 8,
          height: 8,
          child: Scene3D(
            device: DeviceSettings(
              device: CpuDevice(
                width: 8,
                height: 8,
                shaders: CpuShaderLibrary(builtinCpuShaders()),
              ),
              presenter: _noPresenter,
            ),
            view: const ViewSettings(continuous: false),
            onSceneCreated: (Scene3DController it) => controller = it,
            children: <Widget>[
              Node3D(
                key: const ValueKey<String>('left'),
                name: 'left',
                children: <Widget>[if (onTheLeft) crate()],
              ),
              Node3D(
                key: const ValueKey<String>('right'),
                name: 'right',
                children: <Widget>[if (!onTheLeft) crate()],
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(scene(false));
      await tester.pump();
      await tester.pump();
      MeshNode named() =>
          controller!.scene.meshes.firstWhere((m) => m.name == 'crate');
      final node = named();
      final uploaded = node.mesh;

      await tester.pumpWidget(scene(true));
      await tester.pump();
      expect(identical(named(), node), isTrue);
      expect(node.parent?.name, 'left');
      expect(identical(node.mesh, uploaded), isTrue);
    });
  });

  group('a rebuild loads nothing', () {
    test('a model rebuilt with new properties is not loaded again', () async {
      // Mutation: start the load from `apply`, which every rebuild runs, and
      // the count follows the rebuilds.
      final stage = _Stage();
      var loads = 0;
      ModelInstance? instance;
      Future<ModelAsset> load(GraphicsDevice device) async {
        loads++;
        return ModelAsset.fromMesh(device, CuboidShape().build(), name: 'box');
      }

      Widget model(Vector3 at) => Model3D(
        key: const ValueKey<String>('model'),
        load: load,
        position: at,
        onLoaded: (ModelInstance it) => instance = it,
      );
      stage.mount.update(<Widget>[model(Vector3.zero())]);
      await pumpEventQueue();
      expect(loads, 1);
      final first = instance;
      expect(first, isNotNull);

      for (var i = 1; i <= 3; i++) {
        stage.mount.update(<Widget>[model(Vector3(i.toDouble(), 0.0, 0.0))]);
        await pumpEventQueue();
      }
      expect(loads, 1);
      expect(identical(instance, first), isTrue);
      expect(first!.root.worldMatrix.getTranslation().x, 3.0);
      stage.mount.dispose();
    });

    test('a mesh rebuilt with an equal shape is not uploaded again', () {
      final stage = _Stage();
      stage.mount.update(<Widget>[_box('a')]);
      final uploaded = stage.mesh('a').mesh;
      stage.mount.update(<Widget>[_box('a', at: Vector3(1.0, 0.0, 0.0))]);
      expect(identical(stage.mesh('a').mesh, uploaded), isTrue);
      stage.mount.dispose();
    });
  });

  group('gone is released', () {
    test('a mesh widget gone takes its node out and gives its upload back', () {
      // Mutation: drop the release from `_Mesh3DState.dispose`, and the
      // uploaded mesh stays on the device for the life of the renderer.
      // The renderer gives it back once no frame in flight can read it, to
      // the device: that is where the release is seen.
      final device = FakeBackend();
      final stage = _Stage(device: device);
      stage.mount.update(<Widget>[_box('a'), _box('b')]);
      final a = stage.mesh('a');
      final uploaded = a.mesh as DeviceMesh;
      stage.frames();
      expect(device.releasedGeometry, isNot(contains(uploaded.vertices)));

      stage.mount.update(<Widget>[_box('b')]);
      expect(a.parent, isNull);
      expect(stage.scene.meshes.map((m) => m.name), <String?>['b']);
      stage.frames();
      expect(
        device.releasedGeometry,
        containsAll(<Object>[uploaded.vertices, uploaded.indices]),
      );
      stage.mount.dispose();
    });

    test('a mesh given a different shape gives the old upload back', () {
      final device = FakeBackend();
      final stage = _Stage(device: device);
      Widget box(Shape shape) => Mesh3D(
        key: const ValueKey<String>('a'),
        shape: shape,
        material: _grey,
        name: 'a',
      );
      stage.mount.update(<Widget>[box(CuboidShape())]);
      final old = stage.mesh('a').mesh as DeviceMesh;
      stage.mount.update(<Widget>[box(SphereShape())]);
      expect(identical(stage.mesh('a').mesh, old), isFalse);
      stage.frames();
      expect(
        device.releasedGeometry,
        containsAll(<Object>[old.vertices, old.indices]),
      );
      stage.mount.dispose();
    });

    test('a geometry handed in is the caller\'s and is left alone', () {
      final stage = _Stage();
      final geometry = DeviceMesh.upload(stage.device, CuboidShape().build());
      stage.mount.update(<Widget>[
        Mesh3D(geometry: geometry, material: _grey, name: 'given'),
      ]);
      stage.mount.update(const <Widget>[]);
      stage.frames();
      expect(geometry.isDisposed, isFalse);
      stage.mount.dispose();
    });

    test('a model widget gone takes its instance out and disposes the asset '
        'it loaded', () async {
      // Mutation: drop the dispose from `_Model3DState.dispose`, and every
      // model a level ever showed stays on the device.
      final stage = _Stage();
      late ModelAsset asset;
      stage.mount.update(<Widget>[
        Model3D(
          load: (GraphicsDevice device) async => asset = ModelAsset.fromMesh(
            device,
            CuboidShape().build(),
            name: 'box',
          ),
        ),
      ]);
      await pumpEventQueue();
      expect(stage.scene.meshes, isNotEmpty);

      stage.mount.update(const <Widget>[]);
      expect(stage.scene.meshes, isEmpty);
      expect(asset.isDisposed, isTrue);
      stage.mount.dispose();
    });

    test('a model whose widget went before it arrived is disposed as it '
        'arrives', () async {
      final stage = _Stage();
      late ModelAsset asset;
      stage.mount.update(<Widget>[
        Model3D(
          load: (GraphicsDevice device) async {
            await Future<void>.delayed(Duration.zero);
            return asset = ModelAsset.fromMesh(
              device,
              CuboidShape().build(),
              name: 'late',
            );
          },
        ),
      ]);
      stage.mount.update(const <Widget>[]);
      await pumpEventQueue();
      expect(asset.isDisposed, isTrue);
      expect(stage.scene.meshes, isEmpty);
      stage.mount.dispose();
    });
  });
}
