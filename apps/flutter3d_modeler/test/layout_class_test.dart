/// `LayoutClass`: `ui-05`'s own width boundary, without Flutter.
///
///     dart test test/layout_class_test.dart
library;

import 'package:flutter3d_modeler/src/ui/layout_class.dart';
import 'package:test/test.dart';

void main() {
  group('LayoutClass.of', () {
    test('599 is a phone — the row\'s own worked boundary', () {
      expect(LayoutClass.of(599), LayoutClass.phone);
    });

    test('600 is a tablet — the row\'s own worked boundary', () {
      expect(LayoutClass.of(600), LayoutClass.tablet);
    });

    test('1199 is still a tablet — the row\'s own worked boundary', () {
      expect(LayoutClass.of(1199), LayoutClass.tablet);
    });

    test('1200 is a desktop — the row\'s own worked boundary', () {
      expect(LayoutClass.of(1200), LayoutClass.desktop);
    });

    test('a narrow phone stays a phone', () {
      expect(LayoutClass.of(320), LayoutClass.phone);
    });

    test('a wide desktop stays a desktop', () {
      expect(LayoutClass.of(2560), LayoutClass.desktop);
    });
  });
}
