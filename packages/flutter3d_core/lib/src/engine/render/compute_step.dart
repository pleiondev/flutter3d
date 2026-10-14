/// A pass of the frame that computes rather than draws, and where it runs
/// — 1.0.
///
/// **Compute everywhere, by placement.** A [ComputeStep] is a [RenderNode]:
/// it declares what it reads and writes, the frame graph orders and culls it
/// like any other pass, and the renderer runs it in order. What is its own is
/// where its work goes. Its kernels are in the kernel language, and [prepare]
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

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show RenderAnchor;
import 'package:flutter3d_shaders/kernel.dart';

import 'frame_graph.dart' show ResourceId;
import 'frame_plan.dart' show FrameResourceIds;
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

  /// Sets where this step stands, for the steps of this library that place
  /// by a rule of their own.
  void _place(
    ComputeExecutor? executor,
    Map<String, ShaderHandle> stages,
    ComputePlacementException? refusal,
  ) {
    _executor = executor;
    _stages = stages;
    _refusal = refusal;
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

/// A `ComputeWorkload` in the frame: placed by the workload rule,
/// `ComputeExecutors.placeWorkload`, its buffers made where it landed, and
/// its work recorded there once a frame — since 1.0.0-rc.1+1.
///
/// **Where is decided here, never by the workload.** [prepare] loads the
/// workload's kernels on the drawing device's compute, then on the sidecar,
/// and asks the rule: the first that loaded them, else the workload's own
/// host implementation when it has one, else the CPU executor. The workload
/// is told the outcome (`ComputeWorkload.placed`) and nothing else.
///
/// **What it draws reaches the drawing device.** A buffer the workload
/// declares drawn is made with `BufferUsage.vertex` on the drawing device
/// and bound as vertices there as it is; from a sidecar or the CPU
/// executor it is copied across through the host after each frame's work,
/// the way a `SharedBuffer` without a shared allocation is, so what is
/// drawn trails the step by the copy.
///
/// **On the host it is in the frame and does nothing**: the workload's own
/// code steps it, and the frame keeps the step only so that a later
/// [prepare] can move it onto a device without the graph changing shape.
final class WorkloadStep extends ComputeStep {
  /// The step that runs [workload].
  WorkloadStep(this.workload);

  /// What it runs.
  final ComputeWorkload workload;

  @override
  String get name => workload.name;

  @override
  late final List<ComputeKernel> kernels = ComputeKernel.parseAll(
    workload.kernelSource,
  );

  @override
  List<ResourceId> get writes => const <ResourceId>[
    FrameResourceIds.computedVertices,
  ];

  /// Whether the last [prepare] left it to the workload's own host code.
  bool get isOnHost => _onHost;
  bool _onHost = false;

  /// Where the last [prepare] put it, as the workload was told; null before.
  WorkloadBinding? get binding => _binding;
  WorkloadBinding? _binding;

  @override
  bool get isSupported => _onHost || super.isSupported;

  _WorkloadResources? _resources;

  /// Each device's kernels and pipelines, by the source they were read
  /// from, so a hundred steps of one workload load and compile them once.
  static final Expando<Map<String, Future<Map<String, ShaderHandle>>>>
  _libraries = Expando<Map<String, Future<Map<String, ShaderHandle>>>>(
    'workload kernels',
  );
  static final Expando<Future<ComputePipelineHandle>> _pipelines =
      Expando<Future<ComputePipelineHandle>>('workload pipelines');

  Future<Map<String, ShaderHandle>> _load(GraphicsDevice device) {
    final libraries = _libraries[device] ??=
        <String, Future<Map<String, ShaderHandle>>>{};
    return libraries[workload.kernelSource] ??= () async {
      final library = await device.loadShaders(
        kernelBundle(name, kernels).encode(),
      );
      return <String, ShaderHandle>{
        for (final kernel in kernels)
          kernel.name:
              library[kernel.name] ??
              (throw StateError(
                '${device.backendName} loaded the bundle and has no stage '
                '"${kernel.name}"',
              )),
      };
    }();
  }

  /// Places the workload by `ComputeExecutors.placeWorkload`, makes its
  /// buffers there and tells it where it landed. Answers the refusal when
  /// nothing fits — a demand nothing meets, or no executor and no host
  /// code — and null when it is placed or left to its host code.
  @override
  Future<ComputePlacementException?> prepare(ComputeExecutors executors) async {
    _release();
    final loaded = <ComputeExecutor, Map<String, ShaderHandle>>{};
    Object? cause;
    final candidates = <ComputeExecutor>[
      if (demand != null)
        ?executors.executorFor(demand!)
      else ...[
        for (final placement in ComputeExecutors.aheadOfHost)
          ?executors.executorFor(placement),
        if (!workload.hasHost) ?executors.executorFor(ComputePlacement.cpu),
      ],
    ];
    for (final candidate in candidates) {
      try {
        loaded[candidate] = await _load(candidate.device);
        break;
      } on Object catch (error) {
        // A device that refused once refuses again; asked afresh next time.
        _libraries[candidate.device]?.remove(workload.kernelSource)?.ignore();
        cause ??= error;
      }
    }
    final ComputeExecutor? chosen;
    try {
      chosen = executors.placeWorkload(
        step: name,
        hasHost: workload.hasHost,
        demand: demand,
        accepts: loaded.containsKey,
      );
    } on ComputePlacementException catch (refused) {
      _onHost = false;
      final refusal = ComputePlacementException(
        step: refused.step,
        reason: refused.reason,
        demand: refused.demand,
        tried: refused.tried,
        cause: cause,
      );
      _place(null, const <String, ShaderHandle>{}, refusal);
      return refusal;
    }
    if (chosen == null) {
      _onHost = true;
      _place(null, const <String, ShaderHandle>{}, null);
      workload.placed(_binding = WorkloadBinding.host());
      return null;
    }
    final stages = loaded[chosen]!;
    final pipelines = <String, ComputePipelineHandle>{
      for (final MapEntry(key: kernel, value: stage) in stages.entries)
        kernel: await (_pipelines[stage] ??= chosen.device
            .createComputePipelineAsync(stage)),
    };
    final resources = _resources = _WorkloadResources.make(
      workload,
      chosen,
      drawing: executors.device,
      pipelines: pipelines,
      stages: stages,
    );
    _onHost = false;
    _place(chosen, stages, null);
    workload.placed(
      _binding = WorkloadBinding.placed(
        chosen.placement,
        drawn: resources.drawnVertices,
      ),
    );
    return null;
  }

  /// Records the workload's frame on the executor it was placed on, then
  /// hands what it draws to the drawing device and starts its reads back.
  @override
  void record(ComputeContext context) {
    final resources = _resources;
    if (resources == null) return;
    final encoder = context.beginPass(label: name);
    final recorder = _Recorder(resources, encoder, context.placement);
    workload.record(recorder);
    encoder.submit();
    resources.afterFrame(recorder.reads);
  }

  @override
  void execute(RenderFrame frame) {
    if (_onHost) return;
    super.execute(frame);
  }

  /// Lets go of its buffers and tells the workload: what a renderer calls
  /// once no frame in flight can still be using them.
  void release() {
    _release();
    _binding = null;
    workload.released();
  }

  void _release() {
    _resources?.dispose();
    _resources = null;
  }
}

/// A workload's buffers on its executor, the drawing device's copies of the
/// drawn ones where those are two devices, and the reads in flight.
final class _WorkloadResources {
  _WorkloadResources._(
    this.executor,
    this.drawing,
    this.buffers,
    this.copies,
    this.pipelines,
    this.stages,
    this.kernels,
  );

  static _WorkloadResources make(
    ComputeWorkload workload,
    ComputeExecutor executor, {
    required GraphicsDevice drawing,
    required Map<String, ComputePipelineHandle> pipelines,
    required Map<String, ShaderHandle> stages,
  }) {
    final device = executor.device;
    final here = identical(device, drawing);
    final buffers = <String, StorageBuffer>{};
    final copies = <String, StorageBuffer>{};
    for (final b in workload.buffers) {
      final usage = switch ((
        drawnHere: b.drawn && here,
        read: b.readable || (b.drawn && !here),
      )) {
        (drawnHere: true, read: true) =>
          BufferUsage.standardStorage |
              BufferUsage.vertex |
              BufferUsage.hostReadable,
        (drawnHere: true, read: false) =>
          BufferUsage.standardStorage | BufferUsage.vertex,
        (drawnHere: false, read: true) =>
          BufferUsage.standardStorage | BufferUsage.hostReadable,
        (drawnHere: false, read: false) => BufferUsage.standardStorage,
      };
      buffers[b.name] = device.createBuffer(
        BufferDescriptor(
          lengthInBytes: b.lengthInBytes,
          usage: usage,
          label: '${workload.name} ${b.name}',
        ),
      );
      if (b.drawn && !here) {
        copies[b.name] = drawing.createBuffer(
          BufferDescriptor(
            lengthInBytes: b.lengthInBytes,
            usage: BufferUsage.vertex | BufferUsage.copyDestination,
            label: '${workload.name} ${b.name}, drawn',
          ),
        );
      }
    }
    final kernels = <String, ComputeKernel>{
      for (final k in ComputeKernel.parseAll(workload.kernelSource)) k.name: k,
    };
    return _WorkloadResources._(
      executor,
      drawing,
      buffers,
      copies,
      pipelines,
      stages,
      kernels,
    );
  }

  final ComputeExecutor executor;
  final GraphicsDevice drawing;
  final Map<String, StorageBuffer> buffers;

  /// The drawing device's copy of each drawn buffer made elsewhere.
  final Map<String, StorageBuffer> copies;
  final Map<String, ComputePipelineHandle> pipelines;
  final Map<String, ShaderHandle> stages;
  final Map<String, ComputeKernel> kernels;

  /// The buffers a read of is in flight: one at a time each.
  final Set<String> _reading = <String>{};
  bool _disposed = false;

  /// Each drawn buffer as the drawing device binds it.
  Map<String, GeometryBuffer> get drawnVertices => <String, GeometryBuffer>{
    for (final MapEntry(key: name, value: buffer) in buffers.entries)
      name: ?(copies[name] ?? buffer).asVertices,
  };

  StorageBuffer buffer(String name) =>
      buffers[name] ??
      (throw ArgumentError.value(
        name,
        'buffer',
        'is not one of the workload\'s buffers (${buffers.keys.join(', ')})',
      ));

  /// Starts the reads the frame asked for, and the copies of what is drawn
  /// across to the drawing device.
  void afterFrame(List<(String, void Function(ByteData bytes))> reads) {
    final device = executor.device;
    for (final (name, done) in reads) {
      unawaited(
        device.readBuffer(buffer(name)).then((bytes) {
          _reading.remove(name);
          if (!_disposed) done(bytes);
        }),
      );
    }
    for (final MapEntry(key: name, value: copy) in copies.entries) {
      final key = '\u0000copy $name';
      if (!_reading.add(key)) continue;
      unawaited(
        device.readBuffer(buffers[name]!).then((bytes) {
          _reading.remove(key);
          if (!_disposed) drawing.writeBuffer(copy, 0, bytes);
        }),
      );
    }
  }

  /// Whether a read of [name] may start now; marks it started.
  bool startRead(String name) => _reading.add(name);

  void dispose() {
    _disposed = true;
    for (final b in buffers.values) {
      b.dispose();
    }
    for (final b in copies.values) {
      b.dispose();
    }
  }
}

/// The recorder a frame hands a workload: its names bound to the buffers
/// and pipelines of the executor it runs on.
final class _Recorder extends WorkloadRecorder {
  _Recorder(this._resources, this._encoder, this.placement);

  final _WorkloadResources _resources;
  final ComputeEncoder _encoder;

  @override
  final ComputePlacement placement;

  /// The reads asked for this frame, started once its work is submitted.
  final List<(String, void Function(ByteData bytes))> reads =
      <(String, void Function(ByteData bytes))>[];

  @override
  void write(String buffer, ByteData bytes, {int offsetInBytes = 0}) =>
      _resources.executor.device.writeBuffer(
        _resources.buffer(buffer),
        offsetInBytes,
        bytes,
      );

  @override
  void dispatch(String kernel, int x, {int y = 1, int z = 1}) {
    final pipeline =
        _resources.pipelines[kernel] ??
        (throw ArgumentError.value(
          kernel,
          'kernel',
          'is not one of the workload\'s kernels '
              '(${_resources.pipelines.keys.join(', ')})',
        ));
    final stage = _resources.stages[kernel]!;
    _encoder.bindPipeline(pipeline);
    for (final b in _resources.kernels[kernel]!.bindings) {
      if (b.kind != KernelBindingKind.buffer) continue;
      _encoder.bindStorageBuffer(stage, b.name, _resources.buffer(b.name));
    }
    _encoder.dispatch(x, y, z);
  }

  @override
  bool readBack(String buffer, void Function(ByteData bytes) done) {
    _resources.buffer(buffer);
    if (!_resources.startRead(buffer)) return false;
    reads.add((buffer, done));
    return true;
  }
}
