/// A caller's own full-screen effect, as a node the graph already understands
/// — `gfx-28n`.
///
/// **The machinery was all there and writing one still meant reading the
/// engine.** `RenderServices.drawFullscreen` owns the triangle, the shared
/// vertex stage and the pipeline cache; `RendererSteps.addNode` places a node
/// at any anchor. What was missing between them is this: the four lines that
/// declare a read-modify-write of the right resource, take a transient of the
/// right shape, and hand the new version back under the old name. Every author
/// of an effect would write those four lines, three of them would write them
/// correctly, and the fourth would ship a pass that drew into a texture
/// nothing reads.
///
/// **It carries a [name] and an [enabled] from the first version**, which is
/// not decoration: a frame with a caller's effect in it reports that effect
/// by [name] in `FrameResult.passes` and in `skipped`, with the same
/// `PassSkip` reasons, beside the engine's own, and [enabled] is the switch
/// the step it is added with throws.
library;

import 'dart:typed_data';

import 'package:flutter3d_foundation/flutter3d_foundation.dart'
    show MaterialParameters;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show RenderAnchor;

import '../../formats/material_language/material_ast.dart'
    show MaterialStageKind, materialParametersBlock;
import '../../formats/material_language/material_bundle.dart'
    show BundledMaterials;
import 'frame_graph.dart';
import 'frame_plan.dart';
import 'pass_contributor.dart';
import 'render_node.dart';

/// One full-screen shader over the picture, as a graph node.
///
/// Added like any node, with `RendererSteps.addNode`, which places it at its
/// [defaultAnchor] unless told otherwise — so an effect built for the
/// finished image cannot be placed where the image does not exist yet simply
/// by leaving an argument off. Since 1.0 it is one of the nodes, not a way of
/// its own into the frame: it no longer registers anywhere by itself.
final class FullscreenEffect extends RenderNode {
  /// An effect over the scene's light, before tone mapping.
  ///
  /// Reads and writes `hdr_color`: the picture is linear and unbounded here,
  /// so anything physical belongs here — it will bloom and tone map
  /// with the rest of the world.
  FullscreenEffect.overlay({
    required this.name,
    required this.shader,
    this.enabled = true,
    this.textures = const <String, TextureHandle>{},
    this.uniforms = const <String, Map<String, Float32List>>{},
    this.sourceSlot = 'scene_texture',
    this.sampler = SamplerDescriptor.linearClamp,
    this.readsSurface = false,
    this.parameters,
  }) : defaultAnchor = RenderAnchor.afterScene,
       _target = FrameResourceIds.hdrColor;

  /// An effect over the finished image, after tone mapping.
  ///
  /// Reads and writes `frame`: display-referred sRGB, which is what a grade, a
  /// letterbox or a watermark is honestly about. Anything meant to blow out
  /// belongs in [FullscreenEffect.overlay] instead — there is no range left
  /// here to blow out into.
  FullscreenEffect.present({
    required this.name,
    required this.shader,
    this.enabled = true,
    this.textures = const <String, TextureHandle>{},
    this.uniforms = const <String, Map<String, Float32List>>{},
    this.sourceSlot = 'scene_texture',
    this.sampler = SamplerDescriptor.linearClamp,
    this.readsSurface = false,
    this.parameters,
  }) : defaultAnchor = RenderAnchor.beforePresent,
       _target = FrameResourceIds.frame;

  /// A full-screen stage written in the material language, from the
  /// bundle [materials] that carries it under [stage]: every block it
  /// declares bound at the source's defaults ([parameters], unless one is
  /// given), [readsSurface] set when the body reads `sceneDepth`, and each
  /// texture of its own bound from [textures] by the name its source binds
  /// it under. Over `frame` when [present], over `hdr_color` otherwise, as
  /// [FullscreenEffect.present] and [FullscreenEffect.overlay] are.
  ///
  /// **Nothing it declares is left unbound.** A full-screen stage made with
  /// the plain constructors bound only what the caller listed, so a
  /// `uniform float strength = 0.5;` or a `sceneDepth` read without
  /// `readsSurface` drew with a block or a sampler unbound: WebGPU threw at
  /// the next frame, Impeller crashed on the sampler, WebGL2 read zeros.
  ///
  /// Throws an [ArgumentError] when [stage] is not a full-screen stage of
  /// the bundle, or when a texture of its own has no handle in [textures],
  /// naming each.
  factory FullscreenEffect.material(
    BundledMaterials materials,
    String stage, {
    required String name,
    required ShaderHandle shader,
    bool present = false,
    bool enabled = true,
    Map<String, TextureHandle> textures = const <String, TextureHandle>{},
    MaterialParameters? parameters,
    SamplerDescriptor sampler = SamplerDescriptor.linearClamp,
  }) {
    final bindings = materials.stages[stage];
    if (bindings == null || bindings.kind != MaterialStageKind.fullscreen) {
      throw ArgumentError.value(
        stage,
        'stage',
        bindings == null
            ? 'bundle "${materials.bundle.name}" has no stage of that name'
            : 'is a ${bindings.kind} source, not a full-screen stage',
      );
    }
    final unnamed = <String>[
      for (final binding in bindings.textureBindings)
        if (binding != 'scene_texture' && !textures.containsKey(binding))
          binding,
    ];
    if (unnamed.isNotEmpty) {
      throw ArgumentError.value(
        textures,
        'textures',
        '"$stage" samples ${unnamed.join(', ')}, which nothing binds: hand '
            'each a texture by that name',
      );
    }
    final values = parameters ?? materials.parameters(stage);
    return present
        ? FullscreenEffect.present(
            name: name,
            shader: shader,
            enabled: enabled,
            textures: textures,
            sampler: sampler,
            readsSurface: bindings.readsSurfaceBuffer,
            parameters: values,
          )
        : FullscreenEffect.overlay(
            name: name,
            shader: shader,
            enabled: enabled,
            textures: textures,
            sampler: sampler,
            readsSurface: bindings.readsSurfaceBuffer,
            parameters: values,
          );
  }

