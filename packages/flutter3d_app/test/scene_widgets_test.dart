/// A scene written as widgets — `P10`.
///
///     flutter test test/scene_widgets_test.dart
///
/// The claims are about the graph underneath: which nodes exist, whether a
/// rebuild keeps them, and whether a frame drawn from widgets is the frame
/// the same scene draws when it is built by hand.
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart';

const int _width = 48;
const int _height = 36;

CpuDevice _device() => CpuDevice(
  width: _width,
  height: _height,
  shaders: CpuShaderLibrary(builtinCpuShaders()),
);

/// Shows nothing: the frame is drawn by the surface whether or not it is
/// shown, and a test reads it off the controller's renderer.
Widget _noPresenter(
  GraphicsDevice device,
  TextureHandle frame, {
  BoxFit fit = BoxFit.contain,
  FilterQuality quality = FilterQuality.low,
}) => const SizedBox.expand();

/// [children] in a [Scene3D] of a fixed size, on [device].
Widget _scene(
  CpuDevice device,
  List<Widget> children, {
  void Function(Scene3DController)? onCreated,
  bool continuous = false,
}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Center(
    child: SizedBox(
      width: _width.toDouble(),
      height: _height.toDouble(),
      child: Scene3D(
        device: device,
        continuous: continuous,
        presenter: _noPresenter,
        onCreated: onCreated,
        settings: const RenderSettings(
          bloom: BloomSettings(enabled: false),
          look: LookSettings(dither: 0.0),
        ),
        children: children,
      ),
    ),
  ),
);

/// Pumps until the device has opened and the children are built.
Future<Scene3DController> _pump(
  WidgetTester tester,
  CpuDevice device,
  List<Widget> children,
) async {
  Scene3DController? controller;
  await tester.pumpWidget(
    _scene(device, children, onCreated: (c) => controller = c),
  );
  await tester.pump();
  await tester.pump();
  return controller!;
}

