import 'package:flutter/material.dart';

/// The colours of a game's own screens: the settings panel, the heads-up
/// display, the sheets around play, the maps and the touch controls.
///
/// **A [ThemeExtension], not constructor defaults.** Every widget here typed
/// its colours in — a white at three quarters for a heading, an amber for a
/// row waiting for its key, a yellow for a HUD line that just came true — so
/// a game with a palette of its own had to pass a colour to every widget
/// that took one and could not reach those that did not. Put one of these in
/// the app's theme and every widget reads it:
///
/// ```dart
/// MaterialApp(
///   theme: ThemeData(
///     extensions: const <ThemeExtension<Object?>>[
///       GameUiTheme(accent: Color(0xFF7FDBFF)),
///     ],
///   ),
/// );
/// ```
///
/// Without one, [of] answers the colours the widgets always had.
@immutable
final class GameUiTheme extends ThemeExtension<GameUiTheme> {
  const GameUiTheme({
    this.text = const Color(0xFFFFFFFF),
    this.label = const Color(0xD9FFFFFF),
    this.heading = const Color(0xBFFFFFFF),
    this.faint = const Color(0x99FFFFFF),
    this.scrim = const Color(0xB8000000),
    this.panel = const Color(0x73000000),
    this.waiting = const Color(0xFFFFC107),
    this.warning = const Color(0xFFFFCC80),
    this.error = const Color(0xFFFF8A80),
    this.accent = const Color(0xFFFFD166),
    this.hudLabel = const Color(0xFF9AA4B2),
    this.hudLabelWidth = 72.0,
    this.mapFloor = const Color(0xFF9A9284),
    this.mapWall = const Color(0xFF2B2622),
    this.mapPlayer = const Color(0xFFF2D133),
    this.mapBackdrop = const Color(0xA0000000),
    this.miniMapTrack = const Color(0xFF7E8794),
    this.miniMapPlayer = const Color(0xFFFFFFFF),
    this.miniMapOthers = const Color(0xFFE0553F),
    this.miniMapBackdrop = const Color(0x66000000),
    this.touchTrack = const Color(0x22FFFFFF),
    this.touchFill = const Color(0x33FFFFFF),
    this.touchUnavailable = const Color(0x14FFFFFF),
    this.touchOutline = const Color(0x55FFFFFF),
    this.touchHeld = const Color(0x66FFFFFF),
    this.touchPressed = const Color(0x99FFFFFF),
    this.touchKnob = const Color(0x88FFFFFF),
    this.touchGlyph = const Color(0xCCFFFFFF),
    this.touchOn = const Color(0xE6FFFFFF),
    this.touchOnGlyph = const Color(0xFF101010),
  });

  /// What is read: a value, a binding's name.
  final Color text;

  /// The label beside a slider or a switch.
  final Color label;

  /// A section's heading.
  final Color heading;

  /// What is there to be read when wanted: a binding's sources, a line of
  /// explanation under a switch.
  final Color faint;

  /// What a full-screen panel puts over the game.
  final Color scrim;

  /// A small panel's background: the heads-up display's.
  final Color panel;

  /// A row listening for its new key.
  final Color waiting;

  /// Something that did not happen and should be said: a write that failed,
  /// a conflict a rebind met.
  final Color warning;

  /// An answer that could not be kept.
  final Color error;

  /// A heads-up line that has just become true.
  final Color accent;

  /// A heads-up line's label.
  final Color hudLabel;

  /// How wide a heads-up line's label column is, in logical pixels: wide
  /// enough for a seven-letter label at thirteen points, bold, with a point
  /// and a half of tracking.
  final double hudLabelWidth;

  /// The automap's floor where the player has walked.
  final Color mapFloor;

  /// The automap's walls.
  final Color mapWall;

  /// The automap's arrow where the player stands.
  final Color mapPlayer;

  /// What the automap is drawn over.
  final Color mapBackdrop;

  /// A mini-map's course line.
  final Color miniMapTrack;

  /// A mini-map's dot for the player.
  final Color miniMapPlayer;

  /// A mini-map's dots for everyone else.
  final Color miniMapOthers;

  /// A mini-map's box.
  final Color miniMapBackdrop;

  /// What a moving touch part travels over: a stick's base, a steering band's track, a pedal at rest.
  final Color touchTrack;

  /// A touch button or toggle at rest, and a slot that can be chosen.
  final Color touchFill;

  /// A touch slot that cannot be chosen.
  final Color touchUnavailable;

  /// A touch control's rim, and the label of a slot that cannot be chosen.
  final Color touchOutline;

  /// A pedal held down, and a steering band's straight-ahead mark.
  final Color touchHeld;

  /// A touch button held down, and a steering band's thumb.
  final Color touchPressed;

  /// A stick's knob, and a toggle's rim.
  final Color touchKnob;

  /// A touch control's label.
  final Color touchGlyph;

  /// A toggle that is on, and a slot that is held.
  final Color touchOn;

  /// The label on a control drawn [touchOn].
  final Color touchOnGlyph;

