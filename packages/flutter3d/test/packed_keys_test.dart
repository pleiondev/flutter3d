/// The two storage forms of a sort key, held to the same behaviour.
///
///     flutter test test/packed_keys_test.dart
///     flutter test --platform chrome test/packed_keys_test.dart
///
/// **Run it both ways.** One implementation exists per platform and each is
/// invisible to the other, so a suite that only ever runs on the VM would leave
/// the web form to rot — which is the failure this whole session kept finding
/// in other guises: code no test can reach.
///
/// Nothing here mentions Int64List or Float64List. That is the point: the two
/// forms differ in how they hold a key and agree on everything a caller can
/// observe.
library;

import 'package:flutter3d/src/engine/render/key_sort.dart';
import 'package:flutter3d/src/engine/render/packed_keys.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ordering', () {
    test('payloads come back ordered by their keys', () {
      final keys = PackedKeys()
        ..ensure(4)
        ..setEntry(0, 30, 100)
        ..setEntry(1, 10, 200)
        ..setEntry(2, 20, 300)
        ..setEntry(3, 5, 400)
        ..sort(4);

      expect(
        <int>[for (var i = 0; i < 4; i++) keys.payloadAt(i)],
        <int>[400, 200, 300, 100],
      );
    });

    test('equal keys keep the order they arrived in', () {
      // What `SortMode.manual` is, and the only thing that makes it free: the
      // native form gets it from the payload sitting in the low bits, the web
      // form has to arrange it, and a caller cannot tell which.
      final keys = PackedKeys()..ensure(5);
      for (var i = 0; i < 5; i++) {
        keys.setEntry(i, 7, i * 11);
      }
      keys.sort(5);

      expect(
        <int>[for (var i = 0; i < 5; i++) keys.payloadAt(i)],
        <int>[0, 11, 22, 33, 44],
      );
    });

    test('a key using every available bit still orders correctly', () {
      // kSortKeyBits is 43, which is why the web form can keep the key in a
      // double and stay exact. A key wider than that would silently round
      // there, and two draws that differ only in their lowest bits would swap
      // — visible in back-to-front mode as transparent surfaces blending in the
      // wrong order.
      // Built by doubling rather than by shifting: `1 << 43` is a 32-bit
      // shift on the web and would quietly make this test check a much smaller
      // number — which is the same trap the sort key itself fell into.
      var top = 1;
      for (var i = 0; i < kSortKeyBits; i++) {
        top *= 2;
      }
      top -= 1;
      final keys = PackedKeys()
        ..ensure(3)
        ..setEntry(0, top, 1)
        ..setEntry(1, top - 1, 2)
        ..setEntry(2, 0, 3)
        ..sort(3);

      expect(
        <int>[for (var i = 0; i < 3; i++) keys.payloadAt(i)],
        <int>[3, 2, 1],
      );
    });

    test('the largest payload survives a round trip', () {
      final keys = PackedKeys()
        ..ensure(1)
        ..setEntry(0, 1, kMaxPayload)
        ..sort(1);
      expect(keys.payloadAt(0), kMaxPayload);
    });
  });

  group('sizing', () {
    test('growing past the initial capacity keeps working', () {
      // 300 crosses both the default capacity of 128 and kRadixThreshold, so
      // the native form takes its radix path here and the small-count path in
      // the tests above.
      final keys = PackedKeys()..ensure(300);
      for (var i = 0; i < 300; i++) {
        keys.setEntry(i, 300 - i, i);
      }
      keys.sort(300);

      expect(keys.payloadAt(0), 299);
      expect(keys.payloadAt(299), 0);
    });

    test('a count below two is a no-op rather than an error', () {
      final keys = PackedKeys()
        ..ensure(1)
        ..setEntry(0, 5, 9);
      expect(() => keys.sort(0), returnsNormally);
      expect(() => keys.sort(1), returnsNormally);
      expect(keys.payloadAt(0), 9);
    });

    test('sorting fewer entries than were written leaves the rest alone', () {
      // The frame fills as many entries as it has draws and sorts exactly that
      // many; anything beyond is last frame's and must not be read.
      final keys = PackedKeys()..ensure(4);
      keys
        ..setEntry(0, 9, 10)
        ..setEntry(1, 1, 20)
        ..setEntry(2, 5, 30)
        ..sort(2);

      expect(<int>[keys.payloadAt(0), keys.payloadAt(1)], <int>[20, 10]);
    });
  });
}
