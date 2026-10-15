/// A pass of the frame that computes rather than draws, and where it runs
/// — 1.0.
///
/// **Compute everywhere, placed by the hardware layer.** A [ComputeStep] is
/// a [RenderNode]: it declares what it reads and writes, the frame graph
/// orders and culls it like any other pass, and the renderer runs it in
/// order. What is its own is where its work goes, and that is not its to
/// say: [prepare] hands its kernels to `FrameCompute`, which loads them on
/// the first device of the frame's that takes them and answers a
/// [ComputeSite]. A step that cannot be placed is not supported
/// ([isSupported] false), so the frame reports it as `PassSkip.unsupported`
/// with [refusal] saying why, and whatever only read its output is culled
/// with it, rather than a frame that throws.
///
/// **Placed before the frame, not by it.** Loading a kernel is asynchronous
/// on every device (`GraphicsDevice.loadShaders`), and a frame is not; so the
/// placement is a step of its own, done when the step is added, the way
/// pipelines are warmed up. `FrameGraph.compile` needs nothing new for it:
/// it already asks every node [isSupported], and that answer is the
/// placement's. A step never prepared is unsupported.
///
/// **A step may take the site's encoder directly.** [record] is handed the
/// [ComputeContext]: the device its work is encoded on, each kernel's stage
/// on that device and `beginPass`, which is that device's own
/// `ComputeEncoder`. A step on the drawing device reads and writes the
/// frame's buffers as they are; one elsewhere hands its results over
/// through `SharedBuffer` or `SharedTexture`, which copy through host
/// memory where the two devices share nothing.
///
/// **Breaking in 1.0.0-rc.1+1.** A step no longer demands a placement
/// (`demand` is gone), is no longer handed executors (`prepare` takes the
/// device the frame is drawn on), and learns a [ComputeSite], not an
/// executor: where compute runs is the hardware layer's alone.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show RenderAnchor;
import 'package:flutter3d_shaders/kernel.dart';

import 'frame_graph.dart' show PlacementRequest, ResourceId;
import 'frame_plan.dart' show FrameResourceIds;
import 'render_node.dart';

/// What a [ComputeStep] records its work with: where it was placed, its
/// kernels' stages there, and the frame it is part of.
///
/// **One context that can grow**, never a list of parameters that does: a
/// later minor adds members here, and a step written against this one keeps
/// compiling.
final class ComputeContext {
  ComputeContext._(this.step, this.frame, this.site, this._stages);

  /// The step recording, by its name in the frame.
  final String step;

  /// The frame this step is a pass of: its resources, its settings, the
  /// device that draws it.
  final RenderFrame frame;

  /// Where the step was placed. Since 1.0.0-rc.1+1, in place of the
  /// executor.
  final ComputeSite site;

  final Map<String, ShaderHandle> _stages;

  /// The device the step's work is encoded on.
  GraphicsDevice get device => site.device;

  /// Whether that is the device drawing the frame, so the frame's own
  /// buffers and textures can be bound as they are.
  ///
  /// For whoever writes a step's `record` — a game, a plugin: a step that
  /// may land elsewhere asks this before it binds `frame.resources`
  /// directly, and otherwise hands its output over through `SharedBuffer`
  /// or `SharedTexture`.
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

  /// Opens a compute pass on [device]: its own encoder, which the caller
  /// binds, dispatches and submits. Labelled with the step's name unless
  /// [label] says otherwise.
  ComputeEncoder beginPass({String? label}) =>
      device.beginComputePass(label: label ?? step);
}