final engine.Material _grey = engine.Material(
  baseColor: Vector4(0.6, 0.6, 0.6, 1.0),
);

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.devicePixelRatio = 1.0;
  });

  testWidgets('the widgets become the scene\'s nodes', (tester) async {
    final controller = await _pump(tester, _device(), <Widget>[
      Mesh3D(shape: CuboidShape(), material: _grey, name: 'a'),
      Node3D(
        name: 'group',
        children: <Widget>[
          Mesh3D(shape: CuboidShape(), material: _grey, name: 'b'),
        ],
      ),
    ]);
    final names = <String?>[for (final m in controller.scene.meshes) m.name];
    expect(names, containsAll(<String>['a', 'b']));
    final b = controller.scene.meshes.firstWhere((m) => m.name == 'b');
    expect(b.parent?.name, 'group');
  });

  testWidgets('a rebuild with the same keys keeps each node', (tester) async {
    // Mutation: make the node in `build` rather than once in
    // `didChangeDependencies`, and every rebuild hands the scene new nodes,
    // losing whatever a game set on the old ones.
    final device = _device();
    Widget mesh(String name) => Mesh3D(
      key: ValueKey<String>(name),
      shape: CuboidShape(),
      material: _grey,
      name: name,
    );
    final controller = await _pump(tester, device, <Widget>[
      mesh('first'),
      mesh('second'),
    ]);
    MeshNode named(String name) =>
        controller.scene.meshes.firstWhere((m) => m.name == name);
    final first = named('first');
    final second = named('second');
    // Something a game did imperatively, which a new node would not have.
    first.tint.setValues(1.0, 0.0, 0.0, 1.0);

    await tester.pumpWidget(
      _scene(device, <Widget>[mesh('second'), mesh('first')]),
    );
    expect(identical(named('first'), first), isTrue);
    expect(identical(named('second'), second), isTrue);
    expect(named('first').tint.x, 1.0);
  });

  testWidgets('properties reach the node, and a widget gone takes its node', (
    tester,
  ) async {
    final device = _device();
    final controller = await _pump(tester, device, <Widget>[
      Mesh3D(
        key: const ValueKey<String>('moving'),
        shape: CuboidShape(),
        material: _grey,
        position: Vector3(1.0, 2.0, 3.0),
        name: 'moving',
      ),
    ]);
    final node = controller.scene.meshes.single;
    expect(node.worldMatrix.getTranslation(), Vector3(1.0, 2.0, 3.0));

    await tester.pumpWidget(
      _scene(device, <Widget>[
        Mesh3D(
          key: const ValueKey<String>('moving'),
          shape: CuboidShape(),
          material: _grey,
          position: Vector3(-1.0, 0.0, 0.0),
          name: 'moving',
        ),
      ]),
    );
    expect(identical(controller.scene.meshes.single, node), isTrue);
    expect(node.worldMatrix.getTranslation(), Vector3(-1.0, 0.0, 0.0));

    await tester.pumpWidget(_scene(device, const <Widget>[]));
    expect(controller.scene.meshes, isEmpty);
    expect(node.parent, isNull);
  });

  testWidgets('a Camera3D is the one drawn through, while it is there', (
    tester,
  ) async {
    final device = _device();
    final controller = await _pump(tester, device, <Widget>[
      Camera3D(position: Vector3(0.0, 3.0, 4.0), target: Vector3.zero()),
    ]);
    expect(
      controller.camera.worldMatrix.getTranslation(),
      Vector3(0.0, 3.0, 4.0),
    );

    await tester.pumpWidget(_scene(device, const <Widget>[]));
    expect(
      controller.camera.worldMatrix.getTranslation(),
      Vector3(0.0, 0.0, 5.0),
    );
  });

  testWidgets('a model stands in with its placeholder until it has loaded', (
    tester,
  ) async {
    // Mutation: drop the placeholder from `_Model3DState.build` once the
    // instance is set, and both stand in the scene together.
    final device = _device();
    final bytes = File(
      '../flutter3d_samples/assets/BoxAnimated.glb',
    ).readAsBytesSync();
    final asset = await tester.runAsync(
      () async => ModelAsset.fromDocument(
        await GltfLoader().load(bytes),
        device: device,
      ),
    );
    final arrived = Completer<ModelAsset>();
    ModelInstance? loaded;
    final controller = await _pump(tester, device, <Widget>[
      Model3D(
        load: (GraphicsDevice device) => arrived.future,
        placeholder: Mesh3D(
          shape: CuboidShape(),
          material: _grey,
          name: 'placeholder',
        ),
        onLoaded: (instance) => loaded = instance,
      ),
    ]);
    expect(controller.scene.meshes.map((m) => m.name), <String?>[
      'placeholder',
    ]);

    arrived.complete(asset);
    await tester.pump();
    await tester.pump();
    expect(loaded, isNotNull);
    expect(
      controller.scene.meshes.map((m) => m.name),
      isNot(contains('placeholder')),
    );
    expect(controller.scene.meshes, isNotEmpty);
  });

  testWidgets('a model\'s animation plays while playing, and holds when not', (
    tester,
  ) async {
    // Mutation: advance the player whatever `playing` says, and the paused
    // model keeps turning.
    final device = _device();
    final bytes = File(
      '../flutter3d_samples/assets/BoxAnimated.glb',
    ).readAsBytesSync();
    final document = (await tester.runAsync(() => GltfLoader().load(bytes)))!;
    final asset = await tester.runAsync(
      () => ModelAsset.fromDocument(document, device: device),
    );
    ModelInstance? loaded;
    Widget model({required bool playing}) => _scene(device, <Widget>[
      Model3D(
        key: const ValueKey<String>('box'),
        load: (GraphicsDevice device) async => asset!,
        animation: document.animations.first.name,
        playing: playing,
        onLoaded: (instance) => loaded = instance,
      ),
    ], continuous: true);

    await tester.pumpWidget(model(playing: true));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(loaded, isNotNull);
    List<double> pose() => <double>[
      for (final mesh in loaded!.meshes) ...mesh.worldMatrix.storage,
    ];

    final before = pose();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    final moving = pose();
    expect(moving, isNot(before));

    await tester.pumpWidget(model(playing: false));
    final held = pose();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(pose(), held);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a frame drawn from widgets is the frame built by hand', (
    tester,
  ) async {
    // The golden this item asks for, held to the strictest reference there
    // is: the same scene through the imperative API, on the same backend,
    // to the byte.
    final device = _device();
    final controller = await _pump(tester, device, <Widget>[
      Camera3D(position: Vector3(2.0, 2.0, 4.0), target: Vector3.zero()),
      Light3D.directional(direction: Vector3(-1.0, -2.0, -1.5), intensity: 3.0),
      Mesh3D(
        shape: CuboidShape(),
        material: _grey,
        rotation: Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.5),
      ),
    ]);
    const settings = RenderSettings(
      bloom: BloomSettings(enabled: false),
      look: LookSettings(dither: 0.0),
    );
    Future<Uint8List> frame(
      Renderer renderer,
      Scene scene,
      CameraNode camera,
    ) async {
      final result = renderer.render(
        width: _width,
        height: _height,
        scene: scene,
        views: <RenderView>[RenderView(camera: camera)],
        settings: settings,
      );
      return (await device.readPixels(result.frame))!.buffer.asUint8List();
    }

    final fromWidgets = await tester.runAsync(
      () => frame(controller.renderer, controller.scene, controller.camera),
    );

    final scene = Scene();
    final camera = CameraNode()
      ..setPosition(2.0, 2.0, 4.0)
      ..lookAt(Vector3.zero());
    scene
      ..add(camera)
      ..add(
        LightNode(intensity: 3.0)
          ..setLocalForward(Vector3(-1.0, -2.0, -1.5).normalized()),
      )
      ..add(
        MeshNode(DeviceMesh.upload(device, CuboidShape().build()), _grey)
          ..setRotation(Quaternion.axisAngle(Vector3(0.0, 1.0, 0.0), 0.5)),
      );
    final byHand = await tester.runAsync(
      () => frame(Renderer.create(device: device), scene, camera),
    );
    expect(fromWidgets, byHand);
  });
}
