/// `formatByteSize`: a byte count in the unit a person reads it in.
///
///     dart test test/byte_size_test.dart
library;

import 'package:flutter3d_model_core/flutter3d_model_core.dart';
import 'package:test/test.dart';

void main() {
  test('bytes under a kilobyte stay bytes', () {
    expect(formatByteSize(0), '0 Б');
    expect(formatByteSize(512), '512 Б');
    expect(formatByteSize(1023), '1023 Б');
  });

  test('a round kilobyte count', () {
    expect(formatByteSize(1024), '1 КБ');
    expect(formatByteSize(1024 * 170), '170 КБ');
  });

  test('kilobytes round to the nearest whole one', () {
    expect(formatByteSize(1024 * 170 + 400), '170 КБ');
    expect(formatByteSize(1024 * 170 + 600), '171 КБ');
  });

  test('megabytes take over once a kilobyte count would be four digits', () {
    expect(formatByteSize(1024 * 1024), '1 МБ');
    expect(formatByteSize(1024 * 1024 * 12), '12 МБ');
  });

  test('gigabytes past that', () {
    expect(formatByteSize(1024 * 1024 * 1024 * 2), '2 ГБ');
  });
}
