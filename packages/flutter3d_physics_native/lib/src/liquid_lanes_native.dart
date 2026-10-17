/// The liquid's native CPU executor through dart:ffi: the pair loops of
/// `csrc/lanes/f3d_liquid_lanes.c`, which the hook builds apart from the
/// core where there is a C compiler.
// ignore_for_file: non_constant_identifier_names
@DefaultAsset('package:flutter3d_physics_native/src/liquid_lanes_native.dart')
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'liquid_lanes.dart';

@Native<Int32 Function()>(symbol: 'f3d_lanes_version', isLeaf: true)
external int _version();

@Native<Int32 Function()>(symbol: 'f3d_lanes_width', isLeaf: true)
external int _width();

@Native<Int32 Function(Int32)>(symbol: 'f3d_lanes_set_width', isLeaf: true)
external int _setWidth(int lanes);

@Native<Pointer<Void> Function(Int64)>(symbol: 'f3d_lanes_alloc', isLeaf: true)
external Pointer<Void> _alloc(int bytes);

@Native<Void Function(Pointer<Void>)>(symbol: 'f3d_lanes_free', isLeaf: true)
external void _free(Pointer<Void> block);

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Int32>,
    Pointer<Int32>,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
  )
>(symbol: 'f3d_lanes_densities', isLeaf: true)
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
>(symbol: 'f3d_lanes_normals', isLeaf: true)
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
>(symbol: 'f3d_lanes_forces', isLeaf: true)
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
    Pointer<Double>,
  )
>(symbol: 'f3d_lanes_lambdas', isLeaf: true)
external void _lambdas(
  Pointer<Double> p,
  Pointer<Int32> start,
  Pointer<Int32> list,
  int n,
  Pointer<Double> k,
  Pointer<Double> lambda,
  Pointer<Double> crowd,
);

@Native<
  Void Function(
    Pointer<Double>,
    Pointer<Int32>,
    Pointer<Int32>,
    Int32,
    Pointer<Double>,
    Pointer<Double>,
    Int32,
    Pointer<Double>,
  )
>(symbol: 'f3d_lanes_deltas', isLeaf: true)
external void _deltas(
  Pointer<Double> p,
  Pointer<Int32> start,
  Pointer<Int32> list,
  int n,
  Pointer<Double> k,
  Pointer<Double> lambda,
  int artificial,
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
>(symbol: 'f3d_lanes_viscosity', isLeaf: true)
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

/// The version of the C this binds, which the binding is written against.
const int _expectedVersion = 7;

/// The native executor for a fluid whose constants are [constants], or
/// null where the hook built none (no C compiler) or built another version.
LiquidPairLoops? openLiquidLanes(Float64List constants) {
  try {
    if (_version() != _expectedVersion) return null;
  } on Object {
    // The asset is not there: the hook found no compiler.
    return null;
  }
  return _Lanes(constants);
}

/// How many neighbours the native executor sums at a time, or sets it to
/// [lanes] (1, 2, 4 or 8) where the processor has them; for a test to hold
/// each width to the kernels. Null where there is no native executor.
int? liquidLanesWidth({int? lanes}) {
  try {
    return lanes == null ? _width() : _setWidth(lanes);
  } on Object {
    return null;
  }
}

/// A block of the C library's memory, copied in from and back out to Dart.
final class _Block {
  _Block(int bytes) : address = _alloc(bytes);

  final Pointer<Void> address;

  Pointer<Double> get doubles => address.cast<Double>();
  Pointer<Int32> get ints => address.cast<Int32>();

  void free() => _free(address);
}

final class _Lanes extends LiquidPairLoops {
  _Lanes(Float64List constants) : _k = _Block(constants.length * 8) {
    _k.doubles.asTypedList(constants.length).setAll(0, constants);
  }

  final _Block _k;

  // A typed list's bytes in the library's memory, kept for the call.
  final List<_Block> _held = <_Block>[];

  Pointer<Double> _doubles(Float64List from) {
    final block = _Block(from.length * 8);
    _held.add(block);
    block.doubles.asTypedList(from.length).setAll(0, from);
    return block.doubles;
  }

  Pointer<Int32> _ints(Int32List from) {
    final block = _Block(from.length * 4);
    _held.add(block);
    block.ints.asTypedList(from.length).setAll(0, from);
    return block.ints;
  }

  void _back(Pointer<Double> from, Float64List to) =>
      to.setAll(0, from.asTypedList(to.length));

  void _release() {
    for (final block in _held) {
      block.free();
    }
    _held.clear();
  }

  @override
  void densities(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
  ) {
    try {
      final out = _doubles(density);
      _densities(_doubles(x), _ints(start), _ints(list), n, _k.doubles, out);
      _back(out, density);
    } finally {
      _release();
    }
  }

  @override
  void normals(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
    Float64List normal,
  ) {
    try {
      final out = _doubles(normal);
      _normals(
        _doubles(x),
        _ints(start),
        _ints(list),
        n,
        _k.doubles,
        _doubles(density),
        out,
      );
      _back(out, normal);
    } finally {
      _release();
    }
  }

  @override
  void forces(
    Float64List x,
    Int32List start,
    Int32List list,
    int n,
    Float64List density,
    Float64List normal,
    Float64List accel,
  ) {
    try {
      // The C adds the accelerations to a velocity over a step: from
      // nought over one second, that is the accelerations themselves.
      final zero = _doubles(Float64List(3 * n));
      final out = _doubles(Float64List(3 * n));
      _forces(
        _doubles(x),
        _ints(start),
        _ints(list),
        n,
        _k.doubles,
        _doubles(density),
        _doubles(normal),
        _doubles(accel),
        zero,
        out,
        1.0,
      );
      _back(out, accel);
    } finally {
      _release();
    }
  }

  @override
  void lambdas(
    Float64List p,
    Int32List start,
    Int32List list,
    int n,
    Float64List lambda,
    Float64List crowd,
  ) {
    try {
      final outLambda = _doubles(lambda);
      final outCrowd = _doubles(crowd);
      _lambdas(
        _doubles(p),
        _ints(start),
        _ints(list),
        n,
        _k.doubles,
        outLambda,
        outCrowd,
      );
      _back(outLambda, lambda);
      _back(outCrowd, crowd);
    } finally {
      _release();
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
    try {
      final out = _doubles(delta);
      _deltas(
        _doubles(p),
        _ints(start),
        _ints(list),
        n,
        _k.doubles,
        _doubles(lambda),
        artificial ? 1 : 0,
        out,
      );
      _back(out, delta);
    } finally {
      _release();
    }
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
    try {
      final out = _doubles(smoothed);
      _viscosity(
        _doubles(p),
        _doubles(v),
        _ints(start),
        _ints(list),
        n,
        _k.doubles,
        share,
        out,
      );
      _back(out, smoothed);
    } finally {
      _release();
    }
  }
}
