/// A shallow water's columns as a compute workload: the physics core's
/// substep as kernels (`shallowWaterKernels`, which the core publishes
/// beside the calls that hand a water's columns over), handed to the
/// engine, which runs it where the hardware layer's rule says.
///
/// **Here and not in the core**, because the core draws nothing and names
/// no device: it says what the step is in its own terms, and this file
/// says it in the engine's. **And it decides nothing about where.** It says what the step is: the
/// buffers, the kernels, what a frame records. The engine tells it the
/// outcome (`placed`): on an executor, the core hands the columns over
/// (`NativeWorld.setShallowExternal`) and keeps what is round them; on the
/// host — the core itself, which is this workload's own implementation
/// there — the core steps them as it always has.
///
/// **A frame, on an executor:** what the core did to the water since the
/// last frame — the bodies standing in it, the springs, the spray landing,
/// a pour — is written as changes and added (`ShallowApply`); the step's
/// substeps run; and two reads come back later: the state, which the core
/// mirrors for the bodies and the spray to stand on, and what went over
/// the lips, which the core throws as sheets. So the core's view of the
/// water trails the GPU's by the reads, and no water is made or lost by the
/// trailing: every change crosses as a change. See
/// `flutter3d_physics_native/doc/gpu_water.md` for the tolerance this has
/// against the core stepping it.
library;

import 'dart:typed_data';

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show NativeShallowLiquid, NativeWorld, nativeLipFloats, shallowWaterKernels;

/// [water] of [world], its columns stepped wherever the engine places this.
///
/// **A base class**, so a view can draw from the same buffers on the same
/// executor: it adds its kernels to [kernelSource], its buffers to
/// [buffers], and dispatches them after `super.record`.
base class ShallowWaterWorkload extends ComputeWorkload {
  /// The workload of [water] in [world].
  ShallowWaterWorkload(this.world, this.water);

  /// The world the water is in.
  final NativeWorld world;

  /// The water.
  final NativeShallowLiquid water;

  /// The kernels' own source, which a subclass adds to.
  static final String kernels = shallowWaterKernels;

  @override
  String get name => 'shallow water ${water.id}';

  @override
  String get kernelSource => kernels;

  /// How many floats the parameter block holds: the core's, padded.
  static const int paramFloats = 32;

  @override
  List<WorkloadBuffer> get buffers => <WorkloadBuffer>[
    const WorkloadBuffer('params', paramFloats * 4),
    WorkloadBuffer('state', water.stateLength * 4, readable: true),
    WorkloadBuffer('changes', water.stateLength * 4),
    WorkloadBuffer('cells', 4 * water.cells * 4),
    WorkloadBuffer('fa', water.faces * 4),
    WorkloadBuffer('fb', water.faces * 4),
    WorkloadBuffer('eddies', water.cells * 4),
    WorkloadBuffer('share', water.cells * 4),
    WorkloadBuffer('flux', water.faces * 4),
    WorkloadBuffer('came', water.faces * 4),
    WorkloadBuffer('lip', nativeLipFloats * water.faces * 4, readable: true),
  ];

  /// The core: what steps the water where nothing else does.
  @override
  bool get hasHost => true;

  /// Where it was last placed, or null before.
  WorkloadBinding? get binding => _binding;
  WorkloadBinding? _binding;

  /// Whether the next frame sends the whole state rather than changes.
  bool _fresh = true;

  /// Whether the lips were read last frame, and so are cleared first.
  bool _lipsTaken = false;

  /// The seconds of water that went over the lips since they were last
  /// read.
  double _lipSeconds = 0.0;

  /// The substeps the last frame ran.
  int get lastSubsteps => _lastSubsteps;
  int _lastSubsteps = 0;

  @override
  void placed(WorkloadBinding binding) {
    _binding = binding;
    if (!world.containsShallowLiquid(water)) return;
    world.setShallowExternal(water, on: !binding.isOnHost);
    _fresh = true;
    _lipsTaken = false;
    _lipSeconds = 0.0;
  }

  @override
  void released() {
    _binding = null;
    if (world.isDisposed || !world.containsShallowLiquid(water)) return;
    world.setShallowExternal(water, on: false);
  }

  static int _groups(int count) => (count + 63) ~/ 64;

  @override
  void record(WorkloadRecorder recorder) {
    if (world.isDisposed || !world.containsShallowLiquid(water)) return;
    final taken = world.drainShallowExternal(water);
    if (taken == null) return;
    final n = water.cells;
    final state = water.stateLength;
    var apply = false;
    if (_fresh || taken.wasReset) {
      final block = world.readShallowState(water);
      // The core's block is ground, depth, u, w, filled, roughness, walls;
      // the GPU's state is depth, u, w, and its cells the other four.
      final cells = Float32List(4 * n)
        ..setRange(0, n, block)
        ..setRange(n, 4 * n, block, n + state);
      recorder
        ..write('state', ByteData.sublistView(block, n, n + state))
        ..write('cells', ByteData.sublistView(cells));
      _fresh = false;
    } else {
      if (taken.changes case final changes?) {
        recorder.write('changes', ByteData.sublistView(changes));
        apply = true;
      }
      if (taken.filled case final filled?) {
        recorder.write(
          'cells',
          ByteData.sublistView(filled),
          offsetInBytes: n * 4,
        );
      }
    }
    final params = Float32List(paramFloats)..setAll(0, taken.params);
    recorder.write('params', ByteData.sublistView(params));
    if (_lipsTaken) {
      recorder.dispatch(
        'ShallowClearLips',
        _groups(nativeLipFloats * water.faces),
      );
      _lipsTaken = false;
    }
    if (apply) recorder.dispatch('ShallowApply', _groups(state));
    final substeps = taken.substeps;
    _lastSubsteps = substeps;
    final faces = _groups(water.faces), columns = _groups(n);
    for (var s = 0; s < substeps; s++) {
      recorder
        ..dispatch('ShallowAdvect', faces)
        ..dispatch('ShallowEddies', columns)
        ..dispatch('ShallowDiffuse', faces)
        ..dispatch('ShallowSlope', faces)
        ..dispatch('ShallowOutflow', columns)
        ..dispatch('ShallowTransport', faces)
        ..dispatch('ShallowSettle', columns);
    }
    recordAfterStep(recorder);
    if (substeps == 0) return;
    _lipSeconds += taken.seconds;
    final seconds = _lipSeconds;
    if (recorder.readBack('lip', (bytes) => _throw(bytes, seconds))) {
      _lipsTaken = true;
      _lipSeconds = 0.0;
    }
    recorder.readBack('state', _mirror);
  }

  /// What a subclass records after the step, on the same executor: a view
  /// building its surface from the state. Nothing here.
  void recordAfterStep(WorkloadRecorder recorder) {}

  bool get _live =>
      _binding != null &&
      !_binding!.isOnHost &&
      !world.isDisposed &&
      world.containsShallowLiquid(water);

  void _throw(ByteData bytes, double seconds) {
    if (!_live || !(seconds > 0.0)) return;
    final lips = bytes.buffer.asFloat32List(
      bytes.offsetInBytes,
      nativeLipFloats * water.faces,
    );
    // Most frames nothing went over: the core is not asked to look.
    var any = false;
    for (var k = 0; k < lips.length && !any; k += nativeLipFloats) {
      any = lips[k] > 0.0;
    }
    if (any) world.throwShallowLips(water, lips, seconds);
  }

  void _mirror(ByteData bytes) {
    if (!_live) return;
    world.putShallowState(
      water,
      bytes.buffer.asFloat32List(bytes.offsetInBytes, water.stateLength),
    );
  }
}
