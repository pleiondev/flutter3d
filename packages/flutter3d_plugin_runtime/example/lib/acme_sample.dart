/// A plugin from outside the engine that reaches every extension point of
/// the frame that needs no backend's own work, and names everything in its
/// own namespace, `acme_sample`.
///
/// Written against the published libraries only: what a package on
/// pub.dev would see.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_hardware/flutter3d_hardware.dart'
    show ClearColor, ColorTarget, DepthTarget, RenderPassDescriptor;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';
import 'package:flutter3d_shaders/kernel.dart' show ComputeKernel;

/// A light type of the plugin's own: a tube, lit as a point by the engine's
/// stages until its own model reads it.
const LightType tubeLight = LightType.custom(
  'acme_sample.tube',
  base: LightType.point,
);

/// The tube's hook: its length into the row's free component.
final class TubeHook extends LightTypeHook {
  /// A hook for tubes [length] metres long.
  const TubeHook({this.length = 1.5});

  /// How long the tube is, in metres.
  final double length;

  @override
  LightType get type => tubeLight;

  @override
  void pack(LightPackContext context) => context.row[15] = length;
}

/// A lit model of the plugin's own, with a uniform block and a texture of
/// its own: the slot table every backend binds by.
///
/// It reads the plugin's own light too (version 3): `tube` is one while the
/// block shades a [tubeLight], and `lightParams.w` is the length [TubeHook]
/// packs, so a longer tube reaches further. The engine's stages skip a light
/// type of a plugin's own; this block is handed it with its direction and
/// `nDotL`, which is what lights a box under a tube alone on every backend.
///
/// **The source writes the bare name, `Hair`.** The namespace is the
/// plugin's, not the file's: the build compiles it as `acme_sample__Hair`
/// for the plugin that ships it (`compileMaterial(namespace:)`, which
/// `tool/build_bundle.dart` and a project's build hook both pass), and a data
/// plugin's run time does the same with its manifest's namespace.
const String hairSource = '''
f3dmat 3
material Hair {
  uniform float gloss = 0.5;
  uniform(Strands) vec3 tint = vec3(0.4, 0.3, 0.2);
  uniform(Strands) float shift = 0.1;
  texture fur;
  lighttype tube = acme_sample.tube;

  light {
    let reach = mix(1.0, 0.5 + 0.25 * lightParams.w, tube);
    return albedo * tint * nDotL * reach;
  }
  fragment {
    let strands = sample(fur, uv).rgb;
    return vec4(lit * strands * (gloss + shift), alpha);
  }
}
''';

/// [hairSource] described as a lighting model, `acme_sample.Hair`: its
/// stage is the one the build compiles the source as in this plugin's
/// namespace.
final LightingModel hairModel = describeMaterial(parseMaterial(hairSource))
    .lightingModel(
      label: 'Hair',
      shaderName: materialStageIn(
        'acme_sample',
        parseMaterial(hairSource).name,
      )!,
    );

/// A decal stage of the plugin's own, with the engine's decal interface.
const LightingModel decalStage = LightingModel(
  'Scorch decal',
  'acme_sample__Decal',
);

/// The post effect's step.
const RenderStep smearStep = RenderStep('acme_sample.smear');

/// A post effect that reads the motion of every pixel: it asks for the
/// velocity, and the frame draws it whether or not the temporal resolve or
/// the motion blur run.
final class SmearNode extends RenderNode {
  /// The frames it was handed, for a test.
  final List<FrameContext> frames = <FrameContext>[];

  @override
  String get name => 'acme_sample.smear';

  @override
  void setup(FrameGraphBuilder builder) {
    builder
      ..read(FrameResourceIds.hdrColor)
      ..read(FrameResourceIds.velocity)
      ..write(FrameResourceIds.hdrColor);
  }

  @override
  RenderAnchor get defaultAnchor => RenderAnchor.afterVelocity;

  @override
  void execute(RenderFrame frame) {
    frames.add(frame);
    frame.resources.provide(
      FrameResourceIds.hdrColor,
      frame.resources.texture(FrameResourceIds.hdrColor),
    );
  }
}

/// A shadow technique with a producer of its own for the directional map.
final class SoftSun extends ShadowTechnique {
  /// The technique; it holds nothing, and makes its producers when a frame
  /// asks for them.
  const SoftSun();

