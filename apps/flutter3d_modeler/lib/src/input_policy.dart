/// Which pointer gets the camera and which gets the tool — `ui-19`'s own
/// `InputPolicy`, pure Dart.
///
///     dart test test/input_policy_test.dart
///
/// **The same touch that orbits the camera everywhere else must not sculpt.**
/// `orbit_gestures.dart` already gives a single finger the camera unconditionally
/// — the right answer in every mode that has no continuous-stroke tool. Once one
/// exists, that same finger would otherwise both orbit the view and paint the
/// surface from one motion, and a person cannot aim a brush while the thing it is
/// aimed at is sliding under it. So a tool that draws a stroke — so far only
/// [ToolCategory.sculpting] — pulls touch back to the camera on purpose, and only
/// a stylus or a mouse reaches the brush at all.
///
/// **A mouse presses with a force it does not have.** The alternative — a brush
/// that goes translucent under a mouse because there is no pressure channel to
/// read — makes every mouse user's stroke look like a mistake. Reporting 1.0
/// instead means a mouse always paints at full strength, matching what
/// `ui-19`'s own worked example asks for.
///
/// **A stylus's inverted end is still the same stroke, not a different tool.**
/// Flipping a pen over to erase is the one gesture every drawing app on every
/// platform already agrees on, so [ToolStroke.erase] rides along on the same
/// value rather than asking the caller to have armed an eraser tool first.
library;

import 'orbit_gestures.dart' show PointerKind;

/// A category of tool this policy has an opinion about routing pointers to.
///
/// One case today because sculpting is the only continuous-stroke tool this
/// plan has reached; a future paint or weight tool joins here rather than
/// forking a second policy, since the routing rule — touch stays with the
/// camera, stylus and mouse reach the tool — does not change with what the
/// stroke does once it lands.
enum ToolCategory {
  /// A brush dragged across the surface in a continuous stroke.
  sculpting,
}

/// What a pointer's input means, once [InputPolicy] has decided.
sealed class InputIntent {
  const InputIntent();
}

/// The pointer should drive the camera. `orbit_gestures.dart` decides what
/// that means; this only says that it, and not the armed tool, gets it.
final class CameraInput extends InputIntent {
  const CameraInput();
}

/// The pointer is drawing on the model, at a normalised [force].
final class ToolStroke extends InputIntent {
  const ToolStroke({required this.force, this.erase = false});

  /// 0 at no pressure, 1 at the device's own maximum — already resolved by
  /// [InputPolicy.classify], never a raw sensor reading a caller has to scale
  /// itself.
  final double force;

  /// The inverted end of a stylus: the same stroke, the opposite effect.
  final bool erase;

  @override
  String toString() => 'ToolStroke(force: $force, erase: $erase)';
}

/// A touch held past the long-press threshold.
///
/// Offered as its own case rather than folded into [CameraInput] so a caller
/// can open a context menu on it without having first nudged the camera by
/// the tremor of a finger held still.
final class LongPressInput extends InputIntent {
  const LongPressInput();
}

/// Decides, per pointer, whether the camera or the armed tool gets it.
///
/// Stateless on purpose: every call answers from its own arguments, so a
/// widget, a test or the replay of a recorded session can all ask it the same
/// question without sharing a session's worth of pointer state the way
/// `OrbitGestures` has to for its multi-finger gestures.
final class InputPolicy {
  const InputPolicy();

  /// The minimum touch target, in logical pixels — Material's own 48dp
  /// guideline, `ui-19`'s own "tap target 48 на тач". Kept here rather than
  /// invented again at each call site that lays out a button for touch.
  static const double touchTapTarget = 48.0;

  /// What a pointer going down means for [tool], the category of tool
  /// currently armed.
  InputIntent classify({
    required PointerKind kind,
    required ToolCategory tool,
    double? pressure,
    bool inverted = false,
    bool longPress = false,
  }) {
    switch (kind) {
      case PointerKind.touch:
        return longPress ? const LongPressInput() : const CameraInput();
      // A trackpad never reaches a stroke tool: it has no down-and-drag of
      // its own, only the scroll and pinch `OrbitGestures.scroll` already
      // reads. Treated as the camera's for the same reason touch is —
      // nothing here should ever see one, and idle would silently drop a
      // gesture a future caller adds without anyone noticing.
      case PointerKind.trackpad:
        return const CameraInput();
      case PointerKind.mouse:
        return const ToolStroke(force: 1.0);
      case PointerKind.stylus:
        return ToolStroke(force: normalizePressure(pressure), erase: inverted);
    }
  }

  /// A stylus's own pressure reading, clamped to what a stroke expects: 0 at
  /// nothing, 1 at the device's own maximum. A pen that reports nothing —
  /// `pressure: null`, which platforms do between contact and the first
  /// sample — is read as full force rather than none, since a stroke that
  /// starts invisible would read as the application dropping the first touch
  /// of every mark.
  static double normalizePressure(double? pressure) {
    if (pressure == null) return 1.0;
    return pressure.clamp(0.0, 1.0);
  }
}
