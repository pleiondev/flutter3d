/// A pass of the frame that computes rather than draws, and where it runs
/// — 1.0.
///
/// **Compute everywhere, by placement.** A [ComputeStep] is a [RenderNode]:
/// it declares what it reads and writes, the frame graph orders and culls it
/// like any other pass, and the renderer runs it in order. What is its own is
/// where its work goes. Its kernels are `.f3dmat compute`, and [prepare]
/// places them on the first executor that loads them — the device that draws
/// the frame, then the wgpu sidecar, then the CPU (`ComputeExecutors`) — or
/// on the one the step [demand]s. A step that cannot be placed is not
/// supported ([isSupported] false), so the frame reports it as
/// `PassSkip.unsupported` with [refusal] saying why, and whatever only read
/// its output is culled with it, rather than a frame that throws.
///
/// **Placed before the frame, not by it.** Loading a kernel is asynchronous
/// on every device (`GraphicsDevice.loadShaders`), and a frame is not; so the
/// placement is a step of its own, done when the step is added or the
/// executors change, the way pipelines are warmed up. `FrameGraph.compile`
/// needs nothing new for it: it already asks every node [isSupported], and
/// that answer is the placement's. A step never prepared is unsupported.
///
/// **A step may take the executor's encoder directly.** [record] is handed
/// the [ComputeContext]: the chosen [ComputeExecutor], its device, each
/// kernel's stage on that device and `beginPass`, which is the executor's
/// own `ComputeEncoder`. A step on the drawing device reads and writes the
/// frame's buffers as they are; one on another executor hands its results
/// over through `SharedBuffer` or `SharedTexture`, which copy through host
/// memory where the two devices share nothing.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show RenderAnchor;
import 'package:flutter3d_shaders/kernel.dart';

import 'render_node.dart';

/// What a [ComputeStep] records its work with: where it was placed, its
/// kernels' stages there, and the frame it is part of.
///
/// **One context that can grow**, never a list of parameters that does: a
/// later minor adds members here, and a step written against this one keeps
/// compiling.
final class ComputeContext {
  ComputeContext._(this.step, this.frame, this.executor, this._stages);

  /// The step recording, by its name in the frame.
  final String step;

  /// The frame this step is a pass of: its resources, its settings, the
  /// device that draws it.
  final RenderFrame frame;

  /// Where the step was placed.
  final ComputeExecutor executor;

  final Map<String, ShaderHandle> _stages;

  /// [executor]'s placement.
  ComputePlacement get placement => executor.placement;

  /// The device the step's work is encoded on.
  GraphicsDevice get device => executor.device;

  /// Whether that is the device drawing the frame, so the frame's own
  /// buffers and textures can be bound as they are.
  ///
  /// For whoever writes a step's `record` — a game, a plugin: a step that
  /// may land on the sidecar or the CPU asks this before it binds
  /// `frame.resources` directly, and otherwise hands its output over
  /// through `SharedBuffer` or `SharedTexture`.
  bool get isOnFrameDevice => identical(device, frame.device);

  /// The stage of the kernel called [kernel] on [device]. Throws an
  /// [ArgumentError] for a name the step's kernels do not have.
  ShaderHandle stage(String kernel) =>
      _stages[kernel] ??
      (throw ArgumentError.value(
        kernel,
        'kernel',
        'is not one of this step\'s kernels (${_stages.keys.join(', ')})',
      ));

  /// Opens a compute pass on [device]: the executor's own encoder, which the
  /// caller binds, dispatches and submits. Labelled with the step's name
  /// unless [label] says otherwise.
  ComputeEncoder beginPass({String? label}) =>
      device.beginComputePass(label: label ?? step);
}

/// A compute pass in the frame graph, run on the executor [prepare] chose.
///
/// A subclass names its [kernels], declares its reads and writes as any
/// node does, and [record]s its passes; it may [demand] a placement.
///
/// **Implementable outside this package, and stays so through 1.x**: a
/// member added later arrives with a default body.
abstract base class ComputeStep extends RenderNode {
  /// A step; a subclass says what it computes.
  ComputeStep();

  /// The kernels this step dispatches, loaded together on its executor.
  List<ComputeKernel> get kernels;

  /// The placement this step must run at, or null for the first that loads
  /// its kernels in `ComputePlacement.values` order.
  ComputePlacement? get demand => null;

  /// Records this frame's work: binds, dispatches and submits on
  /// `context.beginPass()`.
  void record(ComputeContext context);

  /// Where compute meant for the frame's draws belongs when nobody says:
  /// before the opaque scene, which is what reads a compute step's output
  /// most often.
  @override
  RenderAnchor get defaultAnchor => RenderAnchor.beforeOpaque;

  ComputeExecutor? _executor;
  Map<String, ShaderHandle> _stages = const <String, ShaderHandle>{};
  ComputePlacementException? _refusal = const ComputePlacementException(
    step: '',
    reason: ComputeRefusalReason.notPlaced,
    tried: <String>['ComputeStep.prepare places a step before its frame'],
  );

  /// Where the last [prepare] placed this step, or null.
  ComputeExecutor? get executor => _executor;

  /// Why this step is not placed: the refusal of the last [prepare], or
  /// that it was never prepared. Null once placed.
  ComputePlacementException? get refusal => switch (_refusal) {
    final r? when r.step.isEmpty => ComputePlacementException(
      step: name,
      reason: r.reason,
      tried: r.tried,
    ),
    final r => r,
  };

  /// Placed, and so in the frame.
  @override
  bool get isSupported => _executor != null;

  /// Places this step on [executors]: at its [demand], or on the first in
  /// placement order whose device loads the step's [kernels]. A device that
  /// refuses the bundle is passed over, and its refusal kept as the cause.
  ///
  /// Answers the refusal when nothing fits, which [refusal] also holds;
  /// null when placed.
  Future<ComputePlacementException?> prepare(ComputeExecutors executors) async {
    final bundle = kernelBundle(name, kernels).encode();
    final loaded = <ComputeExecutor, Map<String, ShaderHandle>>{};
    Object? cause;
    // In placement order, stopping at the first that loads: the rule below
    // then chooses that one, and asking the rest would only load the
    // kernels again on devices nobody will use.
    for (final candidate in <ComputeExecutor>[
      if (demand == null)
        ...executors.available
      else
        ?executors.executorFor(demand!),
    ]) {
      try {
        final library = await candidate.device.loadShaders(bundle);
        loaded[candidate] = <String, ShaderHandle>{
          for (final kernel in kernels)
            kernel.name:
                library[kernel.name] ??
                (throw StateError(
                  '${candidate.device.backendName} loaded the bundle and '
                  'has no stage "${kernel.name}"',
                )),
        };
        break;
      } on Object catch (error) {
        cause ??= error;
      }
    }
    try {
      final chosen = executors.place(
        step: name,
        demand: demand,
        accepts: loaded.containsKey,
      );
      _executor = chosen;
      _stages = loaded[chosen]!;
      _refusal = null;
      return null;
    } on ComputePlacementException catch (refused) {
      _executor = null;
      _stages = const <String, ShaderHandle>{};
      return _refusal = ComputePlacementException(
        step: refused.step,
        reason: refused.reason,
        demand: refused.demand,
        tried: refused.tried,
        cause: cause,
      );
    }
  }

  /// Runs [record] on the placed executor. Called only for a step the frame
  /// kept, which a step that is not placed never is.
  @override
  void execute(RenderFrame frame) {
    final executor = _executor;
    if (executor == null) {
      throw StateError('"$name" ran without a placement: ${refusal?.message}');
    }
    record(ComputeContext._(name, frame, executor, _stages));
  }
}
