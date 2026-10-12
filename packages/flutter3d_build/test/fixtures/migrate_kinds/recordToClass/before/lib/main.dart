import 'package:flutter3d_kinds/flutter3d_kinds.dart';

int width(String text) {
  final span = spanOf(text);
  return span.$2 - span.$1;
}

String label(String text) => spanOf(text).label;

int start(String text) {
  final (first, _, label: _) = spanOf(text);
  return first;
}

Frame framed(int w) => (width: w, height: w * 2);

Future<Frame> later(int w) async {
  return (width: w, height: w);
}
