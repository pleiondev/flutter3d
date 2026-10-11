/// The render checks: a plugin's points in the frame, drawn on a device.
library;

import 'dart:typed_data';

import 'package:flutter3d_conformance/plugins.dart' show PluginCheckOutcome;
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_sim/flutter3d_sim.dart' show EngineLoop, InputState;
import 'package:vector_math/vector_math.dart';

/// What a plugin adds to the frame, named for the render checks: each one
/// set is drawn and checked, each one left null is not asked.
///
/// The plugin installs its points itself, through the registries a
/// renderer hands it; this says which of them a check should find and what
/// it should look for. A data class, and it grows: a point added to the
/// frame later arrives as a member here with a null default.
final class PluginRenderPoints {
  const PluginRenderPoints({
    this.nodes = const <String>[],
    this.litModel,
    this.lightType,
    this.decal,
    this.velocityReader,
    this.shadows,
  });

  /// The nodes the plugin places in the frame graph, by name, which a frame
  /// runs while it is on and does not once it is off.
  final List<String> nodes;

  /// A lit model the plugin registers, drawn on a box with every member of
  /// its slot table's blocks and every texture of its own bound.
  final LightingModel? litModel;

  /// A light type the plugin hooks, lighting a box on its own.
  final LightType? lightType;

  /// A decal stage of the plugin's own, painted on the floor.
  final LightingModel? decal;

  /// The name of a node that reads the velocity, which a frame with neither
  /// of the engine's readers on draws for it.
  final String? velocityReader;

  /// A shadow technique with producers of its own, put in the frame's
  /// shadow settings.
  final ShadowTechnique? shadows;
}

/// The render checks' names, in the order they are reported.
const List<String> pluginRenderCheckNames = <String>[
  'render.nodes',
  'render.lit model',
  'render.light type',
  'render.decal',
  'render.velocity',
  'render.shadows',
];

const int _size = 32;

/// One renderer with the plugin installed into it on a fresh device.
final class _Stage {
  _Stage(this.device, Flutter3dPlugin plugin)
    : renderer = Renderer.create(device: device) {
    loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[renderer.renderSteps],
      plugins: <Flutter3dPlugin>[plugin],
    );
  }

  final GraphicsDevice device;
  final Renderer renderer;
  late final EngineLoop loop;

  late final DeviceMesh _box = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3.all(1.2)).build(),
  );
  late final DeviceMesh _floor = DeviceMesh.upload(
    device,
    CuboidShape(size: Vector3(8.0, 0.2, 8.0)).build(),
  );

  late final CameraNode camera = CameraNode()
    ..setPosition(0.0, 4.0, 3.0)
    ..lookAt(Vector3.zero());

  /// A floor, a box drawn with [material] and the camera; a sun unless
  /// [sun] is false.
  Scene scene({RenderMaterial? material, bool sun = true}) {
    final scene = Scene()
      ..add(
        MeshNode(
          _floor,
          RenderMaterial(
            name: 'floor',
            lighting: LightingModel.lambert,
            baseColor: LinearColor.fromSrgb(0.5, 0.5, 0.5, 1.0),
          ),
        )..setPosition(0.0, -0.1, 0.0),
      )
      ..add(
        MeshNode(_box, material ?? RenderMaterial(name: 'box'))
          ..setPosition(0.0, 0.6, 0.0),
      )
      ..add(camera);
    if (sun) {
      scene.add(
        LightNode(name: 'sun', intensity: 0.5 * LightNode.defaultIntensity)
          ..lookAt(Vector3(-0.4, -1.0, -0.3)),
      );
    }
    return scene;
  }

  FrameResult render(Scene scene, {RenderSettings? settings}) =>
      renderer.render(
        width: _size,
        height: _size,
        scene: scene,
        settings: settings ?? _settings,
        views: <RenderView>[RenderView(camera: camera)],
      );

  Future<Uint8List> picture(Scene scene, {RenderSettings? settings}) async {
    final frame = render(scene, settings: settings);
    final bytes = await device.readback(frame.frame);
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  }

  /// A texture of one texel of [value] in every channel.
  TextureHandle texel(int value) => device.createTextureFromPixels(
    width: 1,
    height: 1,
    format: TextureFormat.r8g8b8a8UNormInt,
    pixels: Uint8List.fromList(<int>[
      value,
      value,
      value,
      255,
    ]).buffer.asByteData(),
  );
}

