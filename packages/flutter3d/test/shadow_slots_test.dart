import 'package:flutter_test/flutter_test.dart';

import 'package:flutter3d/src/engine/render/shadow_slots.dart';

/// Stands in for a `LightNode`. The allocator compares by identity and reads
/// nothing else, so a named box is a truer test subject than a real light —
/// a real one would let a test pass by accident on some other field.
final class FakeLight {
  FakeLight(this.name);
  final String name;
  @override
  String toString() => name;
}

ShadowCandidate candidate(FakeLight light, double priority, {int bakeKey = 0}) =>
    ShadowCandidate(light: light, priority: priority, bakeKey: bakeKey);

void main() {
  group('assigning rows', () {
    test('the best candidates get rows, in priority order', () {
      final allocator = ShadowSlotAllocator(slotCount: 2);
      final a = FakeLight('a');
      final b = FakeLight('b');
      final c = FakeLight('c');

      final result = allocator.assign(<ShadowCandidate>[
        candidate(c, 1.0),
        candidate(a, 3.0),
        candidate(b, 2.0),
      ]);

      expect(result.owners, <Object?>[a, b]);
      expect(result.occupied, 2);
      expect(allocator.slotOf(c), isNull);
    });

    test('a candidate with no priority is not a candidate', () {
      final allocator = ShadowSlotAllocator(slotCount: 2);
      final a = FakeLight('a');
      final b = FakeLight('b');

      final result = allocator.assign(<ShadowCandidate>[
        candidate(a, 0.0),
        candidate(b, -1.0),
      ]);

      expect(result.owners, <Object?>[null, null]);
      expect(result.occupied, 0);
    });

    test('equal priorities resolve by list order, not by the sort', () {
      // List.sort is not stable in Dart. Without the explicit tiebreak two
      // lights of the same size could swap rows on nothing at all, and every
      // swap costs a full re-bake.
      final a = FakeLight('a');
      final b = FakeLight('b');
      final input = <ShadowCandidate>[candidate(a, 1.0), candidate(b, 1.0)];

      for (var i = 0; i < 5; i++) {
        final allocator = ShadowSlotAllocator(slotCount: 1);
        expect(allocator.assign(input).owners, <Object?>[a]);
      }
    });
  });

  group('keeping a row', () {
    test('an incumbent keeps its row even when it slips down the order', () {
      final allocator = ShadowSlotAllocator(slotCount: 2);
      final a = FakeLight('a');
      final b = FakeLight('b');

      allocator.assign(<ShadowCandidate>[candidate(a, 3.0), candidate(b, 2.0)]);
      // a walks away, b comes closer: the ranking inverts but the rows do not.
      final result =
          allocator.assign(<ShadowCandidate>[candidate(a, 1.0), candidate(b, 9.0)]);

      expect(result.owners, <Object?>[a, b]);
    });

    test('a light that stops asking frees its row', () {
      final allocator = ShadowSlotAllocator(slotCount: 2);
      final a = FakeLight('a');
      final b = FakeLight('b');

      allocator.assign(<ShadowCandidate>[candidate(a, 3.0), candidate(b, 2.0)]);
      final result = allocator.assign(<ShadowCandidate>[candidate(b, 2.0)]);

      expect(result.owners, <Object?>[null, b]);
      expect(allocator.slotOf(a), isNull);
    });
  });

  group('hysteresis', () {
    test('a marginally better challenger does not take a row', () {
      final allocator = ShadowSlotAllocator(slotCount: 1, hysteresis: 1.25);
      final incumbent = FakeLight('incumbent');
      final challenger = FakeLight('challenger');

      allocator.assign(<ShadowCandidate>[candidate(incumbent, 1.0)]);
      final result = allocator.assign(<ShadowCandidate>[
        candidate(incumbent, 1.0),
        candidate(challenger, 1.2),
      ]);

      expect(result.owners, <Object?>[incumbent]);
    });

    test('a clearly better challenger does', () {
      final allocator = ShadowSlotAllocator(slotCount: 1, hysteresis: 1.25);
      final incumbent = FakeLight('incumbent');
      final challenger = FakeLight('challenger');

      allocator.assign(<ShadowCandidate>[candidate(incumbent, 1.0)]);
      final result = allocator.assign(<ShadowCandidate>[
        candidate(incumbent, 1.0),
        candidate(challenger, 2.0),
      ]);

      expect(result.owners, <Object?>[challenger]);
    });

    test('two lights of steady size never trade a row', () {
      // The thrash this exists to stop: without hysteresis these two swap
      // every frame and the static atlas is redrawn every frame with it.
      final allocator = ShadowSlotAllocator(slotCount: 1, hysteresis: 1.25);
      final a = FakeLight('a');
      final b = FakeLight('b');

      // b is fractionally larger on the first frame, so b takes the row. The
      // point is what happens next: the two keep crossing over and the row
      // does not move.
      allocator.assign(<ShadowCandidate>[candidate(a, 1.0), candidate(b, 1.1)]);
      final first = allocator.assign(
          <ShadowCandidate>[candidate(a, 1.1), candidate(b, 1.0)]);
      final second = allocator.assign(
          <ShadowCandidate>[candidate(a, 1.0), candidate(b, 1.1)]);

      expect(first.owners, <Object?>[b]);
      expect(second.owners, <Object?>[b]);
    });

    test('at most one row changes hands per frame', () {
      final allocator = ShadowSlotAllocator(slotCount: 2, hysteresis: 1.25);
      final a = FakeLight('a');
      final b = FakeLight('b');
      final x = FakeLight('x');
      final y = FakeLight('y');

      allocator.assign(<ShadowCandidate>[candidate(a, 1.0), candidate(b, 1.0)]);
      final result = allocator.assign(<ShadowCandidate>[
        candidate(a, 1.0),
        candidate(b, 1.0),
        candidate(x, 50.0),
        candidate(y, 50.0),
      ]);

      final newcomers =
          result.owners.where((o) => identical(o, x) || identical(o, y)).length;
      expect(newcomers, 1, reason: 'each eviction costs a full re-bake');
    });
  });

  group('static bake tracking', () {
    test('a fresh assignment is dirty until something draws it', () {
      final allocator = ShadowSlotAllocator(slotCount: 2);
      final a = FakeLight('a');

      expect(allocator.assign(<ShadowCandidate>[candidate(a, 1.0)]).staticDirty,
          isTrue);
      allocator.recordStaticBake();
      expect(allocator.assign(<ShadowCandidate>[candidate(a, 1.0)]).staticDirty,
          isFalse);
    });

    test('deciding rows does not clear the flag; only baking does', () {
      // The flag has to survive a frame that decided rows and then skipped the
      // bake — shadows off, no device, an early return. Cleared by deciding, it
      // would promise walls that were never drawn.
      final allocator = ShadowSlotAllocator(slotCount: 1);
      final a = FakeLight('a');

      allocator.assign(<ShadowCandidate>[candidate(a, 1.0)]);
      final again = allocator.assign(<ShadowCandidate>[candidate(a, 1.0)]);

      expect(again.staticDirty, isTrue);
    });

    test('a light moving makes its baked walls stale', () {
      final allocator = ShadowSlotAllocator(slotCount: 1);
      final a = FakeLight('a');

      allocator.assign(<ShadowCandidate>[candidate(a, 1.0, bakeKey: 1)]);
      allocator.recordStaticBake();
      final moved =
          allocator.assign(<ShadowCandidate>[candidate(a, 1.0, bakeKey: 2)]);

      expect(moved.staticDirty, isTrue);
    });

    test('a row changing hands makes the atlas stale', () {
      final allocator = ShadowSlotAllocator(slotCount: 1, hysteresis: 1.25);
      final a = FakeLight('a');
      final b = FakeLight('b');

      allocator.assign(<ShadowCandidate>[candidate(a, 1.0)]);
      allocator.recordStaticBake();
      final swapped = allocator.assign(<ShadowCandidate>[
        candidate(a, 1.0),
        candidate(b, 5.0),
      ]);

      expect(swapped.owners, <Object?>[b]);
      expect(swapped.staticDirty, isTrue);
    });

    test('a light leaving makes the atlas stale', () {
      final allocator = ShadowSlotAllocator(slotCount: 1);
      final a = FakeLight('a');

      allocator.assign(<ShadowCandidate>[candidate(a, 1.0)]);
      allocator.recordStaticBake();

      expect(allocator.assign(<ShadowCandidate>[]).staticDirty, isTrue);
    });

    test('reset forgets the rows and what was baked into them', () {
      final allocator = ShadowSlotAllocator(slotCount: 1);
      final a = FakeLight('a');

      allocator.assign(<ShadowCandidate>[candidate(a, 1.0)]);
      allocator.recordStaticBake();
      allocator.reset();

      expect(allocator.slotOf(a), isNull);
      final result = allocator.assign(<ShadowCandidate>[candidate(a, 1.0)]);
      expect(result.staticDirty, isTrue,
          reason: 'the texture those rows lived in is gone');
    });
  });

  test('no slots at all is not an error', () {
    // The atlas is allocated lazily, so a frame can ask before there is
    // anywhere to put anything.
    final allocator = ShadowSlotAllocator(slotCount: 0);
    final result = allocator.assign(<ShadowCandidate>[
      candidate(FakeLight('a'), 1.0),
    ]);

    expect(result.owners, isEmpty);
    expect(result.staticDirty, isFalse);
  });
}
