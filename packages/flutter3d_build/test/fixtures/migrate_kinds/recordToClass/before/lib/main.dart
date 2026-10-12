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

int build(Frame Function() make) => make().width;

final int built = build(() {
  return (width: 1, height: 2);
});

final List<Frame> frames = <Frame>[(width: 1, height: 1)];

const List<Frame> fixed = <Frame>[(width: 1, height: 1)];

int area({required Frame frame}) => frame.width * frame.height;

final int deep = area(frame: (width: 2, height: 3, depth: 1));

int takes(Frame frame) => frame.width;

int later() {
  final f = (width: 1, height: 2);
  return takes(f);
}
