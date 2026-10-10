/// The 1.0 side of every break the fixtures beside this one migrate, under a
/// name the migration scan counts as the engine's (`flutter3d_*`). Each
/// fixture's `before/` was written against the 0.8 side, which the comments
/// give.
library;

// ------------------------------------------------------------- internal
// 0.8 also exported `OldStage` and `oldHelper`, the package's own since.

/// What stays public where `OldStage` was.
final class Kit {
  const Kit();
}

// -------------------------------------------------------------- regroup
// 0.8: `View3d({double fov = 60, double near = 0.1, String title = ''})`.

final class ViewOptions {
  const ViewOptions({this.fov = 60, this.near = 0.1});
  final double fov;
  final double near;
}

final class View3d {
  const View3d({this.view = const ViewOptions(), this.title = ''});
  final ViewOptions view;
  final String title;
}

// ---------------------------------------------------------- enumToClass
// 0.8: `enum Weather { sun, rain }`.

final class Weather {
  const Weather._(this.name);
  final String name;
  static const Weather sun = Weather._('sun');
  static const Weather rain = Weather._('rain');
  static const Weather fog = Weather._('fog');
}

// -------------------------------------------------------- recordToClass
// 0.8: `typedef Span = (int, int, {String label})`.

final class Span {
  const Span(this.start, this.end, {this.label = ''});
  final int start;
  final int end;
  final String label;
}

Span spanOf(String text) => Span(0, text.length, label: text);

// ---------------------------------------------------------- nullToThrow
// 0.8: `String? loadText(String path)`, null for a path that is not there.

final class AssetNotFoundException implements Exception {
  const AssetNotFoundException(this.path);
  final String path;
}

String loadText(String path) => throw AssetNotFoundException(path);