  @override
  String get name => 'acme_sample.soft sun';

  @override
  ShadowKernel kernelFor(ShadowSettings settings) => ShadowKernel.box3x3;

  @override
  RenderNode? shadowMapProducer(ShadowProducerContext context) => SunMapNode();

  @override
  RenderNode? cubeAtlasProducer(ShadowProducerContext context) =>
      switch (context.cubeAtlas) {
        null => null,
        final atlas => LampAtlasNode(atlas),
      };
}

/// What [SoftSun] draws the directional map with.
final class SunMapNode extends RenderNode {
  @override
  String get name => 'acme_sample.sun map';

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.shadowMap];

  @override
  void execute(RenderFrame frame) {}
}

/// What [SoftSun] keeps the cube atlas of point and spot lights with: no
/// moving caster, every tile cleared to nothing in the way, so the lamps
/// cast only what the engine baked of the casters that never move.
final class LampAtlasNode extends RenderNode {
  /// A node clearing [atlas] for this frame.
  LampAtlasNode(this.atlas);

  /// The rows the engine laid out and fitted this frame.
  final ShadowCubeAtlas atlas;

  @override
  String get name => 'acme_sample.lamp atlas';

  @override
  List<ResourceId> get keeps => const <ResourceId>[FrameResourceIds.cubeShadow];

  @override
  void execute(RenderFrame frame) => frame.device
      .beginRenderPass(
        RenderPassDescriptor(
          colors: <ColorTarget>[
            ColorTarget(
              texture: atlas.atlas,
              clearValue: ClearColor(1.0, 1.0, 1.0, 1.0),
            ),
          ],
          depth: DepthTarget(texture: atlas.depth),
        ),
      )
      .submit();
}

/// Leaves out of every view a mesh whose name starts `acme_sample.hidden`,
/// and draws the rest nearest first.
final class HideHook extends DrawListHook {
  /// The hook; it holds nothing.
  const HideHook();

  @override
  bool keeps(DrawListContext context) =>
      !(context.node.name ?? '').startsWith('acme_sample.hidden');

  @override
  int? sortKey(DrawListContext context) =>
      (context.viewDepth * 1000).round().clamp(0, 1 << 30);
}

/// Shows every group at its coarsest level.
final class CoarsePolicy extends LodPolicy {
  /// The policy; it holds nothing.
  const CoarsePolicy();

  @override
  int? select(LodContext context) => context.group.levels.length - 1;
}

/// An image format of the plugin's own: `PIX!`, a width and a height of a
/// byte each, then grey.
final class PixCodec extends TextureCodec {
  /// The codec; it holds nothing.
  const PixCodec();

  @override
  String get name => 'acme_sample.pix';

  @override
  bool sniff(Uint8List head) =>
      head.length >= 6 && String.fromCharCodes(head.sublist(0, 4)) == 'PIX!';

  @override
  Future<Rgba8Image?> decode(TextureDecodeContext context) async {
    final width = context.bytes[4];
    final height = context.bytes[5];
    return Rgba8Image(
      width: width,
      height: height,
      pixels: Uint8List(width * height * 4)
        ..fillRange(0, width * height * 4, 96),
    );
  }
}

/// What [SparksStep] writes and [SparksNode] reads.
const ResourceId sparksResource = ResourceId('acme_sample.sparks');

/// A compute step of the plugin's own: one kernel, placed by the hardware
/// layer where it chooses and skipped with the typed refusal where nothing
/// computes it. It dispatches nothing; what it holds a frame to is where
/// the step is placed and that the frame runs it there.
final class SparksStep extends ComputeStep {
  /// The step; it holds nothing, and is placed by the frame that runs it.
  SparksStep();

  @override
  String get name => 'acme_sample.sparks';

  @override
  List<ResourceId> get writes => const <ResourceId>[sparksResource];

  @override
  late final List<ComputeKernel> kernels = ComputeKernel.parseAll('''
kernel 1
compute Sparks {
  workgroup 64;
  buffer sparks: f32[] read_write;
  kernel { }
}
''');

  @override
  void record(ComputeContext context) {}
}

/// Reads the sparks after the scene, as a draw of them would, and hands the
/// scene's colour on: the reader that keeps [SparksStep] in the frame,
/// which culls a step whose output nothing reads.
final class SparksNode extends RenderNode {
  /// The node; it holds nothing.
  const SparksNode();

