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

  test('a material written in the language is drawn, edited and drawn again '
      'from its compiled bundle', () async {
    // `P8`: what `loadMaterial` adds over `registerLibrary` — the bundle read
    // from where the hook wrote it, the lighting model read off the source,
    // and on the software backend the edited source compiled again under the
    // stage a draw already holds.
    //
    // Mutation: register the library without `loadedFrom`, and the first
    // swap takes the unchanged bundle as a change; drop the registration,
    // and the edit never reaches the frame.
    ByteData bundle(String colour) => ShaderBundle(
      name: 'paint',
      sdk: '',
      stages: const <ShaderBundleStage>[
        ShaderBundleStage('Paint', fragment: true),
      ],
      sections: <String, ByteData>{
        ShaderBundle.materialSection: encodeMaterialSection(<String, String>{
          'Paint': 'material Paint { fragment { return vec4($colour, 1.0); } }',
        }),
      },
    ).encode();
    var current = bundle('vec3(1.0, 0.0, 0.0)');
    String? asked;

    const size = 16;
    final device = CpuDevice(
      width: size,
      height: size,
      shaders: CpuShaderLibrary(builtinCpuShaders()),
      materialCompiler: materialLanguageCompiler,
    );
    final swap = HotSwap(enabled: true);
    final loaded = await swap.loadMaterial(
      'assets_src/fx/paint.f3dmat',
      device: device,
      read: () async {
        asked = 'read';
        return current;
      },
    );
    expect(asked, 'read');
    expect(
      generatedMaterialPathFor('assets_src/fx/paint.f3dmat'),
      'flutter3d_generated/fx/paint.f3dshaders',
    );

    final renderer = Renderer.create(device: device, materials: loaded.library);
    swap.registerRenderer(renderer);
    final camera = CameraNode()..setPosition(0.0, 0.0, 3.0);
    final scene = Scene()
      ..add(camera)
      ..add(
        MeshNode(
          DeviceMesh.upload(device, CuboidShape().build()),
          engine.Material(lighting: loaded.materials['Paint']),
        ),
      );
    Future<List<int>> centre() async {
      final frame = renderer.render(
        width: size,
        height: size,
        scene: scene,
        views: <RenderView>[RenderView(camera: camera)],
        settings: const RenderSettings(
          bloom: BloomSettings(enabled: false),
          tonemap: false,
        ),
      );
      final pixels = (await device.readPixels(frame.frame))!;
      final at = ((size ~/ 2) * size + size ~/ 2) * 4;
      return <int>[pixels.getUint8(at), pixels.getUint8(at + 2)];
    }

    expect(await centre(), <int>[255, 0]);
    expect((await swap.swap()).refreshed, isEmpty);

    current = bundle('vec3(0.0, 0.0, 1.0)');
    expect((await swap.swap()).refreshed, <String>['paint']);
    expect(await centre(), <int>[0, 255]);
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

    /// A scene with one quad in a material whose shader reads `wind` and
    /// `tint`, as a `.fmat` with parameters is bound.
    ({Scene scene, engine.Material material}) waving() {
      final material = engine.Material(
        name: 'grass',
        parameters: <String, Float32List>{
          'wind': Float32List.fromList(<double>[0.3]),
          'tint': Float32List.fromList(<double>[0.1, 0.4, 0.5]),
        },
      );
      final scene = Scene()
        ..add(
          MeshNode(
            DeviceMesh.upload(
              device,
              CuboidShape(size: Vector3.all(1.0)).build(),
            ),
            material,
          ),
        );
      swap.registerScene(scene);
      return (scene: scene, material: material);
    }

    test('sets a parameter of its shader in the list the frame binds', () {
      // `HR4`'s last half: a slider over a `.fmat` parameter reaches the
      // game. Into the list the material already has, so the renderer, which
      // binds `parameters` every frame, draws it next frame.
      //
      // Mutation: build a new list instead of writing into the old one. The
      // values match but `held` is not the list the material was loaded with,
      // and the second expectation fails — as a cached reference to it would.
      final (scene: _, :material) = waving();
      final held = material.parameters['wind']!;

      final touched = swap.setMaterial('grass', <String, Object?>{
        'parameters/wind': 1.5,
        'parameters/tint': <double>[0.2, 0.2, 0.9],
      });

      expect(touched, 1);
      expect(material.parameters['wind'], <double>[1.5]);
      expect(material.parameters['wind'], same(held));
      expect(material.parameters['tint']![2], closeTo(0.9, 1e-6));
    });

    test('refuses a parameter the material was not loaded with, or one of '
        'another length, and keeps nothing of the call', () {
      // A member the compiled block does not have throws in the encoder on
      // every frame of that material, so a typo in a panel must stop here.
      //
      // Mutation: drop `_checkParameter`. `gust` is stored as an override, the
      // first expectation fails, and `tint` takes two numbers into three.
      final (scene: _, :material) = waving();

      expect(
        () => swap.setMaterial('grass', <String, Object?>{
          'parameters/gust': 1.0,
          'roughness': 0.2,
        }),
        throwsA(
          isA<ArgumentError>().having(
            (ArgumentError e) => e.message,
            'message',
            contains('it has wind, tint'),
          ),
        ),
      );
      expect(
        () => swap.setMaterial('grass', <String, Object?>{
          'parameters/tint': <double>[1, 0],
        }),
        throwsArgumentError,
      );
      expect(
        () => swap.setMaterial('grass', <String, Object?>{
          'parameters/wind': <Object?>['strong'],
        }),
        throwsArgumentError,
      );
      expect(material.roughness, isNot(0.2), reason: 'nothing of it taken');
      expect(material.parameters['tint']![0], closeTo(0.1, 1e-6));

      // And nothing kept to come back on a later call for another field.
      swap.setMaterial('grass', <String, Object?>{'metallic': 0.5});
      expect(material.roughness, isNot(0.2));
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

  group('an environment', () {
    late CpuDevice device;
    late HotSwap swap;
    late int builds;

    /// A "panorama" whose first byte is the side of the cube it builds and
    /// whose second is its level count; a zero side does not build. A flat
    /// texture stands in for the cube: what a swap does with it is the same.
    BuiltEnvironment? build(Uint8List bytes) {
      builds++;
      if (bytes.first == 0) return null;
      final texture = device.createTextureFromPixels(
        width: bytes.first,
        height: bytes.first,
        format: TextureFormat.r8g8b8a8UNormInt,
        pixels: ByteData(bytes.first * bytes.first * 4),
      );
      return texture == null ? null : (texture: texture, levels: bytes[1]);
    }

    setUp(() {
      device = CpuDevice(
        width: 16,
        height: 9,
        shaders: CpuShaderLibrary(builtinCpuShaders()),
      );
      swap = HotSwap(enabled: true);
      builds = 0;
    });

    ({
      SwappableEnvironment environment,
      Scene lit,
      Scene other,
      void Function(int side, int levels) write,
    })
    stage() {
      var file = Uint8List.fromList(<int>[4, 2]);
      final environment = swap.registerEnvironment(
        'assets/sky.hdr',
        build(file)!,
        read: () async => file,
        build: (Uint8List bytes) async => build(bytes),
        loadedFrom: file,
      );
      final lit = Scene();
      environment.applyTo(lit);
      final elsewhere = build(Uint8List.fromList(<int>[2, 1]))!;
      final other = Scene()
        ..environment = elsewhere.texture
        ..environmentLevels = elsewhere.levels;
      swap
        ..registerScene(lit)
        ..registerScene(other);
      return (
        environment: environment,
        lit: lit,
        other: other,
        write: (int side, int levels) =>
            file = Uint8List.fromList(<int>[side, levels]),
      );
    }

    test('is prefiltered again when its file changes, and the scenes it lit '
        'take the new cube with its level count', () async {
      // Mutation: set only `Scene.environment` and the scene reads the new
      // chain's roughness against the old count, so every surface takes the
      // wrong lobe.
      final it = stage();
      final otherCube = it.other.environment;
      final heard = <BuiltEnvironment>[];
      it.environment.changes.addListener(() => heard.add(it.environment.built));

      it.write(8, 3);
      final report = await swap.swap();

      expect(report.environments, <String>['assets/sky.hdr']);
      final now = it.environment.built;
      expect(now.texture.width, 8);
      expect(it.lit.environment, same(now.texture));
      expect(it.lit.environmentLevels, 3);
      expect(
        it.other.environment,
        same(otherCube),
        reason: 'a scene lit by another environment keeps it',
      );
      expect(it.other.environmentLevels, 1);
      expect(heard, hasLength(1));
    });

    test('an unchanged file is not prefiltered again', () async {
      // Mutation: drop the fingerprint and every hot reload pays for a
      // convolution of a sky nobody touched.
      final it = stage();
      final before = it.lit.environment;
      final built = builds;

      final report = await swap.swap();

      expect(report.environments, isEmpty);
      expect(builds, built);
      expect(it.lit.environment, same(before));
    });

    test('a file that does not build keeps the cube that did', () async {
      final it = stage();
      final before = it.environment.built;

      it.write(0, 2);
      final report = await swap.swap();

      expect(report.refused.single, contains('assets/sky.hdr'));
      expect(it.environment.built, same(before));
      expect(it.lit.environment, same(before.texture));
      expect(it.lit.environmentLevels, 2);
    });

    test('bytes put over the VM service take the file\'s place', () async {
      final it = stage();

      final refused = await swap.putEnvironment(
        'assets/sky.hdr',
        Uint8List.fromList(<int>[16, 4]),
      );

      expect(refused, isNull);
      expect(swap.hasEnvironment('assets/sky.hdr'), isTrue);
      expect(it.lit.environment!.width, 16);
      expect(it.lit.environmentLevels, 4);
    });

    test(
      'the old cube goes back through a renderer, after its frames',
      () async {
        // Mutation: never release it and every saved sky leaks a cube.
        final it = stage();
        final recording = RecordingDevice(device);
        final renderer = Renderer.create(device: recording);
        final camera = CameraNode()..setPosition(0.0, 0.0, 4.0);
        it.lit.add(camera);
        final view = RenderView(camera: camera);
        swap.registerRenderer(renderer);
        void frame() => renderer.render(
          width: 16,
          height: 9,
          scene: it.lit,
          views: <RenderView>[view],
        );
        for (var i = 0; i < 4; i++) {
          frame();
        }
        it.write(8, 2);
        await swap.swap();
        final before = recording.events.length;
        for (var i = 0; i < 4; i++) {
          frame();
        }
        final released = recording.events
            .skip(before)
            .whereType<TraceReleaseTexture>()
            .length;
        renderer.dispose();

        expect(released, 1);
      },
    );
  });
}
