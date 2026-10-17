/// The liquid's native CPU executor: its pair loops in C, a few neighbours
/// at a time — natively where the hook built it, nowhere in the browser.
library;

import 'dart:typed_data';

export 'liquid_lanes_native.dart'
    if (dart.library.js_interop) 'liquid_lanes_web.dart'
    show liquidLanesWidth, openLiquidLanes;

/// The pair loops `KernelLiquid` hands an executor, over flat buffers:
/// positions, velocities and every vector three doubles a particle, the
/// neighbours as compressed rows (particle i's are `list[start[i]]` up to
/// `list[start[i + 1]]`), the constants as `LiquidPairConstants.list`.
///
/// **Implemented by the engine's executors of the loops**: the native
/// lanes here, the kernels on a placed device in `flutter3d_effects`.
abstract base class LiquidPairLoops {
  /// An executor; a subclass says how it runs the loops.
  const LiquidPairLoops();

  /// Each particle's density into [density]: ρ₀·ΣW over the lattice's.
  void densities(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
  );

  /// Each particle's colour-field normal, h·Σ m/ρⱼ·∇W, into [normal].
  void normals(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
    Float64List normal,
  );

  /// Cohesion and curvature from each particle's neighbours, as
  /// accelerations, added to [accel] (gravity, on the way in).
  void forces(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
    Float64List normal,
    Float64List accel,
  );

  /// Each particle's density constraint multiplier into [lambda], and how
  /// far it is compressed past its rest density into [crowd].
  void lambdas(
    Float64List p,
    Int32List start,
    Int32List list,
    int n,
    Float64List lambda,
    Float64List crowd,
  );

  /// Each particle's position correction from [lambda] into [delta], with
  /// Macklin's artificial pressure when [artificial].
  void deltas(
    Float64List p,
    Int32List start,
    Int32List list,
    int n,
    Float64List lambda,
    Float64List delta, {
    required bool artificial,
  });

  /// XSPH: each velocity of [v] drawn towards its neighbours' by [share] of
  /// the kernel's weight, into [smoothed].
  void viscosity(
    Float64List p,
    Float64List v,
    Int32List start,
    Int32List list,
    int n,
    double share,
    Float64List smoothed,
  );
}