  @override
  String get name => 'acme_sample.sparks shown';

  @override
  List<ResourceId> get reads => const <ResourceId>[
    sparksResource,
    FrameResourceIds.hdrColor,
  ];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  void execute(RenderFrame frame) => frame.resources.provide(
    FrameResourceIds.hdrColor,
    frame.resources.texture(FrameResourceIds.hdrColor),
  );
}

/// The kind of node the plugin's components are shown as.
final class EmberKind extends SceneNodeKind {
  /// The kind; it holds nothing.
  const EmberKind();

  @override
  String get name => 'acme_sample.ember';

  @override
  SceneNode create(SceneBindingContext context) =>
      SceneNode(name: 'acme_sample.ember ${context.entity}');
}

/// How the plugin's `heat` component is shown.
const SceneBindingSpec heatBinding = SceneBindingSpec(
  component: 'acme_sample.heat',
  nodeKind: 'acme_sample.ember',
  parameters: <String, String>{'temperature': 'gloss'},
);

/// A kind of pipeline node: a streak of the length a document gives.
final class StreakKind extends PipelineNodeKind {
  /// The kind; it holds nothing, and reads each streak's length from the
  /// document that places it.
  const StreakKind();

  @override
  String get name => 'acme_sample.streak';

  @override
  RenderNode create(PipelineNodeContext context) => StreakNode(
    context.node.name,
    (context.node.options['length'] as num? ?? 4).toInt(),
  );
}

/// What [StreakKind] makes.
final class StreakNode extends RenderNode {
  /// A streak called [name], [length] long as the document gives it.
  StreakNode(this.name, this.length);

  @override
  final String name;

  /// How many pixels it streaks.
  final int length;

  @override
  List<ResourceId> get reads => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  List<ResourceId> get writes => const <ResourceId>[FrameResourceIds.hdrColor];

  @override
  void execute(RenderFrame frame) => frame.resources.provide(
    FrameResourceIds.hdrColor,
    frame.resources.texture(FrameResourceIds.hdrColor),
  );
}

/// A pipeline of the plugin's own: an anchor after bloom, and a streak at
/// it.
final PipelineDocument glowPipeline = PipelineDocument(
  anchors: const <PipelineAnchor>[
    PipelineAnchor(name: 'acme_sample.after glow', after: 'f3d.after_bloom'),
  ],
  nodes: const <PipelineNode>[
    PipelineNode(
      name: 'acme_sample.glow streak',
      kind: 'acme_sample.streak',
      anchor: 'acme_sample.after glow',
      options: <String, Object?>{'length': 6},
    ),
  ],
);

/// The plugin: every extension point above, registered in `install`, all
/// taken back when it is switched off.
final class AcmeSamplePlugin extends Flutter3dPlugin {
  /// The plugin, placing [smear] as its post effect, or a fresh one when it
  /// is null.
  AcmeSamplePlugin({this.smear});

  /// The post effect it places; a fresh one when none is given.
  final SmearNode? smear;

  @override
  PluginManifest get manifest => const PluginManifest(
    id: 'acme_sample.all',
    apiVersion: PluginApiVersion(1, 0),
    touches: PluginTouches.view,
    description: 'Every extension point of the frame, from outside.',
  );

  @override
  void install(PluginHost host) {
    final steps = host.maybeRegistry<RendererSteps>();
    if (steps == null) return;
    steps
      ..addStep(smearStep)
      ..addNode(smear ?? SmearNode(), step: smearStep)
      ..addComputeStep(SparksStep())
      ..addNode(const SparksNode());
    host.registry<LightTypes>().register(const TubeHook());
    host.registry<LightingModels>()
      ..register(hairModel)
      ..register(decalStage);
    host.registry<RenderHooks>()
      ..addDrawListHook(const HideHook())
      ..addLodPolicy(const CoarsePolicy());
    host.maybeRegistry<TextureCodecs>()?.add(const PixCodec());
    host.registry<SceneBindings>()
      ..addKind(const EmberKind())
      ..add(heatBinding);
    host.registry<PipelineNodeKinds>().add(const StreakKind());
    steps.fromDocument(glowPipeline);
  }
}
