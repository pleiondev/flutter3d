/// A caller's own full-screen effect, as a node the graph already understands
/// — `gfx-28n`.
///
/// **The machinery was all there and writing one still meant reading the
/// engine.** `RenderServices.drawFullscreen` owns the triangle, the shared
/// vertex stage and the pipeline cache; `RenderNodeRegistry` takes a node in
/// either phase. What was missing between them is this: the four lines that
/// declare a read-modify-write of the right resource, take a transient of the
/// right shape, and hand the new version back under the old name. Every author
/// of an effect would write those four lines, three of them would write them
/// correctly, and the fourth would ship a pass that drew into a texture
/// nothing reads.
///
/// **It carries a [name] and an [enabled] from the first version**, which is
/// not decoration: `RenderSettings.disabledPasses` is a key space, and an
/// effect whose name a caller cannot type is an effect outside it. A frame
/// with a caller's effect in it reports that effect in `FrameResult.passes`
/// and in `skipped`, with the same four reasons, beside the engine's own.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';

import 'frame_graph.dart';
import 'frame_plan.dart';
import 'pass_contributor.dart';
import 'render_node.dart';

/// One full-screen shader over the picture, as a graph node.
///
/// Registered with `RenderNodeRegistry.add`, which takes the phase from
/// [preferredPhase] unless it is told otherwise — so an effect built for the
/// finished image cannot be registered where the image does not exist yet
/// simply by leaving an argument off.
final class FullscreenEffect extends RenderNode {
  /// An effect over the scene's light, before tone mapping.
  ///
  /// Reads and writes `hdr_colour`: the picture is linear and unbounded here,
  /// so anything physical belongs in this phase — it will bloom and tone map
  /// with the rest of the world.
  FullscreenEffect.overlay({
    required this.name,
    required this.shader,
    this.enabled = true,
    this.textures = const <String, TextureHandle>{},
    this.uniforms = const <String, Map<String, Float32List>>{},
    this.sourceSlot = 'scene_texture',
    this.sampler = SamplerOptions.linearClamp,
  }) : preferredPhase = FramePhase.overlay,
       _target = FrameResourceIds.hdrColour;

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
    this.sampler = SamplerOptions.linearClamp,
  }) : preferredPhase = FramePhase.present,
       _target = FrameResourceIds.frame;

  /// What this pass is called, in `RenderSettings.disabledPasses`' key space.
  ///
  /// **Required, and required to be distinct.** The graph rejects a name it
  /// does not recognise, which is what makes a misspelled toggle an error
  /// rather than a switch that silently does nothing; the other half of that
  /// bargain is that every registered pass has a name worth typing. A name
  /// colliding with one in `RenderSettings.passOrder` would make one toggle
  /// mean two passes.
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
  final SamplerOptions sampler;

  /// Where this belongs in the frame — see the two constructors.
  @override
  final FramePhase preferredPhase;

  final ResourceId _target;

  @override
  bool get isActive => enabled;

  @override
  List<ResourceId> get reads => <ResourceId>[_target];

  @override
  List<ResourceId> get writes => <ResourceId>[_target];

  @override
  void execute(NodeFrame frame) {
    final source = frame.resources.texture(_target);
    // A texture of the source's own shape: a pass cannot sample and write one,
    // which is the rule every effect in this engine meets the same way. It is
    // transient, so it goes back to the pool a safe number of frames later
    // rather than when this node stops looking at it.
    final target = frame.resources.transient(
      RenderTargetSpec(
        width: source.width,
        height: source.height,
        format: source.format,
      ),
    );

    frame.services.drawFullscreen(
      FullscreenDraw(
        target: target,
        fragment: shader,
        textures: <String, TextureHandle>{sourceSlot: source, ...textures},
        uniforms: uniforms,
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
