import 'dart:math' as math;

/// Which display refreshes a frame is drawn on, so that a capped frame rate
/// is an even one — `A1.5`.
///
/// **A cap that skips at random is worse than no cap.** Sixty frames a second
/// on a 120 Hz screen is every other refresh, each frame on screen for the
/// same 16.7 ms. A cap that draws whenever 16.7 ms have passed on the wall
/// lands on refreshes one, three, four, six — one frame shown for 8.3 ms and
/// the next for 25 — and motion judders at the cap's own rate. So the cap
/// here is a whole number of refreshes: [interval] is the refresh rate over
/// [cap], rounded up, and a frame is drawn on every [interval]-th refresh.
/// Forty on a 120 Hz screen is every third; fifty on 120 is every third too,
/// forty frames, because every other would be sixty, over the cap.
///
/// **Counted in refreshes, not in calls.** [due] takes the vsync timestamp —
/// what a `Ticker` hands its callback — and counts the refresh periods since
/// the last frame drawn, so a refresh the application missed still counts
/// towards the next frame rather than pushing it back.
///
/// The refresh rate is [refreshRate] when it is known — Flutter's
/// `Display.refreshRate` — and otherwise measured from the timestamps.
///
/// What a skipped refresh does is the caller's: the simulation's time goes
/// on accumulating ([due] answers with the seconds since the last frame
/// drawn), and the view presents the picture it already has.
final class FrameCadence {
  FrameCadence({this.cap, double? refreshRate})
    : assert(cap == null || cap > 0.0, 'a frame-rate cap is above nought'),
      // Behind a setter of the same name, so the field is private.
      // ignore: prefer_initializing_formals
      _refreshRate = refreshRate;

  /// Frames a second the drawing is held to at most, or null for one frame
  /// every refresh.
  double? cap;

  /// The display's refresh rate in hertz: the one given, or what the
  /// timestamps measured, or sixty until there is anything to measure.
  double get refreshRate => _refreshRate ?? _measured ?? 60.0;
  set refreshRate(double? hertz) => _refreshRate = hertz;
  double? _refreshRate;
  double? _measured;

  /// Draw on every this many refreshes: one without a [cap].
  int get interval {
    final limit = cap;
    if (limit == null || limit >= refreshRate) return 1;
    // A hair under so that sixty on a 59.94 Hz panel stays every refresh,
    // and sixty on 120 is two rather than two and a rounding error.
    return math.max(1, (refreshRate / limit - 1e-3).ceil());
  }

  /// Refreshes passed over since this was made, the frames not drawn.
  int get skipped => _skipped;
  int _skipped = 0;

  Duration? _lastVsync;
  Duration? _lastDrawn;

  /// Whether the refresh at [vsync] is one to draw on, and the seconds since
  /// the last one drawn when it is; null for a refresh to skip.
  ///
  /// Call once a refresh with the ticker's timestamp. The first call always
  /// draws, and answers nought.
  double? due(Duration vsync) {
    final previous = _lastVsync;
    _lastVsync = vsync;
    if (previous != null) _measure(vsync - previous);
    final drawn = _lastDrawn;
    if (drawn == null) {
      _lastDrawn = vsync;
      return 0.0;
    }
    final period = 1e6 / refreshRate;
    final refreshes = math.max(
      1,
      ((vsync - drawn).inMicroseconds / period).round(),
    );
    if (refreshes < interval) {
      _skipped++;
      return null;
    }
    _lastDrawn = vsync;
    return (vsync - drawn).inMicroseconds / 1e6;
  }

  /// Forgets the last frame, so the next [due] draws: a game that was away.
  void reset() {
    _lastDrawn = null;
    _lastVsync = null;
  }

  /// The shortest gap seen is the refresh period: a late frame is a gap of
  /// two periods, never less than one. Smoothed towards a shorter one at
  /// once and a longer one slowly, so one dropped frame cannot halve it.
  void _measure(Duration gap) {
    final micros = gap.inMicroseconds;
    // Nothing refreshes faster than this; a shorter gap is two calls in
    // one refresh, not a measurement.
    if (micros < 2000) return;
    final hertz = 1e6 / micros;
    final now = _measured;
    _measured = now == null || hertz > now ? hertz : now + (hertz - now) * 0.01;
  }
}
