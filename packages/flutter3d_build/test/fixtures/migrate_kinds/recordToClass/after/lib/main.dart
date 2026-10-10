import 'package:flutter3d_kinds/flutter3d_kinds.dart';

int width(String text) {
  final span = spanOf(text);
  return span.end - span.start;
}

String label(String text) => spanOf(text).label;

int start(String text) {
  // TODO(flutter3d-1.0): `Span` is a class in 1.0.0-rc.1, not a record: `.$1` is `.start`, `.$2` is `.end`. See https://flutter3d.pleion.dev/reference/migrating-to-1.0/#kinds-Span-class
  final (first, _, label: _) = spanOf(text);
  return first;
}
