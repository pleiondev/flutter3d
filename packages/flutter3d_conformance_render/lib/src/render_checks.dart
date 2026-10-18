/// The render checks: a plugin's points in the frame, drawn on a device.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter3d_conformance/plugins.dart' show PluginCheckOutcome;
import 'package:flutter3d_core/data_plugins.dart' show RuntimeShaders;
import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show LightType, MaterialParameters;
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
  /// Points named for the checks, every one unset by default and so not asked.
  const PluginRenderPoints({
    this.nodes = const <String>[],
    this.litModel,
    this.lightType,
    this.decal,
    this.velocityReader,
    this.shadows,
    this.drawList,
    this.lod,
    this.skinning,
    this.computeStep,
    this.codec,
  });

  /// The nodes the plugin places in the frame graph, by name, which a frame
  /// runs while it is on and does not once it is off. Every node the plugin
  /// places is named here: one it places and this does not name fails
  /// `render.nodes`.
  final List<String> nodes;

  /// A draw-list hook the plugin adds, by its type: found among the
  /// renderer's while the plugin is on, asked of a frame's meshes, and gone
  /// once it is off.
  final DrawListHook? drawList;

  /// A level-of-detail policy the plugin adds, by its type: found among the
  /// renderer's while the plugin is on, asked by a frame with a group in it,
  /// and gone once it is off.
  final LodPolicy? lod;

  /// A skinning hook the plugin places, by its type: listed among the
  /// renderer's while the plugin is on and gone once it is off.
  final SkinningHook? skinning;

  /// The name of a compute step's node the plugin places, which a frame
  /// runs where the device computes and skips with the typed refusal
  /// (`PassSkip.unsupported`) where it does not — never fails or leaves
  /// pending.
  final String? computeStep;

  /// An image format the plugin brings, with a sample it decodes.
  final PluginCodecPoint? codec;

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

/// An image format a plugin brings, for `render.codec`: its codec's name
/// and a file in its format, with the size it decodes to where the check
/// should hold it to one.
final class PluginCodecPoint {
  /// The codec [name] with a [sample] file, held to [width] by [height] where
  /// those are given.
  const PluginCodecPoint({
    required this.name,
    required this.sample,
    this.width,
    this.height,
  });

  /// The codec's name, `acme.pix`.
  final String name;

  /// A file the codec reads.
  final Uint8List sample;

  /// The width and height, in texels, the sample decodes to; null for
  /// any.
  final int? width;

  /// The height in texels the sample decodes to; null for any.
  final int? height;
}

/// The render checks' names, in the order they are reported.
const List<String> pluginRenderCheckNames = <String>[
  'render.nodes',
  'render.litModel',
  'render.litModelDefaults',
  'render.lightType',
  'render.decal',
  'render.velocity',
  'render.shadows',
  'render.drawList',
  'render.lod',
  'render.skinning',
  'render.compute',
  'render.codec',
];

const int _size = 32;

/// Opens the device a check draws on: a call, or an `await` where the
/// backend opens with one (WebGPU).
typedef RenderCheckDevice = FutureOr<GraphicsDevice> Function();

/// The stages a plugin ships for [device], beside the device's own: a
/// library loaded from the plugin's bundle, or null when the device already
/// answers them.
typedef RenderCheckMaterials =
    FutureOr<ShaderLibrary?> Function(GraphicsDevice device);

/// The registries an application hands the plugin beside the renderer's
/// own, made for each fresh [renderer] on [device]: the runtime shaders a
/// data plugin's materials and render steps are compiled through, a
/// subsystem's registry a plugin asks its host for.
typedef RenderCheckRegistries =
    List<PluginRegistry> Function(Renderer renderer, GraphicsDevice device);

/// One renderer with the plugin installed into it on a fresh device.
final class _Stage {
  _Stage(
    this.device,
    Flutter3dPlugin plugin, {
    ShaderLibrary? materials,
    RenderCheckRegistries? registries,
    String? engineBackend,
  }) : renderer = Renderer.create(device: device, materials: materials) {
    extra = registries?.call(renderer, device) ?? const <PluginRegistry>[];
    loop = EngineLoop(
      input: InputState(),
      registries: <PluginRegistry>[renderer.renderSteps, decoders, ...extra],
      plugins: <Flutter3dPlugin>[plugin],
      backend: engineBackend,
    );
  }

