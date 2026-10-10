/// The sample plugin installed into a renderer, a frame drawn with it on a
/// device with no GPU, and everything taken back when it is switched off;
/// its data half read and installed beside it; and the plugin conformance
/// suite over the Dart half.
///
///     dart test test/acme_sample_test.dart
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter3d_conformance/plugins.dart';
import 'package:flutter3d_core/data_plugins.dart';
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/testing.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_plugin_runtime/flutter3d_plugin_runtime.dart';
import 'package:flutter3d_plugin_runtime_example/acme_sample.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;
import 'package:test/test.dart';
import 'package:vector_math/vector_math.dart' show Vector3;

({Renderer renderer, FakeBackend device, ModelDecoders decoders}) _engine() {
  final device = FakeBackend();
  return (
    renderer: Renderer.create(device: device),
    device: device,
    decoders: ModelDecoders(),
  );
}

EngineLoop _loop(
  ({Renderer renderer, FakeBackend device, ModelDecoders decoders}) engine,
  List<Flutter3dPlugin> plugins,
) => EngineLoop(
  input: InputState(),
  backend: 'cpu',
  registries: <PluginRegistry>[engine.renderer.renderSteps, engine.decoders],
  plugins: plugins,
);

/// Neither of the engine's readers of the velocity on, and the decals on.
RenderSettings get _settings =>
    const RenderSettings(decals: DecalSettings(enabled: true)).copyWith(
      antiAlias: const RenderSettings().antiAlias.copyWith(
        temporal: const RenderSettings().antiAlias.temporal.copyWith(
          enabled: false,
        ),
      ),
      motionBlur: const RenderSettings().motionBlur.copyWith(enabled: false),
    );

void main() {
  test('every extension point is reached, and taken back', () {
    final engine = _engine();
    final renderer = engine.renderer;
    final loop = _loop(engine, <Flutter3dPlugin>[AcmeSamplePlugin()]);

    expect(renderer.lightTypes.hookOf(tubeLight), isA<TubeHook>());
    expect(
      renderer.lightTypes.codeOf(tubeLight),
      greaterThanOrEqualTo(LightTypes.firstPluginCode),
    );
    expect(renderer.lightingModels.named('acme_sample_Hair'), same(hairModel));
    expect(hairModel.slots.blocks.map((b) => b.name), <String>[
      'MaterialParams',
      'Strands',
    ]);
    expect(hairModel.slots.textures.single.binding, 'material_fur');
    expect(renderer.lightingModels.named('acme_sample_Decal'), decalStage);
    expect(renderer.hooks.drawListHooks.single, isA<HideHook>());
    expect(renderer.hooks.lodPolicy, isA<CoarsePolicy>());
    expect(engine.decoders.textureCodecs.codecs.single.name, 'acme_sample.pix');
    expect(renderer.sceneBindings.resolve('acme_sample.heat'), isNotNull);
    expect(renderer.renderSteps.named('acme_sample.smear'), smearStep);
    expect(
      renderer.renderSteps.nodesAt(
        renderer.renderSteps.anchorNamed('acme_sample.after glow')!,
      ),
      <String>['acme_sample.glow streak'],
    );
    expect(
      const SoftSun().shadowMapProducer(
        const ShadowProducerContext(settings: ShadowSettings()),
      ),
      isA<SunMapNode>(),
    );

    loop.plugins.disable('acme_sample.all');
    loop.runSteps(1);
    expect(renderer.lightTypes.hooks, isEmpty);
    expect(renderer.lightingModels.registered, isEmpty);
    expect(renderer.hooks.drawListHooks, isEmpty);
    expect(renderer.hooks.lodPolicy, isNull);
    expect(engine.decoders.textureCodecs.codecs, isEmpty);
    expect(renderer.sceneBindings.bindings, isEmpty);
    expect(renderer.renderSteps.added, isEmpty);
    expect(renderer.renderSteps.anchorNamed('acme_sample.after glow'), isNull);
  });

  test('a frame is drawn with it: the velocity, the streak and the decal', () {
    final engine = _engine();
    final smear = SmearNode();
    _loop(engine, <Flutter3dPlugin>[AcmeSamplePlugin(smear: smear)]);
    final device = engine.device;
    final camera = CameraNode()..setPosition(0.0, 3.0, 3.0);
    camera.lookAt(Vector3.zero());
    final cube = DeviceMesh.upload(device, CuboidShape().build());
    final scene = Scene()
      ..add(MeshNode(cube, RenderMaterial(lighting: hairModel)))
      ..add(MeshNode(cube, RenderMaterial(), name: 'acme_sample.hidden box'))
      ..add(LightNode(type: tubeLight)..setPosition(1.0, 2.0, 0.0))
      ..add(DecalNode(lighting: decalStage)..setScale(2.0, 2.0, 2.0))
      ..add(camera);
    final result = engine.renderer.render(
      width: 32,
      height: 32,
      scene: scene,
      settings: _settings,
      views: <RenderView>[RenderView(camera: camera)],
    );
    final ran = <String>{for (final pass in result.passes) pass.name};
    expect(
      ran,
      containsAll(<String>[
        'camera velocity',
        'acme_sample.smear',
        'acme_sample.glow streak',
      ]),
    );
    expect(smear.frames.single.views, hasLength(1));
    expect(device.linkedPipelines, contains(endsWith('+acme_sample_Hair')));
    expect(device.linkedPipelines, contains(endsWith('+acme_sample_Decal')));
  });

  test('an image of its own format is read', () async {
    final engine = _engine();
    _loop(engine, <Flutter3dPlugin>[AcmeSamplePlugin()]);
    final texture = await uploadEncodedImage(
      engine.device,
      Uint8List.fromList(<int>[...'PIX!'.codeUnits, 4, 2]),
      decodeImage: (_) async => null,
      codecs: engine.decoders.textureCodecs,
    );
    expect((texture!.width, texture.height), (4, 2));
  });

  test('the data half installs its binding and its pipeline', () async {
    final engine = _engine();
    final data =
        await DataPluginLoader(sections: DataSections(renderDataSections)).load(
          File('plugin/acme_sample.f3dplugin').readAsStringSync(),
          MemoryPluginSource(const <String, Uint8List>{}),
        );
    _loop(engine, <Flutter3dPlugin>[AcmeSamplePlugin(), data]);
    final renderer = engine.renderer;
    expect(renderer.sceneBindings.bindingOf('acme_sample.glow'), isNotNull);
    final anchor = renderer.renderSteps.anchorNamed('acme_sample.after haze')!;
    expect(renderer.renderSteps.nodesAt(anchor), <String>['acme_sample.haze']);
  });

  group('plugin conformance', () {
    runPluginConformance(
      AcmeSamplePlugin.new,
      harness: PluginHarness(
        registries: (backend) => <PluginRegistry>[
          Renderer.create(device: FakeBackend()).renderSteps,
          ModelDecoders(),
        ],
      ),
    );
  });
}
