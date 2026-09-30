/// What a hot reload does to a running world: relink every renderer, refresh
/// the bundles an application loaded itself, and keep the last bundle that
/// loaded when a new one does not.
///
///     flutter test test/hot_swap_test.dart
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter3d/flutter3d.dart' hide Material;
import 'package:flutter3d/flutter3d.dart' as engine show Material;
import 'package:flutter3d_app/flutter3d_app.dart';
import 'package:flutter3d_cpu/flutter3d_cpu.dart';
import 'package:flutter3d_hardware/trace.dart'
    show RecordingDevice, TraceReleaseTexture;
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math.dart' show Vector3, Vector4;

/// A renderer in software with one cube in front of it, so a frame links a
/// material pipeline a reload has to drop.
({Renderer renderer, Scene scene, RenderView view}) _stage() {
  final device = CpuDevice(
    width: 16,
    height: 9,
    shaders: CpuShaderLibrary(builtinCpuShaders()),
  );
  final camera = CameraNode()..setPosition(0.0, 0.0, 4.0);
  final scene = Scene()
    ..add(camera)
    ..add(
      MeshNode(
        DeviceMesh.upload(device, CuboidShape(size: Vector3.all(1.0)).build()),
        engine.Material(name: 'cube'),
      ),
    );
  return (
    renderer: Renderer.create(device: device),
    scene: scene,
    view: RenderView(camera: camera),
  );
}

void _draw(({Renderer renderer, Scene scene, RenderView view}) it) =>
    it.renderer.render(
      width: 16,
      height: 9,
      scene: it.scene,
      views: <RenderView>[it.view],
    );

/// Counts the times a renderer asked it to drop what it linked.
final class _Contributor extends PassContributor {
  int relinks = 0;

  @override
  bool get isActive => false;

  @override
  void encode(ContributorFrame frame) {}

  @override
  void relinkShaders() => relinks++;
}

/// A bundle an application loaded from bytes, refreshed from what [bytes]
/// says now; refuses whatever starts with a zero byte.
final class _Library implements LoadedShaderLibrary {
  final List<ByteData> refreshes = <ByteData>[];

  @override
  String get name => 'game';

  @override
  ShaderHandle? operator [](String name) => null;

  @override
  void refresh(ByteData bytes) {
    if (bytes.getUint8(0) == 0) {
      throw const ShaderBundleRefused(name: 'game', reason: 'not a bundle');
    }
    refreshes.add(bytes);
  }
}

ByteData _bytes(List<int> values) =>
    ByteData.sublistView(Uint8List.fromList(values));

/// A one-quad model whose colour is its file's first byte: 1 red, 2 green,
/// 3 blue; 0 does not build.
Future<ModelAsset> _model(GraphicsDevice device, Uint8List bytes) {
  if (bytes.first == 0) throw const FormatException('not a model');
  final colour = Vector4.zero()
    ..[bytes.first - 1] = 1.0
    ..w = 1.0;
  return ModelAsset.fromDocument(
    PlainModelDocument(
      surfaces: <ModelSurface>[
        ModelSurface(
          mesh: CuboidShape(size: Vector3.all(1.0)).build(),
          materialIndex: 0,
        ),
      ],
      materials: <SurfaceMaterial>[
        SurfaceMaterial(baseColor: colour, unlit: true, name: 'paint'),
      ],
      nodes: <ModelNode>[
        ModelNode(name: 'hull', surfaces: <int>[0]),
      ],
    ),
    device: device,
  );
}

