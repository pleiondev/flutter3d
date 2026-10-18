/// 32-bit integer arithmetic that gives one answer on the VM and in a
/// browser.
///
/// **Written out because a Dart `int` is two different things.** On the VM it
/// is 64 bits; compiled to JavaScript it is a double, exact to 2^53 and no
/// further. A Wasm `i32.mul` done as `a * b` keeps every bit of a 64-bit
/// product on the VM and silently drops the low ones in a browser once the
/// product passes 2^53 — the trap `StateDigest` in `flutter3d_sim` already
/// documents, and the reason its multiply is done in halves. So every
/// operation here keeps its intermediates under 2^53 and folds its answer
/// back to a signed 32-bit value, and the interpreter calls these and nothing
/// else.
library;

import 'dart:typed_data';

/// [value] as a signed 32-bit integer: the low 32 bits, sign-extended.
int i32(int value) => value.toSigned(32);

/// [value]'s low 32 bits, as a non-negative integer.
int u32(int value) => value & 0xFFFFFFFF;

/// `i32.mul`: the low 32 bits of the product, in two halves so that no
/// partial product passes 2^48.
int i32Mul(int a, int b) {
  final ua = u32(a);
  final ub = u32(b);
  final low = (ua & 0xFFFF) * ub;
  final high = ((ua >> 16) * ub) & 0xFFFF;
  return i32(low + high * 65536);
}

/// `i32.shl`: the count taken modulo 32, as Wasm specifies.
int i32Shl(int a, int b) => i32(u32(a) << (b & 31));

/// `i32.shr_s`: an arithmetic shift of the signed value.
int i32ShrS(int a, int b) => i32(a) >> (b & 31);

/// `i32.shr_u`: a logical shift of the unsigned value.
int i32ShrU(int a, int b) => i32(u32(a) >> (b & 31));

/// `i32.rotl`.
int i32Rotl(int a, int b) {
  final k = b & 31;
  if (k == 0) return i32(a);
  final ua = u32(a);
  return i32(u32(ua << k) | (ua >> (32 - k)));
}

/// `i32.rotr`.
int i32Rotr(int a, int b) {
  final k = b & 31;
  if (k == 0) return i32(a);
  final ua = u32(a);
  return i32((ua >> k) | u32(ua << (32 - k)));
}

/// `i32.clz`: leading zero bits, 32 for nought.
int i32Clz(int a) => 32 - u32(a).bitLength;

/// `i32.ctz`: trailing zero bits, 32 for nought.
int i32Ctz(int a) {
  var rest = u32(a);
  if (rest == 0) return 32;
  var count = 0;
  while (rest & 1 == 0) {
    rest >>= 1;
    count++;
  }
  return count;
}

/// `i32.popcnt`: set bits.
int i32Popcnt(int a) {
  var rest = u32(a);
  var count = 0;
  while (rest != 0) {
    count += rest & 1;
    rest >>= 1;
  }
  return count;
}

/// `i32.extend8_s`.
int i32Extend8(int a) => (a & 0xFF).toSigned(8);

/// `i32.extend16_s`.
int i32Extend16(int a) => (a & 0xFFFF).toSigned(16);

// ---------------------------------------------------------------- f32
//
// A render module's `f32` (ABI 3), held as its bits in a signed 32-bit
// integer, so the interpreter's stack, locals, globals and memory hold one
// kind of number. Each operation reads the bits as a float, works in a
// double and rounds back to a float, which is the correctly rounded f32
// answer for `+ - * /` and `sqrt`: a double carries more than twice a
// float's bits. A render module is outside the simulation and its digest,
// so a NaN's payload is whatever the platform gives.

final Float32List _float = Float32List(1);
final Int32List _floatBits = Int32List.view(_float.buffer);

/// The float whose bits are [bits].
double f32Value(int bits) {
  _floatBits[0] = bits;
  return _float[0];
}

/// [value] rounded to a float, as its bits.
int f32Bits(double value) {
  _float[0] = value;
  return _floatBits[0];
}

/// `f32.nearest`: to the nearest whole number, a half to the even one, the
/// sign of nought kept.
double f32Nearest(double v) {
  if (v.isNaN || v.isInfinite) return v;
  final floor = v.floorToDouble();
  final rounded = switch (v - floor) {
    < 0.5 => floor,
    > 0.5 => floor + 1.0,
    _ => floor % 2.0 == 0.0 ? floor : floor + 1.0,
  };
  return rounded == 0.0 ? (v.isNegative ? -0.0 : 0.0) : rounded;
}

/// `f32.min` and `f32.max` (`max` true): NaN when either is, and
/// nought's sign told apart — `min(-0, 0)` is -0.
int f32MinMax(int x, int y, {required bool max}) {
  final a = f32Value(x);
  final b = f32Value(y);
  if (a.isNaN || b.isNaN) return f32Bits(double.nan);
  if (a == b) return max ? i32(x & y) : i32(x | y);
  return (max ? a > b : a < b) ? x : y;
}

/// `i32.trunc_f32_s` and `_u` (`unsigned` true): toward nought, or null
/// for a NaN or a value no i32 holds, which traps.
int? f32Truncate(int bits, {required bool unsigned}) {
  final v = f32Value(bits);
  if (v.isNaN || v.isInfinite) return null;
  final t = v.truncateToDouble();
  if (unsigned) {
    if (t <= -1.0 || t >= 4294967296.0) return null;
    return i32(t.toInt());
  }
  if (t < -2147483648.0 || t >= 2147483648.0) return null;
  return t.toInt();
}
