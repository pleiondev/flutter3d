import 'dart:collection';

import '../theme/contrast.dart';

/// Holds a brightness that changes over time to at most
/// [Wcag.flashesPerSecond] flashes in any one second.
///
/// **A full-screen change of brightness is a flash whoever asked for it.** A
/// cutscene's fade, a hit that whitens the screen, lightning: each is a
/// number from nought to one that a game sets frame by frame, and a script
/// that sets it to one and back faster than three times a second can bring
/// on a seizure in a player with photosensitive epilepsy (WCAG 2.3.1). This
/// is the gate such a number goes through before it is drawn:
///
/// ```dart
/// final flashes = FlashLimit();
/// ColoredBox(color: white.withValues(alpha: flashes.limit(hit, at: now)));
/// ```
///
/// **A flash is a pair of opposing changes**, each at least
/// [Wcag.flashLuminanceChange] of the whole range. A change in the same
/// direction as the last one, or one smaller than that, always goes
/// through, so a fade is never touched; an opposing change that would make
/// the seventh edge inside a second is held at the last value shown until
/// the oldest edge is a second old.
final class FlashLimit {
  /// A gate with nothing shown yet, allowing [flashesPerSecond] flashes a
  /// second of changes at least [threshold]; WCAG's three flashes and a
  /// tenth of the range by default.
  FlashLimit({
    this.flashesPerSecond = Wcag.flashesPerSecond,
    this.threshold = Wcag.flashLuminanceChange,
  });

  /// The most flashes allowed in any one second.
  final int flashesPerSecond;

  /// How far a value has to turn back to count as half a flash, as a
  /// fraction of the range from nought to one.
  final double threshold;

  /// When each counted change happened, oldest first, within the last
  /// second.
  final Queue<Duration> _edges = ListQueue<Duration>();

  /// The value last shown, and the furthest it has gone since the last
  /// counted change; null before the first.
  double? _shown;
  double _extreme = 0.0;

  /// Which way the last counted change went: 1 up, -1 down, 0 none yet.
  int _direction = 0;

  /// What to show at [at] for the [wanted] value, a fraction from nought to
  /// one; [at] only moves forward.
  double limit(double wanted, {required Duration at}) {
    final shown = _shown;
    if (shown == null) {
      _extreme = wanted;
      return _shown = wanted;
    }
    while (_edges.isNotEmpty &&
        at - _edges.first >= const Duration(seconds: 1)) {
      _edges.removeFirst();
    }
    final moved = wanted - _extreme;
    if (_direction != 0 && moved * _direction > 0) {
      // Further the way it was already going: a fade, or the same flash.
      _extreme = wanted;
      return _shown = wanted;
    }
    if (moved.abs() < threshold) return _shown = wanted;
    if (_edges.length >= 2 * flashesPerSecond) return shown;
    _edges.addLast(at);
    _direction = moved > 0 ? 1 : -1;
    _extreme = wanted;
    return _shown = wanted;
  }

  /// Forgets what was shown, for a new scene.
  void reset() {
    _edges.clear();
    _shown = null;
    _direction = 0;
  }
}
