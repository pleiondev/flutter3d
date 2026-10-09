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
import 'package:flutter3d/flutter3d.dart';
import 'package:flutter3d/flutter3d.dart' as engine show RenderMaterial;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_particles/flutter3d_particles.dart';
import 'package:flutter_test/flutter_test.dart';

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

final engine.RenderMaterial _grey = engine.RenderMaterial(
  baseColor: LinearColor.fromSrgb(0.6, 0.6, 0.6, 1.0),
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
    first.tint = const LinearColor(1.0, 0.0, 0.0);

    await tester.pumpWidget(
      _scene(device, <Widget>[mesh('second'), mesh('first')]),
    );
    expect(identical(named('first'), first), isTrue);
    expect(identical(named('second'), second), isTrue);
    expect(named('first').tint.r, 1.0);
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
      return (await device.readback(result.frame)).buffer.asUint8List();
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
        LightNode(intensity: 3.0 * Photometric.legacyUnit)
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

  group('materials, probes, decals, mirrors and particles as widgets', () {
    testWidgets('the meshes under one Material3D share its one material, '
        'changed in place', (tester) async {
      // Mutation: make a new engine material in `_Material3DState._apply` —
      // the meshes keep the old one and the rebuild's colour reaches neither.
      final device = _device();
      Widget scene(Vector4 color) => _scene(device, <Widget>[
        Material3D(
          key: const ValueKey<String>('paint'),
          baseColor: _fromSrgb(color),
          roughness: 0.3,
          children: <Widget>[
            Mesh3D(shape: CuboidShape(), name: 'a'),
            Mesh3D(shape: CuboidShape(), name: 'b'),
          ],
        ),
      ]);
      Scene3DController? controller;
      await tester.pumpWidget(
        _scene(device, const <Widget>[], onCreated: (c) => controller = c),
      );
      await tester.pump();
      await tester.pumpWidget(scene(Vector4(1.0, 0.0, 0.0, 1.0)));
      final meshes = controller!.scene.meshes.toList();
      expect(meshes, hasLength(2));
      final shared = meshes.first.material;
      expect(identical(meshes.last.material, shared), isTrue);
      expect(shared.roughness, 0.3);

      await tester.pumpWidget(scene(Vector4(0.0, 0.0, 1.0, 1.0)));
      expect(
        identical(controller!.scene.meshes.first.material, shared),
        isTrue,
      );
      expect(shared.baseColor.toSrgb().b, 1.0);
      expect(shared.baseColor.toSrgb().r, 0.0);
    });

    testWidgets('a mesh with no material and none above is refused', (
      tester,
    ) async {
      await tester.pumpWidget(_scene(_device(), const <Widget>[]));
      await tester.pump();
      await tester.pump();
      await tester.pumpWidget(
        _scene(_device(), <Widget>[Mesh3D(shape: CuboidShape())]),
      );
      expect(tester.takeException(), isA<FlutterError>());
    });

    testWidgets('a mesh directly below a Mirror3D is one of its surfaces, '
        'while it is there', (tester) async {
      // Mutation: drop `_joinMirror` from `_Mesh3DState.apply` — the mirror
      // has no surface to be seen in.
      final device = _device();
      final controller = await _pump(tester, device, <Widget>[
        Mirror3D(
          reflectance: 0.8,
          children: <Widget>[
            Mesh3D(
              key: const ValueKey<String>('floor'),
              shape: CuboidShape(),
              material: _grey,
              name: 'floor',
            ),
          ],
        ),
      ]);
      final mirror = controller.scene.root.children
          .whereType<PlanarReflectorNode>()
          .single;
      expect(mirror.reflectance, 0.8);
      expect(mirror.surfaces.map((m) => m.name), <String?>['floor']);

      await tester.pumpWidget(
        _scene(device, <Widget>[Mirror3D(reflectance: 0.8)]),
      );
      expect(mirror.surfaces, isEmpty);
    });

    testWidgets('a probe and a decal are nodes with what the widgets say', (
      tester,
    ) async {
      final controller = await _pump(tester, _device(), <Widget>[
        ReflectionProbe3D(position: Vector3(0.0, 1.0, 0.0), radius: 6.0),
        Decal3D(
          scale: Vector3(2.0, 2.0, 0.5),
          color: LinearColor.fromSrgb(1.0, 0.0, 0.0, 1.0),
          order: 3,
        ),
      ]);
      final probe = controller.scene.root.children
          .whereType<ReflectionProbeNode>()
          .single;
      expect(probe.radius, 6.0);
      final decal = controller.scene.root.children
          .whereType<DecalNode>()
          .single;
      expect(decal.order, 3);
      expect(decal.color.r, 1.0);
    });

    testWidgets('particles are drawn while the widget is there and emitted '
        'as the scene advances', (tester) async {
      // Mutation: leave `host.animated.add(this)` out of
      // `_Particles3DState.createNode` — nothing is ever emitted.
      final device = _device();
      final effect = ParticleEffect(
        count: 1,
        emitter: const SphereEmitter(speed: Range.exact(0.0)),
        lifetime: const Range.exact(5.0),
        size: const Range.exact(0.2),
        color: Vector4(1.0, 0.5, 0.2, 1.0),
      );
      final system = ParticleSystem(capacity: 64);
      Scene3DController? controller;
      Widget torch() => _scene(
        device,
        <Widget>[
          Particles3D(
            key: const ValueKey<String>('torch'),
            effect: effect,
            perSecond: 40.0,
            system: system,
          ),
        ],
        onCreated: (c) => controller = c,
        continuous: true,
      );
      await tester.pumpWidget(torch());
      await tester.pump();
      await tester.pump();
      expect(
        controller!.renderer.renderSteps.contributors
            .whereType<ParticleContributor>(),
        hasLength(1),
      );
      // A second of frames through the scene's own loop.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(system.aliveCount, greaterThan(10));

      await tester.pumpWidget(_scene(device, const <Widget>[]));
      expect(
        controller!.renderer.renderSteps.contributors
            .whereType<ParticleContributor>(),
        isEmpty,
      );
    });
  });

  group('SceneWidgets.mount — widgets in a scene somebody else draws', () {
    test('builds into the scene given, keeps a keyed node, and takes it all '
        'out when disposed', () {
      final device = _device();
      final scene = Scene();
      final renderer = Renderer.create(device: device);
      Widget mesh(Vector3 at) => Mesh3D(
        key: const ValueKey<String>('crate'),
        shape: CuboidShape(),
        material: _grey,
        position: at,
        name: 'crate',
      );
      final mount = SceneWidgets.mount(
        scene: scene,
        renderer: renderer,
        device: device,
        children: <Widget>[
          Camera3D(position: Vector3(0.0, 2.0, 4.0), target: Vector3.zero()),
          mesh(Vector3.zero()),
        ],
      );
      final node = scene.meshes.single;
      expect(mount.camera, isNotNull);

      mount.update(<Widget>[mesh(Vector3(1.0, 0.0, 0.0))]);
      expect(identical(scene.meshes.single, node), isTrue);
      expect(node.worldMatrix.getTranslation().x, 1.0);
      expect(mount.camera, isNull, reason: 'the camera widget went');

      mount.dispose();
      expect(scene.meshes, isEmpty);
    });

    test('a frame drawn from a mount is the frame built by hand', () async {
      // The golden runner's way in: the same scene as the imperative API's,
      // to the byte, on the same backend.
      final device = _device();
      const settings = RenderSettings(
        bloom: BloomSettings(enabled: false),
        look: LookSettings(dither: 0.0),
      );
      Future<Uint8List> frame(Scene scene, CameraNode camera) async {
        final result = Renderer.create(device: device).render(
          width: _width,
          height: _height,
          scene: scene,
          views: <RenderView>[RenderView(camera: camera)],
          settings: settings,
        );
        return (await device.readback(result.frame)).buffer.asUint8List();
      }

      final mounted = Scene();
      final mount = SceneWidgets.mount(
        scene: mounted,
        renderer: Renderer.create(device: device),
        device: device,
        children: <Widget>[
          Camera3D(position: Vector3(2.0, 2.0, 4.0), target: Vector3.zero()),
          Light3D.directional(
            direction: Vector3(-1.0, -2.0, -1.5),
            intensity: 3.0,
          ),
          Material3D(
            baseColor: LinearColor.fromSrgb(0.6, 0.6, 0.6, 1.0),
            children: <Widget>[Mesh3D(shape: CuboidShape())],
          ),
        ],
      );
      final fromWidgets = await frame(mounted, mount.camera!);

      final scene = Scene();
      final camera = CameraNode()
        ..setPosition(2.0, 2.0, 4.0)
        ..lookAt(Vector3.zero());
      scene
        ..add(camera)
        ..add(
          LightNode(intensity: 3.0 * Photometric.legacyUnit)
            ..setLocalForward(Vector3(-1.0, -2.0, -1.5).normalized()),
        )
        ..add(
          MeshNode(DeviceMesh.upload(device, CuboidShape().build()), _grey),
        );
      expect(fromWidgets, await frame(scene, camera));
    });
  });
}

/// A `Vector4` holding a colour sRGB-encoded, as the linear colour it names.
LinearColor _fromSrgb(Vector4 c) => LinearColor.fromSrgb(c.x, c.y, c.z, c.w);