/// Neither of the engine's readers of the velocity on, decals on.
final RenderSettings _settings =
    const RenderSettings(decals: DecalSettings(enabled: true)).copyWith(
      antiAlias: const RenderSettings().antiAlias.copyWith(
        temporal: const RenderSettings().antiAlias.temporal.copyWith(
          enabled: false,
        ),
      ),
      motionBlur: const RenderSettings().motionBlur.copyWith(enabled: false),
    );

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _describe(Object error) => switch (error) {
  StateError(:final message) => message,
  ArgumentError(:final message) => '$message',
  _ => '$error',
};

/// Runs every render check of [points] on devices [device] makes, one fresh
/// device a check, and returns what each found under [backend]'s name.
///
/// **Pictures where the device draws them.** A device that draws the same
/// picture with a box as without one (a recording fake) is held to the
/// structure alone: the parts of a check that compare pictures are
/// declined, saying so, and a declined check is never green.
Future<List<PluginCheckOutcome>> checkPluginRender(
  Flutter3dPlugin Function() create, {
  required GraphicsDevice Function() device,
  required PluginRenderPoints points,
  required String backend,
}) async {
  final probe = _Stage(device(), create());
  final draws = !_same(
    await probe.picture(probe.scene()),
    await probe.picture(Scene()..add(probe.camera)),
  );

  PluginCheckOutcome outcome(
    String check,
    bool passed,
    String says, {
    bool declined = false,
  }) => PluginCheckOutcome(
    check: check,
    backend: backend,
    passed: passed && !declined,
    declined: declined,
    says: says,
  );

  Future<PluginCheckOutcome> guarded(
    String check,
    Future<PluginCheckOutcome> Function(_Stage stage) run,
  ) async {
    try {
      return await run(_Stage(device(), create()));
    } on Object catch (error) {
      return outcome(check, false, 'drawing it threw: ${_describe(error)}');
    }
  }

  final pictures = draws
      ? null
      : 'this device draws the same picture with a box as without, so no '
            'picture is compared';

  return <PluginCheckOutcome>[
    if (points.nodes.isNotEmpty)
      await guarded('render.nodes', (stage) async {
        final ran = <String>{
          for (final pass in stage.render(stage.scene()).passes) pass.name,
        };
        final missing = points.nodes.where((n) => !ran.contains(n)).toList();
        if (missing.isNotEmpty) {
          return outcome(
            'render.nodes',
            false,
            'the frame did not run ${missing.join(', ')}',
          );
        }
        final id = stage.loop.plugins.order.single;
        stage.loop.plugins.disable(id);
        stage.loop.runSteps(1);
        final after = <String>{
          for (final pass in stage.render(stage.scene()).passes) pass.name,
        };
        final left = points.nodes.where(after.contains).toList();
        return outcome(
          'render.nodes',
          left.isEmpty,
          left.isEmpty
              ? '${points.nodes.length} nodes ran, and none once switched off'
              : '${left.join(', ')} still ran once the plugin was off',
        );
      }),
    if (points.litModel case final model?)
      await guarded('render.lit model', (stage) async {
        if (stage.renderer.lightingModels.named(model.shaderName) == null) {
          return outcome(
            'render.lit model',
            false,
            '"${model.shaderName}" is not registered with the renderer',
          );
        }
        if (pictures != null) {
          stage.render(stage.scene(material: RenderMaterial(lighting: model)));
          return outcome('render.lit model', false, pictures, declined: true);
        }
        // Every member of every block at a half, every texture of its own
        // white; then each block's first member and each texture moved on
        // its own, which has to move the picture.
        Map<String, Float32List> filled(String? member, double value) =>
            <String, Float32List>{
              for (final block in model.slots.blocks)
                for (final m in block.members)
                  m.name: Float32List(m.type.components)
                    ..fillRange(
                      0,
                      m.type.components,
                      m.name == member ? value : 0.5,
                    ),
            };
        final white = stage.texel(255);
        final black = stage.texel(0);
        Map<String, TextureHandle> textures(String? dark) =>
            <String, TextureHandle>{
              for (final t in model.slots.textures)
                t.binding: t.binding == dark ? black : white,
            };
        Future<Uint8List> draw(
          Map<String, Float32List> parameters,
          Map<String, TextureHandle> extra,
        ) => stage.picture(
          stage.scene(
            material: RenderMaterial(
              lighting: model,
              parameters: parameters,
              extraTextures: extra,
            ),
          ),
        );
        final base = await draw(filled(null, 0), textures(null));
        if (_same(base, await stage.picture(stage.scene()))) {
          return outcome(
            'render.lit model',
            false,
            'a box drawn through "${model.shaderName}" is the picture of one '
                'drawn through the engine\'s: the stage did not draw',
          );
        }
        final unreached = <String>[
          for (final block in model.slots.blocks)
            if (block.members.isNotEmpty)
              if (_same(
                await draw(filled(block.members.first.name, 0), textures(null)),
                await draw(filled(block.members.first.name, 1), textures(null)),
              ))
                'block ${block.name}',
          for (final t in model.slots.textures)
            if (_same(base, await draw(filled(null, 0), textures(t.binding))))
              'texture ${t.binding}',
        ];
        return outcome(
          'render.lit model',
          unreached.isEmpty,
          unreached.isEmpty
              ? '"${model.shaderName}" drew, with ${model.slots.blocks.length} '
                    'blocks and ${model.slots.textures.length} textures of '
                    'its own reaching it'
              : 'nothing changed the picture through ${unreached.join(', ')}',
        );
      }),
    if (points.lightType case final type?)
      await guarded('render.light type', (stage) async {
        final hook = stage.renderer.lightTypes.hookOf(type);
        final code = stage.renderer.lightTypes.codeOf(type);
        if (hook == null || code < LightTypes.firstPluginCode) {
          return outcome(
            'render.light type',
            false,
            '$type has no hook or no code of a plugin\'s own (code $code)',
          );
        }
        final material = switch (points.litModel) {
          null => null,
          final model => RenderMaterial(lighting: model),
        };
        final lit = stage.scene(material: material, sun: false)
          ..add(LightNode(type: type)..setPosition(1.0, 2.0, 0.5));
        final drawn = await stage.picture(lit);
        if (pictures != null) {
          return outcome('render.light type', false, pictures, declined: true);
        }
        final dark = await stage.picture(
          stage.scene(material: material, sun: false),
        );
        return outcome(
          'render.light type',
          !_same(drawn, dark),
          'code $code; a box lit by it alone '
              '${_same(drawn, dark) ? 'is the picture of one in the dark' : 'is lit'}',
        );
      }),
    if (points.decal case final decal?)
      await guarded('render.decal', (stage) async {
        final painted = stage.scene()
          ..add(
            DecalNode(
                lighting: decal,
                color: LinearColor.fromSrgb(0.9, 0.1, 0.1, 1.0),
              )
              ..setPosition(1.5, 0.0, 1.0)
              ..setScale(2.0, 2.0, 2.0),
          );
        final result = stage.render(painted);
        if (!result.passes.any((p) => p.name == FramePassNames.decals)) {
          return outcome('render.decal', false, 'the decal pass did not run');
        }
        if (pictures != null) {
          return outcome('render.decal', false, pictures, declined: true);
        }
        final same = _same(
          await stage.picture(painted),
          await stage.picture(stage.scene()),
        );
        return outcome(
          'render.decal',
          !same,
          same
              ? '"${decal.shaderName}" painted nothing on the floor'
              : '"${decal.shaderName}" painted the floor',
        );
      }),
    if (points.velocityReader case final reader?)
      await guarded('render.velocity', (stage) async {
        final order = <String>[
          for (final pass in stage.render(stage.scene()).passes) pass.name,
        ];
        final velocity = order.indexOf(FramePassNames.cameraVelocity);
        final at = order.indexOf(reader);
        final passed = velocity >= 0 && at > velocity;
        return outcome(
          'render.velocity',
          passed,
          passed
              ? '"$reader" ran after the camera velocity, with no engine '
                    'reader on'
              : 'the order was ${order.join(', ')}',
        );
      }),
    if (points.shadows case final technique?)
      await guarded('render.shadows', (stage) async {
        final recording = _RecordingTechnique(technique);
        final scene = stage.scene()
          ..add(
            LightNode(
              type: LightType.point,
              intensity: 10.0 * LightNode.defaultIntensity,
              range: 6.0,
              castsShadow: true,
            )..setPosition(-1.0, 2.0, 0.5),
          );
        stage.render(
          scene,
          settings: _settings.copyWith(
            shadows: ShadowSettings(
              cubeResolution: ShadowSettings.minCubeTile,
              filter: ShadowFilter.custom(
                technique.name,
                base: ShadowFilter.pcf,
                technique: recording,
              ),
            ),
          ),
        );
        final says = <String>[
          if (recording.sun != null)
            recording.sunRan
                ? 'its directional producer ran'
                : 'its directional producer was handed and never ran',
          if (recording.cube != null)
            recording.cubeRan
                ? 'its cube atlas producer ran'
                : 'its cube atlas producer was handed and never ran',
        ];
        final passed =
            says.isNotEmpty &&
            (recording.sun == null || recording.sunRan) &&
            (recording.cube == null || recording.cubeRan);
        return outcome(
          'render.shadows',
          passed,
          says.isEmpty
              ? 'it produced nothing the frame asked of it'
              : says.join('; '),
        );
      }),
  ];
}

