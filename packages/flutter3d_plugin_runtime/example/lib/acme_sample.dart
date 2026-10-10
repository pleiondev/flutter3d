/// A plugin from outside the engine that reaches every extension point of
/// the frame that needs no backend's own work, and names everything in its
/// own namespace, `acme_sample`.
///
/// Written against the published libraries only: what a package on
/// pub.dev would see.
library;

import 'dart:typed_data';

import 'package:flutter3d_core/flutter3d_core.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart';

/// A light type of the plugin's own: a tube, lit as a point by the engine's
/// stages until its own model reads it.
const LightType tubeLight = LightType.custom(
  'acme_sample.tube',
  base: LightType.point,
);

/// The tube's hook: its length into the row's free component.
final class TubeHook extends LightTypeHook {
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
const String hairSource = '''
f3dmat 2
material acme_sample_Hair {
  uniform float gloss = 0.5;
  uniform(Strands) vec3 tint = vec3(0.4, 0.3, 0.2);
  uniform(Strands) float shift = 0.1;
  texture fur;

  light { return albedo * tint * nDotL; }
  fragment {
    let strands = sample(fur, uv).rgb;
    return vec4(lit * strands * (gloss + shift), alpha);
  }
}
''';

/// [hairSource] described as a lighting model.
final LightingModel hairModel = describeMaterial(
  parseMaterial(hairSource),
).lightingModel(label: 'Hair', shaderName: 'acme_sample_Hair');

/// A decal stage of the plugin's own, with the engine's decal interface.
const LightingModel decalStage = LightingModel(
  'Scorch decal',
  'acme_sample_Decal',
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
  const SoftSun();

  @override
  String get name => 'acme_sample.soft sun';

  @override
  ShadowKernel kernelFor(ShadowSettings settings) => ShadowKernel.box3x3;

  @override
  RenderNode? shadowMapProducer(ShadowProducerContext context) => SunMapNode();
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

/// Leaves out of every view a mesh whose name starts `acme_sample.hidden`,
/// and draws the rest nearest first.
final class HideHook extends DrawListHook {
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
  const CoarsePolicy();

  @override
  int? select(LodContext context) => context.group.levels.length - 1;
}

/// An image format of the plugin's own: `PIX!`, a width and a height of a
/// byte each, then grey.
final class PixCodec extends TextureCodec {
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

/// The kind of node the plugin's components are shown as.
final class EmberKind extends SceneNodeKind {
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
    PipelineAnchor(name: 'acme_sample.after glow', after: 'after bloom'),
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
      ..addNode(smear ?? SmearNode(), step: smearStep);
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