  /// The colours the widgets have without a theme.
  static const GameUiTheme fallback = GameUiTheme();

  /// The theme's [GameUiTheme], or [fallback].
  static GameUiTheme of(BuildContext context) =>
      Theme.of(context).extension<GameUiTheme>() ?? fallback;

  @override
  GameUiTheme copyWith({
    Color? text,
    Color? label,
    Color? heading,
    Color? faint,
    Color? scrim,
    Color? panel,
    Color? waiting,
    Color? warning,
    Color? error,
    Color? accent,
    Color? hudLabel,
    double? hudLabelWidth,
    Color? mapFloor,
    Color? mapWall,
    Color? mapPlayer,
    Color? mapBackdrop,
    Color? miniMapTrack,
    Color? miniMapPlayer,
    Color? miniMapOthers,
    Color? miniMapBackdrop,
    Color? touchTrack,
    Color? touchFill,
    Color? touchUnavailable,
    Color? touchOutline,
    Color? touchHeld,
    Color? touchPressed,
    Color? touchKnob,
    Color? touchGlyph,
    Color? touchOn,
    Color? touchOnGlyph,
  }) => GameUiTheme(
    text: text ?? this.text,
    label: label ?? this.label,
    heading: heading ?? this.heading,
    faint: faint ?? this.faint,
    scrim: scrim ?? this.scrim,
    panel: panel ?? this.panel,
    waiting: waiting ?? this.waiting,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    accent: accent ?? this.accent,
    hudLabel: hudLabel ?? this.hudLabel,
    hudLabelWidth: hudLabelWidth ?? this.hudLabelWidth,
    mapFloor: mapFloor ?? this.mapFloor,
    mapWall: mapWall ?? this.mapWall,
    mapPlayer: mapPlayer ?? this.mapPlayer,
    mapBackdrop: mapBackdrop ?? this.mapBackdrop,
    miniMapTrack: miniMapTrack ?? this.miniMapTrack,
    miniMapPlayer: miniMapPlayer ?? this.miniMapPlayer,
    miniMapOthers: miniMapOthers ?? this.miniMapOthers,
    miniMapBackdrop: miniMapBackdrop ?? this.miniMapBackdrop,
    touchTrack: touchTrack ?? this.touchTrack,
    touchFill: touchFill ?? this.touchFill,
    touchUnavailable: touchUnavailable ?? this.touchUnavailable,
    touchOutline: touchOutline ?? this.touchOutline,
    touchHeld: touchHeld ?? this.touchHeld,
    touchPressed: touchPressed ?? this.touchPressed,
    touchKnob: touchKnob ?? this.touchKnob,
    touchGlyph: touchGlyph ?? this.touchGlyph,
    touchOn: touchOn ?? this.touchOn,
    touchOnGlyph: touchOnGlyph ?? this.touchOnGlyph,
  );

  @override
  GameUiTheme lerp(covariant GameUiTheme? other, double t) {
    if (other == null) return this;
    return GameUiTheme(
      text: Color.lerp(text, other.text, t)!,
      label: Color.lerp(label, other.label, t)!,
      heading: Color.lerp(heading, other.heading, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
      panel: Color.lerp(panel, other.panel, t)!,
      waiting: Color.lerp(waiting, other.waiting, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      hudLabel: Color.lerp(hudLabel, other.hudLabel, t)!,
      hudLabelWidth: t < 0.5 ? hudLabelWidth : other.hudLabelWidth,
      mapFloor: Color.lerp(mapFloor, other.mapFloor, t)!,
      mapWall: Color.lerp(mapWall, other.mapWall, t)!,
      mapPlayer: Color.lerp(mapPlayer, other.mapPlayer, t)!,
      mapBackdrop: Color.lerp(mapBackdrop, other.mapBackdrop, t)!,
      miniMapTrack: Color.lerp(miniMapTrack, other.miniMapTrack, t)!,
      miniMapPlayer: Color.lerp(miniMapPlayer, other.miniMapPlayer, t)!,
      miniMapOthers: Color.lerp(miniMapOthers, other.miniMapOthers, t)!,
      miniMapBackdrop: Color.lerp(miniMapBackdrop, other.miniMapBackdrop, t)!,
      touchTrack: Color.lerp(touchTrack, other.touchTrack, t)!,
      touchFill: Color.lerp(touchFill, other.touchFill, t)!,
      touchUnavailable: Color.lerp(
        touchUnavailable,
        other.touchUnavailable,
        t,
      )!,
      touchOutline: Color.lerp(touchOutline, other.touchOutline, t)!,
      touchHeld: Color.lerp(touchHeld, other.touchHeld, t)!,
      touchPressed: Color.lerp(touchPressed, other.touchPressed, t)!,
      touchKnob: Color.lerp(touchKnob, other.touchKnob, t)!,
      touchGlyph: Color.lerp(touchGlyph, other.touchGlyph, t)!,
      touchOn: Color.lerp(touchOn, other.touchOn, t)!,
      touchOnGlyph: Color.lerp(touchOnGlyph, other.touchOnGlyph, t)!,
    );
  }
}