/// [inner], with what its producers made watched.
final class _RecordingTechnique extends ShadowTechnique {
  _RecordingTechnique(this.inner);

  final ShadowTechnique inner;
  _Watched? sun;
  _Watched? cube;
  bool get sunRan => sun?.ran ?? false;
  bool get cubeRan => cube?.ran ?? false;

  @override
  String get name => inner.name;

  @override
  ShadowKernel kernelFor(ShadowSettings settings) => inner.kernelFor(settings);

  @override
  ShadowPrefilter? prefilterFor(ShadowSettings settings) =>
      inner.prefilterFor(settings);

  @override
  int cascadesFor(ShadowSettings settings) => inner.cascadesFor(settings);

  @override
  RenderNode? shadowMapProducer(ShadowProducerContext context) =>
      switch (inner.shadowMapProducer(context)) {
        null => null,
        final node => sun = _Watched(node),
      };

  @override
  RenderNode? cubeAtlasProducer(ShadowProducerContext context) =>
      switch (inner.cubeAtlasProducer(context)) {
        null => null,
        final node => cube = _Watched(node),
      };
}

/// A producer's node, run as itself and remembered as run.
final class _Watched extends RenderNode {
  _Watched(this.inner);

  final RenderNode inner;
  bool ran = false;

  @override
  String get name => inner.name;

  @override
  List<ResourceId> get reads => inner.reads;

  @override
  List<ResourceId> get writes => inner.writes;

  @override
  List<ResourceId> get keeps => inner.keeps;

  @override
  void execute(RenderFrame frame) {
    ran = true;
    inner.execute(frame);
  }
}