/// A compute pass in the frame graph, run where [prepare] placed it.
///
/// A subclass names its [kernels], declares its reads and writes as any
/// node does, and [record]s its passes.
///
/// **Implementable outside this package, and stays so through 1.x**: a
/// member added later arrives with a default body.
abstract base class ComputeStep extends RenderNode {
  /// A step; a subclass says what it computes.
  ComputeStep();

  /// The kernels this step dispatches, loaded together where it is placed.
  List<ComputeKernel> get kernels;

  /// Records this frame's work: binds, dispatches and submits on
  /// `context.beginPass()`.
  void record(ComputeContext context);

  /// Where compute meant for the frame's draws belongs when nobody says:
  /// before the opaque scene, which is what reads a compute step's output
  /// most often.
  @override
  RenderAnchor get defaultAnchor => RenderAnchor.beforeOpaque;

  ComputeSite? _site;
  Map<String, ShaderHandle> _stages = const <String, ShaderHandle>{};
  ComputePlacementException? _refusal = const ComputePlacementException(
    step: '',
    reason: ComputeRefusalReason.notPlaced,
    tried: <String>['ComputeStep.prepare places a step before its frame'],
  );

  /// Where the last [prepare] placed this step, or null. Since
  /// 1.0.0-rc.1+1, in place of `executor`.
  ComputeSite? get site => _site;

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
  bool get isSupported => _site != null;

  /// False while a [prepare] is loading the kernels: the frame reports the
  /// step as `PassSkip.pending` until it is placed or refused.
  @override
  bool get isReady => _preparing == 0;
  int _preparing = 0;

  /// Once a frame: compute has no view.
  @override
  ViewRuns get viewRuns => ViewRuns.once;

  /// Places this step for frames drawn on [device]: `FrameCompute.of`
  /// that device loads the step's [kernels] on the first of the frame's
  /// compute devices that takes them. A device that refuses the bundle is
  /// passed over, and its refusal kept as the cause.
  ///
  /// Answers the refusal when nothing fits, which [refusal] also holds;
  /// null when placed. Until it answers the step is not [isReady].
  Future<ComputePlacementException?> prepare(GraphicsDevice device) =>
      _waiting(_prepare(device, besideFrame: true));

  /// [placing] with the step held not ready until it settles: what every
  /// placement of a subclass goes through.
  Future<T> _waiting<T>(Future<T> placing) {
    _preparing++;
    return placing.whenComplete(() => _preparing--);
  }

  Future<ComputePlacementException?> _prepare(
    GraphicsDevice device, {
    required bool besideFrame,
  }) async {
    try {
      final placed = await FrameCompute.of(device).place(
        name,
        (GraphicsDevice on) => _loadKernels(on, name, kernels),
        besideFrame: besideFrame,
      );
      _place(placed.site, placed.loaded, null);
      return null;
    } on ComputePlacementException catch (refused) {
      _place(null, const <String, ShaderHandle>{}, refused);
      return refused;
    }
  }

  /// Sets where this step stands, for the steps of this library that place
  /// by a rule of their own.
  void _place(
    ComputeSite? site,
    Map<String, ShaderHandle> stages,
    ComputePlacementException? refusal,
  ) {
    _site = site;
    _stages = stages;
    _refusal = refusal;
  }

  /// Runs [record] where it was placed. Called only for a step the frame
  /// kept, which a step that is not placed never is.
  @override
  void execute(RenderFrame frame) {
    final site = _site;
    if (site == null) {
      throw StateError('"$name" ran without a placement: ${refusal?.message}');
    }
    record(ComputeContext._(name, frame, site, _stages));
  }
}

/// Places [step] as [ComputeStep.prepare] does, kept off a compute-only
/// device beside the frame's: for the engine's own steps whose output the
/// frame draws the same frame, a skinning hook's. Not exported.
Future<ComputePlacementException?> prepareForThisFrame(
  ComputeStep step,
  GraphicsDevice device,
) => step._waiting(step._prepare(device, besideFrame: false));

/// [kernels] loaded on [device] as one bundle called [name], each kernel's
/// stage by its name.
Future<Map<String, ShaderHandle>> _loadKernels(
  GraphicsDevice device,
  String name,
  List<ComputeKernel> kernels,
) async {
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
}

/// What a node that is not a [ComputeStep] asks with
/// `FrameGraphBuilder.place` to have compute of its own: [kernels] loaded
/// where the hardware layer puts them (`FrameCompute.place`), and the
/// answer handed to it as `RenderFrame.placement`, a
/// [ComputeNodePlacement].
///
/// **The frame's placer does the work.** A renderer hands the graph a
/// placer that takes this request to the hardware layer's placement: the
/// first frame that asks starts loading the kernels and leaves the node
/// out as `PassSkip.pending`; the frame after the load is done runs it
/// where they loaded; a request nothing can run leaves it out as
/// `PassSkip.unsupported`. Asked again with an equal request — the same
/// kernels — it answers what it answered, so a node may make its request
/// afresh in every `setup`.
final class ComputePlacementRequest extends PlacementRequest {
  /// A request for [kernels], loaded together.
  const ComputePlacementRequest(this.kernels);

  /// The kernels the node dispatches.
  final List<ComputeKernel> kernels;

  @override
  String get name => kernels.map((ComputeKernel k) => k.name).join(', ');