  /// What this pass is called, in `FrameResult.passes` and `skipped`.
  ///
  /// **Required, and required to be distinct.** A name colliding with one in
  /// `RenderSettings.passOrder` would make one report mean two passes, and a
  /// step that owns the name would switch off both.
  @override
  final String name;

  /// The fragment stage. Where it comes from differs per backend — see
  /// [RenderServices.drawFullscreen], which says all three answers.
  final ShaderHandle shader;

  /// Whether to run at all this frame.
  ///
  /// Read once per compile, like every other node's, and reported as
  /// `PassSkip.settings` when false — the same answer the engine's own effects
  /// give, because from the graph's side it is the same fact.
  ///
  /// Mutable, because a node outlives a frame: an effect is registered once
  /// and switched on and off for as long as the renderer lives.
  bool enabled;

  /// Extra samplers this stage reads, by slot name.
  ///
  /// The picture itself is bound to [sourceSlot] and is not in here — it is
  /// this frame's, and a caller holding a handle to it would be holding the
  /// texture from some earlier frame.
  Map<String, TextureHandle> textures;

  /// Uniform blocks, by block name then member name.
  ///
  /// Mutable for the reason [enabled] is: an effect that could not change its
  /// own numbers between frames would be a constant with a pass around it.
  Map<String, Map<String, Float32List>> uniforms;

  /// The `MaterialParams` of a stage written in the material language, or
  /// null: bound as that block on every draw, over whatever [uniforms] says
  /// of it, so a value set here (`parameters['strength']![0] = 0.8`) is the
  /// next frame's. [FullscreenEffect.material] seeds it at the source's
  /// defaults, so a declared block is never left unbound.
  final MaterialParameters? parameters;

  /// The sampler slot the picture is bound to.
  ///
  /// `scene_texture` because that is what every post stage in this engine
  /// calls it, and a caller writing their first effect should be able to copy
  /// one of ours. Nameable because a caller porting a shader from somewhere
  /// else should not have to rename a uniform to use it.
  final String sourceSlot;

  /// How the picture is sampled. Linear and clamped, as every full-screen read
  /// in this engine is; nearest is the one worth changing it to, for an effect
  /// that reads exact texels rather than a neighbourhood.
  final SamplerDescriptor sampler;

  /// Whether the stage reads the surface buffer — the scene's normals and
  /// its depth along the view axis — as `surface_texture`, nearest-sampled:
  /// what a full-screen stage written in the material language reads as
  /// `sceneDepth` (1.0). A read the pass cannot run without, so on a device
  /// with no surface buffer the frame skips it and says why, as it skips
  /// the engine's own passes that read it.
  final bool readsSurface;

  /// Where this belongs in the frame — see the two constructors.
  @override
  final RenderAnchor defaultAnchor;

  final ResourceId _target;

  @override
  bool get isActive => enabled;

  @override
  List<ResourceId> get reads => <ResourceId>[
    _target,
    if (readsSurface) FrameResourceIds.surfaceBuffer,
  ];

  @override
  List<ResourceId> get writes => <ResourceId>[_target];

  @override
  void execute(RenderFrame frame) {
    final source = frame.resources.texture(_target);
    // A texture of the source's own shape: a pass cannot sample and write one,
    // which is the rule every effect in this engine meets the same way. It is
    // transient, so it goes back to the pool a safe number of frames later
    // rather than when this node stops looking at it.
    final target = frame.resources.transient(
      RenderTargetDescriptor(
        width: source.width,
        height: source.height,
        format: source.format,
      ),
    );

    frame.services.drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: shader,
        textures: <String, TextureHandle>{
          sourceSlot: source,
          if (readsSurface)
            'surface_texture': frame.resources.texture(
              FrameResourceIds.surfaceBuffer,
            ),
          ...textures,
        },
        uniforms: switch (parameters) {
          null => uniforms,
          final own => <String, Map<String, Float32List>>{
            ...uniforms,
            materialParametersBlock: own.uniforms,
          },
        },
        sampler: sampler,
      ),
    );

    // The new version, under the old name. Without this the pass would have
    // drawn into a texture nothing reads — a frame that costs its time and
    // shows nothing, which is the failure that looks exactly like an effect
    // whose shader is wrong.
    frame.resources.provide(_target, target);
  }
}
