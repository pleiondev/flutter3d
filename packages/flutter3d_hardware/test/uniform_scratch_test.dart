/// A uniform block is filled in a buffer kept per size, not made per draw.
library;

import 'package:flutter3d_hardware/backend.dart';
import 'package:test/test.dart';

void main() {
  test('one size is one buffer, every time it is asked for', () {
    // Mutation: `zeroed` making a fresh list per call, as every backend's
    // bind did — the identity fails, and so does the point of it.
    final scratch = UniformScratch();
    final first = scratch.zeroed(64);
    expect(first, hasLength(16));
    expect(identical(scratch.zeroed(64), first), isTrue);
    expect(identical(scratch.zeroed(128), first), isFalse);
    expect(scratch.sizes, 2);
  });

  test('a reused buffer reads zero where the last block wrote', () {
    // Mutation: the `fillRange` dropped — a member the next draw does not
    // write keeps this draw's value, where a fresh list read zero.
    final scratch = UniformScratch();
    scratch.zeroed(32).setAll(0, <double>[1, 2, 3, 4, 5, 6, 7, 8]);
    expect(scratch.zeroed(32), everyElement(0));
  });
}
