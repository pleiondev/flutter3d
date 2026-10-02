/// What `indexWindow` lets a draw read, and what it refuses.
///
///     flutter test test/index_window_test.dart
///
/// The conformance check `a window of the index buffer draws that window` asks
/// the same of a live device; this asks it of the rule the four backends share,
/// which is where a refusal is added and so where a test of one belongs.
library;

import 'package:flutter3d_hardware/flutter3d_hardware.dart';
import 'package:test/test.dart';

void main() {
  test('leaving both out is the whole binding', () {
    expect(indexWindow(6), (first: 0, count: 6));
  });

  test('a start with no count reads to the end', () {
    expect(indexWindow(6, firstIndex: 3), (first: 3, count: 3));
  });

  test('a window inside the binding is the window', () {
    expect(indexWindow(6, firstIndex: 3, indexCount: 3), (first: 3, count: 3));
    expect(indexWindow(6, firstIndex: 0, indexCount: 0), (first: 0, count: 0));
  });

  test('nothing bound is an empty whole, not a refusal', () {
    // The encoders return early on a count of nought, which is how a draw
    // with nothing bound has always drawn nothing.
    expect(indexWindow(0), (first: 0, count: 0));
  });

  test('a window past the end is refused, naming the three numbers', () {
    expect(
      () => indexWindow(6, firstIndex: 4, indexCount: 3),
      throwsA(
        isA<RangeError>().having(
          (e) => e.message,
          'message',
          allOf(contains('3 indices'), contains('index 4'), contains('6')),
        ),
      ),
    );
  });

  test('a negative start or count is refused', () {
    expect(() => indexWindow(6, firstIndex: -1), throwsRangeError);
    expect(() => indexWindow(6, indexCount: -1), throwsRangeError);
    expect(() => indexWindow(6, firstIndex: 7), throwsRangeError);
  });
}
