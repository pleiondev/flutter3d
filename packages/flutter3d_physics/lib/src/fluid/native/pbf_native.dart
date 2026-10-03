// The native Position Based Fluids kernels, `src/pbf_kernels.c`, as built by
// `hook/build.dart`, bound through `@Native` and passed the fluid's own
// buffers by address: nothing is copied in or out.
import 'dart:ffi';
import 'dart:typed_data';

import '../pbf_kernels.dart';

@Native<Int32 Function()>(symbol: 'f3d_pbf_version', isLeaf: true)
external int _version();

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Int32>,
    Pointer<Int32>,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
  )
>(symbol: 'f3d_pbf_densities', isLeaf: true)
external void _densities(
  Pointer<Double> x,
  Pointer<Int32> start,
  Pointer<Int32> list,
  int n,
  Pointer<Double> k,
  Pointer<Double> density,
);

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Int32>,
    Pointer<Int32>,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
  )
>(symbol: 'f3d_pbf_normals', isLeaf: true)
external void _normals(
  Pointer<Double> x,
  Pointer<Int32> start,
  Pointer<Int32> list,
  int n,
  Pointer<Double> k,
  Pointer<Double> density,
  Pointer<Double> normal,
);

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Int32>,
    Pointer<Int32>,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Double,
  )
>(symbol: 'f3d_pbf_forces', isLeaf: true)
external void _forces(
  Pointer<Double> x,
  Pointer<Int32> start,
  Pointer<Int32> list,
  int n,
  Pointer<Double> k,
  Pointer<Double> density,
  Pointer<Double> normal,
  Pointer<Double> before,
  Pointer<Double> after,
  Pointer<Double> v,
  double dt,
);

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Int32>,
    Pointer<Int32>,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
  )
>(symbol: 'f3d_pbf_lambdas', isLeaf: true)
external void _lambdas(
  Pointer<Double> p,
  Pointer<Int32> start,
  Pointer<Int32> list,
  int n,
  Pointer<Double> k,
  Pointer<Double> lambda,
);

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Int32>,
    Pointer<Int32>,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
  )
>(symbol: 'f3d_pbf_deltas', isLeaf: true)
external void _deltas(
  Pointer<Double> p,
  Pointer<Int32> start,
  Pointer<Int32> list,
  int n,
  Pointer<Double> k,
  Pointer<Double> lambda,
  Pointer<Double> delta,
);

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Int32>,
    Pointer<Int32>,
    Int32,
    Pointer<Double>,
    Double,
    Pointer<Double>,
  )
>(symbol: 'f3d_pbf_viscosity', isLeaf: true)
external void _viscosity(
  Pointer<Double> p,
  Pointer<Double> v,
  Pointer<Int32> start,
  Pointer<Int32> list,
  int n,
  Pointer<Double> k,
  double share,
  Pointer<Double> smoothed,
);

@Native<
  Int32 Function(
    Pointer<Double>,
    Int32,
    Double,
    Pointer<Int32>,
    Pointer<Int32>,
    Int32,
    Pointer<Int64>,
  )
>(symbol: 'f3d_pbf_neighbours', isLeaf: true)
external int _neighbours(
  Pointer<Double> x,
  int n,
  double radius,
  Pointer<Int32> start,
  Pointer<Int32> list,
  int capacity,
  Pointer<Int64> scratch,
);

@Native<
  Int32 Function(
    Pointer<Double>,
    Int32,
    Pointer<Int32>,
    Pointer<Int32>,
    Double,
    Pointer<Int32>,
    Pointer<Int32>,
  )
>(symbol: 'f3d_pbf_within', isLeaf: true)
external int _within(
  Pointer<Double> x,
  int n,
  Pointer<Int32> start,
  Pointer<Int32> list,
  double radius,
  Pointer<Int32> outStart,
  Pointer<Int32> out,
);

@Native<
  Int32 Function(
    Int32,
    Pointer<Int32>,
    Pointer<Int32>,
    Double,
    Int32,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
    Pointer<Double>,
  )
>(symbol: 'f3d_surface_lanczos', isLeaf: true)
external int _surfaceLanczos(
  int n,
  Pointer<Int32> start,
  Pointer<Int32> adjacent,
  double cell2,
  int band,
  int steps,
  Pointer<Double> q0,
  Pointer<Double> basis,
  Pointer<Double> alpha,
  Pointer<Double> beta,
  Pointer<Double> scratch,
);

/// The Lanczos steps of `FreeSurface.solveModes` in C, into [basis],
/// [alpha] and [beta]: how many ran, or -1 where there is no native code.
int nativeSurfaceLanczos(
  int n,
  Int32List start,
  Int32List adjacent,
  double cell2,
  int band,
  int steps,
  Float64List q0,
  Float64List basis,
  Float64List alpha,
  Float64List beta,
) {
  if (!nativePbfAvailable) return -1;
  final scratch = Float64List(n * (band + 1) + 2 * n);
  return _surfaceLanczos(
    n,
    start.address,
    (adjacent.isEmpty ? Int32List(1) : adjacent).address,
    cell2,
    band,
    steps,
    q0.address,
    basis.address,
    alpha.address,
    (beta.isEmpty ? Float64List(1) : beta).address,
    scratch.address,
  );
}

@Native<
  Int32 Function(
    Double,
    Double,
    Double,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
    Int32,
    Pointer<Double>,
  )
>(symbol: 'f3d_meniscus', isLeaf: true)
external int _meniscus(
  double radius,
  double bond,
  double contactAngle,
  int samples,
  Pointer<Double> rs,
  Pointer<Double> zs,
  int capacity,
  Pointer<Double> apex,
);