void main() {
  test('a reload drops every pipeline the renderer and its contributors '
      'linked', () async {
    final it = _stage();
    final contributor = it.renderer.addContributor(_Contributor());
    final swap = HotSwap(enabled: true)..registerRenderer(it.renderer);
    _draw(it);
    expect(it.renderer.pipelineCount, greaterThan(0));

    final report = await swap.swap();

    expect(report.renderers, 1);
    expect(it.renderer.pipelineCount, 0);
    expect(contributor.relinks, 1);
    // And the next frame links them again: the reload costs one frame's
    // links, not the picture.
    _draw(it);
    expect(it.renderer.pipelineCount, greaterThan(0));
  });

  test('a bundle is refreshed when its bytes change, and only then', () async {
    final library = _Library();
    var current = _bytes(<int>[1, 2, 3]);
    final swap = HotSwap(
      enabled: true,
    )..registerLibrary(library, read: () async => current, loadedFrom: current);

    expect((await swap.swap()).refreshed, isEmpty);
    expect(library.refreshes, isEmpty);

    current = _bytes(<int>[1, 2, 4]);
    expect((await swap.swap()).refreshed, <String>['game']);
    expect(library.refreshes, hasLength(1));

    expect((await swap.swap()).refreshed, isEmpty);
    expect(library.refreshes, hasLength(1));
  });

  test('a bundle that does not load keeps the last one that did, and is '
      'not tried again until it changes', () async {
    final library = _Library();
    var current = _bytes(<int>[1, 2, 3]);
    final swap = HotSwap(
      enabled: true,
    )..registerLibrary(library, read: () async => current, loadedFrom: current);

    current = _bytes(<int>[0, 9]);
    final refused = await swap.swap();
    expect(refused.refused, hasLength(1));
    expect(refused.refused.single, contains('not a bundle'));
    expect(library.refreshes, isEmpty);

    expect((await swap.swap()).refused, isEmpty);

    current = _bytes(<int>[1, 9]);
    expect((await swap.swap()).refreshed, <String>['game']);
  });

  test('two surfaces reassembling in one hot reload share one run', () async {
    final it = _stage();
    final contributor = it.renderer.addContributor(_Contributor());
    final swap = HotSwap(enabled: true)
      ..registerRenderer(it.renderer)
      ..registerRenderer(it.renderer);

    await Future.wait(<Future<HotSwapReport>>[swap.swap(), swap.swap()]);

    expect(contributor.relinks, 1);
  });

  test('outside a debug build nothing is held and nothing reloads', () async {
    final it = _stage();
    final contributor = it.renderer.addContributor(_Contributor());
    final swap = HotSwap(enabled: false)..registerRenderer(it.renderer);

    final report = await swap.swap();

    expect(report.renderers, 0);
    expect(contributor.relinks, 0);
  });

  testWidgets('a hot reload of the app relinks the renderer a surface draws '
      'with', (WidgetTester tester) async {
    final it = _stage();
    final contributor = it.renderer.addContributor(_Contributor());
    await tester.pumpWidget(
      MaterialApp(
        home: SceneSurface(
          renderer: it.renderer,
          scene: it.scene,
          view: it.view,
          onBeforeFrame: () {},
          settings: () => const RenderSettings(),
          presentFrame:
              (
                GraphicsDevice device,
                TextureHandle frame, {
                BoxFit fit = BoxFit.fill,
                FilterQuality quality = FilterQuality.none,
              }) => const SizedBox.shrink(),
        ),
      ),
    );
    final before = HotSwap.instance.swaps.value;

    // Not awaited: it completes at the end of a frame, and a widget test has
    // frames only when it pumps them.
    unawaited(tester.binding.reassembleApplication());
    await tester.pump();
    await tester.pump();

    expect(contributor.relinks, 1);
    expect(HotSwap.instance.swaps.value, before + 1);
  });

  group('a model', () {
    late CpuDevice device;
    late Uint8List file;
    late HotSwap swap;
    late SwappableModel model;

    setUp(() async {
      device = CpuDevice(
        width: 16,
        height: 9,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      file = Uint8List.fromList(<int>[1]);
      swap = HotSwap(enabled: true);
      model = swap.registerModel(
        'assets_src/ship.glb',
        await _model(device, file),
        read: () async => file,
        build: (Uint8List bytes) => _model(device, bytes),
        device: device,
        loadedFrom: file,
      );
    });

    double blue(ModelInstance ship) => ship.meshes.single.material.baseColor.z;

    test('is drawn anew in every instance when its file changes, and '
        'only then', () async {
      final scene = Scene();
      final a = model.instantiate(scene);
      final b = model.instantiate(scene);

      expect((await swap.swap()).models, isEmpty);

      file = Uint8List.fromList(<int>[3]);
      final report = await swap.swap();

      expect(report.models.single.instances, 2);
      expect(blue(a), 1.0);
      expect(blue(b), 1.0);
      expect(model.instantiate(scene).meshes.single.material.baseColor.z, 1.0);
      expect((await swap.swap()).models, isEmpty);
    });

    test(
      'put draws bytes the file never had, until the file changes',
      () async {
        final ship = model.instantiate(Scene());

        final put = await swap.put(
          'assets_src/ship.glb',
          Uint8List.fromList(<int>[3]),
        );
        expect(put!.instances, 1);
        expect(blue(ship), 1.0);

        expect((await swap.swap()).models, isEmpty, reason: 'file unchanged');
        expect(blue(ship), 1.0);

        file = Uint8List.fromList(<int>[2]);
        await swap.swap();
        expect(ship.meshes.single.material.baseColor.y, 1.0);
        expect(await swap.put('assets_src/boat.glb', file), isNull);
      },
    );

    test('that does not build keeps the version that did', () async {
      final ship = model.instantiate(Scene());
      final before = model.asset;

      file = Uint8List.fromList(<int>[0]);
      final report = await swap.swap();

      expect(report.refused.single, contains('not a model'));
      expect(model.asset, same(before));
      expect(ship.meshes.single.material.baseColor.x, 1.0);
    });
  });

  group('a material', () {
    late CpuDevice device;
    late HotSwap swap;

    setUp(() {
      device = CpuDevice(
        width: 16,
        height: 9,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      swap = HotSwap(enabled: true);
    });

    test('is set in every scene registered, once however many nodes wear '
        'it', () async {
      final asset = await _model(device, Uint8List.fromList(<int>[1]));
      final scene = Scene();
      final a = asset.instantiate(scene);
      asset.instantiate(scene);
      swap.registerScene(scene);

      final touched = swap.setMaterial('paint', <String, Object?>{
        'baseColor': <double>[0.0, 0.5, 1.0, 1.0],
        'roughness': 0.25,
      });

      expect(touched, 1, reason: 'the two instances share it');
      final material = a.meshes.single.material;
      expect(material.baseColor.z, 1.0);
      expect(material.roughness, 0.25);
      expect(swap.setMaterial('chrome', <String, Object?>{'metallic': 1}), 0);
    });

    test('refuses a field it does not know or a value of the wrong size', () {
      expect(
        () => swap.setMaterial('paint', <String, Object?>{'shine': 1}),
        throwsArgumentError,
      );
      expect(
        () => swap.setMaterial('paint', <String, Object?>{
          'baseColor': <double>[1, 0, 0],
        }),
        throwsArgumentError,
      );
    });

    test('keeps what was dragged when the model is swapped under it', () async {
      var file = Uint8List.fromList(<int>[1]);
      final model = swap.registerModel(
        'assets_src/ship.glb',
        await _model(device, file),
        read: () async => file,
        build: (Uint8List bytes) => _model(device, bytes),
        loadedFrom: file,
      );
      final scene = Scene();
      final ship = model.instantiate(scene);
      swap
        ..registerScene(scene)
        ..setMaterial('paint', <String, Object?>{'roughness': 0.1});

      file = Uint8List.fromList(<int>[3]);
      await swap.swap();

      final material = ship.meshes.single.material;
      expect(material.baseColor.z, 1.0, reason: 'the file\'s new colour');
      expect(material.roughness, 0.1, reason: 'and the drag, kept');

      swap.clearMaterial('paint');
      file = Uint8List.fromList(<int>[2]);
      await swap.swap();
      expect(ship.meshes.single.material.roughness, isNot(0.1));
    });
  });

  group('a texture', () {
    late CpuDevice device;
    late HotSwap swap;

    /// A "file" whose first byte is the side of the square it decodes to,
    /// and zero a file that does not decode.
    TextureHandle? decode(Uint8List bytes) => bytes.first == 0
        ? null
        : device.createTextureFromPixels(
            width: bytes.first,
            height: bytes.first,
            format: TextureFormat.r8g8b8a8UNormInt,
            pixels: ByteData(bytes.first * bytes.first * 4),
          );

    setUp(() {
      device = CpuDevice(
        width: 16,
        height: 9,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      swap = HotSwap(enabled: true);
    });

    ({
      SwappableTexture texture,
      engine.Material wall,
      Scene scene,
      void Function(int) write,
    })
    stage() {
      var file = Uint8List.fromList(<int>[4]);
      final first = decode(file)!;
      final texture = swap.registerTexture(
        'assets/wall.png',
        first,
        read: () async => file,
        build: (Uint8List bytes) async => decode(bytes),
        loadedFrom: file,
      );
      final wall = engine.Material(name: 'wall')
        ..albedo = first
        ..normal = first;
      final scene = Scene()
        ..environment = first
        ..add(
          MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3.all(1.0)).build(),
            ),
            wall,
          ),
        );
      swap.registerScene(scene);
      return (
        texture: texture,
        wall: wall,
        scene: scene,
        write: (int side) => file = Uint8List.fromList(<int>[side]),
      );
    }

    test('of a new size takes the old one\'s place in every slot', () async {
      // Mutation: skip `_replaceTexture` and the material keeps sampling the
      // four-texel texture the file no longer is.
      final it = stage();
      final heard = <TextureHandle>[];
      it.texture.changes.addListener(() => heard.add(it.texture.texture));

      it.write(8);
      final report = await swap.swap();

      expect(report.textures, <String>['assets/wall.png']);
      final now = it.texture.texture;
      expect(now.width, 8);
      expect(it.wall.albedo, same(now));
      expect(it.wall.normal, same(now), reason: 'every slot that held it');
      expect(it.scene.environment, same(now));
      expect(heard, <TextureHandle>[now]);
    });

    test('an unchanged file is not uploaded again', () async {
      final it = stage();
      final before = it.texture.texture;

      final report = await swap.swap();

      expect(report.textures, isEmpty);
      expect(it.wall.albedo, same(before));
    });

    test('a file that does not decode keeps the texture that did', () async {
      final it = stage();
      final before = it.texture.texture;

      it.write(0);
      final report = await swap.swap();

      expect(report.refused.single, contains('assets/wall.png'));
      expect(it.texture.texture, same(before));
      expect(it.wall.albedo, same(before));
    });

    test(
      'the old texture goes back through a renderer, after its frames',
      () async {
        // Mutation: release through no renderer and nothing is ever given
        // back; release at once and it is gone before the frames that still
        // sample it are.
        Future<List<int>> releasesPerFrame({required bool change}) async {
          final it = stage();
          final recording = RecordingDevice(device);
          final renderer = Renderer.create(device: recording);
          final camera = CameraNode()..setPosition(0.0, 0.0, 4.0);
          it.scene.add(camera);
          final view = RenderView(camera: camera);
          swap.registerRenderer(renderer);
          void frame() => renderer.render(
            width: 16,
            height: 9,
            scene: it.scene,
            views: <RenderView>[view],
          );
          for (var i = 0; i < 4; i++) {
            frame();
          }
          if (change) it.write(8);
          await swap.swap();
          final counts = <int>[];
          for (var i = 0; i < 4; i++) {
            final before = recording.events.length;
            frame();
            counts.add(
              recording.events
                  .skip(before)
                  .whereType<TraceReleaseTexture>()
                  .length,
            );
          }
          renderer.dispose();
          return counts;
        }

        final unchanged = await releasesPerFrame(change: false);
        swap = HotSwap(enabled: true);
        final swapped = await releasesPerFrame(change: true);

        expect(unchanged.every((int n) => n == 0), isTrue);
        expect(swapped.fold<int>(0, (int a, int b) => a + b), 1);
        expect(
          swapped.first,
          0,
          reason: 'not while a frame may still sample it',
        );
      },
    );
  });
}
