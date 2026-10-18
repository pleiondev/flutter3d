/// The spilt liquid's pair loops placed by the hardware layer:
/// [placeKernelLiquid], which hands `flutter3d_physics_native`'s
/// [KernelLiquid] the executor its kernels landed on.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter3d_hardware/backend.dart' show SynchronousBufferReadback;
import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:flutter3d_physics/flutter3d_physics.dart'
    show DartFluid, FluidSolver;
import 'package:flutter3d_physics_native/flutter3d_physics_native.dart'
    show
        KernelLiquid,
        LiquidLoopsContext,
        LiquidPairConstants,
        LiquidPairLoops,
        liquidPairKernels,
        liquidParamFloats;
import 'package:flutter3d_plugin_api/flutter3d_plugin_api.dart'
    show SimulationProfile;
import 'package:flutter3d_shaders/kernel.dart';
import 'package:vector_math/vector_math.dart';

/// A [KernelLiquid] whose pair loops run where [compute]'s rule places
/// them for a run under [profile]; the rest of a step is [rest]'s.
///
/// **The work brings its native lanes, the hardware layer decides**: where
/// the package's hook built the loops in C, they are handed to
/// [FrameCompute.placeHosted] as [NativeLanes], stating
/// [KernelLiquid.nativeTolerance]; the rule runs them after the GPUs and
/// ahead of the CPU executor wherever the run is not bit-exact. Otherwise
/// the kernels ([liquidPairKernels]) run on the first device the rule
/// offers that computes and reads back in the same turn — the liquid steps
/// in the turn it is asked to. Under a bit-exact profile the work requires
/// `ComputeRequirement.bitExact`, which refuses the lanes and which only
/// the CPU kernel meets for kernels that divide and take square roots: a
/// GPU is passed over, with that reason.
///
/// Throws `ComputePlacementException` where nothing takes it.
Future<KernelLiquid> placeKernelLiquid(
  FrameCompute compute, {
  SimulationProfile profile = SimulationProfile.deterministic,
  FluidSolver rest = const DartFluid(),
}) async {
  final bundle = kernelBundle(
    KernelLiquid.workName,
    ComputeKernel.parseAll(liquidPairKernels),
  ).encode();
  final placed = await compute.placeHosted<LoadedShaderLibrary>(
    KernelLiquid.workName,
    (GraphicsDevice device) async {
      device.features
        ..require(DeviceFeature.compute, backend: device.backendName)
        ..require(
          DeviceFeature.synchronousReadback,
          backend: device.backendName,
          reason: 'the liquid steps in the turn it is asked to',
        );
      return device.loadShaders(bundle);
    },
    hasHost: false,
    lanes: KernelLiquid.isNativeLanesBuilt
        ? const NativeLanes(tolerance: KernelLiquid.nativeTolerance)
        : null,
    needs: ComputeNeeds(
      requirements: <ComputeRequirement>{
        if (profile.isBitExact) ComputeRequirement.bitExact,
      },
      invocationsPerWorkgroup: 64,
      storageBuffersPerStage: 7,
      inexactOperations: const <String>{'/', 'sqrt'},
    ),
  );
  if (placed == null) {
    // The rule chose the lanes, which it does only where the run is not
    // bit-exact: KernelLiquid.native answers them for such a run.
    return KernelLiquid.native(profile: profile, rest: rest) ??
        (throw StateError('the native lanes were placed and are not there'));
  }
  final site = placed.site;
  return KernelLiquid(
    loops: (LiquidLoopsContext context) =>
        _KernelLoops(site, placed.loaded, context.constants, context.origin),
    backend: site.device.backendName,
    rest: rest,
  );
}

/// The pair loops as kernels on a placed device that reads back in the
/// same turn: each call writes its inputs, dispatches one kernel and reads
/// its output.
final class _KernelLoops extends LiquidPairLoops {
  _KernelLoops(this.site, this.library, LiquidPairConstants c, this.origin)
    : device = site.device {
    final norm = c.norm;
    _params
      ..[1] = c.h
      ..[2] = c.h2
      ..[3] = c.restDensity
      ..[4] = c.mass
      ..[5] = norm
      ..[6] = c.gamma
      ..[7] = c.restStiffness
      ..[8] = c.poly6
      ..[9] = c.spiky
      ..[10] = c.cohesion
      ..[11] = c.h6
      ..[12] = c.wq
      ..[15] = 1e-6 * norm * norm / c.h2
      ..[16] = 1e-12;
    _artificial = -0.02 / c.restStiffness;
  }

  final ComputeSite site;
  final LoadedShaderLibrary library;
  final GraphicsDevice device;

  /// Where the positions are taken from before they are handed over in
  /// single precision.
  final Vector3 origin;

  final Float32List _params = Float32List(liquidParamFloats);
  late final double _artificial;
  final Map<String, StorageBuffer> _buffers = <String, StorageBuffer>{};
  final Map<String, ComputePipelineHandle> _pipelines =
      <String, ComputePipelineHandle>{};