/// `TubeMeniscus`'s solve in C: the apex curvature and the surface's
/// points, or null where there is no native code.
({double apexCurvature, List<double> r, List<double> z})? nativeMeniscus(
  double radius,
  double bond,
  double contactAngle,
  int samples,
) {
  if (!nativePbfAvailable) return null;
  var capacity = samples * 4;
  final apex = Float64List(1);
  while (true) {
    final rs = Float64List(capacity);
    final zs = Float64List(capacity);
    final count = _meniscus(
      radius,
      bond,
      contactAngle,
      samples,
      rs.address,
      zs.address,
      capacity,
      apex.address,
    );
    if (count <= capacity) {
      return (
        apexCurvature: apex[0],
        r: List<double>.of(Float64List.sublistView(rs, 0, count)),
        z: List<double>.of(Float64List.sublistView(zs, 0, count)),
      );
    }
    capacity = count;
  }
}

@Native<Int32 Function()>(symbol: 'f3d_pbf_lanes', isLeaf: true)
external int _lanes();

@Native<Int32 Function(Int32)>(symbol: 'f3d_pbf_set_lanes', isLeaf: true)
external int _setLanes(int lanes);

/// How many neighbours the native pair loops take at a time: chosen by the
/// running processor (eight with AVX-512F, four with AVX2, two with SSE2 or
/// NEON), or 0 where there is no native code.
int get nativePbfLanes => nativePbfAvailable ? _lanes() : 0;

/// Sets [nativePbfLanes] to [lanes] where the processor has them, 0 for its
/// own choice, and returns what is now in use: for a test to hold each
/// width to the Dart kernels. One setting for the whole process.
int setNativePbfLanes(int lanes) => nativePbfAvailable ? _setLanes(lanes) : 0;

/// Whether the native kernels were built and load: false where the build
/// had no C compiler, and asked once.
final bool nativePbfAvailable = () {
  try {
    return _version() == 6;
  } on Object {
    return false;
  }
}();

/// [PbfKernels] in C, vectorised: [DartPbfKernels]' results to within a
/// tolerance, several times as fast.
final class NativePbfKernels implements PbfKernels {
  NativePbfKernels(PbfConstants k)
    : _k = Float64List.fromList([
        k.h,
        k.h2,
        k.restDensity,
        k.mass,
        k.norm,
        k.gamma,
        k.restStiffness,
        k.poly6,
        k.spiky,
        k.cohesion,
        k.h6,
        k.wq,
      ]);

  final Float64List _k;

  // Kept between calls, grown as the fluid does.
  Int32List _list = Int32List(1024);
  Int64List _scratch = Int64List(5);

  @override
  (Int32List, Int32List) within(
    Float64List x,
    int n,
    Int32List start,
    Int32List list,
    double radius,
  ) {
    final outStart = Int32List(n + 1);
    final out = Int32List(list.length + 1);
    final count = _within(
      x.address,
      n,
      start.address,
      _rows(list).address,
      radius,
      outStart.address,
      out.address,
    );
    return (outStart, Int32List.sublistView(out, 0, count));
  }

  @override
  (Int32List, Int32List) neighbours(Float64List x, int n, double radius) {
    final start = Int32List(n + 1);
    if (n == 0) return (start, Int32List(0));
    if (_scratch.length < 5 * n) _scratch = Int64List(5 * n);
    var count = _neighbours(
      x.address,
      n,
      radius,
      start.address,
      _list.address,
      _list.length,
      _scratch.address,
    );
    if (count > _list.length) {
      _list = Int32List(count * 2);
      count = _neighbours(
        x.address,
        n,
        radius,
        start.address,
        _list.address,
        _list.length,
        _scratch.address,
      );
    }
    return (start, Int32List.fromList(Int32List.sublistView(_list, 0, count)));
  }

  // A list with nothing in it has no address to give; one element stands in.
  static final Int32List _none = Int32List(1);
  static Int32List _rows(Int32List list) => list.isEmpty ? _none : list;

  @override
  void densities(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
  ) => _densities(
    x.address,
    start.address,
    _rows(list).address,
    n,
    _k.address,
    density.address,
  );

  @override
  void normals(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
    Float64List normal,
  ) => _normals(
    x.address,
    start.address,
    _rows(list).address,
    n,
    _k.address,
    density.address,
    normal.address,
  );

  @override
  void forces(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
    Float64List normal,
    Float64List before,
    Float64List after,
    Float64List v,
    double dt,
  ) => _forces(
    x.address,
    start.address,
    _rows(list).address,
    n,
    _k.address,
    density.address,
    normal.address,
    before.address,
    after.address,
    v.address,
    dt,
  );

  @override
  void lambdas(
    Float64List p,
    Int32List start,
    Int32List list,
    int n,
    Float64List lambda,
  ) => _lambdas(
    p.address,
    start.address,
    _rows(list).address,
    n,
    _k.address,
    lambda.address,
  );

  @override
  void deltas(
    Float64List p,
    Int32List start,
    Int32List list,
    int n,
    Float64List lambda,
    Float64List delta,
  ) => _deltas(
    p.address,
    start.address,
    _rows(list).address,
    n,
    _k.address,
    lambda.address,
    delta.address,
  );

  @override
  void viscosity(
    Float64List p,
    Float64List v,
    Int32List start,
    Int32List list,
    int n,
    double share,
    Float64List smoothed,
  ) => _viscosity(
    p.address,
    v.address,
    start.address,
    _rows(list).address,
    n,
    _k.address,
    share,
    smoothed.address,
  );
}

/// The native kernels for [k], or null where there are none.
PbfKernels? nativePbfKernels(PbfConstants k) =>
    nativePbfAvailable ? NativePbfKernels(k) : null;
