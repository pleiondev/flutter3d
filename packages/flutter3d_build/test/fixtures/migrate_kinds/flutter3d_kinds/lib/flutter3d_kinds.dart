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

// 0.8: `typedef Frame = ({int width, int height})`, and a frame with a
// `depth` was a record of its own; the class takes it.

final class Frame {
  const Frame({required this.width, required this.height, this.depth = 0});
  final int width;
  final int height;
  final int depth;
}

Frame frameOf(int side) => Frame(width: side, height: side);

// ---------------------------------------------------------- nullToThrow
// 0.8: `String? loadText(String path)`, null for a path that is not there.

final class AssetNotFoundException implements Exception {
  const AssetNotFoundException(this.path);
  final String path;
}

String loadText(String path) => throw AssetNotFoundException(path);

// ------------------------------------------------------------- argument
// 0.8: `Lamp({Vector4? glow, double beamDegrees = 30})` with `glow` an
// sRGB-encoded vector and the beam in degrees, `Lamp.tinted(Vector3
// color)` with a linear one, and `Vector4 glow` a field changed in place.

/// The vectors of `vector_math`, as far as the fixtures use them.
final class Vector3 {
  Vector3(this.x, this.y, this.z);
  final double x;
  final double y;
  final double z;
}

final class Vector4 {
  Vector4(this.x, this.y, this.z, this.w);
  final double x;
  final double y;
  final double z;
  final double w;
  Vector4 operator *(double s) => Vector4(x * s, y * s, z * s, w * s);
}

final class LinearColor {
  const LinearColor(this.r, this.g, this.b, [this.a = 1]);
  factory LinearColor.fromSrgb(double r, double g, double b, [double a = 1]) =>
      LinearColor(r, g, b, a);
  final double r;
  final double g;
  final double b;
  final double a;
  static const LinearColor white = LinearColor(1, 1, 1);
}

extension LinearColorVector on LinearColor {
  Vector3 toVector3() => Vector3(r, g, b);
}

final class Lamp {
  Lamp({this.glow = LinearColor.white, this.beam = 0.5});
  Lamp.tinted(LinearColor color) : glow = color, beam = 0.5;
  LinearColor glow;
  final double beam;
}

// ----------------------------------------------------------------- gone
// 0.8: `class Shade { const Shade(); }`, renamed `KindShade`; and
// `Board.table()`, a static that is `Board.fill(Table())` now.

final class Table {
  Table();
  final List<int> rows = <int>[];
}

final class KindShade {
  const KindShade();
}

abstract final class Board {
  static Table fill(Table into) => into..rows.add(1);

  // 0.8: `static Table pile(Table table)`.
  static Pile pile(Pile pile) => pile;
}

final class Pile {
  Pile(this.table);
  final Table table;
}

// 0.8 also had `srgbColor(r, g, b, [a])`, which is `LinearColor.fromSrgb`
// now; `extension Tally on List<Object>` with `has<T>()`; `Mode.touch`, a
// static getter that is an instance's field now; `oldHelperGone()`, gone
// with nothing to write instead; and `roster.dart`, a library gone whole
// with its `Roster`.

final class Mode {
  const Mode({required this.touch});
  factory Mode.ofPlatform() => const Mode(touch: false);
  final bool touch;
}

// 0.8: `abstract interface class Shelf { int count(); }`, asynchronous
// since.

abstract base class Shelf {
  const Shelf();
  Future<int> count();
}

// 0.8: `Dial({int level = 0, String label = '', onTurn})`; the label is gone.

final class Dial {
  const Dial({this.level = 0, this.onTurn});
  final int level;

  /// 0.8: `void Function(int from, int to)`.
  final void Function(int to)? onTurn;
}

// 0.8: `class Match`, which shadowed `dart:core`'s; `KindMatch` since.

final class KindMatch {
  const KindMatch();
}

// 0.8: `class Ledger { int get total; int get count; }`; `KindLedger` with
// `sum` and `tally` since.

final class KindLedger {
  const KindLedger(this.sum, this.tally);
  final int sum;
  final int tally;
}

// 0.8: `class Store { int load(); bool save(); }`; asynchronous since, and
// a save answers nothing.

final class Store {
  Future<int> load() async => 1;
  Future<void> save() async {}
}

// 0.8 had two `Seat`s; this one is `KindSeat` since.

final class KindSeat {
  KindSeat();
}

// 0.8: `typedef Credit = ({String title, String licence})`.

typedef Credit = ({String title, String license});

// ----------------------------------------------------------- parameters
// 0.8: `Gauge(double reading, [double scale = 1])` and
// `Sieve([int coarse = 4, int fine = 1])`, optional positional arguments
// that became named.

final class Gauge {
  const Gauge(this.reading, {this.scale = 1});
  final double reading;
  final double scale;
}

final class Sieve {
  const Sieve({this.coarse = 4, this.fine = 1});
  final int coarse;
  final int fine;
}

// ---------------------------------------------------------- hookContext
// 0.8: `abstract base class Sensor` whose `sense(String what, double
// amount, {bool loud = false})` an outside class overrides.

final class Sensing {
  const Sensing({required this.what, required this.amount, this.loud = false});
  final String what;
  final double amount;
  final bool loud;
}

abstract base class Sensor {
  const Sensor();
  void sense(Sensing sensing);
}

// 0.8: `abstract base class Store` whose `read()` took nothing.

final class Reading {
  const Reading({this.from = 0});
  final int from;
}

abstract base class Store {
  const Store();
  Future<int> read(Reading reading);
}

// 0.8: `Tap({int centre = 0})`, the parameter renamed since.

final class Tap {
  const Tap({this.center = 0});
  final int center;
}

// ----------------------------------------------------- subclassModifier
// 0.8: `class Component` and `class Badge`, both plain classes.

/// A class outside code extends, `base` since 1.0.
base class Component {
  void update(double dt) {}
}

/// A value outside code only holds, `final` since 1.0.
final class Badge {
  const Badge(this.text);
  final String text;
}