  StorageBuffer _write(String name, TypedData data) {
    final bytes = math.max(data.lengthInBytes, 4);
    var buffer = _buffers[name];
    if (buffer == null || buffer.lengthInBytes < bytes) {
      if (buffer != null) device.releaseStorageBuffer(buffer);
      buffer = device.createBuffer(
        BufferDescriptor(
          lengthInBytes: bytes,
          usage: BufferUsage.standardStorage | BufferUsage.hostReadable,
          label: 'liquid $name',
        ),
      );
      _buffers[name] = buffer;
    }
    if (data.lengthInBytes > 0) {
      device.writeBuffer(buffer, 0, ByteData.sublistView(data));
    }
    return buffer;
  }

  Float32List _f32(Float64List from) => Float32List.fromList(from);

  Float32List _positions(Float64List p) {
    final out = Float32List(p.length);
    for (var i = 0; i < p.length; i += 3) {
      out
        ..[i] = p[i] - origin.x
        ..[i + 1] = p[i + 1] - origin.y
        ..[i + 2] = p[i + 2] - origin.z;
    }
    return out;
  }

  void _run(
    String kernel,
    int n,
    Map<String, TypedData> inputs,
    String output,
    Float64List into,
  ) {
    _params[0] = n.toDouble();
    final stage = library[kernel]!;
    final pipeline = _pipelines[kernel] ??= device.createComputePipeline(stage);
    final bound = <String, StorageBuffer>{
      for (final MapEntry(:key, :value) in inputs.entries)
        key: _write(key, value),
      'params': _write('params', _params),
    };
    final pass = site.beginPass(label: kernel)..bindPipeline(pipeline);
    for (final MapEntry(:key, :value) in bound.entries) {
      pass.bindStorageBuffer(stage, key, value);
    }
    pass
      ..dispatch((n + 63) ~/ 64)
      ..submit();
    final read = (device as SynchronousBufferReadback).readBufferSync(
      bound[output]!,
      sizeInBytes: into.length * 4,
    );
    final values = Float32List.sublistView(read);
    for (var k = 0; k < into.length; k++) {
      into[k] = values[k];
    }
  }

  @override
  void densities(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
  ) => _run(
    'LiquidDensity',
    n,
    <String, TypedData>{
      'x': _positions(x),
      'start': start,
      'list': list,
      'density': Float32List(n),
    },
    'density',
    density,
  );

  @override
  void normals(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
    Float64List normal,
  ) => _run(
    'LiquidNormal',
    n,
    <String, TypedData>{
      'x': _positions(x),
      'start': start,
      'list': list,
      'density': _f32(density),
      'normal': Float32List(3 * n),
    },
    'normal',
    normal,
  );

  @override
  void forces(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
    Float64List normal,
    Float64List accel,
  ) => _run(
    'LiquidForce',
    n,
    <String, TypedData>{
      'x': _positions(x),
      'start': start,
      'list': list,
      'density': _f32(density),
      'normal': _f32(normal),
      'accel': _f32(accel),
    },
    'accel',
    accel,
  );

  @override
  void lambdas(
    Float64List p,
    Int32List start,
    Int32List list,
    int n,
    Float64List lambda,
    Float64List crowd,
  ) {
    final both = Float64List(2 * n);
    _run(
      'LiquidLambda',
      n,
      <String, TypedData>{
        'x': _positions(p),
        'start': start,
        'list': list,
        'lam': Float32List(2 * n),
      },
      'lam',
      both,
    );
    for (var i = 0; i < n; i++) {
      lambda[i] = both[2 * i];
      crowd[i] = both[2 * i + 1];
    }
  }

  @override
  void deltas(
    Float64List p,
    Int32List start,
    Int32List list,
    int n,
    Float64List lambda,
    Float64List delta, {
    required bool artificial,
  }) {
    final lam = Float32List(2 * n);
    for (var i = 0; i < n; i++) {
      lam[2 * i] = lambda[i];
    }
    _params[14] = artificial ? _artificial : 0.0;
    _run(
      'LiquidDelta',
      n,
      <String, TypedData>{
        'x': _positions(p),
        'start': start,
        'list': list,
        'lam': lam,
        'delta': Float32List(3 * n),
      },
      'delta',
      delta,
    );
  }

  @override
  void viscosity(
    Float64List p,
    Float64List v,
    Int32List start,
    Int32List list,
    int n,
    double share,
    Float64List smoothed,
  ) {
    _params[13] = share;
    _run(
      'LiquidSmooth',
      n,
      <String, TypedData>{
        'x': _positions(p),
        'v': _f32(v),
        'start': start,
        'list': list,
        'smoothed': Float32List(3 * n),
      },
      'smoothed',
      smoothed,
    );
  }
}
