/// How far the renderer lets the CPU run ahead of the GPU, and what it says
/// about a frame that waited on a pipeline — `A1.4` and `A1.7`.
library;

import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart' show BusEvent;

/// The renderer's pacing: frames in flight, holding a frame when the GPU is
/// behind, and the threshold above which a pipeline build is a stall.
///
/// Set on `Renderer.pacing`; read at the top of every `Renderer.render`.
///
/// **Frames in flight.** A frame's GPU work finishes some time after
/// `render` returns, and the renderer counts the frames whose completion the
/// device has not reported (`GraphicsDevice.onFrameComplete`). With
/// [framesInFlight] of them unfinished, a new frame would queue behind them,
/// and on a backend whose uniform ring is that deep it would overwrite
/// uniforms the GPU is still reading. So the new frame is not drawn: `render`
/// hands back the previous frame's result again with `FrameResult.held` set,
/// the view presents the picture it already has, and the UI thread goes on
/// to answer input instead of waiting on the GPU. `Renderer.heldFrames`
/// counts these.
///
/// Three, the default, is the depth every backend's per-frame ring has, and
/// the most this accepts. Two trades a frame of throughput under load for a
/// frame less of latency; one waits for each frame before drawing the next.
/// The frame just submitted is not counted against the limit before the next
/// frame starts — Impeller only learns a frame is complete once the next one
/// begins, and counting it would hold every frame at one for ever.
///
/// A synchronous backend — the software rasteriser, WebGL — reports each
/// frame complete as it is submitted, and never holds.
final class FramePacing {
  const FramePacing({
    this.framesInFlight = maxFramesInFlight,
    this.holdWhenBehind = true,
    this.stallThreshold = const Duration(milliseconds: 8),
  }) : assert(
         framesInFlight >= 1 && framesInFlight <= maxFramesInFlight,
         'frames in flight are one to three',
       );

  /// Frames whose GPU work may be unfinished when the next one starts.
  final int framesInFlight;

  /// Whether a frame that finds [framesInFlight] unfinished is held — the
  /// previous picture presented again — rather than drawn. Off draws it
  /// anyway, which is the renderer before this existed: the finished-frame
  /// ring grows a texture and the GPU's queue grows a frame.
  final bool holdWhenBehind;

  /// How long a pipeline build may take before it is reported as a
  /// [PipelineStall]. Eight milliseconds is half a frame at sixty.
  final Duration stallThreshold;

  /// The depth of the renderer's deferred-release rings and of the backends'
  /// per-frame uniform rings, and so the most frames that may be in flight.
  static const int maxFramesInFlight = 3;

  FramePacing copyWith({
    int? framesInFlight,
    bool? holdWhenBehind,
    Duration? stallThreshold,
  }) => FramePacing(
    framesInFlight: framesInFlight ?? this.framesInFlight,
    holdWhenBehind: holdWhenBehind ?? this.holdWhenBehind,
    stallThreshold: stallThreshold ?? this.stallThreshold,
  );
}

/// The kind of geometry a pipeline was built for: which vertex stage the
/// material's fragment stage was linked with.
///
/// A class of constants rather than an enum, so that a kind added later — a
/// morphing mesh, a split one — breaks no `switch` somebody wrote over these.
final class PipelineGeometry {
  const PipelineGeometry._(this.name);

  /// A plain mesh.
  static const PipelineGeometry plain = PipelineGeometry._('plain');

  /// A mesh with a skeleton.
  static const PipelineGeometry skinned = PipelineGeometry._('skinned');

  /// An instanced batch.
  static const PipelineGeometry instanced = PipelineGeometry._('instanced');

  /// A level mesh drawn with its lightmap.
  static const PipelineGeometry lightmapped = PipelineGeometry._('lightmapped');

  /// Every kind, in the order above.
  static const List<PipelineGeometry> values = <PipelineGeometry>[
    plain,
    skinned,
    instanced,
    lightmapped,
  ];

  /// The kind's name, as a report prints it.
  final String name;

  @override
  String toString() => 'PipelineGeometry.$name';
}

/// A pipeline build that took [PipelineStall.micros] on the frame that asked
/// for it — `A1.7`.
///
/// **A hitch with a name.** Linking a pipeline is the slowest thing a frame
/// can ask of a device, and the frame a door opens on a new material is the
/// frame that pays. Over `FramePacing.stallThreshold`, the build is reported
/// with what asked for it: the material's lighting model by its shader name,
/// whether it was the opaque variant, and the geometry. That is enough to add
/// the pair to a warm-up, or to see that a level loads a material nobody
/// warmed.
///
/// On `FrameResult.pipelineStalls`, through `RenderListener.stalled`, and on
/// the bus as [FramePipelineStall].
final class PipelineStall {
  const PipelineStall({
    required this.material,
    required this.geometry,
    required this.micros,
    required this.frame,
    this.opaque = false,
    this.vertexShader,
  });

  /// The lighting model's shader name — `LightingModel.shaderName`.
  final String material;

  /// The vertex stage a material brought, or null for the engine's own.
  final String? vertexShader;

  final PipelineGeometry geometry;

  /// Whether this was the opaque variant of the model's stage.
  final bool opaque;

  /// Wall-clock time inside the build, in microseconds.
  final int micros;

  /// `Renderer.frameIndex` of the frame that paid for it.
  final int frame;

  @override
  String toString() =>
      'PipelineStall($material${opaque ? ' (opaque)' : ''}, ${geometry.name}'
      '${vertexShader == null ? '' : ', vertex $vertexShader'}, '
      '${(micros / 1000).toStringAsFixed(1)} ms, frame $frame)';
}

/// A pipeline build over the stall threshold: `RenderListener.stalled`, on
/// the frame channel of the bus.
///
/// Nothing goes into the event digest: whether a build crosses the threshold
/// is a fact about the machine, and a replay on another one must not differ
/// by it.
final class FramePipelineStall extends BusEvent {
  const FramePipelineStall(this.stall);

  final PipelineStall stall;

  @override
  String get name => 'render.pipelineStall';
}