  @override
  bool operator ==(Object other) {
    if (other is! ComputePlacementRequest) return false;
    if (other.kernels.length != kernels.length) return false;
    for (var i = 0; i < kernels.length; i++) {
      if (other.kernels[i].name != kernels[i].name ||
          other.kernels[i].source != kernels[i].source) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(<Object>[
    for (final kernel in kernels) ...<Object>[kernel.name, kernel.source],
  ]);
}

/// Where the frame's placer put a node's [ComputePlacementRequest]: the
/// site its work is encoded on and each kernel's stage there.
final class ComputeNodePlacement {
  const ComputeNodePlacement._(this.site, this._stages);

  /// Where the kernels loaded.
  final ComputeSite site;

  final Map<String, ShaderHandle> _stages;

  /// The device the work is encoded on.
  GraphicsDevice get device => site.device;

  /// The stage of the kernel called [kernel]. Throws an [ArgumentError] for
  /// a name the request did not have.
  ShaderHandle stage(String kernel) =>
      _stages[kernel] ??
      (throw ArgumentError.value(
        kernel,
        'kernel',
        'is not one of the placed kernels (${_stages.keys.join(', ')})',
      ));

  @override
  String toString() => 'ComputeNodePlacement($site)';
}

/// Places [request] for the node called [node] on frames drawn on
/// [device], through the hardware layer: the placement, or null when
/// nothing takes the kernels. Not exported; the renderer's placer calls it.
Future<ComputeNodePlacement?> placeComputeRequest(
  String node,
  ComputePlacementRequest request,
  GraphicsDevice device,
) async {
  try {
    final placed = await FrameCompute.of(device).place(
      node,
      (GraphicsDevice on) => _loadKernels(on, node, request.kernels),
    );
    return ComputeNodePlacement._(placed.site, placed.loaded);
  } on ComputePlacementException {
    return null;
  }
}

/// A `ComputeWorkload` in the frame: placed by the hardware layer's
/// workload rule (`FrameCompute.placeHosted`), its buffers made where it
/// landed, and its work recorded there once a frame — since 1.0.0-rc.1+1.
///
/// **Where is decided by the hardware layer, never here and never by the
/// workload.** [prepare] hands the workload's kernels to `FrameCompute`,
/// which loads them on the GPUs a frame has, in its order, and answers the
/// first that took them, or none when the workload's own host code is to
/// step it. The workload is told the outcome (`ComputeWorkload.placed`)
/// and nothing else.
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

  /// Places the workload for frames drawn on [device] by the hardware
  /// layer's workload rule, makes its buffers there and tells it where it
  /// landed. Answers the refusal when nothing fits — no executor and no
  /// host code — and null when it is placed or left to its host code.
  @override
  Future<ComputePlacementException?> prepare(GraphicsDevice device) =>
      _waiting(_prepareWorkload(device));

  Future<ComputePlacementException?> _prepareWorkload(
    GraphicsDevice device,
  ) async {
    _release();
    final PlacedWork<Map<String, ShaderHandle>>? placed;
    try {
      placed = await FrameCompute.of(device).placeHosted(name, (
        GraphicsDevice on,
      ) async {
        try {
          return await _load(on);
        } on Object {
          // A device that refused once refuses again; asked afresh next time.
          _libraries[on]?.remove(workload.kernelSource)?.ignore();
          rethrow;
        }
      }, hasHost: workload.hasHost);
    } on ComputePlacementException catch (refused) {
      _onHost = false;
      _place(null, const <String, ShaderHandle>{}, refused);
      return refused;
    }
    if (placed == null) {
      _onHost = true;
      _place(null, const <String, ShaderHandle>{}, null);
      workload.placed(_binding = WorkloadBinding.host());
      return null;
    }
    final site = placed.site;
    final stages = placed.loaded;
    final pipelines = <String, ComputePipelineHandle>{
      for (final MapEntry(key: kernel, value: stage) in stages.entries)
        kernel: await (_pipelines[stage] ??= site.device
            .createComputePipelineAsync(stage)),
    };
    final resources = _resources = _WorkloadResources.make(
      workload,
      site,
      pipelines: pipelines,
      stages: stages,
    );
    _onHost = false;
    _place(site, stages, null);
    workload.placed(
      _binding = WorkloadBinding.at(site, drawn: resources.drawnVertices),
    );
    return null;
  }

  /// Records the workload's frame where it was placed, then hands what it
  /// draws to the drawing device and starts its reads back.
  @override
  void record(ComputeContext context) {
    final resources = _resources;
    if (resources == null) return;
    final encoder = context.beginPass(label: name);
    final recorder = _Recorder(resources, encoder);
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
  /// once no frame in flight can still be using them, when the registration
  /// that added the workload is cancelled. Since 1.0.0-rc.1+1, `release`.
  @override
  void dispose() {
    _release();
    _binding = null;
    workload.released();
  }

  void _release() {
    _resources?.dispose();
    _resources = null;
  }
}

/// A workload's buffers where it was placed, the drawing device's copies of
/// the drawn ones where those are two devices, and the reads in flight.
final class _WorkloadResources {
  _WorkloadResources._(
    this.site,
    this.drawing,
    this.buffers,
    this.copies,
    this.pipelines,
    this.stages,
    this.kernels,
  );

  static _WorkloadResources make(
    ComputeWorkload workload,
    ComputeSite site, {
    required Map<String, ComputePipelineHandle> pipelines,
    required Map<String, ShaderHandle> stages,
  }) {
    final device = site.device;
    final drawing = site.frameDevice;
    final here = site.isOnFrameDevice;
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
      site,
      drawing,
      buffers,
      copies,
      pipelines,
      stages,
      kernels,
    );
  }

  final ComputeSite site;
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
    final device = site.device;
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
/// and pipelines of the device it runs on.
final class _Recorder extends WorkloadRecorder {
  _Recorder(this._resources, this._encoder);

  final _WorkloadResources _resources;
  final ComputeEncoder _encoder;

  /// The reads asked for this frame, started once its work is submitted.
  final List<(String, void Function(ByteData bytes))> reads =
      <(String, void Function(ByteData bytes))>[];

  @override
  void write(String buffer, ByteData bytes, {int offsetInBytes = 0}) =>
      _resources.site.device.writeBuffer(
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
