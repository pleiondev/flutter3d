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