  final GraphicsDevice device;
  final Renderer renderer;

  /// The decoders a plugin's image format registers with.
  final ModelDecoders decoders = ModelDecoders();

  /// What the application handed beside the renderer's registries.
  late final List<PluginRegistry> extra;
  late final EngineLoop loop;

  /// Completes once what the install started is in place: a compute step's
  /// placement, and the stages the runtime shaders compile behind a data
  /// plugin's materials and render steps.
  Future<void> get settled => Future.wait(<Future<void>>[
    renderer.renderSteps.whenPlaced(),
    for (final registry in extra)
      if (registry is RuntimeShaders) registry.settled,
  ]);

  /// Switches the one plugin off at the next step boundary.
  void switchOff() {
    loop.plugins.disable(loop.plugins.order.single);
    loop.runSteps(1);
  }

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
        views: <CameraView>[CameraView(camera: camera)],
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

/// Runs every render check of [points] on devices [device] opens, one fresh
/// device a check, and returns what each found under [backend]'s name.
///
/// **Pictures where the device draws them.** A device that draws the same
/// picture with a box as without one (a recording fake) is held to the
/// structure alone: the parts of a check that compare pictures are
/// declined, saying so, and a declined check is never green.
///
/// **[materials] is the plugin's stages on a GPU backend**: the library a
/// device loaded from the plugin's bundle (`GraphicsDevice.loadShaders`),
/// which the renderer consults before the device's own. Left out, the
/// device itself answers the plugin's stage names, as a software device
/// built with them does.
///
/// **[registries] is what the application hands beside the renderer**: a
/// data plugin's render steps, its Wasm render nodes among them, are
/// compiled through the engine's `RuntimeShaders`, which a check waits on
/// before it draws. [engineBackend] is the backend the engine's loop says
/// it draws with (`RuntimeBackends.cpu`), which a data plugin's render
/// sections install on and an engine that says none skips; null for none,
/// as a Dart plugin needs.
Future<List<PluginCheckOutcome>> checkPluginRender(
  Flutter3dPlugin Function() create, {
  required RenderCheckDevice device,
  required PluginRenderPoints points,
  required String backend,
  RenderCheckMaterials? materials,
  RenderCheckRegistries? registries,
  String? engineBackend,
}) async {
  Future<_Stage> stage() async {
    final opened = await device();
    final made = _Stage(
      opened,
      create(),
      materials: await materials?.call(opened),
      registries: registries,
      engineBackend: engineBackend,
    );
    await made.settled;
    return made;
  }

  final probe = await stage();
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
      return await run(await stage());
    } on Object catch (error) {
      return outcome(check, false, 'drawing it threw: ${_describe(error)}');
    }
  }

  final pictures = draws
      ? null
      : 'this device draws the same picture with a box as without, so no '
            'picture is compared';
  // Every node the plugin places, which `render.nodes` holds the points to.
  final placed = probe.renderer.renderSteps.nodeNames;

  /// Whether a hook of [hook]'s type is among [hooks].
  bool registered(Object hook, Iterable<Object> hooks) =>
      hooks.any((h) => h.runtimeType == hook.runtimeType);

  return <PluginCheckOutcome>[
    if (points.nodes.isNotEmpty || placed.isNotEmpty)
      await guarded('render.nodes', (stage) async {
        final unnamed = placed.where((n) => !points.nodes.contains(n)).toList();
        if (unnamed.isNotEmpty) {
          return outcome(
            'render.nodes',
            false,
            'it places ${unnamed.join(', ')}, which the points do not name: '
                'name every node it places in PluginRenderPoints.nodes',
          );
        }
        // A compute step loads where it is placed behind its registration,
        // and the frames before it lands skip it as pending: the stage was
        // settled before this frame, so it is the first one that counts.
        final frame = stage.render(stage.scene());
        final ran = <String>{for (final pass in frame.passes) pass.name};
        final skips = <String, PassSkip>{
          for (final skip in frame.skipped) skip.name: skip.reason,
        };
        // A node this device computes nothing for is skipped with the typed
        // refusal, and a reader of what it would have written starves with
        // it: the frame said why, as `render.compute` accepts.
        final refused = points.nodes
            .where((n) => skips[n] == PassSkip.unsupported)
            .toSet();
        final missing = points.nodes
            .where(
              (n) =>
                  !ran.contains(n) &&
                  !refused.contains(n) &&
                  !(refused.isNotEmpty && skips[n] == PassSkip.starved),
            )
            .toList();
        if (missing.isNotEmpty) {
          final why = <String>[
            for (final n in missing)
              if (skips[n] case final reason?) '$n ${reason.name}',
          ];
          return outcome(
            'render.nodes',
            false,
            'the frame did not run ${missing.join(', ')}'
                '${why.isEmpty ? '' : ' (skipped: ${why.join(', ')})'}',
          );
        }
        stage.switchOff();
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
      await guarded('render.litModel', (stage) async {
        if (stage.renderer.lightingModels.named(model.shaderName) == null) {
          return outcome(
            'render.litModel',
            false,
            '"${model.shaderName}" is not registered with the renderer',
          );
        }
        if (pictures != null) {
          stage.render(stage.scene(material: RenderMaterial(lighting: model)));
          return outcome('render.litModel', false, pictures, declined: true);
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
              parameters: MaterialParameters.over(parameters),
              extraTextures: extra,
            ),
          ),
        );
        final base = await draw(filled(null, 0), textures(null));
        if (_same(base, await stage.picture(stage.scene()))) {
          return outcome(
            'render.litModel',
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
          'render.litModel',
          unreached.isEmpty,
          unreached.isEmpty
              ? '"${model.shaderName}" drew, with ${model.slots.blocks.length} '
                    'blocks and ${model.slots.textures.length} textures of '
                    'its own reaching it'
              : 'nothing changed the picture through ${unreached.join(', ')}',
        );
      }),
    if (points.litModel case final model?)
      await guarded('render.litModelDefaults', (stage) async {
        // A material that sets none of the model's own blocks and names
        // none of its textures: every slot is bound anyway, each member at
        // the default its source declares and each texture to white, so
        // the box is the one drawn with those values given outright.
        final bare = stage.scene(material: RenderMaterial(lighting: model));
        if (pictures != null) {
          stage.render(bare);
          return outcome(
            'render.litModelDefaults',
            false,
            pictures,
            declined: true,
          );
        }
        final drawn = await stage.picture(bare);
        final white = stage.texel(255);
        final given = await stage.picture(
          stage.scene(
            material: RenderMaterial(
              lighting: model,
              parameters: MaterialParameters.over(<String, Float32List>{
                for (final block in model.slots.blocks)
                  for (final m in block.members)
                    if (m.defaultValue.isNotEmpty)
                      m.name: Float32List.fromList(m.defaultValue),
              }),
              extraTextures: <String, TextureHandle>{
                for (final t in model.slots.textures) t.binding: white,
              },
            ),
          ),
        );
        return outcome(
          'render.litModelDefaults',
          _same(drawn, given),
          _same(drawn, given)
              ? '"${model.shaderName}" with nothing set drew its defaults'
              : 'a box through "${model.shaderName}" with nothing set is not '
                    'the one drawn with its defaults given',
        );
      }),
    if (points.lightType case final type?)
      await guarded('render.lightType', (stage) async {
        final hook = stage.renderer.lightTypes.hookOf(type);
        final code = stage.renderer.lightTypes.codeOf(type);
        if (hook == null || code < LightTypes.firstPluginCode) {
          return outcome(
            'render.lightType',
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
          return outcome('render.lightType', false, pictures, declined: true);
        }
        final dark = await stage.picture(
          stage.scene(material: material, sun: false),
        );
        return outcome(
          'render.lightType',
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
    if (points.drawList case final hook?)
      await guarded('render.drawList', (stage) async {
        final hooks = stage.renderer.hooks;
        if (!registered(hook, hooks.drawListHooks)) {
          return outcome(
            'render.drawList',
            false,
            'no draw-list hook of its ${hook.runtimeType} is the renderer\'s',
          );
        }
        // A frame asks it of every mesh, which a hook that throws on one
        // fails here.
        stage.render(stage.scene());
        stage.switchOff();
        final gone = !registered(hook, hooks.drawListHooks);
        return outcome(
          'render.drawList',
          gone,
          gone
              ? 'its ${hook.runtimeType} was asked of a frame\'s meshes, and '
                    'went with the plugin'
              : 'its ${hook.runtimeType} stayed once the plugin was off',
        );
      }),
    if (points.lod case final policy?)
      await guarded('render.lod', (stage) async {
        final hooks = stage.renderer.hooks;
        if (!registered(policy, hooks.lodPolicies)) {
          return outcome(
            'render.lod',
            false,
            'no level-of-detail policy of its ${policy.runtimeType} is the '
                'renderer\'s',
          );
        }
        // A group of two levels in the frame, so the chain is asked.
        stage.render(
          stage.scene()..add(
            LodGroup(
              levels: <LodLevel>[
                LodLevel(
                  node: MeshNode(stage._box, RenderMaterial()),
                  maxScreenFraction: 0.5,
                ),
                LodLevel(
                  node: MeshNode(stage._box, RenderMaterial()),
                  maxScreenFraction: 0.0,
                ),
              ],
            ),
          ),
        );
        stage.switchOff();
        final gone = !registered(policy, hooks.lodPolicies);
        return outcome(
          'render.lod',
          gone,
          gone
              ? 'its ${policy.runtimeType} chose for a group, and went with '
                    'the plugin'
              : 'its ${policy.runtimeType} stayed once the plugin was off',
        );
      }),
    if (points.skinning case final hook?)
      await guarded('render.skinning', (stage) async {
        final hooks = stage.renderer.hooks;
        if (!registered(hook, hooks.skinningHooks)) {
          return outcome(
            'render.skinning',
            false,
            'no skinning hook of its ${hook.runtimeType} is listed: place it '
                'with RendererSteps.placeSkinningHook',
          );
        }
        stage.render(stage.scene());
        stage.switchOff();
        final gone = !registered(hook, hooks.skinningHooks);
        return outcome(
          'render.skinning',
          gone,
          gone
              ? 'its ${hook.runtimeType} was placed, and went with the plugin'
              : 'its ${hook.runtimeType} stayed once the plugin was off',
        );
      }),
    if (points.computeStep case final node?)
      await guarded('render.compute', (stage) async {
        // Placed asynchronously: a few frames for the placement to settle,
        // each a microtask apart, before what the frame says is final.
        FrameResult? last;
        for (var frame = 0; frame < 8; frame++) {
          last = stage.render(stage.scene());
          final skipped = last.skipped.where((s) => s.name == node);
          if (skipped.every((s) => s.reason != PassSkip.pending)) break;
          await Future<void>.delayed(Duration.zero);
        }
        final result = last!;
        final ran = result.passes.any((p) => p.name == node);
        final skip = result.skipped.where((s) => s.name == node).firstOrNull;
        final refused = skip?.reason == PassSkip.unsupported;
        return outcome(
          'render.compute',
          ran || refused,
          ran
              ? '"$node" ran on this device'
              : refused
              ? '"$node" was skipped with the typed refusal, this device '
                    'computing nothing it asks'
              : skip == null
              ? 'the frame neither ran nor skipped "$node"'
              : '"$node" was skipped as ${skip.reason.name}',
        );
      }),
    if (points.codec case final codec?)
      await guarded('render.codec', (stage) async {
        final codecs = stage.decoders.textureCodecs;
        if (!codecs.codecs.any((c) => c.name == codec.name)) {
          return outcome(
            'render.codec',
            false,
            '"${codec.name}" is not among the engine\'s texture codecs',
          );
        }
        final texture = await uploadEncodedImage(
          stage.device,
          codec.sample,
          decodeImage: (_) async => null,
          platformDecode: false,
          codecs: codecs,
        );
        final sized =
            (codec.width == null || texture.width == codec.width) &&
            (codec.height == null || texture.height == codec.height);
        stage.switchOff();
        final gone = !codecs.codecs.any((c) => c.name == codec.name);
        return outcome(
          'render.codec',
          sized && gone,
          !sized
              ? '"${codec.name}" decoded the sample to ${texture.width} by '
                    '${texture.height}, not ${codec.width} by ${codec.height}'
              : gone
              ? '"${codec.name}" decoded the sample to ${texture.width} by '
                    '${texture.height}, and went with the plugin'
              : '"${codec.name}" stayed once the plugin was off',
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
