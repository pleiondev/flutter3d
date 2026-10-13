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

Frame framed(int w) => Frame(width: w, height: w * 2);

Future<Frame> later(int w) async {
  return Frame(width: w, height: w);
}

int build(Frame Function() make) => make().width;

final int built = build(() {
  return Frame(width: 1, height: 2);
});

final List<Frame> frames = <Frame>[Frame(width: 1, height: 1)];

const List<Frame> fixed = <Frame>[Frame(width: 1, height: 1)];

int area({required Frame frame}) => frame.width * frame.height;

final int deep = area(frame: Frame(width: 2, height: 3, depth: 1));

int takes(Frame frame) => frame.width;

int later() {
  final f = Frame(width: 1, height: 2);
  return takes(f);
}

int kept() {
  final Frame f = frameOf(2);
  return f.width;
}

final List<Frame> grown = <Frame>[
  for (var i = 1; i < 3; i++) Frame(width: i, height: i),
  if (frames.isEmpty) Frame(width: 0, height: 0),
];

final Map<String, Frame> named = <String, Frame>{
  'unit': Frame(width: 1, height: 1),
};
